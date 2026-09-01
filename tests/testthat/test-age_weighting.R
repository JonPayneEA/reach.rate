campaign_gaugings <- function() {
  stage_seq <- seq(0.3, 3, by = 0.15)
  eras <- data.table(year = c(0, 7, 14, 20), true_C = c(3, 4, 5, 6))
  set.seed(3)
  rbindlist(lapply(seq_len(nrow(eras)), function(i) {
    data.table(
      stage_m = stage_seq,
      discharge_cms = eras$true_C[i] * stage_seq^1.5 * exp(rnorm(length(stage_seq), sd = 0.02)),
      gauging_datetime = as.Date("2000-01-01") + eras$year[i] * 365 + round(seq_along(stage_seq) * 0.5)
    )
  }))
}

test_that(".age_recency_weight matches the closed-form floor/half-life formula", {
  ref <- as.Date("2020-01-01")
  gd <- ref - c(0, 365, 365 * 5, 365 * 10)
  w <- .age_recency_weight(gd, age_halflife = 365 * 5, age_min_weight = 0.1, reference_datetime = ref)

  expect_equal(w[1], 1, tolerance = 1e-10)
  expect_equal(w[3], 0.1 + 0.9 * 0.5, tolerance = 1e-10) # exactly one half-life old
  expect_true(all(diff(w) < 0)) # strictly decreasing with age
  expect_true(all(w >= 0.1)) # never below the floor
})

test_that(".age_recency_weight clamps a future gauging's age to 0, not a weight above 1", {
  ref <- as.Date("2020-01-01")
  w <- .age_recency_weight(ref + 100, age_halflife = 365, age_min_weight = 0.1, reference_datetime = ref)
  expect_equal(w, 1)
})

test_that(".age_recency_weight defaults reference_datetime to max(gauging_datetime)", {
  gd <- as.Date("2020-01-01") + c(0, 10, 20)
  w_explicit <- .age_recency_weight(gd, age_halflife = 100, age_min_weight = 0.1, reference_datetime = max(gd))
  w_default <- .age_recency_weight(gd, age_halflife = 100, age_min_weight = 0.1, reference_datetime = NULL)
  expect_equal(w_explicit, w_default)
  expect_equal(w_default[3], 1) # the most recent gauging is its own reference
})

test_that("age_halflife requires gauging_datetime and validates its own arguments", {
  discharge_cms <- c(1, 2, 3, 4, 5)
  stage_m <- c(0.5, 1, 1.5, 2, 2.5)

  expect_error(rate_optimise(discharge_cms, stage_m, age_halflife = 365), "gauging_datetime")

  gd <- as.Date("2020-01-01") + seq_along(stage_m)
  expect_error(rate_optimise(discharge_cms, stage_m, gauging_datetime = gd, age_halflife = -1), "age_halflife")
  expect_error(
    rate_optimise(discharge_cms, stage_m, gauging_datetime = gd, age_halflife = 365, age_min_weight = 1),
    "age_min_weight"
  )
  expect_error(
    rate_optimise(discharge_cms, stage_m, gauging_datetime = gd, age_halflife = 365, reference_datetime = "2020-01-01"),
    "reference_datetime"
  )
})

test_that("rate_optimise: omitting age_halflife is unaffected by gauging_datetime (regression safety)", {
  set.seed(5)
  stage_m <- seq(0.3, 3, by = 0.05)
  discharge_cms <- 5 * stage_m^1.5 * exp(rnorm(length(stage_m), sd = 0.03))
  gd <- as.Date("2020-01-01") + seq_along(stage_m)

  fit_no_dates <- rate_optimise(discharge_cms, stage_m, n_bounds = c(1.3, 1.7))
  fit_with_dates <- rate_optimise(discharge_cms, stage_m, n_bounds = c(1.3, 1.7), gauging_datetime = gd)

  expect_equal(fit_no_dates@limbs$C, fit_with_dates@limbs$C)
  expect_equal(fit_no_dates@limbs$a, fit_with_dates@limbs$a)
  expect_equal(fit_no_dates@limbs$n, fit_with_dates@limbs$n)
  expect_false("age_weight" %in% names(fit_with_dates@gaugings))
})

test_that("rate_optimise: age_halflife weighting pulls the fit toward the most recent gauging campaign", {
  g <- campaign_gaugings()
  fit_unweighted <- rate_optimise(g$discharge_cms, g$stage_m, gauging_datetime = g$gauging_datetime, n_bounds = c(1.5, 1.5))
  fit_weighted <- rate_optimise(
    g$discharge_cms, g$stage_m,
    gauging_datetime = g$gauging_datetime, n_bounds = c(1.5, 1.5),
    age_halflife = 365 * 3, age_min_weight = 0.02
  )

  # Flat average of true C across four campaigns (3,4,5,6) is 4.5; the
  # most recent campaign's true C is 6 -- weighting should land clearly
  # in between, and clearly closer to 6 than the unweighted fit is.
  expect_equal(fit_unweighted@limbs$C, 4.5, tolerance = 0.15)
  expect_true(fit_weighted@limbs$C > fit_unweighted@limbs$C)
  expect_true(abs(fit_weighted@limbs$C - 6) < abs(fit_unweighted@limbs$C - 6))

  expect_true("age_weight" %in% names(fit_weighted@gaugings))
  expect_true(all(fit_weighted@gaugings$age_weight >= 0.02))
  expect_true(max(fit_weighted@gaugings$age_weight) == 1) # most recent gauging(s)

  expect_equal(fit_weighted@provenance$age_halflife, 365 * 3)
  expect_equal(fit_weighted@provenance$age_min_weight, 0.02)
})

test_that("rate_optimise_segmented: same regression safety and recency behaviour", {
  set.seed(7)
  stage_seg_m <- seq(0.3, 3.5, by = 0.03)
  q1 <- 4 * pmax(stage_seg_m - 0.1, 0)^1.55
  q2 <- (pmax(stage_seg_m - 1.6, 0) + 1)^0.9
  q3 <- (pmax(stage_seg_m - 2.4, 0) + 1)^1.1
  discharge_seg_cms <- q1 * q2 * q3 * exp(rnorm(length(stage_seg_m), sd = 0.03))
  gd <- as.Date("2020-01-01") + seq_along(stage_seg_m)

  fit_no_dates <- rate_optimise_segmented(discharge_seg_cms, stage_seg_m, control = c(1.6, 2.4))
  fit_with_dates <- rate_optimise_segmented(discharge_seg_cms, stage_seg_m, control = c(1.6, 2.4), gauging_datetime = gd)
  expect_equal(fit_no_dates@coefficients$C, fit_with_dates@coefficients$C)
  expect_false("age_weight" %in% names(fit_with_dates@gaugings))

  g <- campaign_gaugings()
  fit_unweighted <- rate_optimise_segmented(g$discharge_cms, g$stage_m, gauging_datetime = g$gauging_datetime)
  fit_weighted <- rate_optimise_segmented(
    g$discharge_cms, g$stage_m,
    gauging_datetime = g$gauging_datetime, age_halflife = 365 * 3, age_min_weight = 0.02
  )
  expect_true(abs(fit_weighted@coefficients$C - 6) < abs(fit_unweighted@coefficients$C - 6))
  expect_true("age_weight" %in% names(fit_weighted@gaugings))
})

test_that("rate_optimise_constrained forwards age_halflife through ... and carries age_weight", {
  set.seed(1)
  stage_m <- seq(0.5, 3.5, by = 0.1)
  discharge_cms <- 5 * stage_m^1.6 + rnorm(length(stage_m), sd = 0.01)
  gauging_datetime <- as.Date("2020-01-01") + seq_along(stage_m)

  fit <- rate_optimise_constrained(
    discharge_cms, stage_m,
    control = c(1.5, 2.5), gauging_datetime = gauging_datetime,
    age_halflife = 365 * 2, age_min_weight = 0.05
  )

  expect_true("age_weight" %in% names(fit@gaugings))
  expect_equal(fit@provenance$age_halflife, 365 * 2)
})
