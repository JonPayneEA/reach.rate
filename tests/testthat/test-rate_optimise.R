test_that("rate_optimise fits a single limb when control is NULL", {
  discharge_cms <- c(177.685, 240.898, 221.954, 205.55, 383.051, 154.061, 216.582)
  stage_m <- c(1.855, 2.109, 2.037, 1.972, 2.574, 1.748, 2.016)

  fit <- rate_optimise(discharge_cms, stage_m)

  expect_s3_class(fit, "reach.rate::FlodeRating")
  expect_true(is.data.table(fit@limbs))
  expect_equal(nrow(fit@limbs), 1L)
  expect_equal(fit@limbs$limb, 1L)
  expect_equal(fit@limbs$lower_stage_m, min(stage_m))
  expect_equal(fit@limbs$upper_stage_m, max(stage_m))
  expect_true(all(c("C", "a", "n", "rmse_cms", "r_squared", "n_obs") %in% names(fit@limbs)))
  expect_true(all(c(
    "n_unique_stage", "mean_error_cms", "median_abs_error_cms",
    "max_abs_error_cms", "residual_df"
  ) %in% names(fit@limbs)))
  expect_equal(fit@limbs$n_unique_stage, length(unique(stage_m)))
  expect_equal(fit@limbs$residual_df, fit@limbs$n_obs - 3L)
  expect_true(fit@limbs$max_abs_error_cms >= fit@limbs$median_abs_error_cms)
  expect_equal(fit@limbs$n_obs, length(stage_m))

  gaugings_dt <- fit@gaugings
  expect_true(is.data.table(gaugings_dt))
  expect_equal(nrow(gaugings_dt), length(stage_m))
})

test_that("rate_optimise splits into limbs at each control breakpoint", {
  set.seed(1)
  stage_m <- seq(0.5, 3.5, by = 0.1)
  discharge_cms <- 5 * stage_m^1.6 + rnorm(length(stage_m), sd = 0.01)

  fit <- rate_optimise(discharge_cms, stage_m, control = c(1.5, 2.5))

  expect_equal(nrow(fit@limbs), 3L)
  expect_equal(fit@limbs$limb, 1:3)
  expect_equal(fit@limbs$lower_stage_m[1], min(stage_m))
  expect_equal(fit@limbs$upper_stage_m[3], max(stage_m))
  # Limb bounds must be contiguous: upper of limb n == lower of limb n+1
  expect_equal(fit@limbs$upper_stage_m[1], fit@limbs$lower_stage_m[2])
  expect_equal(fit@limbs$upper_stage_m[2], fit@limbs$lower_stage_m[3])
  # Diagnostics should be present and sane for a clean synthetic fit
  expect_true(all(fit@limbs$r_squared > 0.99))
  expect_true(all(fit@limbs$rmse_cms >= 0))
})

test_that("rate_optimise limb bounds do not depend on cut() label formatting", {
  set.seed(2)
  stage_m <- seq(0.111, 3.333, by = 0.05)
  discharge_cms <- 4 * stage_m^1.5 + rnorm(length(stage_m), sd = 0.01)
  control <- c(1.234, 2.345)

  fit <- rate_optimise(discharge_cms, stage_m, control = control)

  expect_equal(fit@limbs$lower_stage_m, c(min(stage_m), control))
  expect_equal(fit@limbs$upper_stage_m, c(control, max(stage_m)))
})

test_that("rate_optimise validates its inputs", {
  expect_error(rate_optimise("a", 1:5), "numeric")
  expect_error(rate_optimise(1:5, 1:4), "same length")
  expect_error(rate_optimise(numeric(0), numeric(0)), "at least one value")
  expect_error(rate_optimise(1:5, 1:5, control = "x"), "numeric or NULL")
})

test_that("rate_optimise errors when a limb has too few gaugings", {
  stage_m <- c(0.5, 0.6, 2.0, 2.1, 2.2, 2.3, 2.4, 3.5)
  discharge_cms <- 5 * stage_m^1.5
  # control = 1.0 leaves only 2 points below it
  expect_error(rate_optimise(discharge_cms, stage_m, control = 1.0), "at least 3 gaugings")
})

test_that("rate_optimise stores gauging_datetime on @gaugings when supplied", {
  discharge_cms <- c(177.685, 240.898, 221.954, 205.55, 383.051, 154.061, 216.582)
  stage_m <- c(1.855, 2.109, 2.037, 1.972, 2.574, 1.748, 2.016)
  gauging_datetime <- as.Date("2020-01-01") + 0:6

  fit <- rate_optimise(discharge_cms, stage_m, gauging_datetime = gauging_datetime)

  expect_true("gauging_datetime" %in% names(fit@gaugings))
  expect_equal(fit@gaugings$gauging_datetime, gauging_datetime)
})

test_that("rate_optimise accepts POSIXct as well as Date for gauging_datetime", {
  discharge_cms <- c(177.685, 240.898, 221.954, 205.55, 383.051, 154.061, 216.582)
  stage_m <- c(1.855, 2.109, 2.037, 1.972, 2.574, 1.748, 2.016)
  gauging_datetime <- as.POSIXct("2020-01-01", tz = "UTC") + (0:6) * 3600

  fit <- rate_optimise(discharge_cms, stage_m, gauging_datetime = gauging_datetime)

  expect_equal(fit@gaugings$gauging_datetime, gauging_datetime)
})

test_that("rate_optimise omitting gauging_datetime behaves exactly as before", {
  discharge_cms <- c(177.685, 240.898, 221.954, 205.55, 383.051, 154.061, 216.582)
  stage_m <- c(1.855, 2.109, 2.037, 1.972, 2.574, 1.748, 2.016)

  fit <- rate_optimise(discharge_cms, stage_m)

  expect_false("gauging_datetime" %in% names(fit@gaugings))
})

test_that("rate_optimise validates gauging_datetime", {
  discharge_cms <- c(177.685, 240.898, 221.954, 205.55, 383.051, 154.061, 216.582)
  stage_m <- c(1.855, 2.109, 2.037, 1.972, 2.574, 1.748, 2.016)

  expect_error(
    rate_optimise(discharge_cms, stage_m, gauging_datetime = seq_along(stage_m)),
    "Date or POSIXct"
  )
  expect_error(
    rate_optimise(discharge_cms, stage_m, gauging_datetime = as.Date("2020-01-01") + 0:5),
    "same length"
  )
})

test_that("rate_optimise_constrained forwards gauging_datetime through ...", {
  set.seed(1)
  stage_m <- seq(0.5, 3.5, by = 0.1)
  discharge_cms <- 5 * stage_m^1.6 + rnorm(length(stage_m), sd = 0.01)
  gauging_datetime <- as.Date("2020-01-01") + seq_along(stage_m)

  fit <- rate_optimise_constrained(
    discharge_cms, stage_m,
    control = c(1.5, 2.5), gauging_datetime = gauging_datetime
  )

  expect_equal(fit@gaugings$gauging_datetime, gauging_datetime)
})

test_that("FlodeRatingBase's validator rejects a malformed gauging_datetime column", {
  gaugings_dt <- data.table::data.table(
    discharge_cms = c(1, 2, 3), stage_m = c(1, 2, 3),
    gauging_datetime = c("2020-01-01", "2020-01-02", "2020-01-03")
  )
  limbs_dt <- data.table::data.table(
    limb = 1L, lower_stage_m = 1, upper_stage_m = 3, C = 1, a = 0, n = 1.5
  )
  expect_error(
    FlodeRating(gaugings = gaugings_dt, limbs = limbs_dt),
    "gauging_datetime.*Date or POSIXct"
  )
})

test_that("rating_plot runs without error for single- and multi-limb fits", {
  discharge_cms <- c(177.685, 240.898, 221.954, 205.55, 383.051, 154.061, 216.582)
  stage_m <- c(1.855, 2.109, 2.037, 1.972, 2.574, 1.748, 2.016)
  fit_single <- rate_optimise(discharge_cms, stage_m)

  pdf(NULL)
  on.exit(dev.off())

  expect_silent(rating_plot(fit_single))

  set.seed(3)
  stage_m2 <- seq(0.5, 3.5, by = 0.1)
  discharge_cms2 <- 5 * stage_m2^1.6 + rnorm(length(stage_m2), sd = 0.01)
  fit_multi <- rate_optimise(discharge_cms2, stage_m2, control = c(1.5, 2.5))

  expect_silent(rating_plot(fit_multi))
})

test_that("rating_plot falls back to a single colour when the colour count is wrong", {
  discharge_cms <- c(177.685, 240.898, 221.954, 205.55, 383.051, 154.061, 216.582)
  stage_m <- c(1.855, 2.109, 2.037, 1.972, 2.574, 1.748, 2.016)
  fit <- rate_optimise(discharge_cms, stage_m)

  pdf(NULL)
  on.exit(dev.off())

  expect_warning(rating_plot(fit, colours = c("red", "blue")), "does not match")
})

test_that("plot_rating_residuals returns a ggplot with one row of residuals per gauging", {
  set.seed(4)
  stage_m <- seq(0.5, 3.5, by = 0.1)
  discharge_cms <- 5 * stage_m^1.6 + rnorm(length(stage_m), sd = 0.02)
  fit <- rate_optimise(discharge_cms, stage_m, control = c(1.5, 2.5))

  pdf(NULL)
  on.exit(dev.off())

  p <- plot_rating_residuals(fit)
  expect_s3_class(p, "ggplot")
  expect_equal(nrow(p$data), length(stage_m))
  expect_true("residual_cms" %in% names(p$data))
})

test_that("plot_rating_residuals rejects an object that is not a FlodeRating fit", {
  expect_error(plot_rating_residuals(data.table(a = 1)), "FlodeRating")
})

test_that("flag_extrapolated_limbs flags a limb with a real gap but not a snug one", {
  # Limb 1's gaugings reach right up to the control breakpoint (2.0); limb
  # 2's gaugings don't start until 2.7, well past its declared lower bound
  # of 2.0 -- a genuine, substantial extrapolation gap.
  stage_m <- c(0.5, 0.8, 1.1, 1.4, 1.95, 2.0, 2.7, 2.85, 3.0)
  discharge_cms <- 5 * stage_m^1.5

  fit <- rate_optimise(discharge_cms, stage_m, control = 2.0)
  fit <- flag_extrapolated_limbs(fit)

  expect_true("doubtful" %in% names(fit@limbs))
  expect_false(fit@limbs$doubtful[1]) # limb 1 gaugings span its full declared range
  expect_true(fit@limbs$doubtful[2]) # limb 2 starts 0.7 m above its declared lower bound
})

test_that("flag_extrapolated_limbs rejects a non-FlodeRating object", {
  expect_error(flag_extrapolated_limbs(data.table(a = 1)), "FlodeRating")
})

test_that("flag_extrapolated_limbs returns the documented columns", {
  stage_m <- c(0.5, 0.8, 1.1, 1.4, 1.95, 2.0, 2.7, 2.85, 3.0)
  discharge_cms <- 5 * stage_m^1.5
  fit <- rate_optimise(discharge_cms, stage_m, control = 2.0)
  fit <- flag_extrapolated_limbs(fit)

  expect_true(all(c(
    "gauged_min_stage_m", "gauged_max_stage_m",
    "lower_unsupported_m", "upper_unsupported_m",
    "lower_unsupported_frac", "upper_unsupported_frac",
    "extrapolates_below_range", "extrapolates_above_range", "doubtful"
  ) %in% names(fit@limbs)))
})

test_that("flag_extrapolated_limbs does not flag range extrapolation without an operational range supplied", {
  # The fit's own outer bounds always exactly equal the overall gauged
  # min/max by construction, so without an explicit operational range,
  # extrapolates_below_range/above_range can never be TRUE.
  stage_m <- c(0.5, 0.8, 1.1, 1.4, 1.95, 2.0, 2.7, 2.85, 3.0)
  discharge_cms <- 5 * stage_m^1.5
  fit <- rate_optimise(discharge_cms, stage_m, control = 2.0)
  fit <- flag_extrapolated_limbs(fit)

  expect_false(any(fit@limbs$extrapolates_below_range))
  expect_false(any(fit@limbs$extrapolates_above_range))
})

test_that("flag_extrapolated_limbs flags extrapolation when the operational range exceeds the whole rating's span", {
  stage_m <- c(0.5, 0.8, 1.1, 1.4, 1.95, 2.0, 2.7, 2.85, 3.0)
  discharge_cms <- 5 * stage_m^1.5
  fit <- rate_optimise(discharge_cms, stage_m, control = 2.0)
  # The fit covers 0.5 to 3.0 in total; requesting 0.0 to 4.0 asks the
  # rating to reach further at both ends than it actually does.
  fit_op <- flag_extrapolated_limbs(fit, operational_lower_m = 0.0, operational_upper_m = 4.0)

  expect_true(all(fit_op@limbs$extrapolates_below_range)) # same value on every row
  expect_true(all(fit_op@limbs$extrapolates_above_range))
})

test_that("flag_extrapolated_limbs does not flag extrapolation when the operational range sits inside the fit", {
  stage_m <- c(0.5, 0.8, 1.1, 1.4, 1.95, 2.0, 2.7, 2.85, 3.0)
  discharge_cms <- 5 * stage_m^1.5
  fit <- rate_optimise(discharge_cms, stage_m, control = 2.0)
  # 1.0 to 2.5 sits entirely within the fit's 0.5-3.0 span
  fit_op <- flag_extrapolated_limbs(fit, operational_lower_m = 1.0, operational_upper_m = 2.5)

  expect_false(any(fit_op@limbs$extrapolates_below_range))
  expect_false(any(fit_op@limbs$extrapolates_above_range))
})

test_that("flag_extrapolated_limbs validates operational range arguments", {
  stage_m <- c(0.5, 0.8, 1.1, 1.4, 1.95, 2.0, 2.7, 2.85, 3.0)
  discharge_cms <- 5 * stage_m^1.5
  fit <- rate_optimise(discharge_cms, stage_m, control = 2.0)

  expect_error(flag_extrapolated_limbs(fit, operational_lower_m = "a"), "operational_lower_m")
  expect_error(flag_extrapolated_limbs(fit, operational_upper_m = c(1, 2)), "operational_upper_m")
})

test_that("suggest_breakpoints finds breakpoints near deliberate slope changes", {
  set.seed(5)
  stage_m <- seq(0.5, 3.5, by = 0.1)
  true_limb <- cut(stage_m, breaks = c(0.5, 1.6, 2.2, 3.5), labels = FALSE, include.lowest = TRUE)
  coefs_by_limb <- data.frame(C = c(3, 6, 10), n = c(1.4, 1.9, 2.4))
  discharge_cms <- coefs_by_limb$C[true_limb] * stage_m^coefs_by_limb$n[true_limb] +
    rnorm(length(stage_m), sd = 0.02)

  candidates_dt <- suggest_breakpoints(discharge_cms, stage_m, max_breaks = 2L, min_obs_per_side = 3L)

  expect_true(is.data.table(candidates_dt))
  expect_true(all(c(
    "candidate_stage", "score", "improvement", "n_obs_lower",
    "n_obs_upper", "round", "fit_status", "rank"
  ) %in% names(candidates_dt)))

  breaks <- suggested_breakpoints_vector(candidates_dt)
  expect_true(length(breaks) <= 2L)
  expect_true(is.numeric(breaks))
  expect_equal(breaks, sort(breaks))
  if (length(breaks) == 2L) {
    # Suggested breaks should land reasonably close to the true 1.6/2.2 breakpoints
    expect_true(any(abs(breaks - 1.6) < 0.3))
    expect_true(any(abs(breaks - 2.2) < 0.3))
  }
})

test_that("suggest_breakpoints validates its inputs", {
  expect_error(suggest_breakpoints(1:5, 1:4), "same length")
  expect_error(suggest_breakpoints(1:20, 1:20, min_obs_per_side = 1), "at least 3")
  expect_error(suggest_breakpoints(1:20, 1:20, max_breaks = 0), "at least 1")
  expect_error(suggest_breakpoints(1:20, 1:20, min_improvement = -1), "non-negative")
  expect_error(suggest_breakpoints(1:20, 1:20, min_gap = -1), "positive number")
  expect_error(suggest_breakpoints(1:20, 1:20, max_candidates = 0), "at least 1")
})

test_that("suggest_breakpoints suggests few or no breakpoints for a clean single power law", {
  set.seed(6)
  stage_m <- seq(0.5, 3.5, by = 0.1)
  discharge_cms <- 5 * stage_m^1.6 + rnorm(length(stage_m), sd = 0.001)

  candidates_dt <- suggest_breakpoints(discharge_cms, stage_m, max_breaks = 2L, min_improvement = 0.1)
  breaks <- suggested_breakpoints_vector(candidates_dt)
  expect_true(length(breaks) <= 1L)
})

test_that("suggest_breakpoints reports insufficient_obs for a candidate too close to the edge", {
  stage_m <- seq(0.5, 3.5, by = 0.1)
  discharge_cms <- 5 * stage_m^1.6
  candidates_dt <- suggest_breakpoints(
    discharge_cms, stage_m,
    max_breaks = 1L, min_obs_per_side = 10L, min_gap = 0.01
  )
  expect_true("insufficient_obs" %in% candidates_dt$fit_status)
})

test_that("suggested_breakpoints_vector errors on a malformed argument", {
  expect_error(suggested_breakpoints_vector(list()), "data.table")
  expect_error(suggested_breakpoints_vector(data.table(x = 1)), "selected_breaks")
})

test_that("rate_optimise with n_boot = 0 (default) has no bootstrap columns or attribute", {
  discharge_cms <- c(177.685, 240.898, 221.954, 205.55, 383.051, 154.061, 216.582)
  stage_m <- c(1.855, 2.109, 2.037, 1.972, 2.574, 1.748, 2.016)
  fit <- rate_optimise(discharge_cms, stage_m)

  expect_false(any(c("C_se", "a_se", "n_se") %in% names(fit@limbs)))
  expect_null(fit@bootstrap)
})

test_that("rate_optimise with n_boot > 0 adds *_se columns and a bootstrap slot", {
  set.seed(1)
  stage_m <- seq(0.5, 3.5, by = 0.1)
  discharge_cms <- 5 * stage_m^1.6 + rnorm(length(stage_m), sd = 0.02)

  fit <- rate_optimise(discharge_cms, stage_m, n_boot = 30L, boot_seed = 42L)

  expect_true(all(c("C_se", "a_se", "n_se") %in% names(fit@limbs)))
  expect_true(all(fit@limbs$C_se >= 0))
  expect_true(all(c("C_q025", "C_q50", "C_q975", "a_q025", "n_q975") %in% names(fit@limbs)))
  expect_true(all(c("n_boot_requested", "n_boot_success", "n_boot_failed", "boot_success_fraction") %in% names(fit@limbs)))
  expect_equal(fit@limbs$n_boot_requested, 30L)
  expect_true(fit@limbs$C_q025 <= fit@limbs$C_q50 && fit@limbs$C_q50 <= fit@limbs$C_q975)

  boot_dt <- fit@bootstrap
  expect_true(is.data.table(boot_dt))
  expect_true(all(c("limb", "draw", "success", "reason", "C", "a", "n") %in% names(boot_dt)))
  # Every requested draw is recorded now, success or not
  expect_equal(nrow(boot_dt), 30L)
  expect_equal(boot_dt$draw, 1:30) # single limb, draws keep their original numbering
})

test_that("rate_optimise rejects a degenerate bootstrap resample before fitting, not after", {
  # Three distinct stage values, heavily repeated -- resampling with
  # replacement from only 3 unique stages has a real chance of drawing
  # fewer than 3 unique values in a given resample, which should be
  # rejected (recorded as a failure with a reason) rather than handed to
  # nlsLM to fail on.
  stage_m <- rep(c(1.0, 1.5, 2.0), each = 3)
  discharge_cms <- 5 * stage_m^1.6
  fit <- suppressWarnings(rate_optimise(discharge_cms, stage_m, n_boot = 200L, boot_seed = 3L))

  boot_dt <- fit@bootstrap
  expect_true(any(!boot_dt$success))
  rejected_dt <- boot_dt[boot_dt$success == FALSE]
  expect_true(all(grepl("unique stage|stage span", rejected_dt$reason)))
})

test_that("rate_optimise warns when bootstrap success fraction is below min_boot_success", {
  stage_m <- rep(c(1.0, 1.5, 2.0), each = 3)
  discharge_cms <- 5 * stage_m^1.6
  expect_warning(
    rate_optimise(discharge_cms, stage_m, n_boot = 200L, boot_seed = 3L, min_boot_success = 0.99),
    "success fraction"
  )
})

test_that("rate_optimise multi_start = TRUE (default) adds bookkeeping columns and slot", {
  discharge_cms <- c(177.685, 240.898, 221.954, 205.55, 383.051, 154.061, 216.582)
  stage_m <- c(1.855, 2.109, 2.037, 1.972, 2.574, 1.748, 2.016)
  fit <- rate_optimise(discharge_cms, stage_m)

  expect_true(all(c(
    "n_starts_attempted", "n_starts_converged", "selected_start_id", "near_bound"
  ) %in% names(fit@limbs)))
  expect_true(fit@limbs$n_starts_attempted[1] > 1L)
  expect_true(fit@limbs$n_starts_converged[1] >= 1L)
  expect_true(fit@limbs$selected_start_id[1] >= 1L)
  expect_type(fit@limbs$near_bound, "logical")

  starts_dt <- fit@fit_starts
  expect_true(is.data.table(starts_dt))
  expect_true(all(c(
    "limb", "start_id", "C_start", "a_start", "n_start",
    "converged", "rss", "C_fit", "a_fit", "n_fit", "error_message"
  ) %in% names(starts_dt)))
  expect_equal(nrow(starts_dt), fit@limbs$n_starts_attempted[1])
})

test_that("rate_optimise multi_start = FALSE reproduces the original single-start behaviour", {
  discharge_cms <- c(177.685, 240.898, 221.954, 205.55, 383.051, 154.061, 216.582)
  stage_m <- c(1.855, 2.109, 2.037, 1.972, 2.574, 1.748, 2.016)
  fit <- rate_optimise(discharge_cms, stage_m, multi_start = FALSE)

  expect_equal(fit@limbs$n_starts_attempted, 1L)
  expect_equal(fit@limbs$n_starts_converged, 1L)
  expect_equal(fit@limbs$selected_start_id, 1L)
  expect_null(fit@fit_starts)
})

test_that("rate_optimise multi_start recovers a good fit for an awkward exponent", {
  # A high exponent is a case where a fixed n=1 start is furthest from
  # the truth; multi-start's varied n starting values (1, 1.5, 2, plus a
  # data-driven log-log estimate) give it a real chance to find the
  # right region rather than relying on one guess.
  set.seed(11)
  stage_m <- seq(0.5, 2.5, by = 0.04)
  discharge_cms <- 2 * stage_m^3.2 + rnorm(length(stage_m), sd = 0.01)

  fit <- rate_optimise(discharge_cms, stage_m, multi_start = TRUE)
  expect_true(fit@limbs$n_starts_converged >= 1L)
  expect_equal(fit@limbs$n, 3.2, tolerance = 0.3)
  expect_true(fit@limbs$r_squared > 0.98)
})

test_that("rate_optimise validates multi_start", {
  discharge_cms <- c(177.685, 240.898, 221.954, 205.55, 383.051, 154.061, 216.582)
  stage_m <- c(1.855, 2.109, 2.037, 1.972, 2.574, 1.748, 2.016)
  expect_error(rate_optimise(discharge_cms, stage_m, multi_start = "yes"), "single logical")
})

test_that("rate_optimise validates min_boot_success", {
  discharge_cms <- c(177.685, 240.898, 221.954, 205.55, 383.051, 154.061, 216.582)
  stage_m <- c(1.855, 2.109, 2.037, 1.972, 2.574, 1.748, 2.016)
  expect_error(rate_optimise(discharge_cms, stage_m, min_boot_success = 1.5), "between 0 and 1")
})

test_that("rate_optimise bootstrap is reproducible with the same boot_seed", {
  set.seed(1)
  stage_m <- seq(0.5, 3.5, by = 0.1)
  discharge_cms <- 5 * stage_m^1.6 + rnorm(length(stage_m), sd = 0.02)

  fit_a <- rate_optimise(discharge_cms, stage_m, n_boot = 20L, boot_seed = 7L)
  fit_b <- rate_optimise(discharge_cms, stage_m, n_boot = 20L, boot_seed = 7L)

  expect_equal(fit_a@bootstrap$C, fit_b@bootstrap$C)
})

test_that("rate_optimise validates n_boot", {
  discharge_cms <- c(177.685, 240.898, 221.954, 205.55, 383.051, 154.061, 216.582)
  stage_m <- c(1.855, 2.109, 2.037, 1.972, 2.574, 1.748, 2.016)
  expect_error(rate_optimise(discharge_cms, stage_m, n_boot = -1), "non-negative integer")
})

test_that("rate_optimise rejects non-finite and negative discharge, and a zero stage range", {
  stage_m <- c(1.0, 1.5, 2.0, 2.5, 3.0)
  ok_discharge <- c(5, 8, 12, 16, 20)

  expect_error(rate_optimise(c(ok_discharge[-1], NA), stage_m), "NA, NaN, or infinite")
  expect_error(rate_optimise(c(ok_discharge[-1], Inf), stage_m), "NA, NaN, or infinite")
  expect_error(rate_optimise(ok_discharge, c(stage_m[-1], NA)), "NA, NaN, or infinite")
  expect_error(rate_optimise(c(-1, ok_discharge[-1]), stage_m), "non-negative")
  expect_error(rate_optimise(ok_discharge, rep(1.5, 5)), "non-zero range")
})

test_that("rate_optimise rejects duplicate or out-of-range breakpoints", {
  stage_m <- seq(0.5, 3.5, by = 0.1)
  discharge_cms <- 5 * stage_m^1.6
  expect_error(rate_optimise(discharge_cms, stage_m, control = c(1.5, 1.5)), "unique")
  expect_error(rate_optimise(discharge_cms, stage_m, control = c(0.2)), "strictly inside")
  expect_error(rate_optimise(discharge_cms, stage_m, control = c(4.0)), "strictly inside")
})

test_that("rate_optimise errors clearly on a completely empty limb rather than silently dropping it", {
  # Two tight clusters of gaugings with a control breakpoint placed in the
  # gap between them: the middle limb this implies has zero observations.
  stage_m <- c(0.5, 0.6, 0.7, 0.8, 3.0, 3.1, 3.2, 3.3)
  discharge_cms <- 5 * stage_m^1.5
  expect_error(
    rate_optimise(discharge_cms, stage_m, control = c(1.5, 2.5)),
    "limb\\(s\\) 2 have 0"
  )
})

test_that("rate_optimise restores the caller's RNG state after a seeded bootstrap", {
  set.seed(123)
  runif(1) # advance the RNG once, so "no change at all" isn't trivially true

  stage_m <- seq(0.5, 3.5, by = 0.1)
  discharge_cms <- 5 * stage_m^1.6 + rnorm(length(stage_m), sd = 0.02)

  # Capture the exact pre-call state (after generating discharge_cms, which
  # itself draws from the stream via rnorm()) and compare byte-for-byte,
  # rather than replaying a fixed number of runif() calls from set.seed():
  # the latter silently ignores however many draws building discharge_cms
  # itself consumed, so it doesn't actually reproduce the pre-call state.
  seed_before_call <- .Random.seed
  invisible(rate_optimise(discharge_cms, stage_m, n_boot = 20L, boot_seed = 99L))

  expect_identical(.Random.seed, seed_before_call)
})

build_three_limb_gaugings <- function(seed = 10, sd = 0.03) {
  set.seed(seed)
  stage_seq <- seq(0.5, 3.5, by = 0.03)
  true_limb <- cut(stage_seq, breaks = c(0.5, 1.6, 2.2, 3.5), labels = FALSE, include.lowest = TRUE)
  coefs_by_limb <- data.frame(C = c(3, 6, 10), a = c(0, 0.1, 0.2), n = c(1.4, 1.6, 1.8))
  discharge_seq <- coefs_by_limb$C[true_limb] *
    (stage_seq + coefs_by_limb$a[true_limb])^coefs_by_limb$n[true_limb] +
    rnorm(length(stage_seq), sd = sd)
  list(discharge = discharge_seq, stage = stage_seq)
}

test_that("rate_optimise_constrained keeps the anchor limb's fit unchanged", {
  g <- build_three_limb_gaugings()
  fit_plain <- rate_optimise(g$discharge, g$stage, control = c(1.6, 2.2))
  fit_constrained <- rate_optimise_constrained(g$discharge, g$stage, control = c(1.6, 2.2), anchor_limb = 1L)

  expect_equal(fit_constrained@limbs$C[1], fit_plain@limbs$C[1])
  expect_equal(fit_constrained@limbs$a[1], fit_plain@limbs$a[1])
  expect_equal(fit_constrained@limbs$n[1], fit_plain@limbs$n[1])
  expect_false(fit_constrained@limbs$aligned[1])
  expect_true(all(fit_constrained@limbs$aligned[2:3]))
  expect_equal(fit_constrained@status, "constrained_refit")
})

test_that("rate_optimise_constrained closes every junction exactly", {
  g <- build_three_limb_gaugings()
  fit <- rate_optimise_constrained(g$discharge, g$stage, control = c(1.6, 2.2))
  limbs_dt <- fit@limbs

  eval_q <- function(C, a, n, H) C * (H + a)^n

  q_limb1_top <- eval_q(limbs_dt$C[1], limbs_dt$a[1], limbs_dt$n[1], limbs_dt$upper_stage_m[1])
  q_limb2_bottom <- eval_q(limbs_dt$C[2], limbs_dt$a[2], limbs_dt$n[2], limbs_dt$lower_stage_m[2])
  expect_equal(q_limb1_top, q_limb2_bottom, tolerance = 1e-6)

  q_limb2_top <- eval_q(limbs_dt$C[2], limbs_dt$a[2], limbs_dt$n[2], limbs_dt$upper_stage_m[2])
  q_limb3_bottom <- eval_q(limbs_dt$C[3], limbs_dt$a[3], limbs_dt$n[3], limbs_dt$lower_stage_m[3])
  expect_equal(q_limb2_top, q_limb3_bottom, tolerance = 1e-6)
})

test_that("rate_optimise_constrained still fits each constrained limb reasonably well", {
  g <- build_three_limb_gaugings()
  fit <- rate_optimise_constrained(g$discharge, g$stage, control = c(1.6, 2.2))
  # A clean synthetic fit under a single junction constraint should still
  # explain most of the variance in each limb's own gaugings -- but the
  # constrained refit is always single-start (documented tradeoff: two
  # parameters compensate for the fixed junction rather than three), so
  # this is a "not degenerate" floor, not the >0.99 a multi-start
  # unconstrained fit on the same data reaches.
  expect_true(all(fit@limbs$r_squared > 0.75))
})

test_that("rate_optimise_constrained with a middle anchor propagates both ways", {
  g <- build_three_limb_gaugings()
  fit_plain <- rate_optimise(g$discharge, g$stage, control = c(1.6, 2.2))
  # For this fixture, the downward refit (limb 1, constrained to match
  # anchor limb 2 at their shared junction) converges to a non-finite or
  # non-positive C -- refit_constrained_limb()'s single-start nlsLM
  # landing at a genuinely degenerate solution, not a bug in the
  # constraint logic itself (the upward refit, limb 3, converges fine).
  # rate_optimise_constrained() catches this the same way it already
  # catches outright non-convergence: warn and keep that limb's
  # unconstrained fit rather than returning an invalid rating.
  expect_warning(
    fit_constrained <- rate_optimise_constrained(g$discharge, g$stage, control = c(1.6, 2.2), anchor_limb = 2L),
    "non-finite or non-positive C"
  )

  expect_equal(fit_constrained@limbs$C[2], fit_plain@limbs$C[2])
  expect_false(fit_constrained@limbs$aligned[2]) # anchor: never aligned
  expect_false(fit_constrained@limbs$aligned[1]) # degenerate refit: fell back
  expect_equal(fit_constrained@limbs$C[1], fit_plain@limbs$C[1]) # ...to the unconstrained fit exactly
  expect_true(fit_constrained@limbs$aligned[3]) # upward direction: converges fine
})

test_that("rate_optimise_constrained returns the plain fit unchanged for a single limb", {
  discharge_cms <- c(177.685, 240.898, 221.954, 205.55, 383.051, 154.061, 216.582)
  stage_m <- c(1.855, 2.109, 2.037, 1.972, 2.574, 1.748, 2.016)
  fit <- rate_optimise_constrained(discharge_cms, stage_m)

  expect_equal(nrow(fit@limbs), 1L)
  expect_false(fit@limbs$aligned[1])
})

test_that("rate_optimise_constrained drops bootstrap uncertainty with a warning", {
  g <- build_three_limb_gaugings()
  expect_warning(
    fit <- rate_optimise_constrained(
      g$discharge, g$stage, control = c(1.6, 2.2), n_boot = 20L, boot_seed = 1L
    ),
    "bootstrap uncertainty"
  )
  expect_false(any(c("C_se", "a_se", "n_se") %in% names(fit@limbs)))
  expect_null(fit@bootstrap)
})

test_that("rate_optimise_constrained clears/recomputes multi-start diagnostics for refit limbs", {
  g <- build_three_limb_gaugings()
  fit_constrained <- rate_optimise_constrained(g$discharge, g$stage, control = c(1.6, 2.2), anchor_limb = 1L)
  limbs_dt <- fit_constrained@limbs

  # Anchor limb keeps its original multi-start bookkeeping
  expect_true(limbs_dt$n_starts_attempted[1] > 1L)
  # Refit limbs' bookkeeping is cleared, not left describing the
  # superseded unconstrained fit
  expect_true(is.na(limbs_dt$n_starts_attempted[2]))
  expect_true(is.na(limbs_dt$n_starts_converged[2]))
  expect_true(is.na(limbs_dt$selected_start_id[2]))
  # near_bound is recomputed (not NA) against the new coefficients
  expect_false(is.na(limbs_dt$near_bound[2]))
  expect_null(fit_constrained@fit_starts)
})

test_that("rate_optimise_constrained's refit stays valid when the junction stage sits below the limb's own gaugings", {
  # Deliberately sparse limb 2 whose gaugings start well above its
  # declared lower bound (an extrapolation gap), so the junction stage
  # brk is below min(limb_dt$stage_m) -- exactly the case where the
  # constrained refit's a-bound must be tied to brk, not just the
  # limb's own stage minimum, or (brk + a) could go non-positive.
  set.seed(21)
  stage_m <- c(seq(0.5, 1.6, by = 0.05), seq(2.0, 3.5, by = 0.05))
  true_limb <- ifelse(stage_m <= 1.6, 1L, 2L)
  coefs_by_limb <- data.frame(C = c(3, 8), a = c(0, 0.2), n = c(1.4, 1.7))
  discharge_cms <- coefs_by_limb$C[true_limb] *
    (stage_m + coefs_by_limb$a[true_limb])^coefs_by_limb$n[true_limb] +
    rnorm(length(stage_m), sd = 0.02)

  fit_constrained <- rate_optimise_constrained(discharge_cms, stage_m, control = c(1.6))
  expect_true(all(is.finite(fit_constrained@limbs$C)))
  expect_true(all(is.finite(fit_constrained@limbs$a)))
  expect_true(all(is.finite(fit_constrained@limbs$n)))
})

test_that("rate_optimise_constrained validates anchor_limb", {
  g <- build_three_limb_gaugings()
  expect_error(
    rate_optimise_constrained(g$discharge, g$stage, control = c(1.6, 2.2), anchor_limb = 5L),
    "valid row index"
  )
})
