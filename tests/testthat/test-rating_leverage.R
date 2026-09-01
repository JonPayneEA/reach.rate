test_that("flag_influential_gaugings flags an isolated outlier gauging and barely flags the rest", {
  set.seed(1)
  stage_m <- seq(0.3, 3, by = 0.1)
  discharge_cms <- 5 * stage_m^1.5 * exp(rnorm(length(stage_m), sd = 0.03))
  stage_m <- c(stage_m, 3.5)
  discharge_cms <- c(discharge_cms, 5 * 3.5^1.5 * 1.25)

  fit <- rate_optimise(discharge_cms, stage_m, n_bounds = c(1.3, 1.7))
  flagged <- flag_influential_gaugings(fit)

  expect_true(S7::S7_inherits(flagged, FlodeRating))
  expect_true(all(c("leverage", "cooks_distance", "influential") %in% names(flagged@gaugings)))

  top_row <- flagged@gaugings[which.max(cooks_distance)]
  expect_equal(top_row$stage_m, 3.5)
  expect_true(top_row$influential)
  expect_true(top_row$cooks_distance > 10 * median(flagged@gaugings$cooks_distance, na.rm = TRUE))
})

test_that("dropping the most-influential gauging moves C far more than dropping a low-influence one", {
  set.seed(1)
  stage_m <- seq(0.3, 3, by = 0.1)
  discharge_cms <- 5 * stage_m^1.5 * exp(rnorm(length(stage_m), sd = 0.03))
  stage_m <- c(stage_m, 3.5)
  discharge_cms <- c(discharge_cms, 5 * 3.5^1.5 * 1.25)

  fit <- rate_optimise(discharge_cms, stage_m, n_bounds = c(1.3, 1.7))
  flagged <- flag_influential_gaugings(fit)

  top_idx <- which.max(flagged@gaugings$cooks_distance)
  low_idx <- which.min(flagged@gaugings$cooks_distance)

  fit_drop_top <- rate_optimise(discharge_cms[-top_idx], stage_m[-top_idx], n_bounds = c(1.3, 1.7))
  fit_drop_low <- rate_optimise(discharge_cms[-low_idx], stage_m[-low_idx], n_bounds = c(1.3, 1.7))

  shift_top <- abs(fit@limbs$C - fit_drop_top@limbs$C) / fit_drop_top@limbs$C
  shift_low <- abs(fit@limbs$C - fit_drop_low@limbs$C) / fit_drop_low@limbs$C

  expect_true(shift_top > 10 * shift_low)
})

test_that("flag_influential_gaugings returns NA leverage/cooks_distance for a limb with too few gaugings", {
  fit <- rate_optimise(
    discharge_cms = c(1, 2, 3), stage_m = c(0.5, 1, 1.5)
  )
  flagged <- flag_influential_gaugings(fit)
  expect_true(all(is.na(flagged@gaugings$leverage)))
  expect_true(all(is.na(flagged@gaugings$cooks_distance)))
  expect_true(all(!flagged@gaugings$influential))
})

test_that("flag_influential_gaugings validates its inputs", {
  set.seed(2)
  stage_m <- seq(0.3, 3, by = 0.1)
  discharge_cms <- 5 * stage_m^1.5 * exp(rnorm(length(stage_m), sd = 0.03))
  fit <- rate_optimise(discharge_cms, stage_m)

  expect_error(flag_influential_gaugings(data.frame(x = 1)), "FlodeRating")
  expect_error(flag_influential_gaugings(fit, cooks_mult = -1), "cooks_mult")
  expect_error(flag_influential_gaugings(fit, leverage_mult = 0), "leverage_mult")
})

test_that("plot_rating_leverage returns a ggplot and validates its input", {
  set.seed(3)
  stage_m <- seq(0.3, 3, by = 0.1)
  discharge_cms <- 5 * stage_m^1.5 * exp(rnorm(length(stage_m), sd = 0.03))
  fit <- rate_optimise(discharge_cms, stage_m)

  p <- plot_rating_leverage(fit)
  expect_s3_class(p, "ggplot")
  expect_error(plot_rating_leverage(list()), "FlodeRating")
})

test_that("a well-conditioned fit with no deliberate outliers flags only a small minority, at the sparse ends", {
  set.seed(4)
  stage_m <- seq(0.3, 3, by = 0.05)
  discharge_cms <- 5 * stage_m^1.5 * exp(rnorm(length(stage_m), sd = 0.03))
  fit <- rate_optimise(discharge_cms, stage_m, n_bounds = c(1.3, 1.7))
  flagged <- flag_influential_gaugings(fit)

  n_obs <- nrow(flagged@gaugings)
  n_flagged <- sum(flagged@gaugings$influential, na.rm = TRUE)
  expect_true(n_flagged < 0.2 * n_obs)

  # The rule-of-thumb leverage cutoff is purely positional, so a clean
  # fit's flags (if any) should sit at the sparse ends of the gauged
  # range, not scattered through the well-supported middle.
  flagged_stage <- flagged@gaugings[influential == TRUE]$stage_m
  mid_lo <- quantile(stage_m, 0.25); mid_hi <- quantile(stage_m, 0.75)
  expect_true(all(flagged_stage < mid_lo | flagged_stage > mid_hi))
})
