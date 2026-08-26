# ============================================================ #
# Tool:         rate_optimise / rating_plot / rating diagnostics
# Description:  Fit multi-limb power-law rating curves by non-linear least
#               squares, diagnose fit quality, suggest breakpoints, and
#               plot the fitted rating against gauged points
# Author:       Jonathan Payne
# Created:      2022-01-01
# Modified:     see prior changelog entries in version control for the
#               full history of this file's evolution (snake_case rename,
#               bug fixes, bootstrap uncertainty, box constraints,
#               multi-start fitting, suggest_breakpoints() redesign) --
#               summarised here rather than repeated in full.
# Modified:     2026-08-19 - JP: converted to S7. rate_optimise() and
#               rate_optimise_constrained() now return a FlodeRating
#               instance (flode_classes.R) instead of a plain data.table
#               with a class string and dependent data stashed in
#               attributes -- the attribute approach is vulnerable to
#               going stale under ordinary data.table subsetting, and
#               gave no structural way to distinguish an independently-
#               fitted result from a post-fit amendment beyond
#               remembering to check a column. The fitting logic itself
#               is unchanged: every function still builds/operates on
#               plain data.tables internally, and only wraps the result
#               in FlodeRating() at the return boundary, or unpacks
#               fit@limbs/fit@gaugings at the top. rating_plot() is now
#               registered as an S7 method (method(rating_plot,
#               FlodeRating) <- ...) against the generic defined in
#               flode_classes.R, dispatching alongside
#               rate_optimise_segmented.R's method for FlodeSegmentedRating
#               -- the same call works regardless of which model
#               architecture produced the fit. plot_rating_residuals()
#               and flag_extrapolated_limbs() stay plain functions (no
#               FlodeSegmentedRating equivalent exists yet), with a
#               manual inherits(fit, "FlodeRating") check.
# Modified:     2026-08-25 - JP: converted from a box module to a package
#               R/ file. data.table/minpack.lm/ggplot2/stats/graphics/S7
#               are package-level imports now (R/reach.rate-package.R);
#               FlodeRating and the rating_plot generic (flode_classes.R)
#               need no import at all -- same package namespace.
# Tier:         3
# Inputs:       discharge_cms, stage_m: numeric vectors, equal length,
#               one row per gauging. control: numeric vector of stage
#               breakpoints separating rating limbs (optional).
# Outputs:      rate_optimise() and rate_optimise_constrained() return a
#               FlodeRating instance. rating_plot() and
#               plot_rating_residuals() draw plots.
# Dependencies: data.table, minpack.lm, ggplot2, S7, stats, graphics
# ============================================================ #

#' @include flode_classes.R
NULL

#' Generate several starting-value combinations for a limb's nlsLM fit
#'
#' @description
#' A single fixed start (`C=1, a=0, n=1`) can converge to a poor local
#' fit, or fail to converge at all, on awkward data -- particularly a
#' limb with a strongly curved shape or a wide exponent range. This
#' generates a small, deliberately varied set of starting combinations
#' rather than relying on one: a handful of plausible `n` values at the
#' baseline `a`, a data-driven log-log estimate when one can be computed,
#' a data-scaled `C`, and an alternative `a` well away from its lower
#' bound. Every start is clipped into `[fit_lower, fit_upper]`
#' defensively, in case a generated value would otherwise violate the
#' bounds `rate_optimise()` already enforces.
#'
#' @param limb_dt data.table with `stage_m`, `discharge_cms` for one limb.
#' @param fit_lower,fit_upper Named numeric vectors (`C`, `a`, `n`), the
#'   box constraints already computed for this limb.
#' @return A list of start lists, each with named elements `C`, `a`, `n`.
#' @keywords internal
#' @noRd
.generate_starts <- function(limb_dt, fit_lower, fit_upper) {
  H <- limb_dt$stage_m
  Q <- limb_dt$discharge_cms
  a_lb <- fit_lower[["a"]]
  start_a_base <- if (a_lb > 0) a_lb + 0.01 else 0

  log_log_start <- tryCatch(
    {
      depth <- H - min(H) + 0.1
      fit_ll <- lm(log(Q) ~ log(depth))
      n_hat <- coef(fit_ll)[[2]]
      C_hat <- exp(coef(fit_ll)[[1]])
      list(C = max(C_hat, 0.01), a = -min(H) + 0.1, n = max(n_hat, 0.1))
    },
    error = function(e) NULL
  )

  starts <- list(
    list(C = 1, a = start_a_base, n = 1),
    list(C = 1, a = start_a_base, n = 1.5),
    list(C = 1, a = start_a_base, n = 2),
    list(C = median(Q) / (median(H) + start_a_base)^1.5, a = start_a_base, n = 1.5),
    list(C = 1, a = start_a_base + 0.25 * diff(range(H)), n = 1)
  )
  if (!is.null(log_log_start)) starts <- c(starts, list(log_log_start))

  lapply(starts, function(s) {
    clip <- function(val, lo, hi) min(max(val, lo), if (is.finite(hi)) hi else val)
    list(
      C = clip(s$C, fit_lower[["C"]], fit_upper[["C"]]),
      a = clip(s$a, fit_lower[["a"]], fit_upper[["a"]]),
      n = clip(s$n, fit_lower[["n"]], fit_upper[["n"]])
    )
  })
}

#' Fit one limb from multiple starting points and keep the best
#'
#' @description
#' Tries every start from [.generate_starts()], catches each failure
#' individually rather than letting one bad start abort the limb, checks
#' each converged result against a numerical domain/monotonicity grid,
#' and selects the valid result with the smallest residual sum of
#' squares. Every attempt is recorded, not just the winner.
#'
#' @param limb_dt data.table with `stage_m`, `discharge_cms` for one limb.
#' @param fit_lower,fit_upper Named numeric vectors (`C`, `a`, `n`).
#' @param formula The model formula to fit -- `discharge_cms ~ C * (stage_m
#'   + a)^n` for the default absolute-residual objective, or an
#'   equivalent log-space formula when fitting on relative error. Either
#'   way it must estimate parameters named `C`, `a`, `n`.
#' @param maxiter Integer, passed to `nls.lm.control()`.
#' @param ... Passed to `nlsLM()`.
#' @return A list: `model`, `attempts` (data.table), `n_starts_attempted`,
#'   `n_starts_converged`, `selected_start_id`.
#' @keywords internal
#' @noRd
.fit_limb_multi_start <- function(limb_dt, fit_lower, fit_upper,
                                   formula = discharge_cms ~ C * (stage_m + a)^n,
                                   maxiter = 100L, ...) {
  starts <- .generate_starts(limb_dt, fit_lower, fit_upper)

  attempts <- vector("list", length(starts))
  best_model <- NULL
  best_rss <- Inf
  best_start_id <- NA_integer_

  for (s in seq_along(starts)) {
    st <- starts[[s]]
    fit_attempt <- tryCatch(
      suppressWarnings(nlsLM(
        formula = formula,
        data = limb_dt,
        start = st,
        lower = fit_lower,
        upper = fit_upper,
        control = nls.lm.control(maxiter = maxiter),
        ...
      )),
      error = function(e) e
    )

    if (inherits(fit_attempt, "error")) {
      attempts[[s]] <- data.table(
        start_id = s, C_start = st$C, a_start = st$a, n_start = st$n,
        converged = FALSE, rss = NA_real_, C_fit = NA_real_, a_fit = NA_real_, n_fit = NA_real_,
        error_message = conditionMessage(fit_attempt)
      )
      next
    }

    coefs <- coef(fit_attempt)
    resid_vals <- residuals(fit_attempt)
    rss <- sum(resid_vals^2)

    stage_check <- seq(min(limb_dt$stage_m), max(limb_dt$stage_m), length.out = 20)
    q_check <- coefs[["C"]] * (stage_check + coefs[["a"]])^coefs[["n"]]
    is_valid <- all(is.finite(q_check)) && all(diff(q_check) >= -1e-9)

    attempts[[s]] <- data.table(
      start_id = s, C_start = st$C, a_start = st$a, n_start = st$n,
      converged = is_valid, rss = if (is_valid) rss else NA_real_,
      C_fit = coefs[["C"]], a_fit = coefs[["a"]], n_fit = coefs[["n"]],
      error_message = if (is_valid) NA_character_ else "fitted equation failed the domain/monotonicity check"
    )

    if (is_valid && rss < best_rss) {
      best_rss <- rss
      best_model <- fit_attempt
      best_start_id <- s
    }
  }

  attempts_dt <- rbindlist(attempts)
  list(
    model = best_model,
    attempts = attempts_dt,
    n_starts_attempted = length(starts),
    n_starts_converged = sum(attempts_dt$converged),
    selected_start_id = best_start_id
  )
}

#' Fit a multi-limb power-law rating curve
#'
#' @description
#' Fits the rating equation \eqn{Q = C(H + a)^n} by Levenberg-Marquardt
#' non-linear least squares (`minpack.lm::nlsLM`). A single limb is fitted
#' across the full stage range when `control` is `NULL`; otherwise the
#' gaugings are split into limbs at each stage in `control` and each limb
#' is fitted independently -- this fits each limb separately, not a
#' single globally-optimised multi-limb model (see
#' `rate_optimise_segmented()` for that).
#'
#' @param discharge_cms Numeric vector. Gauged discharge, m\eqn{^3}/s.
#' @param stage_m Numeric vector. Gauged stage, m. Same length as
#'   `discharge_cms`.
#' @param gauging_datetime `Date`/`POSIXct` vector or `NULL`. When each
#'   gauging in `discharge_cms`/`stage_m` was taken, same length as
#'   `discharge_cms` if supplied. Not used by the fit itself -- stored on
#'   the returned rating's `@gaugings` for future age-aware fitting (see
#'   issue #9). Default `NULL`: no dates recorded, matching today's
#'   behaviour.
#' @param control Numeric vector or `NULL`. Stage breakpoints separating
#'   rating limbs, e.g. `c(1.6, 2.2)` for three limbs. `NULL` (default)
#'   fits a single limb across the full range.
#' @param n_boot Integer. Number of bootstrap refits per limb, for
#'   coefficient uncertainty. Default `0L`: no bootstrap.
#' @param boot_seed Integer or `NULL`. Passed to `set.seed()` before
#'   bootstrapping, with the caller's prior RNG state saved and restored
#'   afterward. Default `NULL`.
#' @param min_boot_success Numeric in `[0, 1]`. Warn if the successful-draw
#'   fraction for a limb falls below this. Default `0.8`.
#' @param multi_start Logical. If `TRUE` (default), each limb is fitted
#'   from several starting-value combinations and the best converged,
#'   domain-valid result is kept. Set `FALSE` for the original
#'   single-start behaviour.
#' @param n_bounds Numeric vector `c(lower, upper)`, or `NULL` (default).
#'   Box-constrains the exponent `n` for every limb, e.g. to a
#'   theoretical range implied by known channel-control hydraulics
#'   (roughly 1.5 for a rectangular control, 2.5 for triangular/V-notch).
#'   The top of a rating is usually the least-gauged part of the record,
#'   so this lets known geometry keep the fit realistic there without
#'   more data. Set `lower == upper` to fix `n` outright. `NULL`
#'   (default) keeps today's effectively unconstrained `n > 0`. Not a
#'   default constraint -- most callers don't know their channel-control
#'   type, and an unconstrained fit remains the default behaviour.
#' @param objective Character. `"absolute"` (default) minimises absolute
#'   discharge error, as before. `"relative"` fits `log(discharge_cms)`
#'   residuals instead -- gauging error is typically proportional (a
#'   percentage of the reading) rather than a fixed absolute amount, so
#'   this can better balance low- and high-flow structure than absolute
#'   error does. Requires `discharge_cms` to be strictly positive.
#'   Reported diagnostics (`rmse_cms`, `r_squared`, and the error columns)
#'   are always recomputed on the natural discharge scale regardless of
#'   `objective`, so they stay comparable between the two.  Not a
#'   default -- existing callers see no change in behaviour.
#' @param ... Passed to `minpack.lm::nlsLM()` itself for the primary fit
#'   only, not the bootstrap refits.
#'
#' @return A [FlodeRating] instance. `@limbs` has one row per limb with
#'   bounds, coefficients `C`/`a`/`n`, fit diagnostics, and multi-start
#'   bookkeeping. When `n_boot > 0`, `@bootstrap` holds every draw and
#'   `@limbs` gains SE/percentile/success-count columns. `@gaugings`
#'   holds the input data with a `limb` column (and `gauging_datetime` if
#'   supplied). `@fit_starts` holds every
#'   multi-start attempt when `multi_start = TRUE`. `@status` is
#'   `"independently_fitted"`.
#'
#' @seealso [rating_plot()], [plot_rating_residuals()],
#'   [flag_extrapolated_limbs()], [suggest_breakpoints()],
#'   [rate_optimise_constrained()]
#'
#' @examples
#' discharge_cms <- c(177.685, 240.898, 221.954, 205.55, 383.051, 154.061, 216.582)
#' stage_m <- c(1.855, 2.109, 2.037, 1.972, 2.574, 1.748, 2.016)
#' fit <- rate_optimise(discharge_cms, stage_m)
#' fit@limbs[, .(limb, C, a, n, rmse_cms, r_squared)]
#'
#' @export
rate_optimise <- function(discharge_cms, stage_m, gauging_datetime = NULL, control = NULL,
                           n_boot = 0L, boot_seed = NULL, min_boot_success = 0.8, multi_start = TRUE,
                           n_bounds = NULL, objective = c("absolute", "relative"), ...) {
  objective <- match.arg(objective)
  if (!is.null(n_bounds)) {
    if (!is.numeric(n_bounds) || length(n_bounds) != 2L || any(!is.finite(n_bounds))) {
      stop("n_bounds must be NULL or a finite numeric vector c(lower, upper)")
    }
    if (n_bounds[1] <= 0) stop("n_bounds[1] (the lower bound) must be positive")
    if (n_bounds[1] > n_bounds[2]) stop("n_bounds[1] must not exceed n_bounds[2]")
  }
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
  if (!is.numeric(n_boot) || length(n_boot) != 1L || n_boot < 0) {
    stop("n_boot must be a single non-negative integer")
  }
  if (!is.null(boot_seed) && (!is.numeric(boot_seed) || length(boot_seed) != 1L)) {
    stop("boot_seed must be NULL or a single number")
  }
  if (!is.numeric(min_boot_success) || length(min_boot_success) != 1L ||
    min_boot_success < 0 || min_boot_success > 1) {
    stop("min_boot_success must be a single number between 0 and 1")
  }
  if (!is.logical(multi_start) || length(multi_start) != 1L) {
    stop("multi_start must be a single logical")
  }

  gaugings_dt <- data.table(discharge_cms = discharge_cms, stage_m = stage_m)
  if (!is.null(gauging_datetime)) gaugings_dt[, gauging_datetime := gauging_datetime]

  fit_formula <- if (objective == "relative") {
    log(discharge_cms) ~ log(C) + n * log(stage_m + a)
  } else {
    discharge_cms ~ C * (stage_m + a)^n
  }

  breaks <- c(min(stage_m), sort(control), max(stage_m))
  n_limbs_declared <- length(breaks) - 1L

  gaugings_dt[, limb := cut(
    stage_m,
    breaks = breaks,
    labels = FALSE,
    right = TRUE,
    include.lowest = TRUE
  )]

  obs_per_limb_dt <- gaugings_dt[, .N, by = limb]
  obs_by_declared_limb <- integer(n_limbs_declared)
  obs_by_declared_limb[obs_per_limb_dt$limb] <- obs_per_limb_dt$N
  under_populated <- which(obs_by_declared_limb < 3L)
  if (length(under_populated) > 0) {
    stop(
      "rate_optimise(): each limb needs at least 3 gaugings to fit C, a, and n; ",
      "limb(s) ", paste(under_populated, collapse = ", "),
      " have ", paste(obs_by_declared_limb[under_populated], collapse = ", "),
      " respectively. Check the spacing of `control`."
    )
  }

  bounds_dt <- data.table(
    limb = seq_len(length(breaks) - 1L),
    lower_stage_m = breaks[-length(breaks)],
    upper_stage_m = breaks[-1L]
  )
  range_dt <- gaugings_dt[, .(
    min_discharge_cms = min(discharge_cms),
    max_discharge_cms = max(discharge_cms)
  ), by = limb]

  meta_dt <- bounds_dt[range_dt, on = "limb"]
  setorder(meta_dt, limb)

  n_limbs <- nrow(meta_dt)
  C_vec <- numeric(n_limbs)
  a_vec <- numeric(n_limbs)
  n_vec <- numeric(n_limbs)
  rmse_vec <- numeric(n_limbs)
  r_squared_vec <- numeric(n_limbs)
  n_obs_vec <- integer(n_limbs)
  n_unique_stage_vec <- integer(n_limbs)
  mean_error_vec <- numeric(n_limbs)
  median_abs_error_vec <- numeric(n_limbs)
  max_abs_error_vec <- numeric(n_limbs)
  residual_df_vec <- integer(n_limbs)
  C_se_vec <- rep(NA_real_, n_limbs)
  a_se_vec <- rep(NA_real_, n_limbs)
  n_se_vec <- rep(NA_real_, n_limbs)
  C_q025_vec <- rep(NA_real_, n_limbs)
  C_q50_vec <- rep(NA_real_, n_limbs)
  C_q975_vec <- rep(NA_real_, n_limbs)
  a_q025_vec <- rep(NA_real_, n_limbs)
  a_q50_vec <- rep(NA_real_, n_limbs)
  a_q975_vec <- rep(NA_real_, n_limbs)
  n_q025_vec <- rep(NA_real_, n_limbs)
  n_q50_vec <- rep(NA_real_, n_limbs)
  n_q975_vec <- rep(NA_real_, n_limbs)
  n_boot_requested_vec <- rep(NA_integer_, n_limbs)
  n_boot_success_vec <- rep(NA_integer_, n_limbs)
  n_boot_failed_vec <- rep(NA_integer_, n_limbs)
  boot_success_fraction_vec <- rep(NA_real_, n_limbs)
  n_starts_attempted_vec <- integer(n_limbs)
  n_starts_converged_vec <- integer(n_limbs)
  selected_start_id_vec <- integer(n_limbs)
  near_bound_vec <- logical(n_limbs)
  fit_starts_list <- vector("list", n_limbs)
  boot_list <- vector("list", n_limbs)

  if (n_boot > 0 && !is.null(boot_seed)) {
    old_seed <- if (exists(".Random.seed", envir = .GlobalEnv)) {
      get(".Random.seed", envir = .GlobalEnv)
    } else {
      NULL
    }
    on.exit(
      {
        if (!is.null(old_seed)) {
          assign(".Random.seed", old_seed, envir = .GlobalEnv)
        } else if (exists(".Random.seed", envir = .GlobalEnv)) {
          rm(".Random.seed", envir = .GlobalEnv)
        }
      },
      add = TRUE
    )
    set.seed(boot_seed)
  }

  for (i in seq_len(n_limbs)) {
    lb <- meta_dt$limb[i]
    limb_dt <- gaugings_dt[limb == lb]

    limb_stage_min <- min(limb_dt$stage_m)
    n_lower <- if (is.null(n_bounds)) 1e-6 else n_bounds[1]
    n_upper <- if (is.null(n_bounds)) Inf else n_bounds[2]
    fit_lower <- c(C = 1e-6, a = -limb_stage_min + 1e-6, n = n_lower)
    fit_upper <- c(C = Inf, a = Inf, n = n_upper)
    start_a <- if (fit_lower[["a"]] > 0) fit_lower[["a"]] + 0.01 else 0

    if (multi_start) {
      fit_result <- .fit_limb_multi_start(limb_dt, fit_lower, fit_upper, formula = fit_formula, maxiter = 100L, ...)
      if (is.null(fit_result$model)) {
        stop(sprintf(
          "rate_optimise(): limb %s -- no starting combination converged to a valid, monotonic equation across %d attempts.",
          lb, fit_result$n_starts_attempted
        ))
      }
      model <- fit_result$model
      n_starts_attempted_vec[i] <- fit_result$n_starts_attempted
      n_starts_converged_vec[i] <- fit_result$n_starts_converged
      selected_start_id_vec[i] <- fit_result$selected_start_id
      fit_starts_list[[i]] <- data.table(limb = lb, fit_result$attempts)
    } else {
      start_n <- min(max(1, n_lower), if (is.finite(n_upper)) n_upper else Inf)
      model <- nlsLM(
        formula = fit_formula,
        data = limb_dt,
        start = list(C = 1, a = start_a, n = start_n),
        lower = fit_lower,
        upper = fit_upper,
        control = nls.lm.control(maxiter = 100),
        ...
      )
      n_starts_attempted_vec[i] <- 1L
      n_starts_converged_vec[i] <- 1L
      selected_start_id_vec[i] <- 1L
      fit_starts_list[[i]] <- NULL
    }

    coefs <- coef(model)
    # Diagnostics are always computed on the natural discharge (cms) scale,
    # recomputed from the fitted coefficients rather than taken from
    # residuals(model) -- the latter would be log-scale residuals under
    # objective = "relative", not comparable to the absolute-objective
    # case. For objective = "absolute" this reproduces residuals(model)
    # exactly, since that's literally what was optimised.
    predicted_cms <- coefs[["C"]] * (limb_dt$stage_m + coefs[["a"]])^coefs[["n"]]
    resid_vals <- limb_dt$discharge_cms - predicted_cms
    ss_res <- sum(resid_vals^2)
    ss_tot <- sum((limb_dt$discharge_cms - mean(limb_dt$discharge_cms))^2)
    limb_width_for_bound_check <- max(limb_dt$stage_m) - min(limb_dt$stage_m)
    near_bound_vec[i] <- (coefs[["n"]] - fit_lower[["n"]]) < 0.01 ||
      (is.finite(fit_upper[["n"]]) && (fit_upper[["n"]] - coefs[["n"]]) < 0.01) ||
      (coefs[["a"]] - fit_lower[["a"]]) < 0.01 * max(limb_width_for_bound_check, 1e-6)

    C_vec[i] <- coefs[["C"]]
    a_vec[i] <- coefs[["a"]]
    n_vec[i] <- coefs[["n"]]
    rmse_vec[i] <- sqrt(mean(resid_vals^2))
    r_squared_vec[i] <- if (ss_tot > 1e-12) 1 - ss_res / ss_tot else NA_real_
    n_obs_vec[i] <- nrow(limb_dt)
    n_unique_stage_vec[i] <- length(unique(limb_dt$stage_m))
    mean_error_vec[i] <- mean(resid_vals)
    median_abs_error_vec[i] <- median(abs(resid_vals))
    max_abs_error_vec[i] <- max(abs(resid_vals))
    residual_df_vec[i] <- nrow(limb_dt) - 3L

    if (n_boot > 0) {
      n_limb_obs <- nrow(limb_dt)
      boot_draw_list <- vector("list", n_boot)

      for (b in seq_len(n_boot)) {
        boot_idx <- sample.int(n_limb_obs, n_limb_obs, replace = TRUE)
        limb_boot_dt <- limb_dt[boot_idx]
        n_unique_boot_stage <- length(unique(limb_boot_dt$stage_m))
        boot_stage_span <- diff(range(limb_boot_dt$stage_m))

        if (n_unique_boot_stage < 3L) {
          boot_draw_list[[b]] <- data.table(
            limb = lb, draw = b, success = FALSE,
            reason = "resample has fewer than 3 unique stage values",
            C = NA_real_, a = NA_real_, n = NA_real_
          )
          next
        }
        if (!is.finite(boot_stage_span) || boot_stage_span <= 0) {
          boot_draw_list[[b]] <- data.table(
            limb = lb, draw = b, success = FALSE,
            reason = "resample has zero stage span",
            C = NA_real_, a = NA_real_, n = NA_real_
          )
          next
        }

        boot_fit <- tryCatch(
          suppressWarnings(nlsLM(
            formula = fit_formula,
            data = limb_boot_dt,
            start = list(C = coefs[["C"]], a = coefs[["a"]], n = coefs[["n"]]),
            lower = fit_lower,
            upper = fit_upper,
            control = nls.lm.control(maxiter = 100)
          )),
          error = function(e) e
        )

        if (inherits(boot_fit, "error")) {
          boot_draw_list[[b]] <- data.table(
            limb = lb, draw = b, success = FALSE,
            reason = conditionMessage(boot_fit),
            C = NA_real_, a = NA_real_, n = NA_real_
          )
        } else {
          boot_coefs <- coef(boot_fit)
          boot_draw_list[[b]] <- data.table(
            limb = lb, draw = b, success = TRUE, reason = NA_character_,
            C = boot_coefs[["C"]], a = boot_coefs[["a"]], n = boot_coefs[["n"]]
          )
        }
      }

      limb_boot_all_dt <- rbindlist(boot_draw_list)
      n_success <- sum(limb_boot_all_dt$success)
      success_fraction <- n_success / n_boot

      n_boot_requested_vec[i] <- n_boot
      n_boot_success_vec[i] <- n_success
      n_boot_failed_vec[i] <- n_boot - n_success
      boot_success_fraction_vec[i] <- success_fraction

      if (success_fraction < min_boot_success) {
        warning(sprintf(
          "rate_optimise(): limb %s -- bootstrap success fraction %.2f is below min_boot_success (%.2f); %d of %d draws failed or were rejected.",
          lb, success_fraction, min_boot_success, n_boot - n_success, n_boot
        ))
      }

      if (n_success >= 2L) {
        ok_dt <- limb_boot_all_dt[success == TRUE]
        C_se_vec[i] <- sd(ok_dt$C)
        a_se_vec[i] <- sd(ok_dt$a)
        n_se_vec[i] <- sd(ok_dt$n)
        C_q_vals <- quantile(ok_dt$C, c(0.025, 0.5, 0.975), names = FALSE)
        a_q_vals <- quantile(ok_dt$a, c(0.025, 0.5, 0.975), names = FALSE)
        n_q_vals <- quantile(ok_dt$n, c(0.025, 0.5, 0.975), names = FALSE)
        C_q025_vec[i] <- C_q_vals[1]
        C_q50_vec[i] <- C_q_vals[2]
        C_q975_vec[i] <- C_q_vals[3]
        a_q025_vec[i] <- a_q_vals[1]
        a_q50_vec[i] <- a_q_vals[2]
        a_q975_vec[i] <- a_q_vals[3]
        n_q025_vec[i] <- n_q_vals[1]
        n_q50_vec[i] <- n_q_vals[2]
        n_q975_vec[i] <- n_q_vals[3]
      }

      boot_list[[i]] <- limb_boot_all_dt
    }
  }

  meta_dt[, `:=`(
    C = C_vec, a = a_vec, n = n_vec,
    rmse_cms = rmse_vec, r_squared = r_squared_vec, n_obs = n_obs_vec,
    n_unique_stage = n_unique_stage_vec, mean_error_cms = mean_error_vec,
    median_abs_error_cms = median_abs_error_vec, max_abs_error_cms = max_abs_error_vec,
    residual_df = residual_df_vec, n_starts_attempted = n_starts_attempted_vec,
    n_starts_converged = n_starts_converged_vec, selected_start_id = selected_start_id_vec,
    near_bound = near_bound_vec
  )]

  fit_starts_out <- NULL
  if (multi_start) {
    fit_starts_present <- fit_starts_list[!sapply(fit_starts_list, is.null)]
    if (length(fit_starts_present) > 0) fit_starts_out <- rbindlist(fit_starts_present)
  }

  bootstrap_out <- NULL
  if (n_boot > 0) {
    meta_dt[, `:=`(
      C_se = C_se_vec, a_se = a_se_vec, n_se = n_se_vec,
      C_q025 = C_q025_vec, C_q50 = C_q50_vec, C_q975 = C_q975_vec,
      a_q025 = a_q025_vec, a_q50 = a_q50_vec, a_q975 = a_q975_vec,
      n_q025 = n_q025_vec, n_q50 = n_q50_vec, n_q975 = n_q975_vec,
      n_boot_requested = n_boot_requested_vec, n_boot_success = n_boot_success_vec,
      n_boot_failed = n_boot_failed_vec, boot_success_fraction = boot_success_fraction_vec
    )]
    bootstrap_out <- rbindlist(boot_list)
  }

  FlodeRating(
    limbs = meta_dt[],
    gaugings = gaugings_dt,
    bootstrap = bootstrap_out,
    fit_starts = fit_starts_out,
    status = "independently_fitted",
    provenance = list(
      fitting_equation = if (objective == "relative") {
        "log(Q) = log(C) + n*log(H + a)"
      } else {
        "Q = C(H + a)^n"
      },
      fitting_method = if (multi_start) "multi-start nlsLM (minpack.lm)" else "single-start nlsLM (minpack.lm)",
      objective = objective,
      n_bounds = n_bounds,
      control = control,
      n_boot = n_boot,
      multi_start = multi_start,
      tool_version = "rating_curves 1.0"
    )
  )
}

#' Fit a multi-limb rating with junction continuity built into the fit
#'
#' @description
#' `rate_optimise()` fits each limb independently, which is exactly why
#' junction gaps exist to detect (`detect_rc_gaps()`) and two ways exist
#' to close them (`resolve_rc_gaps()`'s table patch,
#' `align_limb_equations()`'s `C`-only rescale). Neither of those two
#' produces an *optimised* rating once gaps are closed. This does the
#' constrained version properly: starting from `rate_optimise()`'s
#' independent fit, every limb except `anchor_limb` is *refit* against
#' its own gaugings, subject to matching its already-finalised
#' neighbour's discharge exactly at their shared junction stage --
#' propagating outward from the anchor exactly as `align_limb_equations()`
#' does. The constraint is enforced by reparameterising the model:
#' `Q = Q_target * ((H + a) / (brk + a))^n`, which equals `Q_target` at
#' `H = brk` for any `a`/`n`, so `nlsLM` is free to optimise both over
#' the limb's own gaugings while continuity holds automatically.
#'
#' @param discharge_cms,stage_m,control,n_bounds As in [rate_optimise()].
#'   Unlike `objective`, `n_bounds` is honoured by *both* the initial fit
#'   and this function's own constrained refit, since a hydraulic bound
#'   on `n` should hold for every limb, not just the anchor.
#' @param anchor_limb Integer. Row index of the limb left unconstrained.
#'   Default `1L`.
#' @param ... Passed to `rate_optimise()`'s initial (unconstrained) fit --
#'   this includes `gauging_datetime`, which needs no special handling
#'   here since it's simply stored on `@gaugings`, not used by either
#'   function's fitting itself. It also includes `objective`, which
#'   applies to the initial fit (and so to `anchor_limb`, which is never
#'   refit) -- the constrained refit this function performs for every
#'   other limb uses its own reparameterised, absolute-residual-only
#'   formula regardless of `objective`.
#'   `n_boot` is accepted but the resulting bootstrap draws describe the
#'   *unconstrained* fit and are dropped with a warning rather than
#'   presented alongside updated point estimates; `fit_starts` is
#'   dropped silently for the same reason. `n_starts_attempted`/
#'   `n_starts_converged`/`selected_start_id` are set to `NA` and
#'   `near_bound` is recomputed for any limb this function actually
#'   refits, since the constrained refit is always single-start.
#'
#' @return A [FlodeRating] instance in the same shape as
#'   `rate_optimise()`'s, plus an `aligned` logical column in `@limbs`
#'   (`FALSE` for `anchor_limb`, `TRUE` for every refit limb) and
#'   `@status` `"constrained_refit"`. If a constrained refit fails to
#'   converge for some limb, that limb's original unconstrained fit is
#'   kept and a warning is issued.
#'
#' @seealso [rate_optimise()], `align_limb_equations()` (in the
#'   `gap_check` module) for the closed-form, no-refit alternative
#'
#' @export
rate_optimise_constrained <- function(discharge_cms, stage_m, control = NULL, anchor_limb = 1L,
                                       n_bounds = NULL, ...) {
  fit <- rate_optimise(discharge_cms, stage_m, control = control, n_bounds = n_bounds, ...)
  limbs_dt <- copy(fit@limbs)
  gaugings_dt <- fit@gaugings
  n_limbs <- nrow(limbs_dt)

  if (anchor_limb < 1L || anchor_limb > n_limbs) {
    stop("anchor_limb must be a valid row index of the fit")
  }

  limbs_dt[, aligned := FALSE]

  if (n_limbs < 2L) {
    # Nothing to constrain against -- return the plain unconstrained fit
    # (with the just-added `aligned` column) unchanged otherwise.
    return(FlodeRating(
      limbs = limbs_dt[], gaugings = gaugings_dt,
      bootstrap = fit@bootstrap, fit_starts = fit@fit_starts,
      status = fit@status, provenance = fit@provenance
    ))
  }

  bootstrap_out <- fit@bootstrap
  fit_starts_out <- fit@fit_starts

  if (!is.null(fit@bootstrap) || "C_se" %in% names(limbs_dt)) {
    warning(
      "rate_optimise_constrained(): bootstrap uncertainty (n_boot) describes the ",
      "unconstrained fit and is not recomputed for the constrained refit; dropped ",
      "rather than presented alongside updated point estimates."
    )
    bootstrap_out <- NULL
    limbs_dt[, c("C_se", "a_se", "n_se") := NULL]
  }
  if (!is.null(fit_starts_out)) fit_starts_out <- NULL

  eval_q <- function(C, a, n, H) {
    depth <- H + a
    fifelse(depth <= 0, 0, C * depth^n)
  }

  refit_constrained_limb <- function(lb, brk, target_q, start_a, start_n) {
    limb_dt <- gaugings_dt[limb == lb]

    # a must keep both (H + a) and (brk + a) strictly positive -- brk can
    # sit below this limb's own minimum gauged stage (an extrapolation
    # gap), so the binding constraint is whichever of the two is smaller.
    a_lower <- -min(brk, min(limb_dt$stage_m)) + 1e-6
    n_lower <- if (is.null(n_bounds)) 1e-6 else n_bounds[1]
    n_upper <- if (is.null(n_bounds)) Inf else n_bounds[2]
    fit_lower <- c(a = a_lower, n = n_lower)
    fit_upper <- c(a = Inf, n = n_upper)
    start_a_clipped <- max(start_a, a_lower + 0.01)
    start_n_clipped <- min(max(start_n, n_lower), if (is.finite(n_upper)) n_upper else start_n)

    model <- tryCatch(
      suppressWarnings(nlsLM(
        formula = discharge_cms ~ target_q * ((stage_m + a) / (brk + a))^n,
        data = limb_dt,
        start = list(a = start_a_clipped, n = start_n_clipped),
        lower = fit_lower,
        upper = fit_upper,
        control = nls.lm.control(maxiter = 200)
      )),
      error = function(e) NULL
    )

    if (is.null(model)) {
      warning(sprintf(
        "rate_optimise_constrained(): limb %s failed to converge under the junction constraint; keeping its unconstrained fit.",
        lb
      ))
      return(NULL)
    }

    coefs <- coef(model)
    a_new <- coefs[["a"]]
    n_new <- coefs[["n"]]
    C_new <- target_q / (brk + a_new)^n_new

    # nlsLM's own bounds keep (brk + a_new) and n_new inside a valid
    # domain, but that doesn't guarantee C_new comes out finite and
    # positive: a_new landing extremely close to its lower bound can
    # underflow/overflow (brk + a_new)^n_new, and the primary
    # rate_optimise() fit validates exactly this (a stage-grid
    # domain/monotonicity check inside .fit_limb_multi_start()) before
    # accepting a result -- this refit path needs the same guard, not
    # just "did nlsLM converge".
    if (!is.finite(C_new) || C_new <= 0) {
      warning(sprintf(
        "rate_optimise_constrained(): limb %s converged to a non-finite or non-positive C under the junction constraint; keeping its unconstrained fit.",
        lb
      ))
      return(NULL)
    }

    resid_vals <- residuals(model)
    ss_res <- sum(resid_vals^2)
    ss_tot <- sum((limb_dt$discharge_cms - mean(limb_dt$discharge_cms))^2)
    limb_width <- max(limb_dt$stage_m) - min(limb_dt$stage_m)

    list(
      C = C_new, a = a_new, n = n_new,
      rmse_cms = sqrt(mean(resid_vals^2)),
      r_squared = if (ss_tot > 1e-12) 1 - ss_res / ss_tot else NA_real_,
      near_bound = (n_new - fit_lower[["n"]]) < 0.01 ||
        (is.finite(fit_upper[["n"]]) && (fit_upper[["n"]] - n_new) < 0.01) ||
        (a_new - fit_lower[["a"]]) < 0.01 * max(limb_width, 1e-6)
    )
  }

  apply_result <- function(i, result) {
    if (is.null(result)) return(invisible(NULL))
    set(limbs_dt, i = i, j = "C", value = result$C)
    set(limbs_dt, i = i, j = "a", value = result$a)
    set(limbs_dt, i = i, j = "n", value = result$n)
    set(limbs_dt, i = i, j = "rmse_cms", value = result$rmse_cms)
    set(limbs_dt, i = i, j = "r_squared", value = result$r_squared)
    set(limbs_dt, i = i, j = "aligned", value = TRUE)
    if ("n_starts_attempted" %in% names(limbs_dt)) {
      set(limbs_dt, i = i, j = "n_starts_attempted", value = NA_integer_)
      set(limbs_dt, i = i, j = "n_starts_converged", value = NA_integer_)
      set(limbs_dt, i = i, j = "selected_start_id", value = NA_integer_)
    }
    if ("near_bound" %in% names(limbs_dt)) {
      set(limbs_dt, i = i, j = "near_bound", value = result$near_bound)
    }
  }

  if (anchor_limb < n_limbs) {
    for (i in seq(anchor_limb + 1L, n_limbs)) {
      brk <- limbs_dt$lower_stage_m[i]
      target_q <- eval_q(limbs_dt$C[i - 1L], limbs_dt$a[i - 1L], limbs_dt$n[i - 1L], brk)
      result <- refit_constrained_limb(limbs_dt$limb[i], brk, target_q, limbs_dt$a[i], limbs_dt$n[i])
      apply_result(i, result)
    }
  }

  if (anchor_limb > 1L) {
    for (i in seq(anchor_limb - 1L, 1L)) {
      brk <- limbs_dt$upper_stage_m[i]
      target_q <- eval_q(limbs_dt$C[i + 1L], limbs_dt$a[i + 1L], limbs_dt$n[i + 1L], brk)
      result <- refit_constrained_limb(limbs_dt$limb[i], brk, target_q, limbs_dt$a[i], limbs_dt$n[i])
      apply_result(i, result)
    }
  }

  FlodeRating(
    limbs = limbs_dt[],
    gaugings = gaugings_dt,
    bootstrap = bootstrap_out,
    fit_starts = fit_starts_out,
    status = "constrained_refit",
    provenance = c(fit@provenance, list(anchor_limb = anchor_limb))
  )
}

#' Plot a fitted rating curve against gauged points (S7 method)
#'
#' @description
#' Registered against the `rating_plot` generic (`flode_classes.R`) for
#' [FlodeRating]. Discharge on the x-axis, stage on the y-axis. Because
#' the fitted equation gives discharge as a function of stage, each
#' limb's curve is drawn via an explicit stage sequence -> discharge ->
#' `lines()`, since `curve()` only draws y as f(x).
#'
#' `fit` is a [FlodeRating] instance. `colours` is a character or
#' integer vector of plotting colours, one per limb, or `NULL`
#' (default) for a single colour. `n_points` (default `200L`) is the
#' number of points used to draw each limb's curve.
#'
#' @return `NULL`, invisibly.
#' @export
method(rating_plot, FlodeRating) <- function(fit, colours = NULL, n_points = 200L) {
  if (n_points <= 0) stop("n_points must be a positive integer")

  gaugings_dt <- fit@gaugings
  limbs_dt <- fit@limbs
  n_limbs <- nrow(limbs_dt)

  if (!is.null(colours) && length(colours) != n_limbs) {
    warning("Number of colours does not match the limb count; using a single colour.")
    colours <- NULL
  }

  with(gaugings_dt, plot(
    stage_m ~ discharge_cms,
    xlab = "Discharge (m\u00b3/s)",
    ylab = "Stage (m)"
  ))

  for (i in seq_len(n_limbs)) {
    col_i <- if (is.null(colours)) 2 else colours[i]
    stage_seq <- seq(limbs_dt$lower_stage_m[i], limbs_dt$upper_stage_m[i], length.out = n_points)
    discharge_seq <- limbs_dt$C[i] * (stage_seq + limbs_dt$a[i])^limbs_dt$n[i]
    lines(discharge_seq, stage_seq, col = col_i, lwd = 4)
  }

  if (n_limbs > 1L) {
    abline(h = limbs_dt$upper_stage_m[-n_limbs], col = 2, lwd = 2, lty = 2)
  }

  invisible(NULL)
}

#' Plot rating fit residuals by limb
#'
#' @description
#' Residual (observed minus fitted discharge) against stage, one facet
#' per limb. Not an S7 generic method -- [FlodeSegmentedRating] has no
#' equivalent yet -- so this takes a plain `inherits()` check.
#'
#' @param fit A [FlodeRating] instance.
#' @return A `ggplot` object, invisibly.
#' @export
plot_rating_residuals <- function(fit) {
  if (!S7_inherits(fit, FlodeRating)) {
    stop("fit must be a FlodeRating object from rate_optimise()")
  }

  gaugings_dt <- copy(fit@gaugings)
  limbs_dt <- fit@limbs

  gaugings_dt[limbs_dt, on = "limb", `:=`(
    fitted_cms = i.C * (stage_m + i.a)^i.n
  )]
  gaugings_dt[, residual_cms := discharge_cms - fitted_cms]

  p <- ggplot(gaugings_dt, aes(x = stage_m, y = residual_cms)) +
    geom_hline(yintercept = 0, linetype = "dashed", colour = "grey50") +
    geom_point(aes(colour = factor(limb)), size = 2) +
    facet_wrap(~limb, scales = "free_x", labeller = label_both) +
    labs(
      title = "Rating Fit Residuals by Limb",
      x = "Stage (m)", y = "Residual (m\u00b3/s)", colour = "Limb"
    ) +
    theme_minimal(base_size = 12) +
    theme(plot.title = element_text(face = "bold", size = 13))

  print(p)
  invisible(p)
}

#' Flag rating limbs that extrapolate substantially beyond their gaugings
#'
#' @description
#' Assesses support within each limb's own declared bounds (unsupported
#' distance at an internal breakpoint) and, separately, whether the
#' whole fitted rating's combined span fails to reach an operational
#' range if supplied, else the complete gauged range.
#'
#' @param fit A [FlodeRating] instance.
#' @param tol_frac Numeric. Fraction of a limb's stage width the
#'   unsupported gap may reach before being flagged. Default `0.05`.
#' @param operational_lower_m,operational_upper_m Numeric or `NULL`.
#'
#' @return A new [FlodeRating] instance with `@limbs` columns added:
#'   `gauged_min_stage_m`/`gauged_max_stage_m`, `lower_unsupported_m`/
#'   `upper_unsupported_m`, `lower_unsupported_frac`/
#'   `upper_unsupported_frac`, `extrapolates_below_range`/
#'   `extrapolates_above_range` (identical on every row -- a whole-fit
#'   property, not per-limb), and `doubtful`.
#' @export
flag_extrapolated_limbs <- function(fit, tol_frac = 0.05,
                                     operational_lower_m = NULL, operational_upper_m = NULL) {
  if (!S7_inherits(fit, FlodeRating)) {
    stop("fit must be a FlodeRating object from rate_optimise()")
  }
  if (!is.numeric(tol_frac) || tol_frac < 0) stop("tol_frac must be a non-negative number")
  if (!is.null(operational_lower_m) && (!is.numeric(operational_lower_m) || length(operational_lower_m) != 1L)) {
    stop("operational_lower_m must be NULL or a single number")
  }
  if (!is.null(operational_upper_m) && (!is.numeric(operational_upper_m) || length(operational_upper_m) != 1L)) {
    stop("operational_upper_m must be NULL or a single number")
  }

  gaugings_dt <- fit@gaugings
  limbs_dt <- copy(fit@limbs)

  gauge_range_dt <- gaugings_dt[, .(
    gauged_min_stage_m = min(stage_m),
    gauged_max_stage_m = max(stage_m)
  ), by = limb]

  ref_lower <- if (!is.null(operational_lower_m)) operational_lower_m else min(gaugings_dt$stage_m)
  ref_upper <- if (!is.null(operational_upper_m)) operational_upper_m else max(gaugings_dt$stage_m)

  limbs_dt[gauge_range_dt, on = "limb", `:=`(
    gauged_min_stage_m = gauged_min_stage_m,
    gauged_max_stage_m = gauged_max_stage_m
  )]
  limbs_dt[, `:=`(
    lower_unsupported_m = pmax(gauged_min_stage_m - lower_stage_m, 0),
    upper_unsupported_m = pmax(upper_stage_m - gauged_max_stage_m, 0)
  )]
  limbs_dt[, limb_width_m := upper_stage_m - lower_stage_m]
  limbs_dt[, `:=`(
    lower_unsupported_frac = lower_unsupported_m / limb_width_m,
    upper_unsupported_frac = upper_unsupported_m / limb_width_m
  )]
  limbs_dt[, `:=`(
    extrapolates_below_range = ref_lower < min(limbs_dt$lower_stage_m),
    extrapolates_above_range = ref_upper > max(limbs_dt$upper_stage_m)
  )]
  limbs_dt[, doubtful :=
    lower_unsupported_frac > tol_frac | upper_unsupported_frac > tol_frac |
      extrapolates_below_range | extrapolates_above_range]
  limbs_dt[, limb_width_m := NULL]

  FlodeRating(
    limbs = limbs_dt[], gaugings = gaugings_dt,
    bootstrap = fit@bootstrap, fit_starts = fit@fit_starts,
    status = fit@status, provenance = fit@provenance
  )
}

#' Suggest candidate stage breakpoints for a multi-limb rating fit
#'
#' @description
#' A heuristic aid for choosing `control` in [rate_optimise()]. Reuses
#' `rate_optimise()` directly: for each candidate stage, fits a two-limb
#' rating there and compares its AIC against the current best model
#' (penalising the extra parameters, unlike raw RSS). A candidate must
#' also clear `min_improvement`, a minimum relative RSS reduction, to be
#' eligible. Multiple breakpoints are found iteratively and greedily,
#' respecting `min_gap`. Not a claim that a statistically-supported
#' breakpoint corresponds to a real physical control change -- that
#' judgement remains yours.
#'
#' @param discharge_cms,stage_m Numeric vectors, as in [rate_optimise()].
#' @param max_breaks Integer. Maximum breakpoints to search for.
#'   Default `2L`.
#' @param min_obs_per_side Integer. Minimum gaugings required on each
#'   side of a candidate. Default `5L`.
#' @param min_improvement Numeric. Minimum relative RSS reduction
#'   required. Default `0.02`.
#' @param min_gap Numeric or `NULL`. Minimum stage distance between
#'   selected breakpoints. Default `NULL` (5% of the stage range).
#' @param max_candidates Integer. Candidates evaluated per round, capped
#'   and thinned if exceeded. Default `200L`.
#'
#' @return A `data.table`, one row per candidate evaluated across every
#'   round, with `candidate_stage`, `score`, `improvement`,
#'   `n_obs_lower`, `n_obs_upper`, `round`, `fit_status`, `rank`. The
#'   greedily-selected breakpoints are attached as the
#'   `"selected_breaks"` attribute -- use
#'   [suggested_breakpoints_vector()] to extract them.
#'
#' @seealso [rate_optimise()], [suggested_breakpoints_vector()]
#'
#' @export
suggest_breakpoints <- function(discharge_cms, stage_m, max_breaks = 2L,
                                 min_obs_per_side = 5L, min_improvement = 0.02,
                                 min_gap = NULL, max_candidates = 200L) {
  if (!is.numeric(discharge_cms)) stop("discharge_cms must be numeric")
  if (!is.numeric(stage_m)) stop("stage_m must be numeric")
  if (length(discharge_cms) != length(stage_m)) {
    stop("discharge_cms and stage_m must be the same length")
  }
  if (any(!is.finite(discharge_cms))) stop("discharge_cms must not contain NA, NaN, or infinite values")
  if (any(!is.finite(stage_m))) stop("stage_m must not contain NA, NaN, or infinite values")
  if (max_breaks < 1) stop("max_breaks must be at least 1")
  if (min_obs_per_side < 3) stop("min_obs_per_side must be at least 3 (rate_optimise()'s own minimum)")
  if (!is.numeric(min_improvement) || min_improvement < 0) stop("min_improvement must be a non-negative number")
  if (!is.null(min_gap) && (!is.numeric(min_gap) || min_gap <= 0)) stop("min_gap must be NULL or a positive number")
  if (max_candidates < 1) stop("max_candidates must be at least 1")

  ord <- order(stage_m)
  stage_sorted <- stage_m[ord]
  discharge_sorted <- discharge_cms[ord]
  n_total <- length(stage_sorted)
  if (is.null(min_gap)) min_gap <- diff(range(stage_sorted)) * 0.05

  empty_result <- function() {
    data.table(
      candidate_stage = numeric(0), score = numeric(0), improvement = numeric(0),
      n_obs_lower = integer(0), n_obs_upper = integer(0), round = integer(0),
      fit_status = character(0), rank = integer(0)
    )
  }

  .fit_rss_aic <- function(control) {
    fit <- tryCatch(
      rate_optimise(discharge_sorted, stage_sorted, control = control, multi_start = FALSE),
      error = function(e) NULL
    )
    if (is.null(fit)) return(NULL)
    rss <- sum(fit@limbs$rmse_cms^2 * fit@limbs$n_obs)
    k <- 3L * nrow(fit@limbs)
    list(fit = fit, rss = rss, aic = n_total * log(rss / n_total) + 2 * k)
  }

  baseline <- .fit_rss_aic(NULL)
  if (is.null(baseline)) {
    warning("suggest_breakpoints(): the baseline single-limb fit failed to converge; cannot score candidates.")
    return(empty_result())
  }

  unique_stages <- sort(unique(stage_sorted))
  selected_breaks <- numeric(0)
  current_best <- baseline
  all_round_results <- vector("list", max_breaks)

  for (round_i in seq_len(max_breaks)) {
    candidates <- unique_stages[-c(1L, length(unique_stages))]
    if (length(selected_breaks) > 0) {
      too_close <- vapply(candidates, function(s) any(abs(s - selected_breaks) < min_gap), logical(1))
      candidates <- candidates[!too_close]
    }
    if (length(candidates) == 0) break
    if (length(candidates) > max_candidates) {
      candidates <- candidates[round(seq(1, length(candidates), length.out = max_candidates))]
    }

    round_results <- vector("list", length(candidates))
    for (i in seq_along(candidates)) {
      bp <- candidates[i]
      trial_control <- sort(c(selected_breaks, bp))
      result <- .fit_rss_aic(trial_control)

      if (is.null(result)) {
        round_results[[i]] <- data.table(
          candidate_stage = bp, score = NA_real_, improvement = NA_real_,
          n_obs_lower = NA_integer_, n_obs_upper = NA_integer_, fit_status = "failed"
        )
        next
      }

      fit <- result$fit
      idx_lower <- which(abs(fit@limbs$upper_stage_m - bp) < 1e-9)
      idx_upper <- which(abs(fit@limbs$lower_stage_m - bp) < 1e-9)
      n_obs_lower <- if (length(idx_lower) == 1L) fit@limbs$n_obs[idx_lower] else NA_integer_
      n_obs_upper <- if (length(idx_upper) == 1L) fit@limbs$n_obs[idx_upper] else NA_integer_

      if ((!is.na(n_obs_lower) && n_obs_lower < min_obs_per_side) ||
        (!is.na(n_obs_upper) && n_obs_upper < min_obs_per_side)) {
        round_results[[i]] <- data.table(
          candidate_stage = bp, score = NA_real_, improvement = NA_real_,
          n_obs_lower = n_obs_lower, n_obs_upper = n_obs_upper, fit_status = "insufficient_obs"
        )
        next
      }

      round_results[[i]] <- data.table(
        candidate_stage = bp,
        score = current_best$aic - result$aic,
        improvement = (current_best$rss - result$rss) / current_best$rss,
        n_obs_lower = n_obs_lower, n_obs_upper = n_obs_upper, fit_status = "ok"
      )
    }

    round_dt <- rbindlist(round_results)
    round_dt[, round := round_i]
    all_round_results[[round_i]] <- round_dt

    ok_dt <- round_dt[fit_status == "ok" & !is.na(improvement) & improvement >= min_improvement & score > 0]
    if (nrow(ok_dt) == 0) break

    setorder(ok_dt, -score)
    selected_breaks <- sort(c(selected_breaks, ok_dt$candidate_stage[1]))
    current_best <- .fit_rss_aic(selected_breaks)
  }

  all_candidates_dt <- rbindlist(all_round_results[!vapply(all_round_results, is.null, logical(1))])
  if (nrow(all_candidates_dt) == 0) {
    result_dt <- empty_result()
    attr(result_dt, "selected_breaks") <- selected_breaks
    return(result_dt)
  }

  setorder(all_candidates_dt, round, -score)
  all_candidates_dt[, rank := seq_len(.N), by = round]
  attr(all_candidates_dt, "selected_breaks") <- selected_breaks
  all_candidates_dt[]
}

#' Extract the selected breakpoints from suggest_breakpoints() as a vector
#'
#' @param candidates_dt The data.table returned by [suggest_breakpoints()].
#' @return A numeric vector, sorted ascending.
#' @export
suggested_breakpoints_vector <- function(candidates_dt) {
  if (!is.data.table(candidates_dt)) {
    stop("candidates_dt must be the data.table returned by suggest_breakpoints()")
  }
  selected <- attr(candidates_dt, "selected_breaks")
  if (is.null(selected)) {
    stop("suggested_breakpoints_vector(): candidates_dt has no 'selected_breaks' attribute -- was it produced by suggest_breakpoints()?")
  }
  selected
}
