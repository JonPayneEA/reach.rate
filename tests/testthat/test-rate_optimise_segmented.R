build_single_segment_gaugings <- function(seed = 1, sd = 0.03) {
  set.seed(seed)
  stage_m <- seq(0.3, 3.5, by = 0.05)
  discharge_cms <- 4 * pmax(stage_m - 0.1, 0)^1.55 * exp(rnorm(length(stage_m), sd = sd))
  list(discharge = discharge_cms, stage = stage_m)
}

build_three_segment_gaugings <- function(seed = 1, sd = 0.03) {
  set.seed(seed)
  stage_m <- seq(0.3, 3.5, by = 0.03)
  q1 <- 4 * pmax(stage_m - 0.1, 0)^1.55
  q2 <- (pmax(stage_m - 1.6, 0) + 1)^0.9
  q3 <- (pmax(stage_m - 2.4, 0) + 1)^1.1
  discharge_cms <- q1 * q2 * q3 * exp(rnorm(length(stage_m), sd = sd))
  list(discharge = discharge_cms, stage = stage_m)
}

test_that("rate_optimise_segmented fits a single segment close to the true parameters", {
  g <- build_single_segment_gaugings()
  fit_seg <- rate_optimise_segmented(g$discharge, g$stage)

  expect_s3_class(fit_seg, "reach.rate::FlodeSegmentedRating")
  expect_equal(fit_seg@n_segments, 1L)
  expect_false(fit_seg@estimate_breakpoints)
  expect_true(all(c("C", "bp1", "n1", "rmse_cms", "r_squared", "n_obs") %in% names(fit_seg@coefficients)))
  expect_true(fit_seg@coefficients$r_squared > 0.98)
  # bp1 (the zero-flow stage) is estimated from noisy data and testthat's
  # `tolerance` is a *relative* bound -- 0.05 relative to a true value this
  # close to zero is an unrealistically tight absolute window (order
  # 0.005). Assert an absolute difference instead.
  expect_lt(abs(fit_seg@coefficients$bp1 - 0.1), 0.05)
  expect_equal(fit_seg@coefficients$n1, 1.55, tolerance = 0.1)
})

test_that("rate_optimise_segmented stores gauging_datetime on @gaugings when supplied", {
  g <- build_single_segment_gaugings()
  gauging_datetime <- as.Date("2020-01-01") + seq_along(g$stage)

  fit_seg <- rate_optimise_segmented(g$discharge, g$stage, gauging_datetime = gauging_datetime)

  expect_true("gauging_datetime" %in% names(fit_seg@gaugings))
  expect_equal(fit_seg@gaugings$gauging_datetime, gauging_datetime)
})

test_that("rate_optimise_segmented omitting gauging_datetime behaves exactly as before", {
  g <- build_single_segment_gaugings()
  fit_seg <- rate_optimise_segmented(g$discharge, g$stage)
  expect_false("gauging_datetime" %in% names(fit_seg@gaugings))
})

test_that("rate_optimise_segmented validates gauging_datetime", {
  g <- build_single_segment_gaugings()
  expect_error(
    rate_optimise_segmented(g$discharge, g$stage, gauging_datetime = seq_along(g$stage)),
    "Date or POSIXct"
  )
  expect_error(
    rate_optimise_segmented(g$discharge, g$stage, gauging_datetime = as.Date("2020-01-01") + 1:5),
    "same length"
  )
})

test_that("rate_optimise_segmented fits three segments with fixed breakpoints", {
  g <- build_three_segment_gaugings()
  fit_seg <- rate_optimise_segmented(g$discharge, g$stage, control = c(1.6, 2.4))

  expect_equal(fit_seg@n_segments, 3L)
  coefs <- fit_seg@coefficients
  expect_true(all(c("C", "bp1", "n1", "bp2", "n2", "bp3", "n3") %in% names(coefs)))
  # Fixed breakpoints should be stored exactly as supplied, not fitted
  expect_equal(coefs$bp2, 1.6)
  expect_equal(coefs$bp3, 2.4)
  expect_true(coefs$r_squared > 0.9)
})

test_that("apply_rating on a FlodeSegmentedRating matches the closed-form formula directly", {
  g <- build_three_segment_gaugings()
  fit_seg <- rate_optimise_segmented(g$discharge, g$stage, control = c(1.6, 2.4))
  coefs <- fit_seg@coefficients

  stage_check <- c(0.5, 1.2, 2.0, 3.0)
  out_dt <- apply_rating(fit_seg, data.table(stage = stage_check))

  expected <- coefs$C * pmax(stage_check - coefs$bp1, 0)^coefs$n1 *
    (pmax(stage_check - coefs$bp2, 0) + 1)^coefs$n2 *
    (pmax(stage_check - coefs$bp3, 0) + 1)^coefs$n3

  expect_equal(out_dt$discharge, expected, tolerance = 1e-8)
})

test_that("apply_rating gives exactly zero discharge at or below the zero-flow stage", {
  g <- build_single_segment_gaugings()
  fit_seg <- rate_optimise_segmented(g$discharge, g$stage)
  bp1 <- fit_seg@coefficients$bp1

  out_dt <- apply_rating(fit_seg, data.table(stage = c(bp1 - 0.5, bp1, bp1 - 0.01)))
  expect_equal(out_dt$discharge, c(0, 0, 0))
})

test_that("apply_rating flags extrapolation above the highest gauging", {
  g <- build_single_segment_gaugings()
  fit_seg <- rate_optimise_segmented(g$discharge, g$stage)

  out_dt <- apply_rating(fit_seg, data.table(stage = c(1.0, 10.0)))
  expect_false(out_dt$extrapolated[1])
  expect_true(out_dt$extrapolated[2])
})

test_that("apply_rating validates its inputs", {
  g <- build_single_segment_gaugings()
  fit_seg <- rate_optimise_segmented(g$discharge, g$stage)

  # A plain data.table has no apply_rating method -- S7 raises its own
  # no-applicable-method error. The exact wording is S7's, not ours, so
  # only the fact of an error is asserted, not its message.
  expect_error(apply_rating(data.table(a = 1), data.table(stage = 1)))
  expect_error(apply_rating(fit_seg, list(stage = 1)), "data.frame or data.table")
  expect_error(apply_rating(fit_seg, data.table(level = 1)), "stage_col")
})

test_that("rating_plot on a FlodeSegmentedRating returns a ggplot without error", {
  g <- build_three_segment_gaugings()
  fit_seg <- rate_optimise_segmented(g$discharge, g$stage, control = c(1.6, 2.4))

  pdf(NULL)
  on.exit(dev.off())

  p <- rating_plot(fit_seg)
  expect_s3_class(p, "ggplot")
})

test_that("rate_optimise_segmented can also estimate the interior breakpoints", {
  g <- build_three_segment_gaugings(sd = 0.01) # low noise, favourable case for convergence
  fit_seg <- rate_optimise_segmented(
    g$discharge, g$stage,
    control = c(1.6, 2.4), estimate_breakpoints = TRUE
  )

  expect_true(fit_seg@estimate_breakpoints)
  coefs <- fit_seg@coefficients
  expect_true(all(c("bp2", "bp3") %in% names(coefs)))
  # Estimated breakpoints should land reasonably close to the true ones
  # on a clean, low-noise synthetic case
  expect_equal(coefs$bp2, 1.6, tolerance = 0.3)
  expect_equal(coefs$bp3, 2.4, tolerance = 0.3)
})

test_that("rate_optimise_segmented multi_start = TRUE (default) adds bookkeeping columns and slot", {
  g <- build_single_segment_gaugings()
  fit_seg <- rate_optimise_segmented(g$discharge, g$stage)

  expect_true(all(c("n_starts_attempted", "n_starts_converged", "selected_start_id") %in% names(fit_seg@coefficients)))
  expect_true(fit_seg@coefficients$n_starts_attempted > 1L)
  expect_true(fit_seg@coefficients$n_starts_converged >= 1L)

  starts_dt <- fit_seg@fit_starts
  expect_true(is.data.table(starts_dt))
  expect_true(all(c("start_id", "converged", "rss", "error_message") %in% names(starts_dt)))
  expect_equal(nrow(starts_dt), fit_seg@coefficients$n_starts_attempted)
})

test_that("rate_optimise_segmented multi_start = FALSE reproduces the original single-start behaviour", {
  g <- build_single_segment_gaugings()
  fit_seg <- rate_optimise_segmented(g$discharge, g$stage, multi_start = FALSE)

  expect_equal(fit_seg@coefficients$n_starts_attempted, 1L)
  expect_equal(fit_seg@coefficients$n_starts_converged, 1L)
  expect_equal(fit_seg@coefficients$selected_start_id, 1L)
  expect_null(fit_seg@fit_starts)
})

test_that("rate_optimise_segmented validates multi_start", {
  g <- build_single_segment_gaugings()
  expect_error(rate_optimise_segmented(g$discharge, g$stage, multi_start = "yes"), "single logical")
})

test_that("rate_optimise_segmented validates its inputs", {
  expect_error(rate_optimise_segmented("a", 1:5), "numeric")
  expect_error(rate_optimise_segmented(1:5, 1:4), "same length")
  expect_error(rate_optimise_segmented(numeric(0), numeric(0)), "at least one value")
  expect_error(rate_optimise_segmented(1:5, 1:5, control = "x"), "numeric or NULL")
  expect_error(rate_optimise_segmented(1:5, 1:5, estimate_breakpoints = "yes"), "single logical")
})

test_that("rate_optimise_segmented rejects non-finite, negative, and degenerate input", {
  stage_m <- c(1.0, 1.5, 2.0, 2.5, 3.0, 3.5)
  ok_discharge <- c(5, 8, 12, 16, 20, 24)

  expect_error(rate_optimise_segmented(c(ok_discharge[-1], NA), stage_m), "NA, NaN, or infinite")
  expect_error(rate_optimise_segmented(c(-1, ok_discharge[-1]), stage_m), "non-negative")
  expect_error(rate_optimise_segmented(ok_discharge, rep(1.5, 6)), "non-zero range")
  expect_error(rate_optimise_segmented(ok_discharge, stage_m, control = c(1.6, 1.6)), "unique")
  expect_error(rate_optimise_segmented(ok_discharge, stage_m, control = c(0.5)), "strictly inside")
})

test_that("rate_optimise_segmented errors with too few gaugings for the parameter count", {
  # Three segments with estimated breakpoints needs 2 + k + (k-1) = 7
  # free parameters; five points is not enough.
  expect_error(
    rate_optimise_segmented(
      c(1, 2, 3, 4, 5), c(0.5, 1, 1.5, 2, 2.5),
      control = c(1.6, 2.4), estimate_breakpoints = TRUE
    ),
    "free parameters"
  )
})
