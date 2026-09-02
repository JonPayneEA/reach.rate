build_gap_free_table <- function() {
  eval_q <- function(C, a, n, H) C * (H - a)^n

  a1 <- 0; n1 <- 1.5; C1 <- 2.5
  brk1 <- 1.2
  q1 <- eval_q(C1, a1, n1, brk1)

  a2 <- 0; n2 <- 1.7
  C2 <- q1 / (brk1 - a2)^n2
  brk2 <- 2.5
  q2 <- eval_q(C2, a2, n2, brk2)

  a3 <- 0.1; n3 <- 1.6
  C3 <- q2 / (brk2 - a3)^n3

  rating_dt <- data.table::data.table(
    lower_level = c(0.0, brk1, brk2), upper_level = c(brk1, brk2, 4.0),
    C = c(C1, C2, C3), a = c(a1, a2, a3), n = c(n1, n2, n3)
  )
  FlodeRatingTable(table = rating_dt)
}

test_that("apply_rating_inverse round-trips against apply_rating on a gap-free table", {
  tbl <- build_gap_free_table()
  H <- c(0.3, 0.8, 1.2, 1.8, 2.5, 3.0, 3.9)

  fwd <- apply_rating(tbl, data.table::data.table(stage = H), stage_col = "stage", out_col = "discharge")
  inv <- apply_rating_inverse(tbl, fwd[, .(discharge)], discharge_col = "discharge", out_col = "stage_back")

  expect_equal(inv$stage_back, H, tolerance = 1e-8)
  expect_true(all(!inv$extrapolated))
})

test_that("apply_rating_inverse flags and extrapolates discharge outside the rating's range", {
  tbl <- build_gap_free_table()
  # 200 is well above the top limb's own discharge range; -- below the
  # bottom limb's own range doesn't apply here since Q = 0 at H = 0, so
  # use a value just below the lowest limb's own minimum instead
  disch_dt <- data.table::data.table(discharge = c(200))
  inv <- apply_rating_inverse(tbl, disch_dt)

  expect_true(inv$extrapolated[1])
  expect_true(inv$stage[1] > 4.0) # extrapolated beyond the top limb's own upper_level
})

test_that("apply_rating_inverse returns NA and warns for discharge <= 0", {
  tbl <- build_gap_free_table()
  disch_dt <- data.table::data.table(discharge = c(0, -1, 5))

  expect_warning(
    inv <- apply_rating_inverse(tbl, disch_dt),
    "no unique inverse stage"
  )
  expect_true(is.na(inv$stage[1]))
  expect_true(is.na(inv$stage[2]))
  expect_true(is.na(inv$extrapolated[1]))
  expect_false(is.na(inv$stage[3]))
})

test_that("apply_rating_inverse errors, naming the junction, when the table has a real discharge gap", {
  gapped_dt <- data.table::data.table(
    lower_level = c(0.0, 1.2), upper_level = c(1.2, 2.5),
    C = c(2.5, 20), a = c(0, 0), n = c(1.5, 1.5)
  )
  gapped_tbl <- FlodeRatingTable(table = gapped_dt)

  expect_error(
    apply_rating_inverse(gapped_tbl, data.table::data.table(discharge = 1)),
    "junction\\(s\\) 1.*discharge gap"
  )
})

test_that("apply_rating_inverse accepts a FlodeRating directly", {
  set.seed(1)
  stage_m <- seq(0.3, 3, by = 0.05)
  discharge_cms <- 4 * stage_m^1.6 + rnorm(length(stage_m), sd = 0.05)
  fit <- rate_optimise(discharge_cms, stage_m)

  inv <- apply_rating_inverse(fit, data.table::data.table(discharge = c(5, 15)))
  expect_true(all(!is.na(inv$stage)))

  # Consistent with going through as_rating_table() manually
  inv_via_table <- apply_rating_inverse(as_rating_table(fit), data.table::data.table(discharge = c(5, 15)))
  expect_equal(inv$stage, inv_via_table$stage)
})

test_that("apply_rating_inverse validates its inputs", {
  tbl <- build_gap_free_table()
  expect_error(apply_rating_inverse(tbl, "not a data.frame"), "data.frame or data.table")
  expect_error(apply_rating_inverse(tbl, data.frame(x = 1)), "discharge_col")
  expect_error(apply_rating_inverse("not a fit", data.frame(discharge = 1)), "FlodeRatingTable")
})

build_segmented_fit <- function(seed = 1, sd = 0.02) {
  set.seed(seed)
  stage_m <- seq(0.3, 3.5, by = 0.03)
  q1 <- 4 * pmax(stage_m - 0.1, 0)^1.55
  q2 <- (pmax(stage_m - 1.6, 0) + 1)^0.9
  q3 <- (pmax(stage_m - 2.4, 0) + 1)^1.1
  discharge_cms <- q1 * q2 * q3 * exp(rnorm(length(stage_m), sd = sd))
  rate_optimise_segmented(discharge_cms, stage_m, control = c(1.6, 2.4))
}

test_that("apply_rating_inverse round-trips against apply_rating for a FlodeSegmentedRatingTable", {
  fit_seg <- build_segmented_fit()
  seg_table <- as_rating_table(fit_seg)

  H <- c(0.5, 1.0, 1.6, 2.0, 2.4, 3.0, 3.4)
  fwd <- apply_rating(seg_table, data.table::data.table(stage = H), stage_col = "stage", out_col = "discharge")
  inv <- apply_rating_inverse(seg_table, fwd[, .(discharge)], discharge_col = "discharge", out_col = "stage_back")

  expect_equal(inv$stage_back, H, tolerance = 1e-6)
  expect_true(all(!inv$extrapolated))
})

test_that("apply_rating_inverse accepts a FlodeSegmentedRating directly, bridging via as_rating_table()", {
  fit_seg <- build_segmented_fit()
  disch_dt <- data.table::data.table(discharge = c(2, 10, 30))

  inv <- apply_rating_inverse(fit_seg, disch_dt)
  inv_via_table <- apply_rating_inverse(as_rating_table(fit_seg), disch_dt)

  expect_equal(inv$stage, inv_via_table$stage, tolerance = 1e-10)
})

test_that("apply_rating_inverse flags extrapolation above the highest gauged stage for a segmented table", {
  fit_seg <- build_segmented_fit()
  seg_table <- as_rating_table(fit_seg)

  q_at_top <- apply_rating(seg_table, data.table::data.table(stage = seg_table@gauged_upper_m))$discharge
  inv <- apply_rating_inverse(seg_table, data.table::data.table(discharge = q_at_top * 5))

  expect_true(inv$extrapolated[1])
  expect_true(inv$stage[1] > seg_table@gauged_upper_m)
})

test_that("apply_rating_inverse returns NA and warns for discharge <= 0 on a segmented table", {
  fit_seg <- build_segmented_fit()
  seg_table <- as_rating_table(fit_seg)
  disch_dt <- data.table::data.table(discharge = c(0, -1, 5))

  expect_warning(
    inv <- apply_rating_inverse(seg_table, disch_dt),
    "no unique inverse stage"
  )
  expect_true(is.na(inv$stage[1]))
  expect_true(is.na(inv$stage[2]))
  expect_true(is.na(inv$extrapolated[1]))
  expect_false(is.na(inv$stage[3]))
})
