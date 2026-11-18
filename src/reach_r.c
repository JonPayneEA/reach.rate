/* reach_r.c -- R bindings for the evaluation kernel in reach_core.c.
 *
 * Nothing here does arithmetic. Each routine checks its arguments, hands
 * plain double arrays to the kernel, and converts the result to R types:
 * 0-based limb indices become 1-based, and the kernel's -1 markers for a
 * missing input become NA. The R functions in R/kernel.R are the only
 * callers. */
#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>

#include "reach_core.h"

static const double *real_arg(SEXP x, const char *name, R_xlen_t *len) {
  if (TYPEOF(x) != REALSXP) Rf_error("'%s' must be a double vector", name);
  if (len) *len = XLENGTH(x);
  return REAL(x);
}

static void build_rating(reach_rating *r, SEXP lower, SEXP upper, SEXP C, SEXP a, SEXP n) {
  R_xlen_t nl, len;
  r->lower = real_arg(lower, "lower", &nl);
  r->upper = real_arg(upper, "upper", &len);
  if (len != nl) Rf_error("rating columns must all have the same length");
  r->C = real_arg(C, "C", &len);
  if (len != nl) Rf_error("rating columns must all have the same length");
  r->a = real_arg(a, "a", &len);
  if (len != nl) Rf_error("rating columns must all have the same length");
  r->n = real_arg(n, "n", &len);
  if (len != nl) Rf_error("rating columns must all have the same length");
  r->n_limbs = (size_t)nl;
}

static void fail(int status, const char *fn) {
  switch (status) {
    case REACH_ERR_ARG:
      Rf_error("%s: the rating has no limbs or more than %d", fn, REACH_MAX_LIMBS);
    case REACH_ERR_VALUE:
      Rf_error("%s: a rating value is missing or not finite, or C or n is not positive where that is required", fn);
    case REACH_ERR_ORDER:
      Rf_error("%s: limbs must have upper_level above lower_level and be contiguous (upper_level[i] == lower_level[i+1])", fn);
    case REACH_ERR_MONOTONE:
      Rf_error("%s: discharge does not increase across the limbs, so the inverse is not single valued", fn);
    default:
      Rf_error("%s: unexpected status %d", fn, status);
  }
}

SEXP reach_r_forward(SEXP lower, SEXP upper, SEXP C, SEXP a, SEXP n, SEXP stage) {
  reach_rating r;
  R_xlen_t m, i;
  SEXP out, discharge, limb, extrap;
  int8_t *flag;
  int32_t *idx;
  int status;

  build_rating(&r, lower, upper, C, a, n);
  const double *h = real_arg(stage, "stage", &m);

  PROTECT(out = Rf_allocVector(VECSXP, 3));
  SET_VECTOR_ELT(out, 0, discharge = Rf_allocVector(REALSXP, m));
  SET_VECTOR_ELT(out, 1, limb = Rf_allocVector(INTSXP, m));
  SET_VECTOR_ELT(out, 2, extrap = Rf_allocVector(LGLSXP, m));

  flag = (int8_t *)R_alloc((size_t)(m > 0 ? m : 1), sizeof(int8_t));
  idx = (int32_t *)R_alloc((size_t)(m > 0 ? m : 1), sizeof(int32_t));
  status = reach_forward(&r, h, (size_t)m, REAL(discharge), idx, flag);
  if (status != REACH_OK) fail(status, "apply_rating()");

  for (i = 0; i < m; i++) {
    INTEGER(limb)[i] = idx[i] < 0 ? NA_INTEGER : (int)idx[i] + 1;
    LOGICAL(extrap)[i] = flag[i] < 0 ? NA_LOGICAL : (int)flag[i];
  }
  UNPROTECT(1);
  return out;
}

SEXP reach_r_inverse(SEXP lower, SEXP upper, SEXP C, SEXP a, SEXP n, SEXP discharge) {
  reach_rating r;
  R_xlen_t m, i;
  SEXP out, stage, extrap;
  int8_t *flag;
  int status;

  build_rating(&r, lower, upper, C, a, n);
  const double *q = real_arg(discharge, "discharge", &m);

  PROTECT(out = Rf_allocVector(VECSXP, 2));
  SET_VECTOR_ELT(out, 0, stage = Rf_allocVector(REALSXP, m));
  SET_VECTOR_ELT(out, 1, extrap = Rf_allocVector(LGLSXP, m));

  flag = (int8_t *)R_alloc((size_t)(m > 0 ? m : 1), sizeof(int8_t));
  status = reach_inverse(&r, q, (size_t)m, REAL(stage), flag);
  if (status != REACH_OK) fail(status, "apply_rating_inverse()");

  for (i = 0; i < m; i++) {
    LOGICAL(extrap)[i] = flag[i] < 0 ? NA_LOGICAL : (int)flag[i];
  }
  UNPROTECT(1);
  return out;
}

SEXP reach_r_junctions(SEXP lower, SEXP upper, SEXP C, SEXP a, SEXP n) {
  reach_rating r;
  SEXP out, below, above;
  R_xlen_t nj;
  int status;

  build_rating(&r, lower, upper, C, a, n);
  nj = r.n_limbs > 0 ? (R_xlen_t)r.n_limbs - 1 : 0;

  PROTECT(out = Rf_allocVector(VECSXP, 2));
  SET_VECTOR_ELT(out, 0, below = Rf_allocVector(REALSXP, nj));
  SET_VECTOR_ELT(out, 1, above = Rf_allocVector(REALSXP, nj));
  status = reach_junctions(&r, REAL(below), REAL(above));
  if (status != REACH_OK) fail(status, "junction check");
  UNPROTECT(1);
  return out;
}

SEXP reach_r_tangent(SEXP C, SEXP a, SEXP n, SEXP h) {
  SEXP out;
  double c_out, a_out;
  int status;
  if (TYPEOF(C) != REALSXP || XLENGTH(C) != 1 || TYPEOF(a) != REALSXP || XLENGTH(a) != 1 ||
      TYPEOF(n) != REALSXP || XLENGTH(n) != 1 || TYPEOF(h) != REALSXP || XLENGTH(h) != 1) {
    Rf_error("C, a, n and h must each be a single double");
  }
  status = reach_tangent_limb(REAL(C)[0], REAL(a)[0], REAL(n)[0], REAL(h)[0], &c_out, &a_out);
  if (status != REACH_OK) fail(status, "extend_rating_low()");
  PROTECT(out = Rf_allocVector(REALSXP, 2));
  REAL(out)[0] = c_out;
  REAL(out)[1] = a_out;
  UNPROTECT(1);
  return out;
}

SEXP reach_r_version(void) {
  SEXP out = PROTECT(Rf_allocVector(INTSXP, 1));
  INTEGER(out)[0] = reach_abi_version();
  UNPROTECT(1);
  return out;
}

static const R_CallMethodDef call_methods[] = {
  {"reach_r_forward", (DL_FUNC)&reach_r_forward, 6},
  {"reach_r_inverse", (DL_FUNC)&reach_r_inverse, 6},
  {"reach_r_junctions", (DL_FUNC)&reach_r_junctions, 5},
  {"reach_r_tangent", (DL_FUNC)&reach_r_tangent, 4},
  {"reach_r_version", (DL_FUNC)&reach_r_version, 0},
  {NULL, NULL, 0}
};

void R_init_reach_rate(DllInfo *dll) {
  R_registerRoutines(dll, NULL, call_methods, NULL, NULL);
  R_useDynamicSymbols(dll, FALSE);
}
