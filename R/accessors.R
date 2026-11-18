# ============================================================ #
# Tool:         accessors
# Description:  The eight accessors that read a rating without touching
#               its S7 properties: rating_limbs(), rating_coefficients(),
#               rating_evidence(), rating_diagnostics(), rating_history(),
#               rating_provenance(), rating_support() and
#               rating_bootstrap(). Each is a generic with a method for
#               FlodeRating, FlodeSegmentedRating and FlodeRatingTable
#               where the information exists there, and a clear error
#               where it does not. Each returns a data.table with
#               unit-suffixed columns, or a documented list, so user code
#               never depends on where the package stores something.
# Author:       Jonathan Payne
# Created:      2026-11-18
# Tier:         3
# Inputs:       A FlodeRating, FlodeSegmentedRating or FlodeRatingTable.
# Outputs:      A data.table (or, for provenance, a list). Always a copy:
#               changing the result never changes the rating.
# Dependencies: data.table, S7
# ============================================================ #

#' @include flode_classes.R
NULL

.rating_class_label <- function(x) {
  sub("^.*::", "", class(x)[1L])
}

# Raised when an accessor is given something that is not a rating at all.
.accessor_not_a_rating <- function(fn, x) {
  stop(sprintf(
    "%s(): x must be a FlodeRating, FlodeSegmentedRating or FlodeRatingTable, not %s",
    fn, paste(class(x), collapse = "/")
  ), call. = FALSE)
}

# Raised when a rating class does not hold what the accessor returns.
.accessor_not_held <- function(fn, x, what, hint) {
  stop(sprintf("%s(): a %s %s. %s", fn, .rating_class_label(x), what, hint), call. = FALSE)
}

# A column of a table, or NA of the right length if it is absent.
.col_or_na <- function(dt, name, n = nrow(dt)) {
  if (name %in% names(dt)) dt[[name]] else rep(NA_real_, n)
}

# ---------------------------------------------------------------------------
# rating_limbs
# ---------------------------------------------------------------------------

#' Limbs of a rating
#'
#' @description
#' One row per limb: its stage range and its equation `Q = C(H - a)^n`.
#' This is the part of a rating a reader needs to apply or compare it,
#' without the fit diagnostics (see [rating_diagnostics()]) or the
#' uncertainty (see [rating_coefficients()]).
#'
#' @param x A [FlodeRating] or a [FlodeRatingTable]. A
#'   [FlodeSegmentedRating] is one joint model and has no independent
#'   limbs: use [rating_coefficients()] for its parameters.
#' @param all_columns Logical. `FALSE` (default) returns the six stable
#'   columns below. `TRUE` returns everything the rating carries for each
#'   limb: for a fit, the diagnostics and uncertainty columns as well
#'   (`rmse_cms`, `r_squared`, `n_obs`, `C_se` and so on); for a rating
#'   that has been through [flag_extrapolated_limbs()],
#'   [align_limb_equations()] or [align_limb_boundaries()], the columns
#'   those steps add (`doubtful`, `aligned`, `boundary_adjusted`, the
#'   `*_original` values). Select the columns you want by name: the set
#'   available varies with how the rating was made and can grow between
#'   releases.
#'
#' @return A data.table with columns `limb` (integer, 1 is the lowest),
#'   `lower_stage_m`, `upper_stage_m` (stage, m), `C`, `a` (stage of zero
#'   flow, m) and `n` (exponent); with `all_columns = TRUE`, those first
#'   and then the rest. A copy: changing it does not change the rating.
#'
#' @seealso [rating_coefficients()], [rating_diagnostics()],
#'   [as_rating_table()]
#'
#' @examples
#' set.seed(1)
#' stage_m <- seq(0.5, 2.5, by = 0.05)
#' discharge_cms <- 5 * stage_m^1.6 + rnorm(length(stage_m), sd = 0.02)
#' fit <- rate_optimise(discharge_cms, stage_m)
#' rating_limbs(fit)
#'
#' @export
rating_limbs <- new_generic("rating_limbs", "x", function(x, all_columns = FALSE) S7_dispatch())

method(rating_limbs, class_any) <- function(x, all_columns = FALSE) .accessor_not_a_rating("rating_limbs", x)

.limb_columns <- c("limb", "lower_stage_m", "upper_stage_m", "C", "a", "n")

method(rating_limbs, FlodeRating) <- function(x, all_columns = FALSE) {
  limbs <- x@limbs
  out <- data.table(
    limb = as.integer(limbs$limb), lower_stage_m = limbs$lower_stage_m,
    upper_stage_m = limbs$upper_stage_m, C = limbs$C, a = limbs$a, n = limbs$n
  )
  if (isTRUE(all_columns)) {
    rest <- setdiff(names(limbs), .limb_columns)
    out <- cbind(out, copy(limbs[, rest, with = FALSE]))
  }
  out[]
}

method(rating_limbs, FlodeRatingTable) <- function(x, all_columns = FALSE) {
  tbl <- x@table
  out <- data.table(
    limb = seq_len(nrow(tbl)), lower_stage_m = tbl$lower_level,
    upper_stage_m = tbl$upper_level, C = tbl$C, a = tbl$a, n = tbl$n
  )
  if (isTRUE(all_columns)) {
    rest <- setdiff(names(tbl), c("lower_level", "upper_level", "C", "a", "n"))
    out <- cbind(out, copy(tbl[, rest, with = FALSE]))
  }
  out[]
}

method(rating_limbs, FlodeSegmentedRating) <- function(x, all_columns = FALSE) {
  .accessor_not_held(
    "rating_limbs", x, "is one joint model and has no independent limbs",
    "Use rating_coefficients() for its parameters."
  )
}

# ---------------------------------------------------------------------------
# rating_coefficients
# ---------------------------------------------------------------------------

#' Coefficients of a rating, with their uncertainty
#'
#' @description
#' Every fitted parameter on its own row, in long form, with whatever
#' uncertainty the fit carries: the asymptotic standard error from the
#' least-squares fit, and the bootstrap standard error and quantiles when
#' the fit was made with `n_boot > 0`. Uncertainty that was not computed
#' is `NA`, never zero.
#'
#' @param x A [FlodeRating], [FlodeSegmentedRating] or [FlodeRatingTable].
#'
#' @return A data.table with columns `limb` (integer; `NA` for a
#'   [FlodeSegmentedRating], whose parameters belong to the joint model),
#'   `parameter`, `estimate`, `unit`, `se_asymptotic`, `se_bootstrap`,
#'   `q025`, `q50` and `q975` (the bootstrap 2.5, 50 and 97.5 per cent
#'   quantiles). Parameters are `C`, `a` and `n` for each limb of a
#'   [FlodeRating] or [FlodeRatingTable], and `C`, then `bp1`, `n1`,
#'   `bp2`, `n2` and so on for a [FlodeSegmentedRating]. Units: `C` is
#'   cumecs per metre to the power `n`, `a` and the breakpoints are stage
#'   in metres, `n` has no unit (`"1"`).
#'
#' @seealso [rating_limbs()], [rating_diagnostics()], [rating_bootstrap()]
#'
#' @examples
#' set.seed(1)
#' stage_m <- seq(0.5, 2.5, by = 0.05)
#' discharge_cms <- 5 * stage_m^1.6 + rnorm(length(stage_m), sd = 0.02)
#' fit <- rate_optimise(discharge_cms, stage_m, n_boot = 50L, boot_seed = 1L)
#' rating_coefficients(fit)
#'
#' @export
rating_coefficients <- new_generic("rating_coefficients", "x", function(x) S7_dispatch())

method(rating_coefficients, class_any) <- function(x) .accessor_not_a_rating("rating_coefficients", x)

.coefficient_units <- c(C = "cms per m^n", a = "m", n = "1")

method(rating_coefficients, FlodeRating) <- function(x) {
  limbs <- x@limbs
  one <- function(p) {
    data.table(
      limb = as.integer(limbs$limb), parameter = p, estimate = limbs[[p]],
      unit = .coefficient_units[[p]],
      se_asymptotic = .col_or_na(limbs, paste0(p, "_se_asymp")),
      se_bootstrap = .col_or_na(limbs, paste0(p, "_se")),
      q025 = .col_or_na(limbs, paste0(p, "_q025")),
      q50 = .col_or_na(limbs, paste0(p, "_q50")),
      q975 = .col_or_na(limbs, paste0(p, "_q975"))
    )
  }
  out <- rbindlist(lapply(c("C", "a", "n"), one))
  out[order(out$limb, match(out$parameter, c("C", "a", "n")))]
}

method(rating_coefficients, FlodeRatingTable) <- function(x) {
  tbl <- x@table
  one <- function(p) {
    data.table(
      limb = seq_len(nrow(tbl)), parameter = p, estimate = tbl[[p]],
      unit = .coefficient_units[[p]], se_asymptotic = NA_real_, se_bootstrap = NA_real_,
      q025 = NA_real_, q50 = NA_real_, q975 = NA_real_
    )
  }
  out <- rbindlist(lapply(c("C", "a", "n"), one))
  out[order(out$limb, match(out$parameter, c("C", "a", "n")))]
}

method(rating_coefficients, FlodeSegmentedRating) <- function(x) {
  coefs <- x@coefficients
  k <- x@n_segments
  params <- c("C", as.vector(rbind(sprintf("bp%d", seq_len(k)), sprintf("n%d", seq_len(k)))))
  params <- params[params %in% names(coefs)]
  unit_of <- function(p) if (p == "C") "cms per m^n1" else if (grepl("^bp", p)) "m" else "1"
  data.table(
    limb = NA_integer_, parameter = params, estimate = vapply(params, function(p) coefs[[p]][1L], numeric(1)),
    unit = vapply(params, unit_of, character(1)), se_asymptotic = NA_real_, se_bootstrap = NA_real_,
    q025 = NA_real_, q50 = NA_real_, q975 = NA_real_
  )
}

# ---------------------------------------------------------------------------
# rating_evidence
# ---------------------------------------------------------------------------

#' The gaugings a rating was fitted to
#'
#' @description
#' The evidence behind a fit: one row per gauging, as it was used. For a
#' fit made with `age_halflife`, the recency weight each gauging received
#' is included.
#'
#' @param x A [FlodeRating] or [FlodeSegmentedRating]. A
#'   [FlodeRatingTable] holds equations only and has no gaugings.
#'
#' @return A data.table with `gauging_datetime` (when the fit was given
#'   one), `stage_m`, `discharge_cms`, `limb` (the limb each gauging fell
#'   in, for a [FlodeRating]) and `age_weight` (when recency weighting
#'   was used). A copy.
#'
#' @seealso [rating_support()], [flag_influential_gaugings()]
#'
#' @examples
#' set.seed(1)
#' stage_m <- seq(0.5, 2.5, by = 0.05)
#' discharge_cms <- 5 * stage_m^1.6 + rnorm(length(stage_m), sd = 0.02)
#' fit <- rate_optimise(discharge_cms, stage_m)
#' head(rating_evidence(fit))
#'
#' @export
rating_evidence <- new_generic("rating_evidence", "x", function(x) S7_dispatch())

method(rating_evidence, class_any) <- function(x) .accessor_not_a_rating("rating_evidence", x)

.evidence_table <- function(gaugings) {
  g <- copy(gaugings)
  first <- intersect(c(names(.evidence_columns), "limb", "age_weight"), names(g))
  setcolorder(g, c(first, setdiff(names(g), first)))
  g[]
}

method(rating_evidence, FlodeRating) <- function(x) .evidence_table(x@gaugings)
method(rating_evidence, FlodeSegmentedRating) <- function(x) .evidence_table(x@gaugings)

method(rating_evidence, FlodeRatingTable) <- function(x) {
  .accessor_not_held(
    "rating_evidence", x, "holds equations only, with no gaugings",
    "Use a fit from rate_optimise() or rate_optimise_segmented() to see its gaugings."
  )
}

# ---------------------------------------------------------------------------
# rating_diagnostics
# ---------------------------------------------------------------------------

#' Fit diagnostics of a rating
#'
#' @description
#' How well each limb fits its gaugings and how the fit was found: error
#' measures, the number of gaugings, multi-start and bootstrap
#' bookkeeping, and whether an exponent sits on a bound.
#'
#' @param x A [FlodeRating] or [FlodeSegmentedRating]. A
#'   [FlodeRatingTable] holds equations only and has no fit.
#'
#' @return A data.table, one row per limb for a [FlodeRating] and a single
#'   row for a [FlodeSegmentedRating]. For a [FlodeRating]: `limb`,
#'   `rmse_cms` (cumecs), `rmse_pct`, `r_squared`, `n_obs`,
#'   `n_unique_stage`, `mean_error_cms`, `median_abs_error_cms`,
#'   `max_abs_error_cms`, `residual_df`, `n_starts_attempted`,
#'   `n_starts_converged`, `selected_start_id`, `near_bound`,
#'   `n_boot_requested`, `n_boot_success`, `n_boot_failed` and
#'   `boot_success_fraction`; columns the fit did not produce are left
#'   out. For a [FlodeSegmentedRating]: `n_segments`, `rmse_cms`,
#'   `r_squared`, `n_obs` and the multi-start columns.
#'
#' @seealso [rating_coefficients()], [rating_support()]
#'
#' @examples
#' set.seed(1)
#' stage_m <- seq(0.5, 2.5, by = 0.05)
#' discharge_cms <- 5 * stage_m^1.6 + rnorm(length(stage_m), sd = 0.02)
#' fit <- rate_optimise(discharge_cms, stage_m)
#' rating_diagnostics(fit)
#'
#' @export
rating_diagnostics <- new_generic("rating_diagnostics", "x", function(x) S7_dispatch())

method(rating_diagnostics, class_any) <- function(x) .accessor_not_a_rating("rating_diagnostics", x)

.diagnostic_columns <- c(
  "rmse_cms", "rmse_pct", "r_squared", "n_obs", "n_unique_stage", "mean_error_cms",
  "median_abs_error_cms", "max_abs_error_cms", "residual_df", "n_starts_attempted",
  "n_starts_converged", "selected_start_id", "near_bound",
  "converged", "convergence_code", "convergence_message", "iterations", "objective_value",
  "bound_hits", "multi_start_spread", "parameter_correlation", "condition_number",
  "n_boot_requested", "n_boot_success", "n_boot_failed", "boot_success_fraction"
)

method(rating_diagnostics, FlodeRating) <- function(x) {
  limbs <- x@limbs
  keep <- intersect(.diagnostic_columns, names(limbs))
  out <- limbs[, keep, with = FALSE]
  out <- cbind(data.table(limb = as.integer(limbs$limb)), out)
  out[]
}

method(rating_diagnostics, FlodeSegmentedRating) <- function(x) {
  coefs <- x@coefficients
  keep <- intersect(c("rmse_cms", "r_squared", "n_obs", "n_starts_attempted", "n_starts_converged",
                      "selected_start_id"), names(coefs))
  cbind(data.table(n_segments = x@n_segments), coefs[, keep, with = FALSE])[]
}

method(rating_diagnostics, FlodeRatingTable) <- function(x) {
  .accessor_not_held(
    "rating_diagnostics", x, "holds equations only, with no fit to diagnose",
    "Use a fit from rate_optimise() or rate_optimise_segmented()."
  )
}

# ---------------------------------------------------------------------------
# rating_history
# ---------------------------------------------------------------------------

#' The audit chain of a rating
#'
#' @description
#' Where a rating came from. A fit or table that was produced by amending
#' an earlier one (for example by [align_limb_equations()] or
#' [graft_rating()]) keeps the exact earlier object, and that one may
#' keep another. This lists the whole chain, oldest first, so the steps
#' between a first fit and the rating in use can be read off.
#'
#' @param x A [FlodeRating], [FlodeSegmentedRating] or [FlodeRatingTable].
#'
#' @return A data.table with one row per step, oldest first: `step`
#'   (1 is the earliest), `class`, `status` and `n_limbs` (the number of
#'   segments for a [FlodeSegmentedRating]). The last row is `x` itself. A
#'   rating with no earlier version has one row.
#'
#' @seealso [rating_provenance()]
#'
#' @examples
#' table <- FlodeRatingTable(table = data.table::data.table(
#'   lower_level = c(0, 1), upper_level = c(1, 3), C = c(2, 2.5), a = 0, n = 1.5
#' ))
#' aligned <- align_limb_equations(table)
#' rating_history(aligned)
#'
#' @export
rating_history <- new_generic("rating_history", "x", function(x) S7_dispatch())

method(rating_history, class_any) <- function(x) .accessor_not_a_rating("rating_history", x)

.history_step <- function(x) {
  n_limbs <- if (S7_inherits(x, FlodeRating)) nrow(x@limbs)
    else if (S7_inherits(x, FlodeSegmentedRating)) as.integer(x@n_segments)
    else nrow(x@table)
  fb <- if (!S7_inherits(x, FlodeRatingTable)) x@provenance$constrained_fallbacks else NULL
  note <- if (!is.null(fb) && nrow(fb)) {
    sprintf("%s kept the unconstrained fit: %s", .limbs_text(fb$limb), paste(unique(fb$reason), collapse = "; "))
  } else NA_character_
  # A note recorded when a rating was amended (for example, operational limits
  # set) belongs to the step that introduced it. Later amendments copy the
  # provenance, so show it only where it differs from the step before.
  if (is.na(note) && !S7_inherits(x, FlodeRatingTable) && !is.null(x@provenance$amendment_note)) {
    before <- if (!is.null(x@previous) && !S7_inherits(x@previous, FlodeRatingTable)) x@previous@provenance$amendment_note else NULL
    if (!identical(before, x@provenance$amendment_note)) note <- x@provenance$amendment_note
  }
  data.table(class = .rating_class_label(x), fit_origin = x@fit_origin, lifecycle = x@lifecycle,
             n_limbs = as.integer(n_limbs), note = note)
}

.rating_history <- function(x) {
  chain <- list(x)
  node <- x@previous
  while (!is.null(node)) {
    chain[[length(chain) + 1L]] <- node
    node <- node@previous
  }
  steps <- rbindlist(lapply(rev(chain), .history_step))
  cbind(data.table(step = seq_len(nrow(steps))), steps)[]
}

method(rating_history, FlodeRating) <- function(x) .rating_history(x)
method(rating_history, FlodeSegmentedRating) <- function(x) .rating_history(x)
method(rating_history, FlodeRatingTable) <- function(x) .rating_history(x)

# ---------------------------------------------------------------------------
# rating_provenance
# ---------------------------------------------------------------------------

#' How a rating was made
#'
#' @description
#' The settings and versions recorded when a fit was made: the equation,
#' the fitting method and objective, bounds on the exponent, whether
#' multi-start and bootstrap were used, any recency weighting, and the
#' package version. Use it to say exactly how a rating was produced.
#'
#' @param x A [FlodeRating], [FlodeSegmentedRating] or [FlodeRatingTable].
#'
#' @return A list. For a fit, its recorded provenance, a copy. A
#'   [FlodeRatingTable] was not fitted by this package, so it records only
#'   `status` and `has_previous` (whether an earlier version is kept; see
#'   [rating_history()]).
#'
#' @seealso [rating_history()]
#'
#' @examples
#' set.seed(1)
#' stage_m <- seq(0.5, 2.5, by = 0.05)
#' discharge_cms <- 5 * stage_m^1.6 + rnorm(length(stage_m), sd = 0.02)
#' fit <- rate_optimise(discharge_cms, stage_m)
#' str(rating_provenance(fit)[c("fitting_equation", "objective", "tool_version")])
#'
#' @export
rating_provenance <- new_generic("rating_provenance", "x", function(x) S7_dispatch())

method(rating_provenance, class_any) <- function(x) .accessor_not_a_rating("rating_provenance", x)

.provenance_with_state <- function(x) {
  c(x@provenance, list(fit_origin = x@fit_origin, lifecycle = x@lifecycle, schema_version = x@schema_version))
}

method(rating_provenance, FlodeRating) <- function(x) .provenance_with_state(x)
method(rating_provenance, FlodeSegmentedRating) <- function(x) .provenance_with_state(x)

method(rating_provenance, FlodeRatingTable) <- function(x) {
  list(fit_origin = x@fit_origin, lifecycle = x@lifecycle, schema_version = x@schema_version, has_previous = !is.null(x@previous))
}

# ---------------------------------------------------------------------------
# rating_support
# ---------------------------------------------------------------------------

#' What a rating rests on
#'
#' @description
#' The stage ranges a rating rests on, and which of them are evidence and
#' which are decision. There are five:
#'
#' * **observed**: the stage range of the gaugings (evidence of source type
#'   `gauging`), with how many there are;
#' * **modelled**: the stage range of evidence that is not a measurement (a
#'   modelled value, a cross-section or structure computation, or a point read
#'   off another rating);
#' * **fitted**: the stage range the equations are declared over, which can be
#'   wider than the evidence after [extend_rating_low()] or [graft_rating()];
#' * **operational**: the range the rating may be used over, if stated (see
#'   [set_operational_limits()]); `NA` if not;
#' * **numerical**: where the equations give a finite discharge. Beyond it
#'   [apply_rating()] fails.
#'
#' [apply_rating()] uses the same ranges to say, for every stage it
#' computes, how well supported that stage is (its `support` column).
#'
#' With `by = "limb"` it gives instead how much of each limb rests on
#' gaugings: how many fall inside it, the stage range they cover, and how far
#' the limb extends beyond them at either end. A limb that stretches well past
#' its highest gauging is an extrapolation there, whatever its fit statistics
#' say.
#'
#' @param x A [FlodeRating], [FlodeSegmentedRating] or [FlodeRatingTable].
#'   A table holds equations only, so it has no observed or modelled range.
#' @param by `"range"` (default) for the five ranges, or `"limb"` for the
#'   per-limb table. `"limb"` needs gaugings, so a [FlodeRatingTable] is
#'   refused.
#'
#' @return With `by = "range"`, a data.table of five rows with `range`,
#'   `lower_stage_m`, `upper_stage_m`, `n_evidence` (gaugings or modelled
#'   points, `NA` for the ranges that are not evidence) and `basis`, a
#'   sentence on what the range is. A range that does not exist is `NA`.
#'
#'   With `by = "limb"`, for a [FlodeRating], one row per limb: `limb`,
#'   `lower_stage_m`, `upper_stage_m`, `n_gaugings`, `gauged_min_stage_m`,
#'   `gauged_max_stage_m`, `lower_unsupported_m` and `upper_unsupported_m`
#'   (how far the limb extends below its lowest and above its highest
#'   gauging, m), and the same as a fraction of the limb's width,
#'   `lower_unsupported_frac` and `upper_unsupported_frac`. A limb with no
#'   gaugings has `n_gaugings` 0 and `NA` elsewhere. For a
#'   [FlodeSegmentedRating], one row with `n_gaugings`, `gauged_min_stage_m`
#'   and `gauged_max_stage_m`.
#'
#' @seealso [apply_rating()] for the `support` column; [set_operational_limits()];
#'   [flag_extrapolated_limbs()], which the support classes supersede;
#'   [rating_evidence()]
#'
#' @examples
#' set.seed(1)
#' stage_m <- seq(0.5, 2.5, by = 0.05)
#' discharge_cms <- 5 * stage_m^1.6 + rnorm(length(stage_m), sd = 0.02)
#' fit <- rate_optimise(discharge_cms, stage_m)
#' rating_support(fit)
#' rating_support(fit, by = "limb")
#'
#' @export
rating_support <- new_generic("rating_support", "x", function(x, by = "range") S7_dispatch())

method(rating_support, class_any) <- function(x, by = "range") .accessor_not_a_rating("rating_support", x)

.support_by_limb_fit <- function(x) {
  limbs <- x@limbs
  g <- x@gaugings
  n_limbs <- nrow(limbs)
  out <- data.table(
    limb = as.integer(limbs$limb), lower_stage_m = limbs$lower_stage_m,
    upper_stage_m = limbs$upper_stage_m, n_gaugings = 0L,
    gauged_min_stage_m = NA_real_, gauged_max_stage_m = NA_real_
  )
  for (i in seq_len(n_limbs)) {
    on_limb <- g$stage_m[g$limb == limbs$limb[i]]
    on_limb <- on_limb[!is.na(on_limb)]
    if (length(on_limb)) {
      set(out, i, "n_gaugings", length(on_limb))
      set(out, i, "gauged_min_stage_m", min(on_limb))
      set(out, i, "gauged_max_stage_m", max(on_limb))
    }
  }
  width <- out$upper_stage_m - out$lower_stage_m
  out[, "lower_unsupported_m" := pmax(out$gauged_min_stage_m - out$lower_stage_m, 0)]
  out[, "upper_unsupported_m" := pmax(out$upper_stage_m - out$gauged_max_stage_m, 0)]
  out[, "lower_unsupported_frac" := out$lower_unsupported_m / width]
  out[, "upper_unsupported_frac" := out$upper_unsupported_m / width]
  out[]
}

.support_by_limb_segmented <- function(x) {
  s <- x@gaugings$stage_m
  s <- s[!is.na(s)]
  data.table(
    n_gaugings = length(s),
    gauged_min_stage_m = if (length(s)) min(s) else NA_real_,
    gauged_max_stage_m = if (length(s)) max(s) else NA_real_
  )
}

method(rating_support, FlodeRating) <- function(x, by = "range") {
  by <- match.arg(by, c("range", "limb"))
  if (by == "limb") .support_by_limb_fit(x) else .support_ranges(x)
}

method(rating_support, FlodeSegmentedRating) <- function(x, by = "range") {
  by <- match.arg(by, c("range", "limb"))
  if (by == "limb") .support_by_limb_segmented(x) else .support_ranges(x)
}

method(rating_support, FlodeRatingTable) <- function(x, by = "range") {
  by <- match.arg(by, c("range", "limb"))
  if (by == "limb") {
    .accessor_not_held(
      "rating_support", x, "holds equations only, with no gaugings to measure support against",
      "Use a fit from rate_optimise() or rate_optimise_segmented(), or ask for by = \"range\"."
    )
  }
  .support_ranges(x)
}

# ---------------------------------------------------------------------------
# rating_bootstrap
# ---------------------------------------------------------------------------

#' Bootstrap draws of a rating
#'
#' @description
#' The per-draw coefficients from a fit made with `n_boot > 0`: one row
#' per draw and limb, with the limb's stage range alongside, in the shape
#' [apply_rating_interval()] takes. Replaces [bootstrap_to_table()].
#'
#' @param x A [FlodeRating] fitted with `rate_optimise(..., n_boot = )`.
#'   The other rating classes carry no bootstrap.
#' @param successful_only Logical. Drop draws that failed or were
#'   rejected (default `TRUE`). With `FALSE` every requested draw is
#'   returned, with `success` and `reason` columns saying what became of
#'   it; a failed draw has `NA` coefficients.
#'
#' @return A data.table with `limb`, `draw`, `lower_stage_m`,
#'   `upper_stage_m`, `C`, `a` and `n` (plus `success` and `reason` when
#'   `successful_only = FALSE`). Errors, saying how to get one, if the fit
#'   has no bootstrap draws or none succeeded.
#'
#' @seealso [apply_rating_interval()], [rating_coefficients()]
#'
#' @examples
#' set.seed(1)
#' stage_m <- seq(0.5, 2.5, by = 0.05)
#' discharge_cms <- 5 * stage_m^1.6 + rnorm(length(stage_m), sd = 0.02)
#' fit <- rate_optimise(discharge_cms, stage_m, n_boot = 50L, boot_seed = 1L)
#' head(rating_bootstrap(fit))
#'
#' @export
rating_bootstrap <- new_generic("rating_bootstrap", "x", function(x, successful_only = TRUE) S7_dispatch())

method(rating_bootstrap, class_any) <- function(x, successful_only = TRUE) .accessor_not_a_rating("rating_bootstrap", x)

method(rating_bootstrap, FlodeRating) <- function(x, successful_only = TRUE) {
  boot <- x@bootstrap
  if (is.null(boot)) {
    stop("rating_bootstrap(): this fit has no bootstrap draws. Fit with rate_optimise(..., n_boot = <n>) first.",
         call. = FALSE)
  }
  ok <- boot[boot$success == TRUE]
  if (successful_only && nrow(ok) == 0L) {
    stop("rating_bootstrap(): this fit has no successful bootstrap draws; every draw failed or was rejected. ",
         "Use successful_only = FALSE to see why.", call. = FALSE)
  }
  rows <- if (successful_only) ok else boot
  bounds <- data.table(limb = x@limbs$limb, lower_stage_m = x@limbs$lower_stage_m,
                       upper_stage_m = x@limbs$upper_stage_m)
  out <- merge(rows, bounds, by = "limb")
  keep <- c("limb", "draw", "lower_stage_m", "upper_stage_m", "C", "a", "n",
            if (!successful_only) c("success", "reason"))
  out <- out[, keep, with = FALSE]
  out[order(out$limb, out$draw)]
}

method(rating_bootstrap, FlodeSegmentedRating) <- function(x, successful_only = TRUE) {
  .accessor_not_held(
    "rating_bootstrap", x, "carries no bootstrap draws",
    "Only rate_optimise(..., n_boot = <n>) produces them."
  )
}

method(rating_bootstrap, FlodeRatingTable) <- function(x, successful_only = TRUE) {
  .accessor_not_held(
    "rating_bootstrap", x, "holds equations only, with no bootstrap draws",
    "Only rate_optimise(..., n_boot = <n>) produces them."
  )
}
