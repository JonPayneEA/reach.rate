# Tranche B6: check_limb_continuity(). The worked example is by hand:
#   limb 1: Q = 2 H^1.5 on [0.2, 1]      limb 2: Q = 2.1 H^1.6 on [1, 3]
#   at H = 1:  Q below = 2, Q above = 2.1, gap 0.1 (5%)
#   the upper limb reaches 2 at H = (2/2.1)^(1/1.6), so the stage gap is that less 1
#   slopes there: 2 * 1.5 = 3 and 2.1 * 1.6 = 3.36, a change of 12%.

step_table <- function(C2 = 2.1) {
  FlodeRatingTable(table = data.table::data.table(lower_level = c(0.2, 1), upper_level = c(1, 3),
                                                  C = c(2, C2), a = c(0, 0), n = c(1.5, 1.6)))
}

test_that("every measure at the junction is right, by hand", {
  r <- check_limb_continuity(step_table())
  expect_equal(nrow(r), 1L)
  expect_equal(r$junction, 1L)
  expect_equal(r$stage_m, 1)
  expect_equal(c(r$limb_below, r$limb_above), c(1L, 2L))
  expect_equal(r$q_below_cms, 2)
  expect_equal(r$q_above_cms, 2.1)
  expect_equal(r$gap_cms, 0.1)
  expect_equal(r$gap_rel, 0.05)
  expect_equal(r$stage_gap_m, (2 / 2.1)^(1 / 1.6) - 1)
  expect_equal(r$slope_below, 3)
  expect_equal(r$slope_above, 3.36)
  expect_equal(r$slope_change_pct, 12)
  expect_false(r$continuous)
})

test_that("a rating whose limbs meet is continuous, with zero gaps", {
  C2 <- 2 / 1^1.6
  r <- check_limb_continuity(step_table(C2))
  expect_equal(r$gap_cms, 0, tolerance = 1e-12)
  expect_equal(r$stage_gap_m, 0, tolerance = 1e-12)
  expect_true(r$continuous)
})

test_that("the discharge gap passes on the absolute tolerance or on the relative one, and fails when neither holds", {
  t <- step_table()                                  # gap 0.1 cms, 5%
  expect_false(check_limb_continuity(t)$discharge_ok)
  expect_true(check_limb_continuity(t, tol_abs = 0.1, tol_rel = 0)$discharge_ok)     # absolute alone
  expect_true(check_limb_continuity(t, tol_abs = 0, tol_rel = 0.05)$discharge_ok)    # relative alone
  expect_false(check_limb_continuity(t, tol_abs = 0.09, tol_rel = 0.04)$discharge_ok)
})

test_that("the stage gap has its own tolerance, and both must hold for the junction to be continuous", {
  t <- step_table()                                  # stage gap about -0.030 m
  loose <- check_limb_continuity(t, tol_abs = 1, tol_stage = 0.005)
  expect_true(loose$discharge_ok)
  expect_false(loose$stage_ok)
  expect_false(loose$continuous)
  both <- check_limb_continuity(t, tol_abs = 1, tol_stage = 0.05)
  expect_true(both$stage_ok && both$continuous)
})

test_that("the slope is reported but not judged unless asked", {
  t <- step_table()
  expect_true(is.na(check_limb_continuity(t)$slope_ok))
  expect_false(check_limb_continuity(t, tol_slope = 0.1)$slope_ok)    # 12% > 10%
  expect_true(check_limb_continuity(t, tol_slope = 0.15)$slope_ok)
  # A kink alone does not make a junction discontinuous.
  C2 <- 2.1 * 0 + 2
  kink <- FlodeRatingTable(table = data.table::data.table(lower_level = c(0.2, 1), upper_level = c(1, 3),
                                                          C = c(2, C2), a = c(0, 0), n = c(1.5, 2)))
  r <- check_limb_continuity(kink, tol_slope = 0.01)
  expect_true(r$continuous)
  expect_false(r$slope_ok)
})

test_that("several junctions give one row each, in stage order", {
  t3 <- FlodeRatingTable(table = data.table::data.table(
    lower_level = c(0.2, 1, 2), upper_level = c(1, 2, 3), C = c(2, 2.1, 2.1 * 2^1.6 / 2^1.7), a = 0, n = c(1.5, 1.6, 1.7)))
  r <- check_limb_continuity(t3)
  expect_equal(r$junction, 1:2)
  expect_equal(r$stage_m, c(1, 2))
  expect_equal(c(r$continuous[1], r$continuous[2]), c(FALSE, TRUE))
})

test_that("a junction at or below the zero-flow stage has no relative or stage gap, and is judged on the absolute one", {
  t <- FlodeRatingTable(table = data.table::data.table(lower_level = c(0.2, 1), upper_level = c(1, 3),
                                                       C = c(2, 3), a = c(1, 1), n = c(1.5, 1.6)))
  r <- check_limb_continuity(t)
  expect_equal(r$q_below_cms, 0)
  expect_true(is.na(r$gap_rel) && is.na(r$stage_gap_m))
  expect_true(r$continuous)
})

test_that("a single limb, and a segmented fit, have no junction to check", {
  one <- FlodeRatingTable(table = data.table::data.table(lower_level = 0.2, upper_level = 3, C = 2, a = 0, n = 1.5))
  expect_equal(nrow(check_limb_continuity(one)), 0L)
  set.seed(4)
  h <- seq(0.3, 3.5, by = 0.03)
  q <- ifelse(h < 1.5, 3 * h^1.6, 3 * 1.5^1.6 * (h / 1.5)^2.1) * exp(rnorm(length(h), sd = 0.03))
  seg <- rate_optimise_segmented(q, h, control = 1.5)
  expect_equal(nrow(check_limb_continuity(seg)), 0L)
  expect_true(all(c("gap_cms", "continuous") %in% names(check_limb_continuity(seg))))
})

# ---- before and after an alignment -------------------------------------------------------------------------

test_that("after aligning the equations the gap is closed, and the table shows both states", {
  t <- step_table()
  r <- check_limb_continuity(t, after = align_limb_equations(t))
  expect_equal(r$gap_cms_before, 0.1)
  expect_equal(r$gap_cms_after, 0, tolerance = 1e-9)
  expect_false(r$continuous_before)
  expect_true(r$continuous_after)
  expect_true(r$improved)
  expect_equal(r$stage_m_before, r$stage_m_after)
})

test_that("aligning the boundaries can move the junction, so both stages are given", {
  set.seed(3)
  h <- round(seq(0.3, 3.4, length.out = 40), 3)
  q <- ifelse(h < 1.6, 3.2 * h^1.6, 3.2 * 1.6^1.6 * (h / 1.6)^2.1) * exp(rnorm(40, sd = 0.03))
  fit <- fit_rating(data.frame(stage_m = h, discharge_cms = q), controls = 1.6, quiet = TRUE)
  moved <- suppressWarnings(align_limb_boundaries(fit))
  r <- check_limb_continuity(fit, after = moved)
  expect_true(all(c("stage_m_before", "stage_m_after") %in% names(r)))
  expect_equal(r$stage_m_before, 1.6)
  expect_lt(abs(r$gap_cms_after), abs(r$gap_cms_before) + 1e-9)
})

test_that("a rating that was already continuous is not reported as improved", {
  t <- step_table(2)
  r <- check_limb_continuity(t, after = t)
  expect_false(r$improved)
  expect_equal(r$continuous_before, r$continuous_after)
})

test_that("a fit can be checked directly, and compared with its constrained refit", {
  set.seed(1)
  h <- seq(0.4, 3, by = 0.05)
  q <- 3.2 * h^1.6 * exp(rnorm(length(h), sd = 0.03))
  fit <- rate_optimise(q, h, control = 1.5)
  expect_equal(nrow(check_limb_continuity(fit)), 1L)
  constrained <- suppressWarnings(rate_optimise_constrained(q, h, control = 1.5))
  r <- check_limb_continuity(fit, after = constrained)
  expect_lt(abs(r$gap_cms_after), 1e-6)
  expect_true(r$continuous_after)
})

# ---- agreement with the other gap tools ------------------------------------------------------------------

test_that("it agrees with the invariant check on which junctions step", {
  t <- step_table()
  expect_false(check_limb_continuity(t, tol_rel = 0.01, tol_abs = 0)$discharge_ok)
  expect_equal(assessment_checks(rating_invariants(t))[check_id == "limb_continuity"]$status, "warning")
  ok <- step_table(2)
  expect_true(check_limb_continuity(ok)$continuous)
  expect_equal(assessment_checks(rating_invariants(ok))[check_id == "limb_continuity"]$status, "pass")
})

# ---- arguments ---------------------------------------------------------------------------------------------------

test_that("arguments are checked, and a mismatch of limbs is explained", {
  t <- step_table()
  expect_error(check_limb_continuity(1), "must be a FlodeRating or FlodeRatingTable")
  expect_error(check_limb_continuity(t, after = "a"), "after must be a FlodeRating")
  expect_error(check_limb_continuity(t, tol_abs = -1), "tol_abs must be a single non-negative number")
  expect_error(check_limb_continuity(t, tol_rel = NA), "tol_rel")
  expect_error(check_limb_continuity(t, tol_stage = c(1, 2)), "tol_stage")
  expect_error(check_limb_continuity(t, tol_slope = "x"), "tol_slope")
  one <- FlodeRatingTable(table = data.table::data.table(lower_level = 0.2, upper_level = 3, C = 2, a = 0, n = 1.5))
  expect_error(check_limb_continuity(t, after = one), "1 junction\\(s\\) and after has 0")
})

test_that("the input is not changed", {
  t <- step_table()
  before <- data.table::copy(t@table)
  check_limb_continuity(t, after = align_limb_equations(t))
  expect_equal(t@table, before)
})
