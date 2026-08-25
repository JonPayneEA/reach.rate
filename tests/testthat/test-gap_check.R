build_two_limb_rc_dt <- function() {
  stage_seq1 <- seq(8.0, 10.0, by = 0.2)
  limb1_dt <- data.table::data.table(
    stage = stage_seq1,
    discharge = 12 * (stage_seq1 - 8.0)^1.65,
    limb = 1L
  )
  stage_seq2 <- seq(10.0, 11.5, by = 0.2)
  limb2_dt <- data.table::data.table(
    stage = stage_seq2,
    # Limb 2 starts 5 m3/s below where limb 1 ends (deliberate gap)
    discharge = (tail(limb1_dt$discharge, 1) - 5) + 30 * (stage_seq2 - 10.0)^1.4,
    limb = 2L
  )
  data.table::rbindlist(list(limb1_dt, limb2_dt))
}

test_that("expand_rating_table evaluates Q = C(h-A)^B per limb", {
  rating_dt <- data.table::data.table(
    lower_level = c(0.0, 1.2),
    upper_level = c(1.2, 2.5),
    C = c(2.5, 4.1),
    A = c(0.0, 0.0),
    B = c(1.50, 1.70)
  )

  rc_dt <- expand_rating_table(rating_dt, step = 0.1)

  expect_true(is.data.table(rc_dt))
  expect_true(all(c("stage", "discharge", "limb") %in% names(rc_dt)))
  expect_equal(unique(rc_dt$limb), c(1L, 2L))
  # Upper bound of each limb must be present regardless of step rounding
  expect_true(1.2 %in% rc_dt[limb == 1, stage])
  expect_true(2.5 %in% rc_dt[limb == 2, stage])
  # Spot-check the rating equation itself
  q_at_1 <- rc_dt[limb == 1 & stage == 1.0, discharge]
  expect_equal(q_at_1, 2.5 * (1.0 - 0.0)^1.50, tolerance = 1e-8)
})

test_that("expand_rating_table errors on missing required columns", {
  bad_rating_dt <- data.table::data.table(lower_level = 0, upper_level = 1)
  expect_error(expand_rating_table(bad_rating_dt), "missing column")
})

test_that("expand_rating_table caps an open-ended sentinel upper level", {
  rating_dt <- data.table::data.table(
    lower_level = 2.0, upper_level = 999, C = 5, A = 0, B = 1.5
  )
  expect_warning(
    rc_dt <- expand_rating_table(rating_dt, step = 0.5, max_stage = 6.0),
    "exceeds max_stage"
  )
  expect_equal(max(rc_dt$stage), 6.0)
})

test_that("detect_rc_gaps flags a known deliberate gap", {
  rc_raw_dt <- build_two_limb_rc_dt()
  gaps_dt <- detect_rc_gaps(rc_raw_dt)

  expect_equal(nrow(gaps_dt), 1L)
  expect_true(gaps_dt$gap_flagged[1])
  expect_equal(gaps_dt$stage_break[1], 10.0)
  expect_lt(gaps_dt$gap_abs[1], 0) # upper limb starts below lower limb's end
})

test_that("detect_rc_gaps returns NULL invisibly for a single limb", {
  single_limb_dt <- build_two_limb_rc_dt()[limb == 1]
  expect_null(detect_rc_gaps(single_limb_dt))
})

test_that("detect_rc_gaps auto-detects limbs when limb_col is absent", {
  rc_raw_dt <- build_two_limb_rc_dt()
  rc_raw_dt[, limb := NULL]
  gaps_dt <- detect_rc_gaps(rc_raw_dt, limb_col = "limb")
  expect_equal(nrow(gaps_dt), 1L)
})

test_that("resolve_rc_gaps midpoint closes the gap at the junction", {
  rc_raw_dt <- build_two_limb_rc_dt()
  rc_fixed_dt <- resolve_rc_gaps(rc_raw_dt, method = "midpoint")

  gaps_after_dt <- detect_rc_gaps(rc_fixed_dt)
  expect_false(any(gaps_after_dt$gap_flagged))

  q_end_lower <- rc_fixed_dt[limb == 1][stage == max(stage), discharge]
  q_start_upper <- rc_fixed_dt[limb == 2][stage == min(stage), discharge]
  expect_equal(q_end_lower, q_start_upper, tolerance = 1e-8)
})

test_that("resolve_rc_gaps snap_to_lower matches the upper start to the lower end", {
  rc_raw_dt <- build_two_limb_rc_dt()
  q_lower_end <- rc_raw_dt[limb == 1][stage == max(stage), discharge]

  rc_fixed_dt <- resolve_rc_gaps(rc_raw_dt, method = "snap_to_lower")
  q_upper_start <- rc_fixed_dt[limb == 2][stage == min(stage), discharge]

  expect_equal(q_upper_start, q_lower_end, tolerance = 1e-8)
})

test_that("resolve_rc_gaps snap_to_upper matches the lower end to the upper start", {
  rc_raw_dt <- build_two_limb_rc_dt()
  q_upper_start <- rc_raw_dt[limb == 2][stage == min(stage), discharge]

  rc_fixed_dt <- resolve_rc_gaps(rc_raw_dt, method = "snap_to_upper")
  q_lower_end <- rc_fixed_dt[limb == 1][stage == max(stage), discharge]

  expect_equal(q_lower_end, q_upper_start, tolerance = 1e-8)
})

test_that("resolve_rc_gaps returns input unchanged when no gap is flagged", {
  rc_raw_dt <- build_two_limb_rc_dt()
  rc_no_gap_dt <- resolve_rc_gaps(rc_raw_dt, tol_abs = 1e6, tol_rel = 1e6)
  data.table::setorder(rc_raw_dt, stage)
  expect_equal(rc_no_gap_dt$discharge, rc_raw_dt$discharge)
})

test_that("detect_rc_gaps classifies a genuine shared-stage junction correctly", {
  rc_raw_dt <- build_two_limb_rc_dt()
  gaps_dt <- detect_rc_gaps(rc_raw_dt)
  expect_equal(gaps_dt$junction_type, "shared_stage")
  expect_false(is.na(gaps_dt$gap_abs))
})

test_that("detect_rc_gaps identifies a stage gap between limbs and reports NA gap_abs", {
  limb1_dt <- data.table(stage = seq(8.0, 9.8, by = 0.2), discharge = 100, limb = 1L)
  # Limb 2 starts at 10.5, not 10.0 -- a genuine stage gap, not a
  # discharge discontinuity at a shared point
  limb2_dt <- data.table(stage = seq(10.5, 11.5, by = 0.2), discharge = 150, limb = 2L)
  rc_gap_dt <- rbindlist(list(limb1_dt, limb2_dt))

  gaps_dt <- detect_rc_gaps(rc_gap_dt)
  expect_equal(gaps_dt$junction_type, "stage_gap")
  expect_true(is.na(gaps_dt$gap_abs))
  expect_true(is.na(gaps_dt$gap_rel))
  expect_true(gaps_dt$gap_flagged)
  expect_equal(gaps_dt$stage_lower_end, 9.8)
  expect_equal(gaps_dt$stage_upper_start, 10.5)
})

test_that("detect_rc_gaps identifies a stage overlap between limbs", {
  limb1_dt <- data.table(stage = seq(8.0, 10.2, by = 0.2), discharge = 100, limb = 1L)
  # Limb 2 starts at 10.0, before limb 1 actually ends (10.2) -- overlap
  limb2_dt <- data.table(stage = seq(10.0, 11.5, by = 0.2), discharge = 150, limb = 2L)
  rc_overlap_dt <- rbindlist(list(limb1_dt, limb2_dt))

  gaps_dt <- detect_rc_gaps(rc_overlap_dt)
  expect_equal(gaps_dt$junction_type, "stage_overlap")
  expect_true(is.na(gaps_dt$gap_abs))
  expect_true(gaps_dt$gap_flagged)
})

test_that("detect_rc_gaps validates stage_tol", {
  rc_raw_dt <- build_two_limb_rc_dt()
  expect_error(detect_rc_gaps(rc_raw_dt, stage_tol = -1), "non-negative")
})

test_that("resolve_rc_gaps skips a stage-gap junction rather than misapplying midpoint/snap", {
  limb1_dt <- data.table(stage = seq(8.0, 9.8, by = 0.2), discharge = 100, limb = 1L)
  limb2_dt <- data.table(stage = seq(10.5, 11.5, by = 0.2), discharge = 150, limb = 2L)
  rc_gap_dt <- rbindlist(list(limb1_dt, limb2_dt))

  expect_warning(
    rc_out_dt <- resolve_rc_gaps(rc_gap_dt),
    "not a.*shared-stage discontinuity"
  )
  # Discharge values should be untouched -- nothing was resolvable
  expect_equal(sort(rc_out_dt$discharge), sort(rc_gap_dt$discharge))
})

test_that("plot_rc_gaps returns a ggplot object invisibly", {
  rc_raw_dt <- build_two_limb_rc_dt()
  rc_fixed_dt <- resolve_rc_gaps(rc_raw_dt)

  pdf(NULL)
  on.exit(dev.off())

  p <- plot_rc_gaps(rc_raw_dt, rc_fixed_dt)
  expect_s3_class(p, "ggplot")
})

build_three_limb_rating_dt <- function() {
  data.table::data.table(
    lower_level = c(0.0, 1.2, 2.5),
    upper_level = c(1.2, 2.5, 4.0),
    C = c(2.5, 4.1, 7.8),
    A = c(0.0, 0.0, 0.0),
    B = c(1.50, 1.70, 2.00)
  )
}

test_that("align_limb_equations keeps the anchor limb's C unchanged", {
  rating_dt <- build_three_limb_rating_dt()
  aligned_result <- align_limb_equations(rating_dt, anchor_limb = 1L)

  expect_s3_class(aligned_result, "reach.rate::FlodeRatingTable")
  aligned_dt <- aligned_result@table
  expect_equal(aligned_dt$C[1], rating_dt$C[1])
  expect_false(aligned_dt$aligned[1])
  expect_true(all(aligned_dt$aligned[2:3]))
  expect_equal(aligned_dt$C_original, rating_dt$C)
})

test_that("align_limb_equations closes every junction exactly", {
  rating_dt <- build_three_limb_rating_dt()
  aligned_dt <- align_limb_equations(rating_dt)@table

  eval_q <- function(stage, C, A, B) C * (stage - A)^B

  q_limb1_top <- eval_q(aligned_dt$upper_level[1], aligned_dt$C[1], aligned_dt$A[1], aligned_dt$B[1])
  q_limb2_bottom <- eval_q(aligned_dt$lower_level[2], aligned_dt$C[2], aligned_dt$A[2], aligned_dt$B[2])
  expect_equal(q_limb1_top, q_limb2_bottom, tolerance = 1e-10)

  q_limb2_top <- eval_q(aligned_dt$upper_level[2], aligned_dt$C[2], aligned_dt$A[2], aligned_dt$B[2])
  q_limb3_bottom <- eval_q(aligned_dt$lower_level[3], aligned_dt$C[3], aligned_dt$A[3], aligned_dt$B[3])
  expect_equal(q_limb2_top, q_limb3_bottom, tolerance = 1e-10)
})

test_that("align_limb_equations with a middle anchor propagates both ways", {
  rating_dt <- build_three_limb_rating_dt()
  aligned_dt <- align_limb_equations(rating_dt, anchor_limb = 2L)@table

  expect_equal(aligned_dt$C[2], rating_dt$C[2])
  expect_true(aligned_dt$aligned[1])
  expect_false(aligned_dt$aligned[2])
  expect_true(aligned_dt$aligned[3])
})

test_that("a re-expanded aligned table has no junction gaps left", {
  rating_dt <- build_three_limb_rating_dt()
  aligned_result <- align_limb_equations(rating_dt)

  # expand_rating_table() accepts the FlodeRatingTable directly -- no
  # manual column selection needed.
  rc_dt <- expand_rating_table(aligned_result)
  gaps_dt <- detect_rc_gaps(rc_dt)

  expect_false(any(gaps_dt$gap_flagged))
})

test_that("align_limb_equations errors on non-contiguous limbs", {
  bad_rating_dt <- data.table::data.table(
    lower_level = c(0.0, 1.5), # gap: limb 1 ends at 1.2, limb 2 starts at 1.5
    upper_level = c(1.2, 2.5),
    C = c(2.5, 4.1), A = c(0, 0), B = c(1.5, 1.7)
  )
  expect_error(align_limb_equations(bad_rating_dt), "contiguous")
})

test_that("align_limb_equations validates its inputs", {
  expect_error(align_limb_equations(data.frame()), "at least one row")
  expect_error(align_limb_equations(build_three_limb_rating_dt(), anchor_limb = 5L), "valid row index")
  expect_error(
    align_limb_equations(data.table::data.table(lower_level = 0, upper_level = 1)),
    "missing column"
  )
})

test_that("align_limb_equations records scale_factor, pct_change, and junction provenance", {
  rating_dt <- build_three_limb_rating_dt()
  aligned_result <- align_limb_equations(rating_dt, anchor_limb = 1L)
  aligned_dt <- aligned_result@table

  expect_true(is.na(aligned_dt$scale_factor[1])) # anchor limb: never aligned
  expect_true(is.na(aligned_dt$alignment_stage[1]))

  expect_equal(aligned_dt$scale_factor[2], aligned_dt$C[2] / aligned_dt$C_original[2])
  expect_equal(aligned_dt$pct_change[2], 100 * (aligned_dt$C[2] - aligned_dt$C_original[2]) / aligned_dt$C_original[2])
  expect_equal(aligned_dt$alignment_stage[2], rating_dt$lower_level[2])

  expect_equal(aligned_result@status, "post_fit_aligned")
})

test_that("align_limb_equations builds a genuine audit chain from a FlodeRatingTable input", {
  rating_table <- FlodeRatingTable(table = build_three_limb_rating_dt())
  aligned_result <- align_limb_equations(rating_table, anchor_limb = 1L)

  expect_equal(aligned_result@status, "post_fit_aligned")
  # @previous references the exact pre-alignment object
  expect_true(identical(aligned_result@previous, rating_table))
  # The input itself was never mutated
  expect_equal(rating_table@table$C, build_three_limb_rating_dt()$C)
})

test_that("align_limb_equations from a plain table has no previous (nothing to chain to)", {
  aligned_result <- align_limb_equations(build_three_limb_rating_dt())
  expect_null(aligned_result@previous)
})

test_that("expand_rating_table accepts a FlodeRatingTable directly", {
  rating_table <- FlodeRatingTable(table = build_three_limb_rating_dt())
  rc_from_object_dt <- expand_rating_table(rating_table, step = 0.05)
  rc_from_plain_dt <- expand_rating_table(build_three_limb_rating_dt(), step = 0.05)
  expect_equal(rc_from_object_dt, rc_from_plain_dt)
})

test_that("align_limb_equations rejects an invalid depth at the junction", {
  # A = 5 is above the shared junction stage (1.2), so stage - A is
  # negative for limb 2 at the point it needs to be evaluated -- an
  # invalid depth for a fractional exponent, not just a numerically
  # awkward one.
  bad_rating_dt <- data.table::data.table(
    lower_level = c(0.0, 1.2), upper_level = c(1.2, 3.0),
    C = c(2.5, 4.1), A = c(0, 5), B = c(1.5, 1.7)
  )
  expect_error(align_limb_equations(bad_rating_dt), "invalid depth")
})

test_that("align_limb_equations(on_align_failure = 'skip') warns and flags the failing limb instead of erroring", {
  # A three-limb table where limb 2's zero-flow datum sits above the
  # junction stage it shares with limb 1 -- the same invalid-depth
  # situation as above, but with a third limb downstream of it so we can
  # confirm the alignment chain keeps going past the skipped limb.
  bad_rating_dt <- data.table::data.table(
    lower_level = c(0.0, 1.2, 3.0), upper_level = c(1.2, 3.0, 5.0),
    C = c(2.5, 4.1, 1.8), A = c(0, 2.9343028, 0), B = c(1.5, 1.7, 1.3)
  )

  expect_warning(
    aligned_result <- align_limb_equations(bad_rating_dt, on_align_failure = "skip"),
    "invalid depth"
  )
  aligned_dt <- aligned_result@table

  expect_false(aligned_dt$align_failed[1]) # anchor: never attempted
  expect_true(aligned_dt$align_failed[2]) # failed and skipped
  expect_false(aligned_dt$aligned[2])
  expect_equal(aligned_dt$C[2], aligned_dt$C_original[2]) # left unaligned

  # The chain continues past the skipped limb: limb 3 is aligned against
  # limb 2's original (unaligned) equation as its reference point.
  expect_false(aligned_dt$align_failed[3])
  expect_true(aligned_dt$aligned[3])

  eval_q <- function(stage, C, A, B) C * (stage - A)^B
  q_from_limb2 <- eval_q(aligned_dt$upper_level[2], aligned_dt$C[2], aligned_dt$A[2], aligned_dt$B[2])
  q_from_limb3 <- eval_q(aligned_dt$lower_level[3], aligned_dt$C[3], aligned_dt$A[3], aligned_dt$B[3])
  expect_equal(q_from_limb2, q_from_limb3, tolerance = 1e-10)
})

test_that("align_limb_equations(on_align_failure = 'skip') has no effect when nothing fails", {
  rating_dt <- build_three_limb_rating_dt()
  aligned_dt <- align_limb_equations(rating_dt, on_align_failure = "skip")@table
  expect_false(any(aligned_dt$align_failed))
})
