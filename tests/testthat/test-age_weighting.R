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

# ---- E1: magnitude protection ------------------------------------------------

# An old flood on a changed channel. The 2008 gaugings below 2 m follow an old
# channel (C = 3); the 2008 gaugings above 2 m, and every 2024 gauging, follow
# today's (C = 4). Judged against today's rating across the whole range.
old_flood_gaugings <- function(seed = 8L) {
  set.seed(seed)
  tn <- function(h) 4 * h^1.5
  to <- function(h) 3 * h^1.5
  lo <- seq(0.3, 1.9, length.out = 12)
  hi <- c(2.2, 2.5, 2.8, 3.1, 3.4)
  rec <- seq(0.3, 1.4, length.out = 6)
  rbind(
    data.frame(stage_m = c(lo, hi),
               discharge_cms = c(to(lo) * exp(rnorm(12, sd = 0.03)), tn(hi) * exp(rnorm(5, sd = 0.03))),
               observation_time = as.POSIXct("2008-06-01", tz = "UTC")),
    data.frame(stage_m = rec, discharge_cms = tn(rec) * exp(rnorm(6, sd = 0.10)),
               observation_time = as.POSIXct("2024-06-01", tz = "UTC"))
  )
}
e1_ref <- as.POSIXct("2025-01-01", tz = "UTC")
e1_fit <- function(d, ...) {
  suppressWarnings(fit_rating(d, quiet = TRUE, age_halflife = 365 * 3, reference_time = e1_ref, ...))
}
e1_error <- function(fit) {
  s <- seq(0.3, 3.4, length.out = 200)
  max(abs(suppressWarnings(apply_rating(fit, s)$discharge) / (4 * s^1.5) - 1))
}

test_that("magnitude protection obeys its stated properties", {
  q <- seq(1, 20, length.out = 40)
  gd <- as.Date("2020-01-01") - sample(0:4000, 40, replace = TRUE)
  pr <- .resolve_protection(q, 10, NULL, 0.05, age_halflife = 365, fn_name = "x")
  w_age <- .age_recency_weight(gd, 365, 0.1, as.Date("2020-01-01"))
  w <- .age_recency_weight(gd, 365, 0.1, as.Date("2020-01-01"), pr)
  expect_true(all(pr$p >= 0 & pr$p <= 1))
  expect_true(all(w >= w_age - 1e-12 & w <= 1 + 1e-12)) # never lowers a weight, never above 1
  expect_equal(.age_recency_weight(gd, 365, 0.1, as.Date("2020-01-01"), NULL), w_age)
  # fully protected: the largest gauging ignores age; the smallest is untouched
  expect_equal(w[which.max(q)], 1, tolerance = 1e-3)
  expect_equal(w[which.min(q)], w_age[which.min(q)], tolerance = 1e-3)
  # monotone in discharge at fixed age
  fixed <- .age_recency_weight(rep(as.Date("2000-01-01"), 40), 365, 0.1, as.Date("2020-01-01"), pr)
  expect_true(all(diff(fixed[order(q)]) >= -1e-12))
  # no cliff: neighbours get similar weight
  expect_lt(max(abs(diff(fixed[order(q)]))), 0.2)
})

test_that("without protection arguments the fit is exactly what it was", {
  d <- old_flood_gaugings()
  a <- e1_fit(d)
  b <- e1_fit(d, protect_above = NULL, protect_quantile = NULL)
  expect_identical(rating_limbs(a, all_columns = TRUE)[, c("C", "a", "n")], rating_limbs(b, all_columns = TRUE)[, c("C", "a", "n")])
  expect_false(any(c("protect_above", "n_protected") %in% names(a@provenance)))
})

test_that("protection recovers an old flood that age weighting alone loses", {
  d <- old_flood_gaugings()
  age_only <- e1_fit(d)
  protected <- e1_fit(d, protect_above = 10)
  expect_lt(e1_error(protected), e1_error(age_only) * 0.5)
  prov <- protected@provenance
  expect_equal(prov$protect_above, 10)
  expect_equal(prov$protect_width, 0.05)
  expect_equal(prov$n_protected, 5L) # the five 2008 floods above 10 m3/s
  # the weights the assessment and the report read
  g <- as.data.table(protected@gaugings)
  expect_true(all(g[stage_m >= 2.2 & observation_time < as.POSIXct("2010-01-01", tz = "UTC")]$age_weight > 0.9))
})

test_that("with nothing old and large to protect, protection changes nothing material", {
  set.seed(2)
  h <- seq(0.3, 3, length.out = 24)
  d <- data.frame(stage_m = h, discharge_cms = 4 * h^1.5 * exp(rnorm(24, sd = 0.03)),
                  observation_time = as.POSIXct("2008-06-01", tz = "UTC") + (seq_along(h) > 12) * 86400 * 365 * 16)
  # the large gaugings are the recent ones, so they already carry full weight
  a <- e1_fit(d)
  b <- e1_fit(d, protect_above = 15)
  s <- seq(0.3, 3, length.out = 50)
  ra <- suppressWarnings(apply_rating(a, s)$discharge)
  rb <- suppressWarnings(apply_rating(b, s)$discharge)
  expect_lt(max(abs(rb / ra - 1)), 0.01)
})

test_that("a quantile is recorded as the discharge it produced, and refits use the quantile", {
  d <- old_flood_gaugings()
  f <- e1_fit(d, protect_quantile = 0.8)
  q0 <- unname(stats::quantile(f@gaugings$discharge_cms, 0.8))
  expect_equal(f@provenance$protect_above, q0)
  expect_equal(f@provenance$protect_quantile, 0.8)
  expect_no_error(suppressWarnings(rating_sensitivity(f)))
})

test_that("protection supports the segmented model and the direct fitters", {
  d <- old_flood_gaugings()
  g <- suppressWarnings(rate_optimise_segmented(d$discharge_cms, d$stage_m, gauging_datetime = d$observation_time,
                                                control = 1.5, age_halflife = 365 * 3,
                                                reference_datetime = e1_ref, protect_above = 10))
  expect_equal(g@provenance$protect_above, 10)
  expect_true(all(g@gaugings$age_weight[d$discharge_cms >= 10] > 0.9 | d$observation_time[d$discharge_cms >= 10] > as.POSIXct("2020-01-01", tz = "UTC")))
  r <- suppressWarnings(rate_optimise(d$discharge_cms, d$stage_m, gauging_datetime = d$observation_time,
                                      age_halflife = 365 * 3, reference_datetime = e1_ref, protect_above = 10))
  expect_equal(r@provenance$n_protected, 5L)
})

test_that("protection says what is wrong, and why it matters", {
  d <- old_flood_gaugings()
  q <- d$discharge_cms
  expect_error(fit_rating(d, quiet = TRUE, protect_above = 10), "need age_halflife")
  expect_error(e1_fit(d, protect_above = 10, protect_quantile = 0.8), "not both")
  expect_error(e1_fit(d, protect_above = -1), "single positive discharge")
  expect_error(e1_fit(d, protect_above = c(1, 2)), "single positive discharge")
  expect_error(e1_fit(d, protect_quantile = 1), "strictly between 0 and 1")
  expect_error(e1_fit(d, protect_quantile = "a"), "strictly between 0 and 1")
  expect_error(e1_fit(d, protect_above = 10, protect_width = 0), "protect_width")
  expect_error(rate_optimise(q, d$stage_m, protect_above = 10), "age_halflife")
  expect_warning(fit_rating(d, quiet = TRUE, age_halflife = 365 * 3, reference_time = e1_ref, protect_above = 1e6),
                 "nothing is protected")
  expect_warning(fit_rating(d, quiet = TRUE, age_halflife = 365 * 3, reference_time = e1_ref, protect_above = 1e-3),
                 "recency weighting has no effect")
})
