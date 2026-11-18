# ============================================================ #
# Tool:         support
# Description:  What a rating rests on, by stage (tranche B3). Five stage
#               ranges (observed, modelled, fitted, operational and
#               numerical), and a support class for any stage given to
#               apply_rating(): interpolation between observed gaugings,
#               interpolation that crosses modelled evidence, a stage the
#               fitted equations cover with no evidence there, an
#               extrapolation, or a stage beyond the operational limits.
#               A stage beyond the numerical range fails.
# Author:       Jonathan Payne
# Created:      2026-11-18
# Tier:         3
# Inputs:       A FlodeRating, FlodeSegmentedRating or FlodeRatingTable.
# Outputs:      rating_support(x); the `support` column of apply_rating().
# Dependencies: data.table
# ============================================================ #

#' @include flode_classes.R accessors.R invariants.R
NULL

# Evidence types that observe discharge. Everything else (modelled values,
# cross-section and structure computations, points read off another rating)
# supports a rating by argument, not by measurement.
.observed_source_types <- "gauging"

# The highest stage at which the top limb still gives a finite discharge.
# Above it Q = C (H - a)^n overflows, and a number computed there would not
# be a number. NA when there is no usable top limb.
.numerical_upper <- function(C, a, n) {
  if (!is.finite(C) || !is.finite(a) || !is.finite(n) || C <= 0 || n <= 0) return(NA_real_)
  a + (.Machine$double.xmax / C)^(1 / n) * (1 - 1e-12)
}

.range_row <- function(range, lower, upper, n, basis) {
  data.table(range = range, lower_stage_m = as.numeric(lower), upper_stage_m = as.numeric(upper),
             n_evidence = as.integer(n), basis = basis)
}

# Evidence ranges for a fit: observed from gaugings, modelled from the rest.
.evidence_ranges <- function(x) {
  empty <- list(observed = c(NA_real_, NA_real_, 0L), modelled = c(NA_real_, NA_real_, 0L))
  if (S7_inherits(x, FlodeRatingTable)) return(empty)
  g <- as.data.table(x@gaugings)
  g <- g[is.finite(stage_m) & (is.na(included) | included)]
  if (!nrow(g)) return(empty)
  obs <- g[source_type %in% .observed_source_types]
  mod <- g[!source_type %in% .observed_source_types]
  rng <- function(d) if (nrow(d)) c(min(d$stage_m), max(d$stage_m), nrow(d)) else c(NA_real_, NA_real_, 0L)
  list(observed = rng(obs), modelled = rng(mod))
}

# The stage range the equations are declared over.
.fitted_range <- function(x) {
  if (S7_inherits(x, FlodeRating)) return(c(min(x@limbs$lower_stage_m), max(x@limbs$upper_stage_m)))
  if (S7_inherits(x, FlodeRatingTable)) return(c(min(x@table$lower_level), max(x@table$upper_level)))
  s <- x@gaugings$stage_m
  s <- s[is.finite(s)]
  if (length(s)) range(s) else c(NA_real_, NA_real_)
}

.numerical_range <- function(x) {
  top <- if (S7_inherits(x, FlodeRating)) {
    i <- which.max(x@limbs$upper_stage_m); c(x@limbs$C[i], x@limbs$a[i], x@limbs$n[i])
  } else if (S7_inherits(x, FlodeRatingTable)) {
    i <- which.max(x@table$upper_level); c(x@table$C[i], x@table$a[i], x@table$n[i])
  } else NULL
  if (is.null(top)) return(c(NA_real_, NA_real_))
  c(-Inf, .numerical_upper(top[1L], top[2L], top[3L]))
}

.operational_range <- function(x) {
  if (S7_inherits(x, FlodeRatingTable)) return(list(range = c(NA_real_, NA_real_), basis = NA_character_))
  lim <- x@provenance$operational_limits
  if (is.null(lim)) return(list(range = c(NA_real_, NA_real_), basis = NA_character_))
  list(range = c(lim$lower_stage_m, lim$upper_stage_m), basis = if (is.na(lim$basis)) "no basis recorded" else lim$basis)
}

.support_ranges <- function(x) {
  ev <- .evidence_ranges(x)
  fit <- .fitted_range(x)
  num <- .numerical_range(x)
  op <- .operational_range(x)
  rbind(
    .range_row("observed", ev$observed[1L], ev$observed[2L], ev$observed[3L],
               "gaugings: evidence of source type 'gauging'"),
    .range_row("modelled", ev$modelled[1L], ev$modelled[2L], ev$modelled[3L],
               "evidence of any other source type (modelled, cross-section, structure equation, operational rating)"),
    .range_row("fitted", fit[1L], fit[2L], NA_integer_, "the stage range the equations are declared over"),
    .range_row("operational", op$range[1L], op$range[2L], NA_integer_,
               if (is.na(op$basis)) "not stated; see set_operational_limits()" else op$basis),
    .range_row("numerical", num[1L], num[2L], NA_integer_,
               "where the equations give a finite discharge; beyond it apply_rating() fails")
  )
}

# The support class of each stage. In order of precedence: beyond the
# operational limits; inside the range of gaugings; inside the hull of all
# evidence but outside the gaugings; inside the fitted range with no evidence
# there; beyond the fitted range. A rating that holds only equations has no
# evidence, so within its range it is `model_supported`.
.support_class <- function(x, stage) {
  r <- .support_ranges(x)
  get <- function(name) c(r$lower_stage_m[r$range == name], r$upper_stage_m[r$range == name])
  obs <- get("observed"); mod <- get("modelled"); fit <- get("fitted"); op <- get("operational")
  inside <- function(rng) !anyNA(rng) & stage >= rng[1L] & stage <= rng[2L]
  lows <- c(obs[1L], mod[1L]); highs <- c(obs[2L], mod[2L])
  has_evidence <- any(is.finite(lows))
  hull <- if (has_evidence) c(min(lows[is.finite(lows)]), max(highs[is.finite(highs)])) else c(NA_real_, NA_real_)
  out <- rep("extrapolation", length(stage))
  out[inside(fit)] <- "model_supported"
  if (has_evidence) {
    out[stage >= hull[1L] & stage <= hull[2L]] <- "interpolation_mixed"
    out[inside(obs)] <- "interpolation_observed"
  }
  if (!anyNA(op)) out[!is.na(stage) & (stage < op[1L] | stage > op[2L])] <- "outside_operational_range"
  out[is.na(stage)] <- NA_character_
  out
}

# A stage beyond the numerical range fails, with a message that says why.
.require_numerical_range <- function(x, stage, fn = "apply_rating()") {
  up <- .numerical_range(x)[2L]
  if (is.na(up)) return(invisible(TRUE))
  bad <- which(is.finite(stage) & stage > up)
  if (length(bad)) {
    stop(sprintf(
      paste0("%s: %d stage value%s (largest %.4g) lie beyond the numerical range of this rating, above %.4g m, where its top limb's ",
             "equation overflows. A discharge computed there would not be a number. Check the stage values for a unit or datum error."),
      fn, length(bad), if (length(bad) == 1L) "" else "s", max(stage[bad]), up
    ), call. = FALSE)
  }
  invisible(TRUE)
}
