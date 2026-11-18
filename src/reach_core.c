/* reach_core.c -- see reach_core.h for the contract. C99, standard library only. */
#include "reach_core.h"

#include <math.h>

#define REACH_VERSION_STRING "0.1.0"

REACH_API int reach_abi_version(void) { return REACH_ABI_VERSION; }
REACH_API const char *reach_version(void) { return REACH_VERSION_STRING; }

static int is_nan(double x) { return x != x; }

/* x^y as R's `^` does it for finite arguments. Matching the special cases
 * (x^2 as x * x, x^0 and 1^y exactly 1) keeps results bit-identical to the
 * R reference implementation; everything else is the C library's pow(). */
static double reach_pow(double x, double y) {
  if (x == 1.0 || y == 0.0) return 1.0;
  if (isfinite(x) && isfinite(y) && y == 2.0) return x * x;
  return pow(x, y);
}

/* One limb's equation as it stands, with no floor at zero. */
static double eval_raw(double C, double a, double n, double h) {
  return C * reach_pow(h - a, n);
}

/* Index into `b` (nb sorted breakpoints) following R's findInterval() with
 * rightmost.closed = TRUE: 0 below b[0]; i + 1 for b[i] <= x < b[i + 1];
 * nb - 1 for x equal to b[nb - 1]; nb above it. */
static int find_interval(const double *b, int nb, double x) {
  int lo = 0, hi = nb;
  while (lo < hi) {
    int mid = lo + (hi - lo) / 2;
    if (b[mid] <= x) lo = mid + 1; else hi = mid;
  }
  if (lo == nb && x == b[nb - 1]) return nb - 1;
  return lo;
}

static int has_arrays(const reach_rating *r) {
  return r && r->lower && r->upper && r->C && r->a && r->n &&
         r->n_limbs >= 1 && r->n_limbs <= REACH_MAX_LIMBS;
}

REACH_API int reach_rating_check(const reach_rating *r, int *bad_limb) {
  size_t i;
  if (bad_limb) *bad_limb = -1;
  if (!has_arrays(r)) return REACH_ERR_ARG;
  for (i = 0; i < r->n_limbs; i++) {
    if (!isfinite(r->lower[i]) || !isfinite(r->upper[i]) || !isfinite(r->C[i]) ||
        !isfinite(r->a[i]) || !isfinite(r->n[i])) {
      if (bad_limb) *bad_limb = (int)i;
      return REACH_ERR_VALUE;
    }
    if (!(r->upper[i] > r->lower[i])) {
      if (bad_limb) *bad_limb = (int)i;
      return REACH_ERR_ORDER;
    }
    if (i + 1 < r->n_limbs && !(fabs(r->upper[i] - r->lower[i + 1]) < REACH_CONTIGUITY_TOL)) {
      if (bad_limb) *bad_limb = (int)i;
      return REACH_ERR_ORDER;
    }
  }
  return REACH_OK;
}

REACH_API int reach_forward(const reach_rating *r, const double *stage, size_t m,
                            double *discharge, int32_t *limb, int8_t *extrapolated) {
  double breaks[REACH_MAX_LIMBS + 1];
  size_t i, k;
  int nl, nb, status;

  status = reach_rating_check(r, NULL);
  if (status != REACH_OK) return status;
  if (m > 0 && !stage) return REACH_ERR_ARG;

  nl = (int)r->n_limbs;
  nb = nl + 1;
  breaks[0] = r->lower[0];
  for (k = 0; k < r->n_limbs; k++) breaks[k + 1] = r->upper[k];

  for (i = 0; i < m; i++) {
    double h = stage[i];
    int idx, l;
    if (is_nan(h)) {
      if (discharge) discharge[i] = h;
      if (limb) limb[i] = -1;
      if (extrapolated) extrapolated[i] = -1;
      continue;
    }
    idx = find_interval(breaks, nb, h);
    l = idx < 1 ? 0 : (idx > nl ? nl - 1 : idx - 1);
    if (discharge) {
      discharge[i] = (h <= r->a[l]) ? 0.0 : eval_raw(r->C[l], r->a[l], r->n[l], h);
    }
    if (limb) limb[i] = (int32_t)l;
    if (extrapolated) extrapolated[i] = (idx == 0 || idx == nb) ? 1 : 0;
  }
  return REACH_OK;
}

REACH_API int reach_inverse(const reach_rating *r, const double *discharge, size_t m,
                            double *stage, int8_t *extrapolated) {
  double breaks[REACH_MAX_LIMBS + 1];
  size_t i, k;
  int nl, nb, status;

  status = reach_rating_check(r, NULL);
  if (status != REACH_OK) return status;
  if (m > 0 && (!discharge || !stage)) return REACH_ERR_ARG;
  for (k = 0; k < r->n_limbs; k++) {
    if (!(r->C[k] > 0.0) || !(r->n[k] > 0.0)) return REACH_ERR_VALUE;
  }

  nl = (int)r->n_limbs;
  nb = nl + 1;
  breaks[0] = eval_raw(r->C[0], r->a[0], r->n[0], r->lower[0]);
  for (k = 0; k < r->n_limbs; k++) {
    breaks[k + 1] = eval_raw(r->C[k], r->a[k], r->n[k], r->upper[k]);
  }
  for (k = 0; k < (size_t)nb; k++) {
    if (is_nan(breaks[k]) || (k > 0 && breaks[k] < breaks[k - 1])) return REACH_ERR_MONOTONE;
  }

  for (i = 0; i < m; i++) {
    double q = discharge[i];
    int idx, l;
    if (is_nan(q) || q <= 0.0) {
      stage[i] = NAN;
      if (extrapolated) extrapolated[i] = -1;
      continue;
    }
    idx = find_interval(breaks, nb, q);
    l = idx < 1 ? 0 : (idx > nl ? nl - 1 : idx - 1);
    stage[i] = r->a[l] + reach_pow(q / r->C[l], 1.0 / r->n[l]);
    if (extrapolated) extrapolated[i] = (idx == 0 || idx == nb) ? 1 : 0;
  }
  return REACH_OK;
}

REACH_API int reach_junctions(const reach_rating *r, double *q_below, double *q_above) {
  size_t j;
  int status = reach_rating_check(r, NULL);
  if (status != REACH_OK) return status;
  if (r->n_limbs > 1 && (!q_below || !q_above)) return REACH_ERR_ARG;
  for (j = 0; j + 1 < r->n_limbs; j++) {
    double h = r->upper[j];
    q_below[j] = eval_raw(r->C[j], r->a[j], r->n[j], h);
    q_above[j] = eval_raw(r->C[j + 1], r->a[j + 1], r->n[j + 1], h);
  }
  return REACH_OK;
}

REACH_API int reach_tangent_limb(double C, double a, double n, double h,
                                 double *C_out, double *a_out) {
  double depth;
  if (!C_out || !a_out) return REACH_ERR_ARG;
  if (!isfinite(C) || !isfinite(a) || !isfinite(n) || !isfinite(h)) return REACH_ERR_VALUE;
  depth = h - a;
  if (!(depth > 0.0) || !(C > 0.0) || !(n > 0.0)) return REACH_ERR_VALUE;
  *C_out = n * C * reach_pow(depth, n - 1.0);
  *a_out = h - depth / n;
  return REACH_OK;
}
