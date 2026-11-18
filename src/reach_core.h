/* reach_core.h -- evaluation kernel for multi-limb power-law ratings.
 *
 * One rating is a list of limbs. Limb i covers the stage range
 * [lower[i], upper[i]) and gives discharge
 *
 *     Q = C[i] * (H - a[i])^n[i]
 *
 * where H is stage, a is the stage of zero flow and n is the exponent.
 * Limbs are in ascending order and contiguous: upper[i] == lower[i+1].
 *
 * This file and reach_core.c are the single definition of that arithmetic.
 * They depend only on the C standard library, allocate nothing, keep no
 * global state and are safe to call from several threads at once, so any
 * language that can call C can use them. The R package wraps them in
 * reach_r.c; the Python package loads the same source through ctypes.
 * R and Python are required to agree with each other because both call
 * this code, not because two implementations were written to match.
 *
 * Conventions that every caller can rely on:
 *
 *  - Stage ranges are left-closed. A stage exactly on a junction belongs to
 *    the upper limb. The top of the highest limb is closed, so a stage equal
 *    to upper[n_limbs - 1] is inside the rating.
 *  - A stage below lower[0] or above upper[n_limbs - 1] is outside the
 *    rating. It is evaluated with the nearest limb's equation and flagged
 *    as extrapolated, never refused.
 *  - At or below a limb's offset (H <= a) the discharge is exactly 0.
 *  - A NaN input gives a NaN output, limb index -1 and extrapolated flag -1.
 *    Callers that distinguish a missing value from NaN (R does) restore it.
 *  - Exponentiation follows R's `^` for finite arguments: x^2 is computed
 *    as x * x, and x^0 and 1^y are exactly 1. Otherwise it is the C library
 *    pow(). This keeps results bit-identical to the R reference
 *    implementation wherever the C library's pow() is.
 *  - Functions return a status code. A non-zero status means no output
 *    array was written.
 */
#ifndef REACH_CORE_H
#define REACH_CORE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32) && defined(REACH_BUILD_DLL)
#define REACH_API __declspec(dllexport)
#else
#define REACH_API
#endif

/* Changes when a function signature or a documented behaviour changes. */
#define REACH_ABI_VERSION 1

/* Largest number of limbs one rating may have. The inverse keeps its
 * discharge breakpoints on the stack, which is why there is a bound. */
#define REACH_MAX_LIMBS 256

/* Two limbs are contiguous if |upper[i] - lower[i + 1]| is below this. */
#define REACH_CONTIGUITY_TOL 1e-8

enum {
  REACH_OK = 0,
  REACH_ERR_ARG = 1,      /* null pointer, or n_limbs outside 1..REACH_MAX_LIMBS */
  REACH_ERR_VALUE = 2,    /* a limb value is not finite; or, for the inverse
                             and tangent, C <= 0 or n <= 0 */
  REACH_ERR_ORDER = 3,    /* upper <= lower, or limbs not ascending and contiguous */
  REACH_ERR_MONOTONE = 4  /* inverse only: discharge at the limb bounds does
                             not increase with stage */
};

/* A non-owning view of one rating. All five arrays have n_limbs entries. */
typedef struct {
  size_t n_limbs;
  const double *lower;
  const double *upper;
  const double *C;
  const double *a;
  const double *n;
} reach_rating;

REACH_API int reach_abi_version(void);
REACH_API const char *reach_version(void);

/* Check that a rating is well formed: 1..REACH_MAX_LIMBS limbs, every value
 * finite, upper > lower for every limb, and limbs contiguous and ascending.
 * On REACH_ERR_VALUE or REACH_ERR_ORDER, *bad_limb (if not NULL) is the
 * 0-based index of the first offending limb; for a contiguity failure it is
 * the lower of the two limbs involved. */
REACH_API int reach_rating_check(const reach_rating *r, int *bad_limb);

/* Stage to discharge for m stage values.
 *   discharge     out, m values: Q, 0 where H <= a, NaN where stage is NaN
 *   limb          out, m values: 0-based index of the limb whose equation
 *                 was used (the nearest limb when extrapolating), -1 for NaN
 *   extrapolated  out, m values: 1 outside the rating, 0 inside, -1 for NaN
 * Any of the three outputs may be NULL if it is not wanted. */
REACH_API int reach_forward(const reach_rating *r, const double *stage, size_t m,
                            double *discharge, int32_t *limb, int8_t *extrapolated);

/* Discharge to stage for m discharge values, by inverting the limb whose
 * discharge range contains each value: H = a + (Q / C)^(1 / n).
 *   stage         out, m values: NaN where Q <= 0 (no unique inverse) or NaN
 *   extrapolated  out, m values: 1 where Q is outside the discharge range of
 *                 the rating, 0 inside, -1 where Q <= 0 or NaN; may be NULL
 * Needs C > 0 and n > 0 for every limb and discharge that does not decrease
 * across the limb bounds, otherwise the inverse is not single valued
 * (REACH_ERR_VALUE, REACH_ERR_MONOTONE). It does not require limbs to meet:
 * checking the size of a gap at a junction is reach_junctions() plus a
 * tolerance chosen by the caller. */
REACH_API int reach_inverse(const reach_rating *r, const double *discharge, size_t m,
                            double *stage, int8_t *extrapolated);

/* Discharge on each side of each junction, for continuity checks.
 * For j = 0 .. n_limbs - 2, at the stage H = upper[j]:
 *   q_below[j]  limb j's equation at H
 *   q_above[j]  limb j+1's equation at H
 * Both arrays have n_limbs - 1 entries (nothing is written for a single
 * limb). The equations are evaluated as they stand, with no floor at zero,
 * so a limb whose offset lies above the junction gives NaN. */
REACH_API int reach_junctions(const reach_rating *r, double *q_below, double *q_above);

/* The straight line tangent to one limb's curve at stage h, which has the
 * same discharge and the same gradient there. It is returned in the same
 * C(H - a)^n form with n = 1:
 *   C_out = n C (h - a)^(n - 1)       the gradient at h
 *   a_out = h - (h - a) / n           the stage where the line reaches Q = 0
 * Needs h > a, C > 0 and n > 0, all finite (REACH_ERR_VALUE otherwise). */
REACH_API int reach_tangent_limb(double C, double a, double n, double h,
                                 double *C_out, double *a_out);

#ifdef __cplusplus
}
#endif

#endif /* REACH_CORE_H */
