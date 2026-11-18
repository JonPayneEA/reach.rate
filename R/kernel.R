# ============================================================ #
# Tool:         kernel
# Description:  R side of the C evaluation kernel (src/reach_core.c).
#               Each function takes a rating table's columns, calls the
#               kernel through the thin binding in src/reach_r.c, and gives
#               back R types. The kernel is the one definition of the
#               rating arithmetic, shared with the Python package; these
#               wrappers add nothing to it except R's missing-value
#               conventions.
# Author:       Jonathan Payne
# Created:      2026-11-18
# Tier:         3
# Inputs:       A table with lower_level/upper_level/C/a/n, one row per
#               limb, ascending and contiguous.
# Outputs:      Plain lists of vectors; see each function.
# Dependencies: the compiled kernel
# ============================================================ #

#' @useDynLib reach.rate, .registration = TRUE, .fixes = "C_"
NULL

# The five rating columns as the double vectors the kernel expects.
.kernel_columns <- function(rating_dt) {
  list(
    lower = as.numeric(rating_dt$lower_level), upper = as.numeric(rating_dt$upper_level),
    C = as.numeric(rating_dt$C), a = as.numeric(rating_dt$a), n = as.numeric(rating_dt$n)
  )
}

# The kernel marks a missing input with NaN; R distinguishes NA from NaN,
# so an NA going in comes back as NA, not NaN.
.restore_na <- function(x, input) {
  x[is.na(input) & !is.nan(input)] <- NA_real_
  x
}

# Stage to discharge. Returns list(discharge, limb, extrapolated): `limb`
# is the 1-based row of the table whose equation was used (the nearest
# limb when extrapolating), `extrapolated` is logical, both NA where the
# stage is missing.
.kernel_forward <- function(rating_dt, stage) {
  stage <- as.numeric(stage)
  k <- .kernel_columns(rating_dt)
  res <- .Call(C_reach_r_forward, k$lower, k$upper, k$C, k$a, k$n, stage)
  names(res) <- c("discharge", "limb", "extrapolated")
  res$discharge <- .restore_na(res$discharge, stage)
  res
}

# Discharge to stage. Returns list(stage, extrapolated); both NA where the
# discharge is missing, and stage NA (extrapolated NA) where it is not
# positive.
.kernel_inverse <- function(rating_dt, discharge) {
  discharge <- as.numeric(discharge)
  k <- .kernel_columns(rating_dt)
  res <- .Call(C_reach_r_inverse, k$lower, k$upper, k$C, k$a, k$n, discharge)
  names(res) <- c("stage", "extrapolated")
  res$stage[is.na(res$stage)] <- NA_real_
  res
}

# Discharge on either side of each junction: list(below, above), each of
# length nrow(rating_dt) - 1.
.kernel_junctions <- function(rating_dt) {
  k <- .kernel_columns(rating_dt)
  res <- .Call(C_reach_r_junctions, k$lower, k$upper, k$C, k$a, k$n)
  names(res) <- c("below", "above")
  res
}

# The tangent line to one limb at stage h, as c(C, a) of the n = 1 limb.
.kernel_tangent <- function(C, a, n, h) {
  .Call(C_reach_r_tangent, as.numeric(C), as.numeric(a), as.numeric(n), as.numeric(h))
}

# ABI version of the compiled kernel, for tests and bug reports.
.kernel_abi_version <- function() .Call(C_reach_r_version)
