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

/* ---- limb crossing ----------------------------------------------------- */

#define REACH_CROSSING_MAXIT 1000

/* f(H) = C1 (H - a1)^n1 - C2 (H - a2)^n2, each side as written. */
static double crossing_f(double C1, double a1, double n1,
                         double C2, double a2, double n2, double h) {
  return C1 * reach_pow(h - a1, n1) - C2 * reach_pow(h - a2, n2);
}

/* Brent's method (R. P. Brent, Algorithms for Minimization without
 * Derivatives, 1973, ch. 4): bisection safeguarded by secant and inverse
 * quadratic interpolation. Written from the published algorithm. */
REACH_API int reach_crossing(double C1, double a1, double n1,
                             double C2, double a2, double n2,
                             double lo, double hi, double tol, double *root) {
  double a, b, c, fa, fb, fc, d, e;
  int iter;
  const double eps = 2.220446049250313e-16;

  if (!root) return REACH_ERR_ARG;
  if (!isfinite(C1) || !isfinite(a1) || !isfinite(n1) || !isfinite(C2) || !isfinite(a2) ||
      !isfinite(n2) || !isfinite(lo) || !isfinite(hi) || !isfinite(tol) || !(tol > 0.0)) {
    return REACH_ERR_VALUE;
  }
  if (!(lo < hi)) return REACH_ERR_ORDER;

  a = lo;
  b = hi;
  fa = crossing_f(C1, a1, n1, C2, a2, n2, a);
  fb = crossing_f(C1, a1, n1, C2, a2, n2, b);
  if (!isfinite(fa) || !isfinite(fb)) return REACH_NO_CROSSING;
  if (fa == 0.0) { *root = a; return REACH_OK; }
  if (fb == 0.0) { *root = b; return REACH_OK; }
  if ((fa > 0.0) == (fb > 0.0)) return REACH_NO_CROSSING;

  c = a; fc = fa;
  d = e = b - a;
  for (iter = 0; iter < REACH_CROSSING_MAXIT; iter++) {
    double tol1, xm;
    if ((fb > 0.0) == (fc > 0.0)) { c = a; fc = fa; d = e = b - a; }
    if (fabs(fc) < fabs(fb)) { a = b; b = c; c = a; fa = fb; fb = fc; fc = fa; }
    tol1 = 2.0 * eps * fabs(b) + 0.5 * tol;
    xm = 0.5 * (c - b);
    if (fabs(xm) <= tol1 || fb == 0.0) { *root = b; return REACH_OK; }
    if (fabs(e) >= tol1 && fabs(fa) > fabs(fb)) {
      double s = fb / fa, p, q, r, lim_a, lim_b;
      if (a == c) {
        p = 2.0 * xm * s;
        q = 1.0 - s;
      } else {
        q = fa / fc;
        r = fb / fc;
        p = s * (2.0 * xm * q * (q - r) - (b - a) * (r - 1.0));
        q = (q - 1.0) * (r - 1.0) * (s - 1.0);
      }
      if (p > 0.0) q = -q;
      p = fabs(p);
      lim_a = 3.0 * xm * q - fabs(tol1 * q);
      lim_b = fabs(e * q);
      if (2.0 * p < (lim_a < lim_b ? lim_a : lim_b)) { e = d; d = p / q; }
      else { d = xm; e = d; }
    } else {
      d = xm; e = d;
    }
    a = b;
    fa = fb;
    if (fabs(d) > tol1) b += d;
    else b += (xm >= 0.0 ? tol1 : -tol1);
    fb = crossing_f(C1, a1, n1, C2, a2, n2, b);
    if (!isfinite(fb)) return REACH_NO_CROSSING;
  }
  /* Brent's method converges long before this for any sensible bracket;
   * return the best estimate rather than refuse. */
  *root = b;
  return REACH_OK;
}

/* ---- cross-section geometry and Manning -------------------------------- */

REACH_API int reach_xs_geometry(const double *distance, const double *elevation,
                                size_t n_points, const double *stage, size_t m,
                                double *area, double *perimeter) {
  size_t i, k;
  if (!distance || !elevation || n_points < 2) return REACH_ERR_ARG;
  if (m > 0 && !stage) return REACH_ERR_ARG;
  for (i = 0; i < n_points; i++) {
    if (!isfinite(distance[i]) || !isfinite(elevation[i])) return REACH_ERR_VALUE;
    if (i > 0 && !(distance[i] > distance[i - 1])) return REACH_ERR_ORDER;
  }

  for (k = 0; k < m; k++) {
    double h = stage[k], a = 0.0, p = 0.0;
    if (is_nan(h)) {
      if (area) area[k] = h;
      if (perimeter) perimeter[k] = h;
      continue;
    }
    for (i = 0; i + 1 < n_points; i++) {
      double x1 = distance[i], z1 = elevation[i];
      double x2 = distance[i + 1], z2 = elevation[i + 1];
      double d1 = h - z1, d2 = h - z2;
      if (d1 <= 0.0 && d2 <= 0.0) continue;
      if (d1 > 0.0 && d2 > 0.0) {
        a = a + (d1 + d2) / 2.0 * (x2 - x1);
        p = p + sqrt((x2 - x1) * (x2 - x1) + (z2 - z1) * (z2 - z1));
      } else {
        double frac = d1 / (d1 - d2);
        double xc = x1 + frac * (x2 - x1);
        if (d1 > 0.0) {
          a = a + d1 / 2.0 * (xc - x1);
          p = p + sqrt((xc - x1) * (xc - x1) + d1 * d1);
        } else {
          a = a + d2 / 2.0 * (x2 - xc);
          p = p + sqrt((x2 - xc) * (x2 - xc) + d2 * d2);
        }
      }
    }
    if (area) area[k] = a;
    if (perimeter) perimeter[k] = p;
  }
  return REACH_OK;
}

REACH_API int reach_manning(const double *area, const double *perimeter, size_t m,
                            double roughness, double slope, double *discharge) {
  size_t k;
  if (m > 0 && (!area || !perimeter || !discharge)) return REACH_ERR_ARG;
  if (!isfinite(roughness) || !isfinite(slope) || !(roughness > 0.0) || slope < 0.0) {
    return REACH_ERR_VALUE;
  }
  for (k = 0; k < m; k++) {
    double radius = perimeter[k] > 0.0 ? area[k] / perimeter[k] : 0.0;
    discharge[k] = (1.0 / roughness) * area[k] * reach_pow(radius, 2.0 / 3.0) * sqrt(slope);
  }
  return REACH_OK;
}
