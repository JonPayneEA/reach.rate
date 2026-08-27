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

test_that("expand_rating_table evaluates Q = C(h-a)^n per limb", {
  rating_dt <- data.table::data.table(
    lower_level = c(0.0, 1.2),
    upper_level = c(1.2, 2.5),
    C = c(2.5, 4.1),
    a = c(0.0, 0.0),
    n = c(1.50, 1.70)
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
    lower_level = 2.0, upper_level = 999, C = 5, a = 0, n = 1.5
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

test_that("resolve_rc_gaps match_upper_to_lower matches the upper start to the lower end", {
  rc_raw_dt <- build_two_limb_rc_dt()
  q_lower_end <- rc_raw_dt[limb == 1][stage == max(stage), discharge]

  rc_fixed_dt <- resolve_rc_gaps(rc_raw_dt, method = "match_upper_to_lower")
  q_upper_start <- rc_fixed_dt[limb == 2][stage == min(stage), discharge]

  expect_equal(q_upper_start, q_lower_end, tolerance = 1e-8)
  # Only the single junction row changes -- the rest of the upper limb is untouched.
  expect_equal(
    rc_fixed_dt[limb == 2][stage != min(stage), discharge],
    rc_raw_dt[limb == 2][stage != min(stage), discharge]
  )
})

test_that("resolve_rc_gaps match_lower_to_upper matches the lower end to the upper start", {
  rc_raw_dt <- build_two_limb_rc_dt()
  q_upper_start <- rc_raw_dt[limb == 2][stage == min(stage), discharge]

  rc_fixed_dt <- resolve_rc_gaps(rc_raw_dt, method = "match_lower_to_upper")
  q_lower_end <- rc_fixed_dt[limb == 1][stage == max(stage), discharge]

  expect_equal(q_lower_end, q_upper_start, tolerance = 1e-8)
  expect_equal(
    rc_fixed_dt[limb == 1][stage != max(stage), discharge],
    rc_raw_dt[limb == 1][stage != max(stage), discharge]
  )
})

test_that("resolve_rc_gaps snap_to_lower/snap_to_upper are deprecated aliases with identical output", {
  rc_raw_dt <- build_two_limb_rc_dt()

  expect_warning(
    old_result <- resolve_rc_gaps(rc_raw_dt, method = "snap_to_lower"),
    "deprecated.*match_upper_to_lower"
  )
  new_result <- resolve_rc_gaps(rc_raw_dt, method = "match_upper_to_lower")
  expect_identical(old_result, new_result)

  expect_warning(
    old_result2 <- resolve_rc_gaps(rc_raw_dt, method = "snap_to_upper"),
    "deprecated.*match_lower_to_upper"
  )
  new_result2 <- resolve_rc_gaps(rc_raw_dt, method = "match_lower_to_upper")
  expect_identical(old_result2, new_result2)
})

test_that("resolve_rc_gaps extend_lower_to_upper rescales every row of the lower limb, not just the endpoint", {
  rc_raw_dt <- build_two_limb_rc_dt()
  rc_fixed_dt <- resolve_rc_gaps(rc_raw_dt, method = "extend_lower_to_upper")

  q_lower_end <- rc_fixed_dt[limb == 1][stage == max(stage), discharge]
  q_upper_start <- rc_fixed_dt[limb == 2][stage == min(stage), discharge]
  expect_equal(q_lower_end, q_upper_start, tolerance = 1e-8)

  # Upper limb completely untouched.
  expect_identical(rc_fixed_dt[limb == 2], rc_raw_dt[limb == 2])

  # Every row of the lower limb was rescaled by the same constant factor
  # (a real curve reshape, not a single-endpoint patch) -- check on rows
  # away from the zero-flow stage to avoid a 0/0 division.
  orig_lower <- rc_raw_dt[limb == 1][stage > min(stage)]
  new_lower <- rc_fixed_dt[limb == 1][stage > min(stage)]
  scale_factors <- new_lower$discharge / orig_lower$discharge
  expect_true(all(abs(scale_factors - scale_factors[1]) < 1e-8))
  expect_false(isTRUE(all.equal(scale_factors[1], 1))) # an actual rescale happened
})

test_that("resolve_rc_gaps extend_upper_to_lower rescales every row of the upper limb, not just the endpoint", {
  rc_raw_dt <- build_two_limb_rc_dt()
  rc_fixed_dt <- resolve_rc_gaps(rc_raw_dt, method = "extend_upper_to_lower")

  q_lower_end <- rc_fixed_dt[limb == 1][stage == max(stage), discharge]
  q_upper_start <- rc_fixed_dt[limb == 2][stage == min(stage), discharge]
  expect_equal(q_lower_end, q_upper_start, tolerance = 1e-8)

  expect_identical(rc_fixed_dt[limb == 1], rc_raw_dt[limb == 1])

  scale_factors <- rc_fixed_dt[limb == 2]$discharge / rc_raw_dt[limb == 2]$discharge
  expect_true(all(abs(scale_factors - scale_factors[1]) < 1e-8))
  expect_false(isTRUE(all.equal(scale_factors[1], 1)))
})

test_that("resolve_rc_gaps extend_* methods warn and skip a junction when the divisor is near zero", {
  stage1 <- c(8.0, 8.5, 9.0, 9.5, 10.0)
  limb_a <- data.table::data.table(stage = stage1, discharge = c(0, 1, 5, 15, 1e-12), limb = 1L)
  limb_b <- data.table::data.table(stage = c(10.0, 10.5, 11.0), discharge = c(50, 60, 70), limb = 2L)
  rc_dt <- data.table::rbindlist(list(limb_a, limb_b))

  expect_warning(
    result <- resolve_rc_gaps(rc_dt, method = "extend_lower_to_upper"),
    "too close to zero"
  )
  expect_identical(result[limb == 1], limb_a)
  expect_identical(result[limb == 2], limb_b)
})

test_that("resolve_rc_gaps extend methods resolve a 3-limb chain correctly, propagating from the anchor", {
  s1 <- seq(0, 2, by = 0.2); s2 <- seq(2, 4, by = 0.2); s3 <- seq(4, 6, by = 0.2)
  l1 <- data.table::data.table(stage = s1, discharge = 5 * (s1 + 0.1)^1.5, limb = 1L)
  l2 <- data.table::data.table(stage = s2, discharge = 8 * s2^1.6, limb = 2L)
  l3 <- data.table::data.table(stage = s3, discharge = 3 * (s3 - 1)^1.9, limb = 3L)
  rc_dt <- data.table::rbindlist(list(l1, l2, l3))

  # extend_lower_to_upper propagates top-down: limb 3 (the topmost) is the
  # anchor and must be completely untouched; both junctions must close.
  res_down <- resolve_rc_gaps(rc_dt, method = "extend_lower_to_upper")
  expect_identical(res_down[limb == 3], l3)
  expect_equal(max(res_down[limb == 1]$discharge), res_down[limb == 2]$discharge[1], tolerance = 1e-8)
  expect_equal(max(res_down[limb == 2]$discharge), res_down[limb == 3]$discharge[1], tolerance = 1e-8)

  # extend_upper_to_lower propagates bottom-up: limb 1 is the anchor.
  res_up <- resolve_rc_gaps(rc_dt, method = "extend_upper_to_lower")
  expect_identical(res_up[limb == 1], l1)
  expect_equal(max(res_up[limb == 1]$discharge), res_up[limb == 2]$discharge[1], tolerance = 1e-8)
  expect_equal(max(res_up[limb == 2]$discharge), res_up[limb == 3]$discharge[1], tolerance = 1e-8)
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

test_that("rating_plot(FlodeRatingTable) returns a ggplot with per-limb curve data", {
  rating_dt <- data.table::data.table(
    lower_level = c(0.0, 1.2, 3.0),
    upper_level = c(1.2, 3.0, 5.0),
    C = c(2.5, 4.1, 1.8), a = c(0, 0, 0), n = c(1.5, 1.7, 1.3)
  )
  aligned <- align_limb_equations(rating_dt)

  pdf(NULL)
  on.exit(dev.off())

  p <- rating_plot(aligned)

  expect_s3_class(p, "ggplot")
  expect_true(all(c("stage", "discharge", "limb") %in% names(p$data)))
  expect_equal(nlevels(p$data$limb), 3L)
})

test_that("rating_plot(FlodeRatingTable) curve matches Q = C(H-a)^n exactly", {
  rating_dt <- data.table::data.table(
    lower_level = 0.0, upper_level = 5.0, C = 3, a = 0, n = 1.5
  )
  table_obj <- align_limb_equations(rating_dt)

  pdf(NULL)
  on.exit(dev.off())
  p <- rating_plot(table_obj, n_points = 50L)

  expect_equal(nrow(p$data), 50L)
  expected_discharge <- 3 * (p$data$stage - 0)^1.5
  expect_equal(p$data$discharge, expected_discharge, tolerance = 1e-8)
})

test_that("rating_plot(FlodeRatingTable) validates n_points", {
  rating_dt <- data.table::data.table(lower_level = 0, upper_level = 5, C = 3, a = 0, n = 1.5)
  table_obj <- align_limb_equations(rating_dt)
  expect_error(rating_plot(table_obj, n_points = -1), "positive integer")
  expect_error(rating_plot(table_obj, n_points = c(10, 20)), "positive integer")
})

build_three_limb_rating_dt <- function() {
  data.table::data.table(
    lower_level = c(0.0, 1.2, 2.5),
    upper_level = c(1.2, 2.5, 4.0),
    C = c(2.5, 4.1, 7.8),
    a = c(0.0, 0.0, 0.0),
    n = c(1.50, 1.70, 2.00)
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

  eval_q <- function(stage, C, a, n) C * (stage - a)^n

  q_limb1_top <- eval_q(aligned_dt$upper_level[1], aligned_dt$C[1], aligned_dt$a[1], aligned_dt$n[1])
  q_limb2_bottom <- eval_q(aligned_dt$lower_level[2], aligned_dt$C[2], aligned_dt$a[2], aligned_dt$n[2])
  expect_equal(q_limb1_top, q_limb2_bottom, tolerance = 1e-10)

  q_limb2_top <- eval_q(aligned_dt$upper_level[2], aligned_dt$C[2], aligned_dt$a[2], aligned_dt$n[2])
  q_limb3_bottom <- eval_q(aligned_dt$lower_level[3], aligned_dt$C[3], aligned_dt$a[3], aligned_dt$n[3])
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
    C = c(2.5, 4.1), a = c(0, 0), n = c(1.5, 1.7)
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

test_that("align_limb_equations accepts a FlodeRating directly, matching as_rating_table(fit) first", {
  set.seed(10)
  stage_seq <- seq(0.5, 3.5, by = 0.03)
  true_limb <- cut(stage_seq, breaks = c(0.5, 1.6, 2.2, 3.5), labels = FALSE, include.lowest = TRUE)
  coefs_by_limb <- data.frame(C = c(3, 6, 10), a = c(0, 0.1, 0.2), n = c(1.4, 1.6, 1.8))
  discharge_seq <- coefs_by_limb$C[true_limb] *
    (stage_seq - coefs_by_limb$a[true_limb])^coefs_by_limb$n[true_limb] +
    rnorm(length(stage_seq), sd = 0.03)
  fit <- rate_optimise(discharge_seq, stage_seq, control = c(1.6, 2.2))

  from_fit <- align_limb_equations(fit, anchor_limb = 1L)
  from_table <- align_limb_equations(as_rating_table(fit), anchor_limb = 1L)

  expect_equal(from_fit@table, from_table@table)
  expect_s3_class(from_fit@previous, "reach.rate::FlodeRatingTable")
})

test_that("expand_rating_table accepts a FlodeRatingTable directly", {
  rating_table <- FlodeRatingTable(table = build_three_limb_rating_dt())
  rc_from_object_dt <- expand_rating_table(rating_table, step = 0.05)
  rc_from_plain_dt <- expand_rating_table(build_three_limb_rating_dt(), step = 0.05)
  expect_equal(rc_from_object_dt, rc_from_plain_dt)
})

test_that("align_limb_equations rejects an invalid depth at the junction", {
  # a = 5 is above the shared junction stage (1.2), so stage - a is
  # negative for limb 2 at the point it needs to be evaluated -- an
  # invalid depth for a fractional exponent, not just a numerically
  # awkward one.
  bad_rating_dt <- data.table::data.table(
    lower_level = c(0.0, 1.2), upper_level = c(1.2, 3.0),
    C = c(2.5, 4.1), a = c(0, 5), n = c(1.5, 1.7)
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
    C = c(2.5, 4.1, 1.8), a = c(0, 2.9343028, 0), n = c(1.5, 1.7, 1.3)
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

  eval_q <- function(stage, C, a, n) C * (stage - a)^n
  q_from_limb2 <- eval_q(aligned_dt$upper_level[2], aligned_dt$C[2], aligned_dt$a[2], aligned_dt$n[2])
  q_from_limb3 <- eval_q(aligned_dt$lower_level[3], aligned_dt$C[3], aligned_dt$a[3], aligned_dt$n[3])
  expect_equal(q_from_limb2, q_from_limb3, tolerance = 1e-10)
})

test_that("align_limb_equations(on_align_failure = 'skip') has no effect when nothing fails", {
  rating_dt <- build_three_limb_rating_dt()
  aligned_dt <- align_limb_equations(rating_dt, on_align_failure = "skip")@table
  expect_false(any(aligned_dt$align_failed))
})

test_that("align_limb_boundaries relocates the junction to where the curves actually cross", {
  # C1*H^B1 = C2*H^B2 => H = (C1/C2)^(1/(B2-B1)) = (5/1)^(1/1) = 5
  rating_dt <- data.table::data.table(
    lower_level = c(0.0, 2.0), upper_level = c(2.0, 6.0),
    C = c(5, 1), a = c(0, 0), n = c(1.2, 2.2)
  )
  result <- align_limb_boundaries(rating_dt)

  expect_s3_class(result, "reach.rate::FlodeRatingTable")
  out_dt <- result@table
  # C/a/n are never touched
  expect_equal(out_dt$C, rating_dt$C)
  expect_equal(out_dt$a, rating_dt$a)
  expect_equal(out_dt$n, rating_dt$n)
  # Boundary actually moved, and both sides moved together
  expect_false(isTRUE(all.equal(out_dt$upper_level[1], rating_dt$upper_level[1])))
  expect_equal(out_dt$upper_level[1], out_dt$lower_level[2])
  expect_true(all(out_dt$boundary_adjusted))
  # The two curves genuinely agree at the new boundary
  h_star <- out_dt$upper_level[1]
  q1 <- out_dt$C[1] * (h_star - out_dt$a[1])^out_dt$n[1]
  q2 <- out_dt$C[2] * (h_star - out_dt$a[2])^out_dt$n[2]
  expect_equal(q1, q2, tolerance = 1e-6)
  expect_equal(h_star, 5, tolerance = 1e-4)
})

test_that("align_limb_boundaries warns and leaves the junction unchanged when curves don't cross", {
  # Same n (parallel-ish) with limb 2 always above limb 1 in range -- no crossing.
  rating_dt <- data.table::data.table(
    lower_level = c(0.0, 2.0), upper_level = c(2.0, 4.0),
    C = c(1, 5), a = c(0, 0), n = c(1.0, 1.0)
  )
  expect_warning(result <- align_limb_boundaries(rating_dt), "do not cross")

  out_dt <- result@table
  expect_false(any(out_dt$boundary_adjusted))
  expect_equal(out_dt$upper_level[1], rating_dt$upper_level[1])
  expect_equal(out_dt$lower_level[2], rating_dt$lower_level[2])
})

test_that("align_limb_boundaries resolves a 3-limb chain's two junctions independently", {
  rating_dt <- build_three_limb_rating_dt()
  result <- align_limb_boundaries(rating_dt)
  out_dt <- result@table

  expect_equal(out_dt$upper_level[1], out_dt$lower_level[2])
  expect_equal(out_dt$upper_level[2], out_dt$lower_level[3])
  expect_equal(out_dt$C, rating_dt$C)

  eval_q <- function(H, C, a, n) C * (H - a)^n
  h1 <- out_dt$upper_level[1]
  expect_equal(eval_q(h1, out_dt$C[1], out_dt$a[1], out_dt$n[1]), eval_q(h1, out_dt$C[2], out_dt$a[2], out_dt$n[2]), tolerance = 1e-6)
  h2 <- out_dt$upper_level[2]
  expect_equal(eval_q(h2, out_dt$C[2], out_dt$a[2], out_dt$n[2]), eval_q(h2, out_dt$C[3], out_dt$a[3], out_dt$n[3]), tolerance = 1e-6)
})

test_that("align_limb_boundaries validates its inputs", {
  expect_error(align_limb_boundaries(data.frame()), "at least one row")
  expect_error(
    align_limb_boundaries(data.table::data.table(lower_level = 0, upper_level = 1)),
    "missing column"
  )
  bad_dt <- data.table::data.table(
    lower_level = c(0, 1.5), upper_level = c(1.2, 2.5), C = c(1, 1), a = c(0, 0), n = c(1, 1)
  )
  expect_error(align_limb_boundaries(bad_dt), "contiguous")
})

build_three_junction_boundary_dt <- function() {
  data.table::data.table(
    lower_level = c(0.0, 1.2, 2.5),
    upper_level = c(1.2, 2.5, 4.0),
    C = c(2.5, 2.554, 2.337325),
    a = c(0.0, 0.0, 0.0),
    n = c(1.50, 1.65, 1.80)
  )
}

test_that("align_limb_boundaries(junctions = NULL) attempts every junction (the default)", {
  rating_dt <- build_three_junction_boundary_dt()
  result <- align_limb_boundaries(rating_dt)
  expect_true(all(result@table$boundary_adjusted))
  expect_false(isTRUE(all.equal(result@table$upper_level[1], rating_dt$upper_level[1])))
  expect_false(isTRUE(all.equal(result@table$upper_level[2], rating_dt$upper_level[2])))
})

test_that("align_limb_boundaries(junctions = ) restricts relocation to the requested junction(s)", {
  rating_dt <- build_three_junction_boundary_dt()
  result <- align_limb_boundaries(rating_dt, junctions = 2L)

  # Junction 1 (limbs 1/2) untouched, even though it does have a crossing
  expect_false(result@table$boundary_adjusted[1])
  expect_equal(result@table$lower_level[1], rating_dt$lower_level[1])
  expect_equal(result@table$upper_level[1], rating_dt$upper_level[1])
  expect_equal(result@table$lower_level[2], rating_dt$lower_level[2])

  # Junction 2 (limbs 2/3) relocated
  expect_true(result@table$boundary_adjusted[2])
  expect_true(result@table$boundary_adjusted[3])
  expect_false(isTRUE(all.equal(result@table$upper_level[2], rating_dt$upper_level[2])))
  expect_equal(result@table$upper_level[2], result@table$lower_level[3])
})

test_that("align_limb_boundaries(junctions = ) accepts multiple junctions", {
  rating_dt <- build_three_junction_boundary_dt()
  result_both <- align_limb_boundaries(rating_dt, junctions = c(1L, 2L))
  result_default <- align_limb_boundaries(rating_dt)
  expect_equal(result_both@table, result_default@table)
})

test_that("align_limb_boundaries(junctions = ) validates its argument", {
  rating_dt <- build_three_junction_boundary_dt()
  expect_error(align_limb_boundaries(rating_dt, junctions = "a"), "whole numbers")
  expect_error(align_limb_boundaries(rating_dt, junctions = 1.5), "whole numbers")
  expect_error(align_limb_boundaries(rating_dt, junctions = NA_integer_), "whole numbers")
  expect_error(align_limb_boundaries(rating_dt, junctions = 0L), "between 1 and 2")
  expect_error(align_limb_boundaries(rating_dt, junctions = 3L), "between 1 and 2")
})

test_that("align_limb_boundaries is a no-op for a single limb", {
  single_dt <- data.table::data.table(lower_level = 0, upper_level = 5, C = 3, a = 0, n = 1.5)
  result <- align_limb_boundaries(single_dt)
  expect_false(result@table$boundary_adjusted)
  expect_equal(result@table$upper_level, single_dt$upper_level)
})

test_that("align_limb_boundaries builds a genuine audit chain from a FlodeRatingTable input", {
  rating_table <- FlodeRatingTable(table = build_three_limb_rating_dt())
  result <- align_limb_boundaries(rating_table)
  expect_true(identical(result@previous, rating_table))
})

test_that("align_limb_boundaries from a plain table has no previous", {
  result <- align_limb_boundaries(build_three_limb_rating_dt())
  expect_null(result@previous)
})

test_that("align_limb_boundaries accepts a FlodeRating directly, matching as_rating_table(fit) first", {
  set.seed(10)
  stage_seq <- seq(0.5, 3.5, by = 0.03)
  true_limb <- cut(stage_seq, breaks = c(0.5, 1.6, 2.2, 3.5), labels = FALSE, include.lowest = TRUE)
  coefs_by_limb <- data.frame(C = c(3, 6, 10), a = c(0, 0.1, 0.2), n = c(1.4, 1.6, 1.8))
  discharge_seq <- coefs_by_limb$C[true_limb] *
    (stage_seq - coefs_by_limb$a[true_limb])^coefs_by_limb$n[true_limb] +
    rnorm(length(stage_seq), sd = 0.03)
  fit <- rate_optimise(discharge_seq, stage_seq, control = c(1.6, 2.2))

  from_fit <- suppressWarnings(align_limb_boundaries(fit))
  from_table <- suppressWarnings(align_limb_boundaries(as_rating_table(fit)))

  expect_equal(from_fit@table, from_table@table)
  expect_s3_class(from_fit@previous, "reach.rate::FlodeRatingTable")
})
