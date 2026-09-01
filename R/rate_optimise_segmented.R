# ============================================================ #
# Tool:         rate_optimise_segmented
# Description:  Joint multi-segment power-law rating fit using the
#               log-additive (linear-scale multiplicative) parameterisation
#               from Hodson et al. (2024)'s ratingcurve package, rather
#               than this toolkit's usual independent-limb fit.
# Author:       Jonathan Payne
# Created:      2026-08-19
# Modified:     see prior changelog entries in version control (NA/Inf
#               validation, multi-start fitting) -- summarised here.
# Modified:     2026-08-19 - JP: converted to S7. Returns a
#               FlodeSegmentedRating instance (flode_classes.R) instead
#               of a plain list with a class string. apply_segmented_
#               rating() and plot_segmented_rating() are gone entirely --
#               replaced by method(apply_rating, FlodeSegmentedRating)
#               and method(rating_plot, FlodeSegmentedRating), registered
#               against the same generics rate_optimise.R registers for
#               FlodeRating. One name (`apply_rating`, `rating_plot`)
#               works regardless of which model architecture produced
#               the fit; S7 dispatches to the right implementation.
# Tier:         1
# Inputs:       discharge_cms, stage_m: numeric vectors, equal length,
#               one row per gauging. control: numeric vector of interior
#               segment breakpoints (optional; NULL fits a single
#               segment).
# Outputs:      rate_optimise_segmented() returns a FlodeSegmentedRating
#               instance. The registered apply_rating/rating_plot
#               methods compute discharge / draw a plot.
# Dependencies: data.table, minpack.lm, ggplot2, S7, stats
# Modified:     2026-08-25 - JP: converted from a box module to a package
#               R/ file. Imports are now package-level
#               (R/reach.rate-package.R); FlodeSegmentedRating and the
#               rating_plot/apply_rating generics (flode_classes.R) need
#               no import at all -- same package namespace.
# ============================================================ #

#' @include flode_classes.R
NULL

#' Generate several starting-value profiles for the segmented model's fit
#'
#' @description
#' This model's loss surface is genuinely non-convex -- Hodson et al.
#' (2024) use full Bayesian inference specifically because of this, and
#' [rate_optimise_segmented()] deliberately does not reproduce that
#' machinery. Rather than a fixed profile, this varies `n1` (the base
#' segment's exponent) and the later segments' exponents together across
#' a few plausible combinations, since a poor guess there is the most
#' common way this particular model gets stuck.
#'
#' @param k Integer. Number of segments.
#' @param interior_bp Numeric vector, length `k - 1`.
#' @param estimate_breakpoints Logical.
#' @param stage_m Numeric vector, the observed stage values.
#' @return A list of start lists.
#' @keywords internal
#' @noRd
.generate_segmented_starts <- function(k, interior_bp, estimate_breakpoints, stage_m) {
  base_bp1 <- min(stage_m) - 0.1 * diff(range(stage_m))
  profiles <- list(
    list(n1 = 1.5, nj = 0.3),
    list(n1 = 1.0, nj = 0.15),
    list(n1 = 2.0, nj = 0.5),
    list(n1 = 1.2, nj = 0.6)
  )

  lapply(profiles, function(p) {
    st <- list(C = 1, bp1 = base_bp1, n1 = p$n1)
    if (k > 1L) {
      for (j in seq_len(k)[-1]) {
        st[[sprintf("n%d", j)]] <- p$nj
        if (estimate_breakpoints) st[[sprintf("bp%d", j)]] <- interior_bp[j - 1L]
      }
    }
    st
  })
}

#' Fit the segmented model from multiple starts and keep the best
#'
#' @description
#' Same approach as `rate_optimise()`'s own multi-start helper: try every
#' start, catch each failure individually, validate each converged
#' result on a numerical domain/monotonicity grid via `predict()`, and
#' keep the valid result with the smallest RSS.
#'
#' Reconstruct natural-scale (cms) discharge from segmented coefficients
#'
#' @description
#' Shared by [rate_optimise_segmented()]'s post-fit diagnostics and the
#' `apply_rating` method registered for [FlodeSegmentedRating] -- both
#' need the same "evaluate \eqn{Q = C \cdot \max(H-bp_1,0)^{n_1} \cdot
#' \prod_{j \ge 2}(\max(H-bp_j,0)+1)^{n_j}}" reconstruction from a set of
#' coefficients, regardless of which scale the model was actually fitted
#' on (`objective` in `rate_optimise_segmented()`).
#'
#' @param coefs A named list/vector (or one-row data.table) with `C`,
#'   `bp1`, `n1`, and `bp2`/`n2` .. `bpk`/`nk` for `k > 1`.
#' @param k Integer. Number of segments.
#' @param stage_m Numeric vector of stages to evaluate at.
#' @return Numeric vector of predicted discharge, same length as `stage_m`.
#' @keywords internal
#' @noRd
.segmented_predict_cms <- function(coefs, k, stage_m) {
  q <- coefs[["C"]] * pmax(stage_m - coefs[["bp1"]], 0)^coefs[["n1"]]
  for (j in seq_len(k)[-1]) {
    bp_j <- coefs[[sprintf("bp%d", j)]]
    n_j <- coefs[[sprintf("n%d", j)]]
    q <- q * (pmax(stage_m - bp_j, 0) + 1)^n_j
  }
  q
}

#' @keywords internal
#' @noRd
.fit_segmented_multi_start <- function(model_formula, gaugings_dt, starts, maxiter = 300L, ...) {
  # weights = age_weight below is a bare symbol resolved against `data`
  # (gaugings_dt), not a computed value threaded through -- see
  # rate_optimise.R's .fit_limb_multi_start() comment for why nlsLM()'s
  # NSE handling of `weights` makes any other approach unreliable.
  # gaugings_dt is guaranteed an age_weight column by the caller,
  # defaulting to 1 (unweighted) when age_halflife isn't supplied.
  attempts <- vector("list", length(starts))
  best_model <- NULL
  best_rss <- Inf
  best_start_id <- NA_integer_

  stage_check <- seq(min(gaugings_dt$stage_m), max(gaugings_dt$stage_m), length.out = 30)

  for (s in seq_along(starts)) {
    st <- starts[[s]]
    fit_attempt <- tryCatch(
      suppressWarnings(nlsLM(
        formula = model_formula,
        weights = age_weight,
        data = gaugings_dt,
        start = st,
        control = nls.lm.control(maxiter = maxiter),
        ...
      )),
      error = function(e) e
    )

    if (inherits(fit_attempt, "error")) {
      attempts[[s]] <- data.table(
        start_id = s, converged = FALSE, rss = NA_real_,
        error_message = conditionMessage(fit_attempt)
      )
      next
    }

    resid_vals <- residuals(fit_attempt)
    rss <- sum(resid_vals^2)

    q_check <- tryCatch(
      predict(fit_attempt, newdata = data.table(stage_m = stage_check)),
      error = function(e) rep(NA_real_, length(stage_check))
    )
    is_valid <- all(is.finite(q_check)) && all(diff(q_check) >= -1e-9)

    attempts[[s]] <- data.table(
      start_id = s, converged = is_valid, rss = if (is_valid) rss else NA_real_,
      error_message = if (is_valid) NA_character_ else "fitted equation failed the domain/monotonicity check"
    )

    if (is_valid && rss < best_rss) {
      best_rss <- rss
      best_model <- fit_attempt
      best_start_id <- s
    }
  }

  attempts_dt <- rbindlist(attempts, fill = TRUE)
  list(
    model = best_model,
    attempts = attempts_dt,
    n_starts_attempted = length(starts),
    n_starts_converged = sum(attempts_dt$converged),
    selected_start_id = best_start_id
  )
}

#' Fit a rating curve with Hodson et al. (2024)'s segmented parameterisation
#'
#' @description
#' The rest of this toolkit (`rate_optimise()`) fits each limb of a
#' rating independently over disjoint stage ranges. This is a
#' structurally different model, adapted from the log-additive segmented
#' power law in Hodson et al. (2024): every segment contributes
#' multiplicatively across the whole fitted range rather than owning a
#' disjoint stage band --
#'
#' \deqn{Q = C \cdot \max(H - bp_1, 0)^{n_1} \cdot
#'   \prod_{j \ge 2} (\max(H - bp_j, 0) + 1)^{n_j}}
#'
#' `bp_1` is the stage of zero flow. Each later factor equals exactly 1
#' (no effect) at and below its own breakpoint `bp_j`. Continuity is
#' therefore automatic, not imposed afterward.
#'
#' \strong{What this does not reproduce}: Hodson et al. fit this model by
#' full Bayesian inference. This function fits by ordinary nonlinear
#' least squares (`nlsLM`) instead -- no priors, no posterior. `C`,
#' `bp_1`, and every exponent are genuine free parameters. The interior
#' breakpoints `bp_2..bp_k` are held fixed at `control` by default; set
#' `estimate_breakpoints = TRUE` to free them too, at the cost of the
#' non-convexity their paper warns about.
#'
#' @param discharge_cms,stage_m Numeric vectors, as in [rate_optimise()].
#' @param gauging_datetime `Date`/`POSIXct` vector or `NULL`, as in
#'   [rate_optimise()]. Default `NULL`.
#' @param control Numeric vector or `NULL`. Interior segment breakpoints.
#' @param age_halflife,age_min_weight,reference_datetime As in
#'   [rate_optimise()] -- opt-in recency weighting of the single joint
#'   fit (this model has no per-limb structure to weight separately).
#'   `age_halflife = NULL` (default) fits unweighted, exactly as before.
#' @param estimate_breakpoints Logical. If `TRUE`, interior breakpoints
#'   are refit as free parameters. Default `FALSE`.
#' @param multi_start Logical. If `TRUE` (default), fits from several
#'   starting-value profiles and keeps the best converged, domain-valid
#'   result. This matters more here than for `rate_optimise()`'s
#'   independent-limb fits: this model's loss surface is genuinely
#'   non-convex.
#' @param objective Character. `"absolute"` (default) minimises absolute
#'   discharge error, as before. `"relative"` fits `log(discharge_cms)`
#'   residuals instead -- see [rate_optimise()] for the rationale.
#'   Requires `discharge_cms` to be strictly positive. Reported
#'   diagnostics (`rmse_cms`, `r_squared`) are always recomputed on the
#'   natural discharge scale regardless of `objective`. Not a default --
#'   existing callers see no change in behaviour.
#' @param ... Passed to `minpack.lm::nls.lm.control()`.
#'
#' @return A [FlodeSegmentedRating] instance. `@coefficients` is a
#'   one-row data.table: `C`, `bp1..bpk`, `n1..nk`, `rmse_cms`,
#'   `r_squared`, `n_obs`, `n_starts_attempted`, `n_starts_converged`,
#'   `selected_start_id`. `@gaugings` holds the input data (and
#'   `gauging_datetime` if supplied, and `age_weight` if `age_halflife`
#'   was supplied). `@fit_starts`
#'   holds every multi-start attempt when `multi_start = TRUE`.
#'
#' @seealso [rate_optimise()] for this toolkit's usual independent-limb
#'   fit; `rating_plot()` and `apply_rating()` (both in `flode_classes`)
#'   for the generics this class's methods are registered against
#'
#' @examples
#' set.seed(1)
#' stage_m <- seq(0.3, 3.5, by = 0.03)
#' true_bp1 <- 0.1
#' q1 <- 4 * pmax(stage_m - true_bp1, 0)^1.55
#' q2 <- (pmax(stage_m - 1.6, 0) + 1)^0.9
#' q3 <- (pmax(stage_m - 2.4, 0) + 1)^1.1
#' discharge_cms <- q1 * q2 * q3 * exp(rnorm(length(stage_m), sd = 0.03))
#' fit_seg <- rate_optimise_segmented(discharge_cms, stage_m, control = c(1.6, 2.4))
#' fit_seg@coefficients
#'
#' @export
rate_optimise_segmented <- function(discharge_cms, stage_m, gauging_datetime = NULL, control = NULL,
                                     estimate_breakpoints = FALSE, multi_start = TRUE,
                                     objective = c("absolute", "relative"),
                                     age_halflife = NULL, age_min_weight = 0.1, reference_datetime = NULL, ...) {
  objective <- match.arg(objective)
  .validate_age_weighting(gauging_datetime, age_halflife, age_min_weight, reference_datetime, "rate_optimise_segmented")
  if (!is.numeric(discharge_cms)) stop("discharge_cms must be numeric")
  if (!is.numeric(stage_m)) stop("stage_m must be numeric")
  if (length(discharge_cms) != length(stage_m)) {
    stop("discharge_cms and stage_m must be the same length")
  }
  if (length(discharge_cms) == 0) stop("discharge_cms must have at least one value")
  if (any(!is.finite(discharge_cms))) stop("discharge_cms must not contain NA, NaN, or infinite values")
  if (any(!is.finite(stage_m))) stop("stage_m must not contain NA, NaN, or infinite values")
  if (any(discharge_cms < 0)) stop("discharge_cms must be non-negative")
  if (objective == "relative" && any(discharge_cms <= 0)) {
    stop("discharge_cms must be strictly positive when objective = \"relative\" (log(0) is undefined)")
  }
  if (diff(range(stage_m)) <= 0) stop("stage_m must span a non-zero range")
  if (!is.null(gauging_datetime)) {
    if (!inherits(gauging_datetime, c("Date", "POSIXct"))) {
      stop("gauging_datetime must be a Date or POSIXct vector, or NULL")
    }
    if (length(gauging_datetime) != length(discharge_cms)) {
      stop("gauging_datetime must be the same length as discharge_cms")
    }
  }
  if (!is.null(control) && !is.numeric(control)) stop("control must be numeric or NULL")
  if (!is.null(control) && any(!is.finite(control))) stop("control must not contain NA, NaN, or infinite values")
  if (!is.null(control) && anyDuplicated(control)) stop("control breakpoints must be unique")
  if (!is.null(control) && (any(control <= min(stage_m)) || any(control >= max(stage_m)))) {
    stop("control breakpoints must fall strictly inside the observed stage range")
  }
  if (!is.logical(estimate_breakpoints) || length(estimate_breakpoints) != 1L) {
    stop("estimate_breakpoints must be a single logical")
  }
  if (!is.logical(multi_start) || length(multi_start) != 1L) {
    stop("multi_start must be a single logical")
  }

  interior_bp <- sort(control)
  k <- length(interior_bp) + 1L

  n_free_params <- 2L + k + (if (estimate_breakpoints) length(interior_bp) else 0L)
  if (length(stage_m) < n_free_params + 2L) {
    stop(sprintf(
      "rate_optimise_segmented(): only %d gaugings for %d free parameters; need at least %d.",
      length(stage_m), n_free_params, n_free_params + 2L
    ))
  }

  gaugings_dt <- data.table(discharge_cms = discharge_cms, stage_m = stage_m)
  if (!is.null(gauging_datetime)) gaugings_dt[, gauging_datetime := gauging_datetime]
  # See rate_optimise.R's own comment on age_weight: always present as a
  # real data column during fitting (nlsLM() needs it there, not passed
  # as a computed value), defaulting to 1 (unweighted), stripped from
  # the output below when age_halflife wasn't supplied.
  gaugings_dt[, age_weight := if (!is.null(age_halflife)) {
    .age_recency_weight(gauging_datetime, age_halflife, age_min_weight, reference_datetime)
  } else {
    1
  }]

  if (objective == "relative") {
    # log(Q) = log(C) + n1*log(max(H-bp1,0)) + sum_{j>=2} nj*log(max(H-bpj,0)+1).
    # The j >= 2 terms are always >= 1 by construction (never zero), but
    # the base n1 term is exactly 0 at/below bp1 -- add a tiny floor so
    # log() never sees a literal zero there.
    log_terms <- "n1 * log(pmax(stage_m - bp1, 0) + 1e-6)"
    for (j in seq_len(k)[-1]) {
      bp_term <- if (estimate_breakpoints) {
        sprintf("bp%d", j)
      } else {
        sprintf("%.10g", interior_bp[j - 1L])
      }
      log_terms <- c(log_terms, sprintf("n%d * log(pmax(stage_m - %s, 0) + 1)", j, bp_term))
    }
    model_formula <- as.formula(paste("log(discharge_cms) ~ log(C) +", paste(log_terms, collapse = " + ")))
  } else {
    rhs_terms <- "pmax(stage_m - bp1, 0)^n1"
    for (j in seq_len(k)[-1]) {
      bp_term <- if (estimate_breakpoints) {
        sprintf("bp%d", j)
      } else {
        sprintf("%.10g", interior_bp[j - 1L])
      }
      rhs_terms <- c(rhs_terms, sprintf("(pmax(stage_m - %s, 0) + 1)^n%d", bp_term, j))
    }
    model_formula <- as.formula(paste("discharge_cms ~ C *", paste(rhs_terms, collapse = " * ")))
  }

  start_list <- list(
    C = 1,
    bp1 = min(stage_m) - 0.1 * diff(range(stage_m)),
    n1 = 1.5
  )
  for (j in seq_len(k)[-1]) {
    start_list[[sprintf("n%d", j)]] <- 0.3
    if (estimate_breakpoints) start_list[[sprintf("bp%d", j)]] <- interior_bp[j - 1L]
  }

  if (multi_start) {
    starts <- .generate_segmented_starts(k, interior_bp, estimate_breakpoints, stage_m)
    fit_result <- .fit_segmented_multi_start(model_formula, gaugings_dt, starts, maxiter = 300L, ...)
    if (is.null(fit_result$model)) {
      stop(sprintf(
        "rate_optimise_segmented(): no starting profile converged to a valid, monotonic fit across %d attempts.",
        fit_result$n_starts_attempted
      ))
    }
    model <- fit_result$model
    n_starts_attempted <- fit_result$n_starts_attempted
    n_starts_converged <- fit_result$n_starts_converged
    selected_start_id <- fit_result$selected_start_id
    fit_starts_dt <- fit_result$attempts
  } else {
    model <- nlsLM(
      formula = model_formula,
      weights = age_weight,
      data = gaugings_dt,
      start = start_list,
      control = nls.lm.control(maxiter = 300),
      ...
    )
    n_starts_attempted <- 1L
    n_starts_converged <- 1L
    selected_start_id <- 1L
    fit_starts_dt <- NULL
  }

  coefs <- coef(model)
  coefficients_dt <- as.data.table(as.list(coefs))

  # When breakpoints were held fixed, they were baked into the formula as
  # literal constants and never appear in coef(model) -- add them
  # explicitly so the apply_rating/rating_plot methods can always find
  # bp1..bpk regardless of estimate_breakpoints.
  if (!estimate_breakpoints && k > 1L) {
    for (j in seq_len(k)[-1]) {
      coefficients_dt[, (sprintf("bp%d", j)) := interior_bp[j - 1L]]
    }
  }

  # Diagnostics are always computed on the natural discharge (cms) scale,
  # recomputed from the fitted coefficients rather than taken from
  # residuals(model) -- the latter would be log-scale residuals under
  # objective = "relative", not comparable to the absolute-objective case.
  predicted_cms <- .segmented_predict_cms(as.list(coefficients_dt), k, stage_m)
  resid_vals <- discharge_cms - predicted_cms
  ss_res <- sum(resid_vals^2)
  ss_tot <- sum((discharge_cms - mean(discharge_cms))^2)

  coefficients_dt[, `:=`(
    rmse_cms = sqrt(mean(resid_vals^2)),
    r_squared = if (ss_tot > 1e-12) 1 - ss_res / ss_tot else NA_real_,
    n_obs = length(discharge_cms),
    n_starts_attempted = n_starts_attempted,
    n_starts_converged = n_starts_converged,
    selected_start_id = selected_start_id
  )]

  if (is.null(age_halflife)) gaugings_dt[, age_weight := NULL]

  FlodeSegmentedRating(
    coefficients = coefficients_dt[],
    n_segments = k,
    estimate_breakpoints = estimate_breakpoints,
    gaugings = gaugings_dt,
    fit_starts = fit_starts_dt,
    status = "independently_fitted",
    provenance = list(
      fitting_equation = "Hodson et al. (2024) log-additive segmented power law",
      fitting_method = if (multi_start) "multi-start nlsLM (minpack.lm)" else "single-start nlsLM (minpack.lm)",
      objective = objective,
      control = control,
      estimate_breakpoints = estimate_breakpoints,
      multi_start = multi_start,
      age_halflife = age_halflife,
      age_min_weight = age_min_weight,
      reference_datetime = if (!is.null(age_halflife)) {
        if (!is.null(reference_datetime)) reference_datetime else max(gauging_datetime)
      } else {
        NULL
      },
      tool_version = "rating_curves 1.0"
    )
  )
}

#' Apply a segmented rating to a stage series (S7 method)
#'
#' @description
#' Registered against the `apply_rating` generic (`flode_classes.R`) for
#' [FlodeSegmentedRating]. Stage at or below `bp1` (the zero-flow stage)
#' legitimately gives zero discharge -- this falls out of the formula
#' itself, unlike [FlodeRating]'s method which needs a special-cased
#' override for the same thing.
#'
#' `fit` is a [FlodeSegmentedRating] instance. `stage_dt` is a
#' data.frame or data.table with a stage column, named by `stage_col`
#' (default `"stage"`). `out_col` (default `"discharge"`) names the
#' output column.
#'
#' @return `stage_dt` as a data.table with `out_col` and an
#'   `extrapolated` logical column added (`TRUE` above the highest
#'   gauged stage).
#' @export
method(apply_rating, FlodeSegmentedRating) <- function(fit, stage_dt, stage_col = "stage", out_col = "discharge") {
  if (!is.data.frame(stage_dt)) stop("stage_dt must be a data.frame or data.table")
  if (!stage_col %in% names(stage_dt)) stop("stage_col must be a column of stage_dt")

  coefs <- fit@coefficients
  k <- fit@n_segments
  gaugings_dt <- fit@gaugings

  out_dt <- copy(as.data.table(stage_dt))
  H <- out_dt[[stage_col]]

  q <- .segmented_predict_cms(coefs, k, H)

  set(out_dt, j = out_col, value = q)
  set(out_dt, j = "extrapolated", value = H > max(gaugings_dt$stage_m))
  out_dt[]
}

#' Plot a fitted segmented rating against gauged points (S7 method)
#'
#' @description
#' Registered against the `rating_plot` generic (`flode_classes.R`) for
#' [FlodeSegmentedRating]. Discharge on x, stage on y. Dashed horizontal
#' lines mark where each segment's factor turns on (`bp1..bpk`) rather
#' than a hard limb boundary, since the transition is smooth by
#' construction.
#'
#' `fit` is a [FlodeSegmentedRating] instance. `n_points` (default
#' `300L`) is the number of points used to draw the curve.
#'
#' @return A `ggplot` object, invisibly.
#' @export
method(rating_plot, FlodeSegmentedRating) <- function(fit, n_points = 300L) {
  coefs <- fit@coefficients
  k <- fit@n_segments
  gaugings_dt <- fit@gaugings

  bp_vals <- vapply(seq_len(k), function(j) coefs[[sprintf("bp%d", j)]], numeric(1))

  stage_lo <- min(bp_vals[1], min(gaugings_dt$stage_m))
  stage_hi <- max(gaugings_dt$stage_m)
  stage_seq <- seq(stage_lo, stage_hi, length.out = n_points)

  curve_dt <- method(apply_rating, FlodeSegmentedRating)(
    fit, data.table(stage = stage_seq),
    stage_col = "stage", out_col = "discharge"
  )

  p <- ggplot() +
    geom_hline(
      data = data.table(bp = bp_vals),
      aes(yintercept = bp), colour = "grey60", linetype = "dashed", linewidth = 0.5
    ) +
    geom_path(data = curve_dt, aes(x = discharge, y = stage), colour = "#1F4B4A", linewidth = 1.2) +
    geom_point(
      data = gaugings_dt,
      aes(x = discharge_cms, y = stage_m),
      colour = "#e65100", size = 2.2, shape = 21, fill = "#ff8a65", stroke = 1
    ) +
    labs(
      title = sprintf("Segmented Rating (%d segment%s, Hodson et al. parameterisation)", k, if (k > 1) "s" else ""),
      x = "Discharge (m\u00b3/s)", y = "Stage (m)",
      caption = sprintf("R\u00b2 = %.4f  |  RMSE = %.3f m\u00b3/s  |  n = %d", coefs$r_squared, coefs$rmse_cms, coefs$n_obs)
    ) +
    theme_minimal(base_size = 12) +
    theme(
      plot.title = element_text(face = "bold", size = 13),
      panel.grid.minor = element_blank(),
      panel.border = element_rect(colour = "grey80", fill = NA)
    )

  print(p)
  invisible(p)
}
