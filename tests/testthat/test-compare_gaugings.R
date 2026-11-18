build_two_limb_rating <- function() {
  # Q = 2 * H^1.5 up to H = 1, then Q = 2 * H^1.5 again with a different
  # offset-free form so values are easy to compute by hand.
  data.table::data.table(
    lower_level = c(0.5, 1.0), upper_level = c(1.0, 2.0),
    C = c(2, 2), a = c(0, 0), n = c(1.5, 1.5)
  )
}

test_that("residuals match a hand calculation", {
  rating <- build_two_limb_rating()
  g <- data.frame(stage_m = c(0.64, 1.0, 1.44), discharge_cms = c(1.5, 2.0, 6.0))
  out <- compare_gaugings_to_rating(rating, g)$gaugings

  predicted <- 2 * c(0.64, 1.0, 1.44)^1.5   # 1.024, 2, 3.456
  expect_equal(out$discharge_predicted_cms, predicted)
  expect_equal(out$residual_cms, c(1.5, 2.0, 6.0) - predicted)
  expect_equal(out$residual_pct, 100 * (c(1.5, 2.0, 6.0) - predicted) / predicted)
  expect_equal(out$within_tol, c(FALSE, TRUE, FALSE))
})

test_that("limb assignment and extrapolation flags follow apply_rating", {
  rating <- build_two_limb_rating()
  g <- data.frame(stage_m = c(0.2, 0.5, 0.99, 1.0, 2.0, 2.5), discharge_cms = 1)
  out <- compare_gaugings_to_rating(rating, g)$gaugings

  # A stage exactly on a junction belongs to the upper limb; the very top
  # of the rating still belongs to the top limb.
  expect_equal(out$limb, c(1L, 1L, 1L, 2L, 2L, 2L))
  expect_equal(out$extrapolated, c(TRUE, FALSE, FALSE, FALSE, FALSE, TRUE))
  expect_equal(
    out$extrapolated,
    apply_rating(FlodeRatingTable(table = rating), data.table::data.table(stage = g$stage_m))$extrapolated
  )
})

test_that("the limb summary counts, bounds and statistics are right", {
  rating <- build_two_limb_rating()
  stage <- c(0.2, 0.6, 0.8, 1.2, 1.2, 3.0)
  pred <- 2 * stage^1.5
  # limb 1: +8% and -8%; limb 2: 0% and +20%; two extrapolated gaugings
  obs <- pred * c(5, 1.08, 0.92, 1.00, 1.20, 5)
  res <- compare_gaugings_to_rating(rating, data.frame(stage_m = stage, discharge_cms = obs))

  limbs <- res$limbs
  expect_equal(nrow(limbs), 2L)
  expect_equal(limbs$n_gaugings, c(2L, 2L))
  expect_equal(limbs$n_extrapolated, c(1L, 1L))
  expect_equal(limbs$gauged_min_stage, c(0.6, 1.2))
  expect_equal(limbs$gauged_max_stage, c(0.8, 1.2))
  expect_equal(limbs$median_residual_pct, c(0, 10), tolerance = 1e-9)
  expect_equal(limbs$spread_pct, c(8, 10), tolerance = 1e-9)
  expect_equal(limbs$share_within_tol, c(1, 0.5))
  expect_equal(limbs$has_gaugings, c(TRUE, TRUE))
})

test_that("a limb with no gaugings is reported, not hidden", {
  rating <- build_two_limb_rating()
  g <- data.frame(stage_m = c(0.6, 0.7), discharge_cms = 2 * c(0.6, 0.7)^1.5)
  limbs <- compare_gaugings_to_rating(rating, g)$limbs

  expect_equal(limbs$has_gaugings, c(TRUE, FALSE))
  expect_equal(limbs$n_gaugings, c(2L, 0L))
  expect_true(all(is.na(limbs[2, c("gauged_min_stage", "gauged_max_stage", "median_residual_pct", "spread_pct", "share_within_tol")])))
})

test_that("extrapolated gaugings stay out of a limb's fit statistics", {
  rating <- build_two_limb_rating()
  stage <- c(0.7, 3.0)
  g <- data.frame(stage_m = stage, discharge_cms = c(2 * 0.7^1.5, 100))
  limbs <- compare_gaugings_to_rating(rating, g)$limbs
  # The wild extrapolated gauging must not move limb 2's statistics
  expect_equal(limbs$n_gaugings, c(1L, 0L))
  expect_equal(limbs$n_extrapolated, c(0L, 1L))
  expect_true(is.na(limbs$median_residual_pct[2]))
})

test_that("zero predicted discharge gives NA percent residual, not Inf", {
  rating <- data.table::data.table(lower_level = 0.5, upper_level = 2, C = 2, a = 0.8, n = 1.5)
  g <- data.frame(stage_m = c(0.6, 1.0), discharge_cms = c(0.4, 0.2))
  out <- compare_gaugings_to_rating(rating, g)$gaugings
  expect_equal(out$discharge_predicted_cms[1], 0)
  expect_true(is.na(out$residual_pct[1]))
  expect_true(is.na(out$within_tol[1]))
  expect_equal(out$residual_cms[1], 0.4)
  expect_true(is.finite(out$residual_pct[2]))
})

test_that("rows with missing values are kept with missing results", {
  rating <- build_two_limb_rating()
  g <- data.frame(stage_m = c(0.8, NA, 1.2, 1.3), discharge_cms = c(1.0, 1.0, NA, 3.0))
  out <- compare_gaugings_to_rating(rating, g)$gaugings

  expect_equal(nrow(out), 4L)
  expect_true(is.na(out$discharge_predicted_cms[2]))
  expect_true(is.na(out$residual_cms[3]))
  expect_false(is.na(out$residual_cms[4]))
})

test_that("other columns and row order are carried through", {
  rating <- build_two_limb_rating()
  g <- data.frame(
    station = c("A", "B", "C"), stage_m = c(1.5, 0.6, 0.9),
    discharge_cms = c(3, 1, 2), stringsAsFactors = FALSE
  )
  out <- compare_gaugings_to_rating(rating, g)$gaugings
  expect_equal(out$station, c("A", "B", "C"))
  expect_equal(out$stage_m, c(1.5, 0.6, 0.9))
  expect_equal(names(out)[1:3], c("station", "stage_m", "discharge_cms"))
})

test_that("custom column names work, and the input is not modified", {
  rating <- build_two_limb_rating()
  g <- data.table::data.table(h = c(0.6, 1.2), q = c(1, 3))
  before <- data.table::copy(g)
  out <- compare_gaugings_to_rating(rating, g, stage_col = "h", discharge_col = "q")$gaugings
  expect_equal(out$limb, c(1L, 2L))
  expect_equal(g, before)
})

test_that("an unsorted rating table is handled", {
  rating <- build_two_limb_rating()[2:1]
  g <- data.frame(stage_m = c(0.6, 1.2), discharge_cms = c(1, 3))
  out <- compare_gaugings_to_rating(rating, g)$gaugings
  expect_equal(out$limb, c(1L, 2L))
})

test_that("a FlodeRating and a FlodeRatingTable give the same answer", {
  gaugings <- station_gaugings
  fit <- rate_optimise(gaugings$discharge_cms, gaugings$stage_m)
  from_fit <- compare_gaugings_to_rating(fit, gaugings, stage_col = "stage_m")
  from_table <- compare_gaugings_to_rating(as_rating_table(fit), gaugings)
  expect_equal(from_fit, from_table)
  # Against its own gaugings none are extrapolated, and the numbers agree
  # with a calculation straight from the fitted coefficients. (The fit is
  # not close in percentage terms: the default absolute objective is pulled
  # towards the few large flows, so the median residual is far from zero.
  # That is a property of the fit, not of this function.)
  expect_false(any(from_fit$gaugings$extrapolated))
  limb <- fit@limbs
  pred <- limb$C * pmax(gaugings$stage_m - limb$a, 0)^limb$n
  pct <- 100 * (gaugings$discharge_cms - pred) / pred
  pct[!is.finite(pct)] <- NA
  expect_equal(from_fit$gaugings$discharge_predicted_cms, pred)
  expect_equal(from_fit$limbs$median_residual_pct, median(pct, na.rm = TRUE))
})

test_that("one near-zero prediction cannot dominate a limb's summary", {
  # The shape of a real archive row: a measured flow at a stage where the
  # rating predicts almost nothing. Its percent residual is astronomical.
  rating <- data.table::data.table(lower_level = 0, upper_level = 3, C = 2, a = -1e-6, n = 1.5)
  stage <- c(0, seq(0.5, 2.5, length.out = 20))
  pred <- 2 * (stage + 1e-6)^1.5
  obs <- pred * 1.02
  obs[1] <- 0.308
  res <- compare_gaugings_to_rating(rating, data.frame(stage_m = stage, discharge_cms = obs))

  expect_gt(res$gaugings$residual_pct[1], 1e8)
  expect_equal(res$limbs$median_residual_pct, 2, tolerance = 1e-6)
  expect_lt(res$limbs$spread_pct, 1)
  expect_equal(res$limbs$share_within_tol, 20 / 21)
})

test_that("a gauging exactly on the tolerance counts as within it", {
  rating <- build_two_limb_rating()
  stage <- 0.8
  pred <- 2 * stage^1.5
  g <- data.frame(stage_m = c(stage, stage), discharge_cms = c(pred * 1.10, pred * 1.11))
  expect_equal(compare_gaugings_to_rating(rating, g)$gaugings$within_tol, c(TRUE, FALSE))
})

test_that("an empty gauging table gives a limb summary with no support", {
  rating <- build_two_limb_rating()
  g <- data.frame(stage_m = numeric(0), discharge_cms = numeric(0))
  res <- compare_gaugings_to_rating(rating, g)
  expect_equal(nrow(res$gaugings), 0L)
  expect_equal(res$limbs$has_gaugings, c(FALSE, FALSE))
})

test_that("bad input is refused with a message that names the problem", {
  rating <- build_two_limb_rating()
  g <- data.frame(stage_m = c(0.6, 0.7), discharge_cms = c(1, 1))

  expect_error(compare_gaugings_to_rating(rating, g, stage_col = "stage"), "'stage' is not a column")
  expect_error(compare_gaugings_to_rating(rating, g, discharge_col = "flow"), "'flow' is not a column")
  expect_error(
    compare_gaugings_to_rating(rating, data.frame(stage_m = c("0.6", "---"), discharge_cms = c(1, 1))),
    "must be numeric but is character"
  )
  expect_error(compare_gaugings_to_rating(rating, g, tol_rel = 0), "tol_rel")
  expect_error(compare_gaugings_to_rating(rating, g, tol_rel = c(0.1, 0.2)), "tol_rel")
  expect_error(compare_gaugings_to_rating("x", g), "rating must be")
  expect_error(compare_gaugings_to_rating(rating, 1:3), "gaugings must be a data.frame")
  expect_error(compare_gaugings_to_rating(rating, cbind(g, limb = 1L)), "already has column")
  # A table that is not contiguous is rejected by the rating class
  bad <- rating
  bad[2, lower_level := 1.5]
  expect_error(compare_gaugings_to_rating(bad, g), "contiguous")
})
