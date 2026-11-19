# ============================================================ #
# Tool:         sensitivity
# Description:  How much a rating's discharge depends on the choices and the
#               data behind it (tranche B4): leaving out each gauging, the
#               highest gaugings, the starting values, and moving a
#               breakpoint. The consequence is reported in discharge, at
#               stated stages, and linked to the evidence ids concerned.
# Author:       Jonathan Payne
# Created:      2026-11-18
# Tier:         3
# Inputs:       A FlodeRating or FlodeSegmentedRating fitted from evidence.
# Outputs:      A FlodeSensitivity.
# Dependencies: data.table
# ============================================================ #

#' @include flode_classes.R assess_rating.R support.R
NULL

.sensitivity_tests <- c("leave_one_out", "leave_high_out", "starting_values", "boundary_shift")

.sens_dt_class <- new_S3_class(c("data.table", "data.frame"),
                               constructor = function(.data = data.table()) as.data.table(.data))

# The settings a refit must reproduce, read from the rating's provenance.
.sens_settings <- function(x) {
  p <- x@provenance
  list(
    segmented = S7_inherits(x, FlodeSegmentedRating),
    objective = if (is.null(p$objective)) "absolute" else p$objective,
    control = p$control, n_bounds = p$n_bounds,
    multi_start = if (is.null(p$multi_start)) TRUE else p$multi_start,
    age_halflife = p$age_halflife, age_min_weight = if (is.null(p$age_min_weight)) 0.1 else p$age_min_weight,
    reference = p$reference_datetime,
    estimate_breakpoints = isTRUE(p$estimate_breakpoints)
  )
}

# Refit from a subset of the gaugings used (row positions in `x@gaugings`),
# with the same settings and, if given, different breakpoints. Returns the
# fit, or a character string saying why it could not be made.
.sens_refit <- function(x, rows, st, control) {
  g <- as.data.table(x@gaugings)[rows]
  obs <- if (!is.null(st$age_halflife)) g$observation_time else NULL
  fit <- tryCatch(
    suppressWarnings(
      if (st$segmented) {
        rate_optimise_segmented(g$discharge_cms, g$stage_m, gauging_datetime = obs, control = control,
                                estimate_breakpoints = st$estimate_breakpoints, multi_start = st$multi_start,
                                objective = st$objective, age_halflife = st$age_halflife,
                                age_min_weight = st$age_min_weight, reference_datetime = st$reference)
      } else {
        rate_optimise(g$discharge_cms, g$stage_m, gauging_datetime = obs, control = control,
                      multi_start = st$multi_start, n_bounds = st$n_bounds, objective = st$objective,
                      age_halflife = st$age_halflife, age_min_weight = st$age_min_weight,
                      reference_datetime = st$reference)
      }
    ),
    error = function(e) conditionMessage(e)
  )
  fit
}

# Discharge at `stages` from a fit, with the same extrapolation convention for
# every variant (the nearest limb is continued), so differences are the
# fit's, not the evaluation's.
.sens_curve <- function(fit, stages) {
  if (S7_inherits(fit, FlodeSegmentedRating)) {
    return(.segmented_predict_cms(as.list(fit@coefficients), as.integer(fit@n_segments), stages))
  }
  .kernel_forward(.invariant_table(fit), stages)$discharge
}

.sens_status <- function(fit) {
  conv <- if (S7_inherits(fit, FlodeSegmentedRating)) fit@coefficients$converged else fit@limbs$converged
  if (all(conv %in% TRUE)) "ok" else "not_converged"
}

.sens_rows <- function(test, variant, ids, stages, base, curve, status, note = NA_character_) {
  n <- length(stages)
  data.table(
    test = test, variant = variant, evidence_ids = rep(list(as.character(ids)), n),
    stage_m = stages, base_cms = base, variant_cms = curve,
    change_cms = curve - base, change_pct = ifelse(base > 0, 100 * (curve - base) / base, NA_real_),
    status = status, note = note
  )
}

#' How sensitive a rating is to its evidence and its choices
#'
#' @description
#' Refits a rating with something changed and reports what that does to the
#' discharge, at stages you can name. It answers the question a reviewer
#' actually asks: if this gauging were wrong, or the breakpoint a little
#' elsewhere, how much would the flows I report move? The consequence is
#' reported in discharge, in m\eqn{^3}/s and as a percentage, not in
#' coefficients, which can change a great deal while the curve barely moves.
#'
#' Four tests, each of which can be switched off with `tests`:
#'
#' * **`leave_one_out`**: refit with each gauging left out in turn, linked
#'   to that gauging's `evidence_id`. The summary also gives that gauging's
#'   leverage and Cook's distance, so you can see whether the influence
#'   diagnostic and the actual effect agree.
#' * **`leave_high_out`**: refit without the highest gaugings (the top 5%,
#'   10% and 20% by default). The top of a rating is the part least often
#'   gauged, and this shows how far the flows above the remaining gaugings
#'   depend on the few that were taken there.
#' * **`starting_values`**: the discharge from every other valid starting
#'   point the optimiser tried, against the one it chose. No refit is
#'   needed; it uses the record the fit kept. Large differences mean two
#'   almost equally good fits predict different flows.
#' * **`boundary_shift`**: move each breakpoint up and down by `shift` of the
#'   gauged stage range and refit. For a rating with a single limb there is
#'   nothing to shift.
#'
#' Each refit uses the settings the rating recorded (objective, parameter
#' bounds, breakpoints, recency weighting, multi-start) so the only thing that
#' differs is the change being tested. A refit that cannot be made, for
#' example because a limb is left with too few gaugings, is reported with its
#' reason and is never dropped silently.
#'
#' Only a rating as the optimiser produced it can be tested: one that has been
#' amended since (aligned, extended, grafted) cannot be refitted faithfully.
#'
#' @param x A [FlodeRating] or [FlodeSegmentedRating] fitted from gaugings.
#'   A [FlodeRatingTable] holds no gaugings and is refused. A segmented fit
#'   supports `leave_one_out`, `leave_high_out` and, when its breakpoints
#'   were fixed, `boundary_shift`.
#' @param tests Which tests to run: any of `"leave_one_out"`,
#'   `"leave_high_out"`, `"starting_values"`, `"boundary_shift"`.
#' @param stages Numeric vector of stages (m) at which to compare discharge.
#'   Default: 25 stages across the fitted range. Name the stages you report
#'   flows at to see the effect there.
#' @param high_out Fractions of the gaugings, from the top, to leave out.
#'   Default `c(0.05, 0.10, 0.20)`; each leaves out at least one.
#' @param shift Fraction of the gauged stage range to move each breakpoint
#'   by. Default 0.05.
#' @param evidence_ids Character vector of evidence ids to leave out one at a
#'   time, or `NULL` (default) for every gauging.
#' @param max_refits Integer. A guard: `leave_one_out` refuses to run more
#'   than this many refits unless you restrict `evidence_ids`. Default 200.
#'
#' @return A [FlodeSensitivity]. `print()` gives the worst case for each
#'   test, `plot()` draws the change in discharge against stage, and
#'   [sensitivity_summary()] and [sensitivity_results()] return the tables.
#'
#' @seealso [assess_rating()], [rating_support()], [flag_influential_gaugings()],
#'   [FlodeSensitivity]
#'
#' @examples
#' set.seed(1)
#' stage_m <- seq(0.4, 3, length.out = 20)
#' gaugings <- data.frame(stage_m = stage_m,
#'                        discharge_cms = 3.2 * stage_m^1.6 * exp(rnorm(20, sd = 0.04)))
#' fit <- fit_rating(gaugings, quiet = TRUE)
#' sens <- rating_sensitivity(fit, stages = c(0.8, 1.5, 2.5, 3))
#' sens
#' sensitivity_summary(sens)[test == "leave_one_out"][order(-max_abs_change_pct)][1:3]
#' plot(sens)
#'
#' @export
rating_sensitivity <- function(x, tests = .sensitivity_tests, stages = NULL, high_out = c(0.05, 0.10, 0.20),
                               shift = 0.05, evidence_ids = NULL, max_refits = 200L) {
  fn <- "rating_sensitivity()"
  if (S7_inherits(x, FlodeRatingTable)) {
    stop(fn, ": a rating table holds equations only, with no gaugings to leave out. ",
         "Use a fit from fit_rating(), rate_optimise() or rate_optimise_segmented().", call. = FALSE)
  }
  if (!(S7_inherits(x, FlodeRating) || S7_inherits(x, FlodeSegmentedRating))) {
    stop(fn, ": x must be a FlodeRating or FlodeSegmentedRating, not ", class(x)[1L], call. = FALSE)
  }
  tests <- match.arg(tests, .sensitivity_tests, several.ok = TRUE)
  if (!identical(x@fit_origin, "independently_fitted")) {
    stop(sprintf(paste0("%s: this rating has been changed since it was fitted (origin: %s), so it cannot be refitted ",
                        "faithfully. Test the original fit, before it was amended."), fn, x@fit_origin), call. = FALSE)
  }
  if (!is.numeric(high_out) || any(high_out <= 0 | high_out >= 1)) stop(fn, ": high_out must be fractions between 0 and 1", call. = FALSE)
  if (!is.numeric(shift) || length(shift) != 1L || shift <= 0 || shift >= 0.5) stop(fn, ": shift must be a fraction between 0 and 0.5", call. = FALSE)

  st <- .sens_settings(x)
  g <- as.data.table(x@gaugings)
  n <- nrow(g)
  fitted <- .fitted_range(x)
  if (is.null(stages)) stages <- seq(fitted[1L], fitted[2L], length.out = 25L)
  if (!is.numeric(stages) || !length(stages) || any(!is.finite(stages))) stop(fn, ": stages must be finite numbers", call. = FALSE)
  stages <- sort(unique(stages))
  base <- .sens_curve(x, stages)
  span <- diff(range(g$stage_m))
  rows <- list()
  add <- function(...) rows[[length(rows) + 1L]] <<- .sens_rows(...)
  failed <- function(test, variant, ids, reason) {
    rows[[length(rows) + 1L]] <<- .sens_rows(test, variant, ids, stages, base, rep(NA_real_, length(stages)),
                                              "refit_failed", reason)
  }
  run_refit <- function(test, variant, ids, keep, control) {
    fit <- .sens_refit(x, keep, st, control)
    if (is.character(fit)) return(failed(test, variant, ids, fit))
    add(test, variant, ids, stages, base, .sens_curve(fit, stages), .sens_status(fit))
  }

  if ("leave_one_out" %in% tests) {
    idx <- if (is.null(evidence_ids)) seq_len(n) else match(evidence_ids, g$evidence_id)
    if (anyNA(idx)) stop(fn, ": unknown evidence id(s): ", paste(evidence_ids[is.na(idx)], collapse = ", "), call. = FALSE)
    if (length(idx) > max_refits) {
      stop(sprintf(paste0("%s: leave_one_out would make %d refits, more than max_refits (%d). Restrict it with evidence_ids, ",
                          "for example to the gaugings the influence diagnostics flag, or raise max_refits."),
                   fn, length(idx), as.integer(max_refits)), call. = FALSE)
    }
    for (i in idx) run_refit("leave_one_out", paste("without", g$evidence_id[i]), g$evidence_id[i], setdiff(seq_len(n), i), st$control)
  }

  if ("leave_high_out" %in% tests) {
    ord <- order(g$stage_m, decreasing = TRUE)
    ks <- unique(pmax(1L, ceiling(high_out * n)))
    for (k in ks) {
      drop <- ord[seq_len(k)]
      run_refit("leave_high_out", sprintf("without the highest %d (top %s)", k, .pct(k / n)),
                g$evidence_id[drop], setdiff(seq_len(n), drop), st$control)
    }
  }

  if ("starting_values" %in% tests && !st$segmented) {
    fs <- x@fit_starts
    tbl <- .invariant_table(x)
    sel <- x@limbs$selected_start_id
    if (!is.null(fs) && nrow(fs)) {
      for (i in seq_len(nrow(fs))) {
        r <- fs[i]
        if (!(r$valid %in% TRUE) || r$start_id == sel[match(r$limb, x@limbs$limb)]) next
        alt <- copy(tbl)
        li <- match(r$limb, x@limbs$limb)
        set(alt, i = li, j = c("C", "a", "n"), value = list(r$C_fit, r$a_fit, r$n_fit))
        add("starting_values", sprintf("limb %d, start %d%s", r$limb, r$start_id, if (r$converged %in% TRUE) "" else " (not converged)"),
            character(0), stages, base, .kernel_forward(alt, stages)$discharge,
            if (r$converged %in% TRUE) "ok" else "not_converged")
      }
    }
  }

  if ("boundary_shift" %in% tests) {
    breaks <- if (st$segmented) {
      if (is.null(st$control) || st$estimate_breakpoints) numeric(0) else sort(st$control)
    } else if (nrow(x@limbs) > 1L) sort(x@limbs$upper_stage_m)[-nrow(x@limbs)] else numeric(0)
    lo <- min(g$stage_m); hi <- max(g$stage_m)
    for (j in seq_along(breaks)) for (sgn in c(-1, 1)) {
      moved <- breaks; moved[j] <- breaks[j] + sgn * shift * span
      label <- sprintf("breakpoint %.4g moved to %.4g", breaks[j], moved[j])
      if (moved[j] <= lo || moved[j] >= hi || is.unsorted(moved, strictly = TRUE)) {
        failed("boundary_shift", label, character(0), "the shifted breakpoint falls outside the gauged range or crosses a neighbour")
      } else {
        run_refit("boundary_shift", label, character(0), seq_len(n), moved)
      }
    }
  }

  res <- if (length(rows)) rbindlist(rows) else data.table(
    test = character(0), variant = character(0), evidence_ids = list(), stage_m = numeric(0), base_cms = numeric(0),
    variant_cms = numeric(0), change_cms = numeric(0), change_pct = numeric(0), status = character(0), note = character(0))
  FlodeSensitivity(results = res, summary = .sens_summarise(res, x), stages = stages, tests = tests)
}

# One row per variant: the largest change in discharge, and where.
.sens_summarise <- function(res, x) {
  if (!nrow(res)) {
    return(data.table(test = character(0), variant = character(0), evidence_ids = list(), status = character(0),
                      max_abs_change_cms = numeric(0), max_abs_change_pct = numeric(0), stage_at_max_m = numeric(0),
                      leverage = numeric(0), cooks_distance = numeric(0), note = character(0)))
  }
  out <- res[, {
    ok <- is.finite(change_cms)
    w <- if (any(ok)) which.max(ifelse(ok, abs(change_pct), -Inf)) else NA_integer_
    list(evidence_ids = list(evidence_ids[[1L]]), status = status[1L],
         max_abs_change_cms = if (any(ok)) max(abs(change_cms[ok])) else NA_real_,
         max_abs_change_pct = if (any(ok)) max(abs(change_pct[ok]), na.rm = TRUE) else NA_real_,
         stage_at_max_m = if (!is.na(w)) stage_m[w] else NA_real_, note = note[1L])
  }, by = .(test, variant)]
  out[, `:=`(leverage = NA_real_, cooks_distance = NA_real_)]
  if (S7_inherits(x, FlodeRating)) {
    frame <- .rating_frame(x)
    infl <- if (!is.null(frame)) tryCatch(.fit_scale_influence(x, frame), error = function(e) NULL) else NULL
    if (!is.null(infl)) {
      for (i in which(out$test == "leave_one_out")) {
        id <- out$evidence_ids[[i]]
        m <- match(id, infl$evidence_id)
        if (length(m) == 1L && !is.na(m)) set(out, i, c("leverage", "cooks_distance"), list(infl$leverage[m], infl$cooks_distance[m]))
      }
    }
  }
  setcolorder(out, c("test", "variant", "evidence_ids", "status", "max_abs_change_cms", "max_abs_change_pct",
                     "stage_at_max_m", "leverage", "cooks_distance", "note"))
  out[]
}

#' The outcome of a sensitivity analysis (S7)
#'
#' @description
#' What [rating_sensitivity()] returns. It holds two tables:
#'
#' * `results`: one row per variant and stage, with `test`, `variant` (what
#'   was changed, in words), `evidence_ids` (a list column: the gaugings left
#'   out, empty for a test that leaves none out), `stage_m`, `base_cms` and
#'   `variant_cms` (discharge before and after), `change_cms`, `change_pct`,
#'   `status` and `note`;
#' * `summary`: one row per variant, with the largest change in discharge and
#'   the stage it occurs at, and, for `leave_one_out`, the gauging's leverage
#'   and Cook's distance on the scale the fit minimised.
#'
#' `status` is `"ok"`, `"not_converged"` (the variant's own refit did not
#' converge) or `"refit_failed"` (it could not be made, with the reason in
#' `note`).
#'
#' @param results,summary The two tables above.
#' @param stages The stages the comparison was made at.
#' @param tests The tests that were run.
#'
#' @return A `FlodeSensitivity`.
#'
#' @seealso [rating_sensitivity()], [sensitivity_summary()], [sensitivity_results()]
#'
#' @examples
#' set.seed(1)
#' stage_m <- seq(0.4, 3, length.out = 16)
#' fit <- fit_rating(data.frame(stage_m = stage_m,
#'                              discharge_cms = 3.2 * stage_m^1.6 * exp(rnorm(16, sd = 0.04))), quiet = TRUE)
#' sens <- rating_sensitivity(fit, tests = "leave_high_out", stages = c(1, 2, 3))
#' class(sens)
#' sensitivity_summary(sens)
#'
#' @export
FlodeSensitivity <- new_class(
  "FlodeSensitivity",
  properties = list(
    results = new_property(.sens_dt_class, default = quote(data.table())),
    summary = new_property(.sens_dt_class, default = quote(data.table())),
    stages = new_property(class_double, default = numeric(0)),
    tests = new_property(class_character, default = character(0))
  ),
  validator = function(self) {
    if (nrow(self@results) && !all(c("test", "variant", "stage_m", "base_cms", "variant_cms", "change_pct", "status") %in% names(self@results))) {
      return("results is missing columns")
    }
    NULL
  }
)

#' The per-variant summary of a sensitivity analysis
#'
#' @param x A [FlodeSensitivity].
#' @return A data.table, one row per variant: see [FlodeSensitivity].
#' @seealso [rating_sensitivity()]
#' @examples
#' set.seed(1)
#' stage_m <- seq(0.4, 3, length.out = 16)
#' fit <- fit_rating(data.frame(stage_m = stage_m,
#'                              discharge_cms = 3.2 * stage_m^1.6 * exp(rnorm(16, sd = 0.04))), quiet = TRUE)
#' sensitivity_summary(rating_sensitivity(fit, tests = "leave_high_out", stages = c(1, 3)))
#' @export
sensitivity_summary <- function(x) {
  if (!S7_inherits(x, FlodeSensitivity)) stop("x must be a FlodeSensitivity", call. = FALSE)
  copy(x@summary)
}

#' The full results of a sensitivity analysis
#'
#' @param x A [FlodeSensitivity].
#' @return A data.table, one row per variant and stage: see [FlodeSensitivity].
#' @seealso [rating_sensitivity()]
#' @examples
#' set.seed(1)
#' stage_m <- seq(0.4, 3, length.out = 16)
#' fit <- fit_rating(data.frame(stage_m = stage_m,
#'                              discharge_cms = 3.2 * stage_m^1.6 * exp(rnorm(16, sd = 0.04))), quiet = TRUE)
#' head(sensitivity_results(rating_sensitivity(fit, tests = "leave_high_out", stages = c(1, 3))))
#' @export
sensitivity_results <- function(x) {
  if (!S7_inherits(x, FlodeSensitivity)) stop("x must be a FlodeSensitivity", call. = FALSE)
  copy(x@results)
}

#' Print a sensitivity analysis (S7 method)
#' @param x A [FlodeSensitivity].
#' @param ... Unused.
#' @noRd
method(print, FlodeSensitivity) <- function(x, ...) {
  s <- x@summary
  cat(sprintf("<FlodeSensitivity> %d variant(s) over %d stage(s), tests: %s\n", nrow(s), length(x@stages), paste(x@tests, collapse = ", ")))
  for (tst in .sensitivity_tests[.sensitivity_tests %in% x@tests]) {
    d <- s[s$test == tst]
    if (!nrow(d)) {
      cat(sprintf("  %-16s nothing to test\n", paste0(tst, ":")))
      next
    }
    bad <- d[d$status == "refit_failed"]
    ok <- d[d$status != "refit_failed" & is.finite(d$max_abs_change_pct)]
    line <- if (nrow(ok)) {
      w <- ok[which.max(ok$max_abs_change_pct)]
      sprintf("worst: %s changes discharge by %.2f%% (%.3g m3/s) at %.3g m",
              w$variant, w$max_abs_change_pct, w$max_abs_change_cms, w$stage_at_max_m)
    } else "no variant could be compared"
    cat(sprintf("  %-16s %d variant(s); %s%s\n", paste0(tst, ":"), nrow(d), line,
                if (nrow(bad)) sprintf("; %d could not be refitted", nrow(bad)) else ""))
  }
  invisible(x)
}

#' Plot a sensitivity analysis (S7 method)
#'
#' Change in discharge against stage, one panel per test, one line per
#' variant, with the largest change in each test drawn heavier.
#'
#' @param x A [FlodeSensitivity].
#' @param y,... Unused.
#' @return A ggplot object.
#' @noRd
.plot_sensitivity <- function(x) {
  d <- x@results[is.finite(change_pct)]
  if (!nrow(d)) stop("there is nothing to plot: no variant could be compared", call. = FALSE)
  worst <- x@summary[is.finite(max_abs_change_pct), .SD[which.max(max_abs_change_pct)], by = test]
  d[, worst := paste(test, variant) %in% paste(worst$test, worst$variant)]
  ggplot(d, aes(x = stage_m, y = change_pct, group = variant, linewidth = worst, alpha = worst)) +
    geom_hline(yintercept = 0, colour = "grey40") +
    geom_line(colour = "#1F6FB5") +
    scale_linewidth_manual(values = c(`FALSE` = 0.35, `TRUE` = 1.1), guide = "none") +
    scale_alpha_manual(values = c(`FALSE` = 0.35, `TRUE` = 1), guide = "none") +
    facet_wrap(~ test, scales = "free_y") +
    labs(x = "Stage (m)", y = "Change in discharge (%)",
         title = "Sensitivity of discharge to the evidence and the fit",
         subtitle = "Each line is one variant; the largest change in each test is drawn heavier.") +
    theme_minimal(base_size = 11)
}

#' @noRd
method(plot, FlodeSensitivity) <- function(x, y, ...) .plot_sensitivity(x)

#' @noRd
method(autoplot, FlodeSensitivity) <- function(object, ...) .plot_sensitivity(object)
