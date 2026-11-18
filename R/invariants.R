# ============================================================ #
# Tool:         invariants
# Description:  Post-fit invariants (tranche A8). A fixed set of checks on a
#               rating's own equations, returned as a FlodeAssessment and
#               used to refuse to apply a rating that is mathematically
#               unusable. Technical checks can fail and block application;
#               hydrometric checks only warn.
# Author:       Jonathan Payne
# Created:      2026-11-18
# Tier:         3
# Inputs:       A FlodeRating, FlodeSegmentedRating or FlodeRatingTable.
# Outputs:      A FlodeAssessment (rating_invariants()).
# Dependencies: data.table
# ============================================================ #

#' @include flode_classes.R flode_assessment.R accessors.R
NULL

# Number of stages per limb at which the equation is evaluated.
.invariant_grid_n <- 25L

# The equations of a rating as the kernel's columns, sorted by stage, or
# NULL when a segmented rating has no such table.
.invariant_table <- function(x) {
  tbl <- if (S7_inherits(x, FlodeRating)) {
    tryCatch(as_rating_table(x)@table, error = function(e) NULL)
  } else if (S7_inherits(x, FlodeRatingTable)) {
    x@table
  } else {
    NULL
  }
  if (is.null(tbl)) return(NULL)
  tbl <- copy(as.data.table(tbl))
  setorder(tbl, lower_level)
  tbl[]
}

# Discharge by the equation, with zero at or below the offset, matching
# apply_rating(). Vectorised over stage.
.eval_limb <- function(C, a, n, h) ifelse(h <= a, 0, C * (h - a)^n)

# The stages at which a limb is checked: its two ends and points between.
.limb_grid <- function(lower, upper) seq(lower, upper, length.out = .invariant_grid_n)

# ---- the checks --------------------------------------------------------------------
# Each returns a one-row list: check_id, domain, status, message,
# recommendation, affected (limb numbers or NULL). Limb numbers are used in
# the message rather than evidence ids, because these checks are about
# equations, not gaugings.

.inv <- function(check_id, domain, ok, message_ok, message_bad, recommendation = NA_character_,
                 not_assessed = FALSE, blocks = c("forward", "inverse")) {
  status <- if (not_assessed) "not_assessed" else if (ok) "pass" else if (domain == "technical") "fail" else "warning"
  list(check_id = check_id, domain = domain, status = status, blocks = blocks,
       message = if (not_assessed || !ok) message_bad else message_ok,
       recommendation = if (status %in% c("pass")) NA_character_ else recommendation)
}

.limbs_text <- function(idx) {
  paste0(if (length(idx) == 1L) "limb " else "limbs ", paste(idx, collapse = ", "))
}

# Technical checks on an equation table.
.table_technical_checks <- function(tbl) {
  out <- list()
  lo <- tbl$lower_level; up <- tbl$upper_level
  C <- tbl$C; a <- tbl$a; n <- tbl$n
  n_limbs <- nrow(tbl)

  bad_coef <- which(!is.finite(C) | !is.finite(a) | !is.finite(n) | C <= 0 | n <= 0)
  out$coefficients_finite <- .inv(
    "coefficients_finite", "technical", !length(bad_coef),
    "Every C, a and n is finite, and C and n are positive.",
    sprintf("%s: a coefficient is missing or not finite, or C or n is not positive.", .limbs_text(bad_coef)),
    "A rating with such a limb cannot give a meaningful discharge. Refit it, or correct the table."
  )

  bounds_ok <- all(is.finite(lo), is.finite(up)) && all(up > lo)
  sorted_ok <- !is.unsorted(lo)
  contiguous_ok <- n_limbs < 2L || all(abs(up[-n_limbs] - lo[-1L]) < 1e-8, na.rm = TRUE)
  out$limbs_ordered <- .inv(
    "limbs_ordered", "technical", bounds_ok && sorted_ok && contiguous_ok,
    "Limb stage ranges are finite, ascending and contiguous.",
    if (!bounds_ok) "A limb's upper stage is not above its lower stage, or a stage limit is missing."
    else if (!sorted_ok) "Limbs are not in ascending stage order."
    else "Limbs are not contiguous: one limb's upper stage differs from the next limb's lower stage.",
    "Each limb must start where the previous one ends. Correct the stage limits."
  )

  coef_ok <- !length(bad_coef) && bounds_ok
  if (!coef_ok) {
    msg <- "Skipped: the coefficients or stage limits are not usable."
    out$predictions_finite <- .inv("predictions_finite", "technical", NA, "", msg, not_assessed = TRUE)
    out$monotone_discharge <- .inv("monotone_discharge", "technical", NA, "", msg, not_assessed = TRUE)
    out$monotone_across_junctions <- .inv("monotone_across_junctions", "technical", NA, "", msg,
                                          not_assessed = TRUE, blocks = "inverse")
    out$inverse_consistent <- .inv("inverse_consistent", "technical", NA, "", msg,
                                   not_assessed = TRUE, blocks = "inverse")
    return(out)
  }

  grids <- lapply(seq_len(n_limbs), function(i) .limb_grid(lo[i], up[i]))
  q_by_limb <- lapply(seq_len(n_limbs), function(i) .eval_limb(C[i], a[i], n[i], grids[[i]]))
  all_q <- unlist(q_by_limb)
  finite_ok <- all(is.finite(all_q)) && all(all_q >= 0)
  out$predictions_finite <- .inv(
    "predictions_finite", "technical", finite_ok,
    "Discharge is finite and not negative at every stage checked.",
    "Discharge is not finite, or is negative, at some stage within the limbs.",
    "Refit, or check the coefficients: an exponent or offset has produced an impossible value."
  )

  # Non-decreasing across the whole range, junctions included: within each
  # limb, then from the top of one limb to the bottom of the next.
  drops <- unlist(lapply(seq_len(n_limbs), function(i) {
    q <- q_by_limb[[i]]
    tol <- 1e-9 * pmax(1, abs(q[-1L]))
    if (any(diff(q) < -tol, na.rm = TRUE)) i else NULL
  }))
  # What the inverse needs is that the discharge at the top of each limb is
  # no lower than at the top of the one before (the C kernel's own
  # condition), so that every discharge belongs to one limb. A small step at
  # the junction itself does not break that; limb_continuity reports it.
  junction_drops <- integer(0)
  if (n_limbs > 1L) {
    ends <- c(q_by_limb[[1L]][1L], vapply(q_by_limb, function(q) q[length(q)], numeric(1)))
    junction_drops <- which(diff(ends) < 0) - 1L
    junction_drops <- junction_drops[junction_drops >= 1L]
  }
  within_ok <- !length(drops)
  out$monotone_discharge <- .inv(
    "monotone_discharge", "technical", within_ok,
    "Discharge does not decrease as stage rises within any limb.",
    sprintf("Discharge decreases as stage rises within %s.", .limbs_text(drops)),
    "A rating must not fall as stage rises. Refit, or check the exponent and offset."
  )
  # A drop across a junction leaves stage to discharge well defined, so it
  # does not stop apply_rating(). It makes the inverse ambiguous, so it stops
  # apply_rating_inverse(). limb_continuity reports it as a warning too.
  junction_ok <- !length(junction_drops)
  out$monotone_across_junctions <- .inv(
    "monotone_across_junctions", "technical", junction_ok,
    "Discharge at the top of each limb is no lower than at the top of the one before.",
    sprintf("The discharge at the top of limb %s is below that at the top of the limb before, so one discharge corresponds to two stages.",
            paste(junction_drops + 1L, collapse = ", ")),
    "Close the junction with align_limb_equations() or align_limb_boundaries(). The inverse is refused until then.",
    blocks = "inverse"
  )
  mono_ok <- within_ok && junction_ok

  if (!(mono_ok && finite_ok)) {
    out$inverse_consistent <- .inv("inverse_consistent", "technical", NA, "",
      "Skipped: discharge is not finite and non-decreasing, so the inverse is not defined.",
      not_assessed = TRUE, blocks = "inverse")
    return(out)
  }
  probe_h <- unique(unlist(lapply(seq_len(n_limbs), function(i) grids[[i]][-c(1L, .invariant_grid_n)])))
  probe_q <- .eval_limb(C[findInterval(probe_h, c(lo, up[n_limbs]), rightmost.closed = TRUE)],
                        a[findInterval(probe_h, c(lo, up[n_limbs]), rightmost.closed = TRUE)],
                        n[findInterval(probe_h, c(lo, up[n_limbs]), rightmost.closed = TRUE)], probe_h)
  keep <- probe_q > 0
  inverse <- tryCatch(.kernel_inverse(tbl, probe_q[keep]), error = function(e) e)
  if (inherits(inverse, "error")) {
    out$inverse_consistent <- .inv("inverse_consistent", "technical", FALSE, "",
      paste0("The inverse (stage from discharge) could not be evaluated: ", conditionMessage(inverse)),
      "The rating is not single valued. Close the junction, or refit.", blocks = "inverse")
  } else {
    back <- .kernel_forward(tbl, inverse$stage)$discharge
    err <- max(abs(back - probe_q[keep]) / probe_q[keep], na.rm = TRUE)
    out$inverse_consistent <- .inv(
      "inverse_consistent", "technical", is.finite(err) && err < 1e-6,
      "Discharge to stage and back reproduces the discharge.",
      sprintf("Discharge to stage and back differs by up to %.2g (relative).", err),
      "The inverse does not undo the forward rating. Check the coefficients and limb stage limits.",
      blocks = "inverse"
    )
  }
  out
}

# Hydrometric checks on an equation table.
.table_hydrometric_checks <- function(tbl, continuity_tol) {
  out <- list()
  lo <- tbl$lower_level; up <- tbl$upper_level
  n_limbs <- nrow(tbl)
  # Discharge is zero at and below a, so a limb that starts below its own
  # zero-flow stage is a legitimate way to write a table. It is worth a
  # warning because part of the limb then carries no flow.
  above <- if (all(is.finite(tbl$a), is.finite(lo))) which(tbl$a > lo + 1e-9) else integer(0)
  out$domain_valid <- .inv(
    "domain_valid", "hydrometric", !length(above),
    "In every limb the zero-flow stage a is at or below the limb's lower stage, so (H - a) is positive across it.",
    sprintf("%s: the zero-flow stage a lies above the limb's lower stage, so discharge is zero over part of the limb.",
            .limbs_text(above)),
    "Check that this is intended. A limb starting below its own zero-flow stage gives zero discharge there."
  )
  if (n_limbs < 2L) {
    out$stage_gaps_overlaps <- .inv("stage_gaps_overlaps", "hydrometric", TRUE,
      "A single limb has no junction.", "")
    out$limb_continuity <- .inv("limb_continuity", "hydrometric", TRUE,
      "A single limb has no junction to be discontinuous at.", "")
    return(out)
  }
  stage_gap <- lo[-1L] - up[-n_limbs]
  bad <- which(is.finite(stage_gap) & abs(stage_gap) > 1e-8)
  out$stage_gaps_overlaps <- .inv(
    "stage_gaps_overlaps", "hydrometric", !length(bad),
    "No gap or overlap between the stage ranges of adjacent limbs.",
    sprintf("Between %s and the next: %s.", .limbs_text(bad),
            paste(ifelse(stage_gap[bad] > 0, "a gap in stage", "an overlap in stage"), collapse = "; ")),
    "Stages in a gap have no equation; stages in an overlap have two. Make the limbs meet."
  )
  jn <- tryCatch(.kernel_junctions(tbl), error = function(e) NULL)
  if (is.null(jn)) {
    out$limb_continuity <- .inv("limb_continuity", "hydrometric", NA, "",
      "Skipped: the junctions could not be evaluated.", not_assessed = TRUE)
  } else {
    rel <- abs(jn$above - jn$below) / pmax(abs(jn$below), 1e-9)
    flagged <- which(is.na(rel) | rel > continuity_tol)
    out$limb_continuity <- .inv(
      "limb_continuity", "hydrometric", !length(flagged),
      sprintf("Discharge is continuous across every junction, within %g%%.", 100 * continuity_tol),
      sprintf("Discharge jumps by more than %g%% at the junction above %s (largest: %.3g%%).",
              100 * continuity_tol, .limbs_text(flagged), 100 * max(rel[flagged], na.rm = TRUE)),
      "A jump gives two discharges for one stage. Close it with align_limb_equations() or align_limb_boundaries()."
    )
  }
  out
}

# Technical checks on a segmented fit's joint equation.
.segmented_technical_checks <- function(x) {
  out <- list()
  co <- as.list(x@coefficients)
  k <- as.integer(x@n_segments)
  bp <- unlist(co[sprintf("bp%d", seq_len(k))])
  nn <- unlist(co[sprintf("n%d", seq_len(k))])
  coef_ok <- is.finite(co$C) && co$C > 0 && all(is.finite(bp)) && all(is.finite(nn))
  out$coefficients_finite <- .inv(
    "coefficients_finite", "technical", coef_ok,
    "C, every breakpoint and every exponent is finite, and C is positive.",
    "A coefficient is missing or not finite, or C is not positive.",
    "Refit the rating.")
  ordered <- length(bp) < 2L || (all(is.finite(bp)) && !is.unsorted(bp, strictly = TRUE))
  out$limbs_ordered <- .inv(
    "limbs_ordered", "technical", ordered,
    "The breakpoints are in strictly ascending order.",
    "The breakpoints are not in strictly ascending order.",
    "Breakpoints must increase: bp1 < bp2 < ...")
  stage <- x@gaugings$stage_m
  if (!coef_ok || !ordered) {
    msg <- "Skipped: the coefficients or breakpoints are not usable."
    out$predictions_finite <- .inv("predictions_finite", "technical", NA, "", msg, not_assessed = TRUE)
    out$monotone_discharge <- .inv("monotone_discharge", "technical", NA, "", msg, not_assessed = TRUE)
    return(out)
  }
  grid <- seq(min(stage), max(stage), length.out = 4L * .invariant_grid_n)
  q <- .segmented_predict_cms(co, k, grid)
  out$predictions_finite <- .inv(
    "predictions_finite", "technical", all(is.finite(q)) && all(q >= 0),
    "Discharge is finite and not negative across the gauged range.",
    "Discharge is not finite, or is negative, within the gauged range.", "Refit the rating.")
  out$monotone_discharge <- .inv(
    "monotone_discharge", "technical", !any(diff(q) < -1e-9 * pmax(1, abs(q[-1L])), na.rm = TRUE),
    "Discharge does not decrease as stage rises across the gauged range.",
    "Discharge decreases as stage rises somewhere in the gauged range.",
    "A rating must not fall as stage rises. Refit, or constrain the exponents.")
  out
}

# Checks that need the fit and not just its equations.
.fit_only_checks <- function(x) {
  out <- list()
  limbs <- x@limbs
  q_cols <- c("C_q025", "C_q50", "C_q975", "a_q025", "a_q50", "a_q975", "n_q025", "n_q50", "n_q975")
  if (all(q_cols %in% names(limbs)) && any(!is.na(limbs$C_q50))) {
    ord <- function(p) {
      lo <- limbs[[paste0(p, "_q025")]]; mid <- limbs[[paste0(p, "_q50")]]; hi <- limbs[[paste0(p, "_q975")]]
      which(!is.na(lo) & !is.na(mid) & !is.na(hi) & (lo > mid | mid > hi))
    }
    bad <- sort(unique(c(ord("C"), ord("a"), ord("n"))))
    out$interval_ordering <- .inv(
      "interval_ordering", "technical", !length(bad),
      "The bootstrap lower, median and upper bounds are in order for every parameter.",
      sprintf("%s: a bootstrap lower bound is above the median, or the median above the upper bound.", .limbs_text(bad)),
      "Rerun the bootstrap; percentiles of one set of draws cannot be out of order.")
  } else {
    out$interval_ordering <- .inv("interval_ordering", "technical", NA, "",
      "No bootstrap draws, so interval ordering could not be checked.", not_assessed = TRUE)
  }

  g <- x@gaugings
  prov_bounds <- x@provenance$n_bounds
  if (identical(x@fit_origin, "independently_fitted") && "limb" %in% names(g) && nrow(g) > 0L &&
      all(c("C", "a", "n", "limb") %in% names(limbs))) {
    min_stage <- g[, .(m = min(stage_m)), by = limb]
    m <- min_stage$m[match(limbs$limb, min_stage$limb)]
    bad <- which(
      limbs$C < 1e-6 - 1e-12 | limbs$n < 1e-6 - 1e-12 | limbs$a > m - 1e-6 + 1e-9 |
        (!is.null(prov_bounds) & (limbs$n < prov_bounds[1] - 1e-9 | limbs$n > prov_bounds[2] + 1e-9))
    )
    bad <- bad[!is.na(bad)]
    out$bounds_respected <- .inv(
      "bounds_respected", "technical", !length(bad),
      "Every fitted parameter lies inside the bounds the fit was given.",
      sprintf("%s: a fitted parameter lies outside the bounds it was fitted within.", .limbs_text(bad)),
      "The fit and its bounds disagree. Refit; a coefficient outside its bounds was not produced by the optimiser.")
  } else {
    out$bounds_respected <- .inv("bounds_respected", "technical", NA, "",
      "Bounds are only checked for a fit made directly by the optimiser; an amended rating has been changed since.",
      not_assessed = TRUE)
  }
  out
}

# All results for a rating, as a list of one-row lists. `which = "technical"`
# runs only the technical checks, which is all the gate on apply_rating()
# needs and is quicker than building the full assessment.
.invariant_results <- function(x, which = c("all", "technical"), continuity_tol = 0.01) {
  which <- match.arg(which)
  if (S7_inherits(x, FlodeSegmentedRating)) {
    res <- .segmented_technical_checks(x)
    if (which == "all") {
      res$limb_continuity <- .inv("limb_continuity", "hydrometric", TRUE,
        "Continuous by construction: every later factor of the joint equation equals 1 at its breakpoint.", "")
    }
    return(unname(res))
  }
  tbl <- .invariant_table(x)
  if (is.null(tbl)) stop("rating invariants: x must be a FlodeRating, FlodeSegmentedRating or FlodeRatingTable", call. = FALSE)
  res <- .table_technical_checks(tbl)
  # The fit's own technical checks (bootstrap interval order, parameter
  # bounds) are part of the gate too: they are things only the fit can show.
  if (S7_inherits(x, FlodeRating)) res <- c(res, .fit_only_checks(x))
  if (which == "all") res <- c(res, .table_hydrometric_checks(tbl, continuity_tol))
  unname(res)
}

# One FlodeAssessment from the results.
.invariant_assessment <- function(x, continuity_tol = 0.01) {
  res <- .invariant_results(x, "all", continuity_tol)
  rows <- lapply(res, function(r) .check_row(r$check_id, r$domain, r$status, r$message, r$recommendation))
  n_units <- if (S7_inherits(x, FlodeRatingTable)) nrow(x@table)
    else if (S7_inherits(x, FlodeRating)) nrow(x@limbs) else as.integer(x@n_segments)
  FlodeAssessment(checks = rbindlist(rows), subject = "rating", assessed_rows = as.integer(n_units))
}

# The gate. A rating that fails a technical invariant is not applied: the
# equations cannot give a meaningful discharge, and a number from them
# would look like any other. The error says which checks failed and what
# to do next.
.require_valid_rating <- function(x, fn, operation = c("forward", "inverse")) {
  operation <- match.arg(operation)
  res <- .invariant_results(x, "technical")
  failed <- Filter(function(r) identical(r$status, "fail") && operation %in% r$blocks, res)
  if (!length(failed)) return(invisible(TRUE))
  stop(sprintf(
    paste0("%s: this rating fails %d post-fit check%s and will not be applied.\n%s\n",
           "A number computed from a rating that fails these checks would look like any other. ",
           "Read the full list with rating_invariants(x), then correct the rating or refit it."),
    fn, length(failed), if (length(failed) == 1L) "" else "s",
    paste(sprintf("  - %s: %s", vapply(failed, `[[`, "", "check_id"), vapply(failed, `[[`, "", "message")), collapse = "\n")
  ), call. = FALSE)
}

#' Post-fit invariants of a rating
#'
#' @description
#' Checks a rating's own equations, as a [FlodeAssessment], without
#' reference to the gaugings it was fitted to. It answers whether the
#' equations are mathematically usable. It does not say whether the rating
#' is a good one; that is for [validate_gaugings()] and, later, a full
#' assessment.
#'
#' **Technical checks** can fail:
#'
#' * `coefficients_finite`: every `C`, `a` and `n` is finite, and `C` and `n`
#'   are positive;
#' * `limbs_ordered`: stage ranges are finite, ascending and contiguous (for a
#'   segmented fit, the breakpoints strictly ascend);
#' * `predictions_finite`: discharge is finite and not negative at 25 stages
#'   in each limb;
#' * `monotone_discharge`: discharge does not decrease as stage rises within a
#'   limb;
#' * `monotone_across_junctions`: the discharge at the top of each limb is no
#'   lower than at the top of the limb before, so each discharge belongs to
#'   one limb (blocks the inverse only);
#' * `inverse_consistent`: discharge to stage and back reproduces the
#'   discharge to within 1e-6 (blocks the inverse only);
#' * `interval_ordering` (a fit with bootstrap draws): for every parameter the
#'   lower, median and upper bootstrap bounds are in order;
#' * `bounds_respected` (a fit made directly by the optimiser): each fitted
#'   parameter is inside the bounds it was given.
#'
#' **Hydrometric checks** can warn:
#'
#' * `domain_valid`: in each limb the zero-flow stage `a` is not above the
#'   limb's lower stage. Discharge is zero at and below `a`, so a limb that
#'   starts below it is legitimate, but part of it then carries no flow;
#' * `stage_gaps_overlaps`: no gap or overlap between adjacent limbs' stage
#'   ranges;
#' * `limb_continuity`: discharge is continuous across each junction, within
#'   `continuity_tol`.
#'
#' A check that cannot be run is `not_assessed`, never `pass`.
#'
#' **A rating that fails a technical check is not applied.** A failure stops
#' the operation it makes meaningless, and says which check failed, because a
#' number from such a rating would look like any other. [apply_rating()]
#' stops for any failure except the two marked as blocking the inverse only;
#' [apply_rating_inverse()] stops for every failure. A drop in discharge at
#' a junction, for example, leaves stage to discharge well defined but makes
#' the inverse ambiguous. Warnings never block. The invariants are evaluated when asked for, so
#' they always describe the rating as it now stands, including after any
#' change to it.
#'
#' @param x A [FlodeRating], [FlodeSegmentedRating] or [FlodeRatingTable].
#' @param continuity_tol Number. The relative jump in discharge at a
#'   junction above which `limb_continuity` warns. Default 0.01.
#'
#' @return A [FlodeAssessment] with subject `"rating"`, one row per check.
#'
#' @seealso [FlodeAssessment], [assessment_checks()], [validate_gaugings()],
#'   `vignette("mathematical_contract")`
#'
#' @examples
#' set.seed(1)
#' stage_m <- seq(0.4, 3, by = 0.05)
#' discharge_cms <- 3.2 * stage_m^1.6 * exp(rnorm(length(stage_m), sd = 0.03))
#' fit <- rate_optimise(discharge_cms, stage_m, control = 1.5)
#' rating_invariants(fit)
#'
#' # A rating that cannot be applied: its exponent is negative.
#' broken <- FlodeRatingTable(table = data.table::data.table(
#'   lower_level = 0, upper_level = 3, C = 2, a = 0, n = -1
#' ))
#' assessment_checks(rating_invariants(broken))[status == "fail", .(check_id, message)]
#'
#' @export
rating_invariants <- function(x, continuity_tol = 0.01) {
  if (!is.numeric(continuity_tol) || length(continuity_tol) != 1L || is.na(continuity_tol) || continuity_tol < 0) {
    stop("rating_invariants(): continuity_tol must be a single non-negative number", call. = FALSE)
  }
  if (!(S7_inherits(x, FlodeRatingBase) || S7_inherits(x, FlodeRatingTable))) {
    stop("rating_invariants(): x must be a FlodeRating, FlodeSegmentedRating or FlodeRatingTable, not ",
         paste(class(x)[1L]), call. = FALSE)
  }
  .invariant_assessment(x, continuity_tol)
}

# The two lines a rating prints about its state: whether the optimiser
# converged, and whether the equations pass the invariants. Kept separate
# because they answer different questions: a fit can converge to an invalid
# equation, and a valid equation can come from a fit that did not converge.
.state_lines <- function(x) {
  conv <- if (S7_inherits(x, FlodeRating) && "converged" %in% names(x@limbs) && !all(is.na(x@limbs$converged))) {
    n_ok <- sum(x@limbs$converged %in% TRUE); n <- nrow(x@limbs)
    if (n_ok == n) sprintf("yes (%d of %d limb%s)", n_ok, n, if (n == 1L) "" else "s")
    else sprintf("no (limb%s %s: %s)", if (n - n_ok == 1L) "" else "s",
                 paste(which(!(x@limbs$converged %in% TRUE)), collapse = ", "),
                 sub("\\s+$", "", x@limbs$convergence_message[which(!(x@limbs$converged %in% TRUE))[1L]]))
  } else if (S7_inherits(x, FlodeSegmentedRating) && isTRUE(!is.na(x@coefficients$converged))) {
    if (isTRUE(x@coefficients$converged)) "yes" else sprintf("no (%s)", sub("\\s+$", "", x@coefficients$convergence_message))
  } else {
    "not assessed (no optimiser record for this rating)"
  }
  res <- tryCatch(.invariant_results(x, "all"), error = function(e) NULL)
  valid <- if (is.null(res)) {
    "not assessed"
  } else {
    fails <- vapply(Filter(function(r) identical(r$status, "fail"), res), `[[`, "", "check_id")
    warns <- vapply(Filter(function(r) identical(r$status, "warning"), res), `[[`, "", "check_id")
    if (length(fails)) sprintf("no (fails: %s)", paste(fails, collapse = ", "))
    else if (length(warns)) sprintf("yes, with %d warning%s (%s)", length(warns), if (length(warns) == 1L) "" else "s", paste(warns, collapse = ", "))
    else "yes"
  }
  c(sprintf("  converged: %s", conv), sprintf("  valid: %s", valid))
}
