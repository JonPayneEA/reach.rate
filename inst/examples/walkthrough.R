# ============================================================ #
# Tool:         walkthrough
# Description:  Linear, interactive tour of every function in the
#               rating_curves toolkit -- fit, diagnose, flag, bridge,
#               check, resolve, align, apply, and compare a rating curve
#               end to end. Intended to be run section by section, not
#               sourced silently: each step prints or plots something
#               worth looking at before moving on.
# Author:       Jonathan Payne
# Created:      2026-08-18
# Modified:     see prior changelog entries in version control for the
#               full history of this script's evolution -- summarised
#               here rather than repeated in full.
# Modified:     2026-08-19 - JP: updated throughout for the S7
#               conversion. Fits are now FlodeRating/FlodeSegmentedRating
#               instances (@-property access, e.g. fit@limbs, not
#               fit[, ...] or fit$col); fitted_rating_to_table() is gone,
#               replaced by as_rating_table() (returns a
#               FlodeRatingTable); apply_segmented_rating()/plot_
#               segmented_rating() are gone, replaced by the shared
#               apply_rating()/rating_plot() generics also used for
#               FlodeRating; apply_rating()'s argument order flipped to
#               (fit, stage_dt, ...); compare_ratings()/
#               expand_rating_table() now take FlodeRatingTable objects
#               directly rather than manually-selected column subsets.
#               Step 11 now explicitly demonstrates the audit chain
#               align_limb_equations() gained from being an S7 class
#               (@status/@previous) rather than a column to remember to
#               check.
# Modified:     2026-08-25 - JP: moved from rating_curves/walkthrough.R
#               (a box module script) into inst/examples/walkthrough.R
#               now that the toolkit is the reach.rate package. Every
#               box::use() call is gone -- library(reach.rate) is enough
#               -- and steps 18/19 now call demo_cross_section_rating()
#               and rating_curve_explorer() directly instead of sourcing
#               or launching a standalone script.
# Modified:     2026-09-02 - JP: added steps 22-26 covering functions
#               that shipped after the last pass -- rate_from_cross_
#               section(), the weir/flume equations, flag_influential_
#               gaugings()/plot_rating_leverage(), age_halflife recency
#               weighting, and apply_rating_inverse().
# Tier:         1
# Inputs:       None -- self-contained synthetic example throughout
# Outputs:      Printed summaries and several plots, run interactively
# Dependencies: reach.rate (this package)
# ============================================================ #

# HOW TO USE THIS SCRIPT
#
# Run it section by section (in RStudio: place the cursor in a section
# and Ctrl+Enter/Cmd+Enter through it), not source()'d in one go. Each
# section prints or plots something, and the guidance is written to be
# read against that output, not in the abstract.
#
# The story this script tells: a three-limb rating station, gauged
# independently limb by limb (as real stations usually are -- you don't
# gauge the whole range in one session), which is exactly the situation
# that produces junction gaps. It then walks through diagnosing the fit,
# flagging weak limbs, closing the gaps two different ways, applying the
# result to a real-shaped hydrograph, and documenting what changed.
#
# Fits are S7 objects (FlodeRating, FlodeSegmentedRating,
# FlodeRatingTable -- see flode_classes.R): access their contents with
# `@`, e.g. `fit@limbs`, not `fit[, ...]` or `fit$limbs`.
#
# Every number below is synthetic. The point is the shape of the
# workflow, not these particular coefficients.

library(reach.rate)
library(data.table)

cat("\n== 1. Simulate gaugings for a three-limb rating ==============\n")

set.seed(42)
stage_m <- seq(0.5, 3.5, by = 0.03)
true_limb <- cut(
  stage_m,
  breaks = c(0.5, 1.6, 2.2, 3.5),
  labels = FALSE, include.lowest = TRUE
)
true_coefs_dt <- data.table(C = c(3, 6, 10), a = c(0, 0.1, 0.2), n = c(1.4, 1.6, 1.8))
discharge_cms <- true_coefs_dt$C[true_limb] *
  (stage_m - true_coefs_dt$a[true_limb])^true_coefs_dt$n[true_limb] +
  rnorm(length(stage_m), sd = 0.05)

cat(sprintf("Simulated %d gaugings from stage %.2f to %.2f m\n", length(stage_m), min(stage_m), max(stage_m)))

cat("\n== 2. Suggest breakpoints (pretend we don't know them) =======\n")

candidates_dt <- suggest_breakpoints(discharge_cms, stage_m, max_breaks = 2L)
print(candidates_dt[fit_status == "ok"])
suggested_breaks <- suggested_breakpoints_vector(candidates_dt)
cat("Selected breakpoints:\n")
print(suggested_breaks)

cat("\n== 3. Fit the rating curve =====================================\n")

fit <- rate_optimise(discharge_cms, stage_m, control = c(1.6, 2.2))
print(fit@limbs[, .(limb, lower_stage_m, upper_stage_m, C, a, n, rmse_cms, r_squared, n_obs)])

cat("\n== 4. Check fit diagnostics visually ===========================\n")

plot_rating_residuals(fit)

cat("\n== 5. Flag any limb extrapolating beyond its own gaugings ====\n")

fit <- flag_extrapolated_limbs(fit)
print(fit@limbs[, .(limb, lower_stage_m, upper_stage_m, doubtful)])

cat("\n== 6. Plot the fitted rating against the gaugings =============\n")

rating_plot(fit, colours = c(3, 4, 2))

cat("\n== 7. Bridge to a rating table (gap_check's native shape) =====\n")

rating_table <- as_rating_table(fit)
print(rating_table)

cat("\n== 8. Expand to a stage-discharge table ========================\n")

rc_raw_dt <- expand_rating_table(rating_table, step = 0.01)
cat(sprintf("Expanded to %d stage-discharge rows\n", nrow(rc_raw_dt)))

cat("\n== 9. Detect junction gaps ======================================\n")

gaps_dt <- detect_rc_gaps(rc_raw_dt)
print(gaps_dt)

cat("\n== 10. Resolve gaps at the table level =========================\n")

rc_fixed_dt <- resolve_rc_gaps(rc_raw_dt, method = "midpoint")
gaps_after_table_fix_dt <- detect_rc_gaps(rc_fixed_dt)
cat("Gaps remaining in the table after resolve_rc_gaps():\n")
print(gaps_after_table_fix_dt)

cat("\n== 11. Align the equations themselves (survives re-expansion) =\n")

# This is also where the S7 conversion actually pays off: rather than a
# mutated table with a column to remember to check, align_limb_
# equations() returns a NEW FlodeRatingTable with a genuine audit chain.
aligned_result <- align_limb_equations(rating_table, anchor_limb = 1L)
print(aligned_result)
cat(sprintf("aligned_result@status: %s\n", aligned_result@status))
cat(sprintf(
  "aligned_result@previous is the exact pre-alignment object: %s\n",
  identical(aligned_result@previous, rating_table)
))

rc_from_aligned_dt <- expand_rating_table(aligned_result)
gaps_after_align_dt <- detect_rc_gaps(rc_from_aligned_dt)
cat("Gaps remaining after re-expanding the ALIGNED equations (should be none):\n")
print(gaps_after_align_dt)

cat("\n== 12. Plot before vs after (table-level resolution) ==========\n")

plot_rc_gaps(rc_raw_dt, rc_fixed_dt)

cat("\n== 13. Apply the rating to a stage time series =================\n")

hydrograph_dt <- data.table(
  datetime = seq(
    as.POSIXct("2026-01-01 00:00", tz = "UTC"),
    by = "15 min", length.out = 40
  ),
  stage = c(
    seq(0.8, 3.8, length.out = 20),
    seq(3.8, 0.8, length.out = 20)
  )
)
flow_dt <- apply_rating(rating_table, hydrograph_dt, stage_col = "stage", out_col = "discharge_cms")
cat(sprintf(
  "%d of %d stage values were extrapolated (peak above the gauged range)\n",
  sum(flow_dt$extrapolated), nrow(flow_dt)
))
print(flow_dt[c(1, 10, 20, 30, 40)])

cat("\n== 14. Compare the original vs aligned ratings, and plot it ===\n")

comparison <- compare_ratings(rating_table, aligned_result)
cat("Per-limb coefficient diff:\n")
print(comparison$coefficients)
cat("Discharge diff summary across the shared stage range:\n")
print(comparison$discharge[, .(
  max_abs_diff_cms = max(abs(discharge_diff)),
  max_abs_pct_diff = max(abs(discharge_pct_diff), na.rm = TRUE)
)])
plot_rating_comparison(comparison, old_label = "Unaligned", new_label = "Aligned")

cat("\n== 15. Same pipeline, one call (rating_curve_demo::run_demo) ===\n")

demo_result <- run_demo(plot = FALSE)
cat(sprintf(
  "run_demo(): %d limb(s), %d junction gap(s) flagged before resolution\n",
  nrow(demo_result$fit@limbs), sum(demo_result$gaps$gap_flagged)
))

cat("\n== 16. Bootstrap uncertainty ====================================\n")

set.seed(99)
stage_boot_m <- seq(0.5, 3.0, by = 0.08)
discharge_boot_cms <- 4 * stage_boot_m^1.55 + rnorm(length(stage_boot_m), sd = 0.08)
fit_boot <- rate_optimise(discharge_boot_cms, stage_boot_m, n_boot = 200L, boot_seed = 11L)
print(fit_boot@limbs[, .(limb, C, C_se, a, a_se, n, n_se)])

rating_boot_dt <- bootstrap_to_table(fit_boot)
cat(sprintf("%d bootstrap draws across %d limb(s)\n", nrow(rating_boot_dt), length(unique(rating_boot_dt$limb))))

interval_dt <- apply_rating_interval(
  data.table(stage = c(0.8, 1.5, 2.5)),
  rating_boot_dt
)
print(interval_dt)

plot_rating_interval(fit_boot)

cat("\n== 17. Versioned ratings (a rating that shifts over time) =====\n")

rating_history_dt <- data.table(
  version = c("pre-2025", "post-2025"),
  effective_from = as.POSIXct(c("2024-01-01", "2025-06-01"), tz = "UTC"),
  effective_to = as.POSIXct(c("2025-06-01", NA), tz = "UTC"),
  lower_level = c(0.0, 0.0),
  upper_level = c(3.5, 3.5),
  C = c(4.0, 4.6),
  a = c(0.0, 0.0),
  n = c(1.6, 1.6)
)

hydrograph_versioned_dt <- data.table(
  datetime = as.POSIXct(c("2024-06-01", "2025-01-01", "2025-12-01"), tz = "UTC"),
  stage = c(1.5, 1.5, 1.5)
)
versioned_flow_dt <- apply_rating_versioned(hydrograph_versioned_dt, rating_history_dt)
print(versioned_flow_dt)

cat("\n== 18. Cross-section + rating curve, side by side ==============\n")

# demo_cross_section_rating() predates (and is untouched by) the S7
# conversion -- it computes its own curve directly, with no dependency
# on FlodeRating/FlodeRatingTable.
demo_cross_section_rating()

cat("\n== 19. Launch the interactive explorer =========================\n")

# rating_curve_explorer() likewise predates and is untouched by the S7
# conversion. Not launched automatically here: it blocks the console.
# Run separately:
#   reach.rate::rating_curve_explorer()

cat("\n== 20. A genuinely optimised alternative to step 11's rescale ===\n")

fit_constrained <- rate_optimise_constrained(discharge_cms, stage_m, control = c(1.6, 2.2))
print(fit_constrained@limbs[, .(limb, C, a, n, rmse_cms, r_squared, aligned)])

rating_constrained_table <- as_rating_table(fit_constrained)
method_comparison <- compare_ratings(aligned_result, rating_constrained_table)
cat("Discharge diff, C-only rescale vs constrained refit, across the shared stage range:\n")
print(method_comparison$discharge[, .(
  max_abs_diff_cms = max(abs(discharge_diff)),
  max_abs_pct_diff = max(abs(discharge_pct_diff), na.rm = TRUE)
)])
plot_rating_comparison(method_comparison, old_label = "C-only rescale", new_label = "Constrained refit")

cat("\n== 21. A structurally different model: no junction to reconcile ==\n")

set.seed(7)
stage_seg_m <- seq(0.3, 3.5, by = 0.03)
q1 <- 4 * pmax(stage_seg_m - 0.1, 0)^1.55
q2 <- (pmax(stage_seg_m - 1.6, 0) + 1)^0.9
q3 <- (pmax(stage_seg_m - 2.4, 0) + 1)^1.1
discharge_seg_cms <- q1 * q2 * q3 * exp(rnorm(length(stage_seg_m), sd = 0.03))

fit_seg <- rate_optimise_segmented(discharge_seg_cms, stage_seg_m, control = c(1.6, 2.4))
print(fit_seg@coefficients)

# rating_plot() again -- the same generic used in step 6, now dispatching
# to FlodeSegmentedRating's method instead of FlodeRating's.
rating_plot(fit_seg)

# apply_rating() again -- same call shape as step 13's FlodeRatingTable
# case, dispatching to FlodeSegmentedRating's method here.
segmented_flow_dt <- apply_rating(
  fit_seg,
  data.table(stage = c(0.5, 1.5, 2.0, 3.0, 3.8))
)
print(segmented_flow_dt)

cat("\n== 22. A rating derived from a cross-section alone, no gaugings ==\n")

# rate_from_cross_section() needs no gaugings at all: it derives a
# theoretical rating straight from surveyed channel geometry via
# Manning's equation, then fits it through the same rate_optimise()
# pipeline as every other rating in this script. Same trapezoidal
# section as demo_cross_section_rating() -- a 6 m flat bed, 1.25:1 side
# slopes, 2.4 m banks.
xs_dt <- data.table(
  distance_m = c(-6, -3, 3, 6),
  elevation_m = c(2.4, 0, 0, 2.4)
)
fit_xs <- rate_from_cross_section(xs_dt, slope = 0.001, roughness = 0.035, n_points = 30)
cat(sprintf("fit_xs@provenance$source: %s\n", fit_xs@provenance$source))
print(fit_xs@limbs[, .(limb, C, a, n, rmse_cms, r_squared)])

# The plot is the point here: overlay the derived rating on the very
# geometry that produced it, as a sanity check that the curve's shape
# actually matches the channel.
plot_rating_cross_section(fit_xs, xs_dt)

cat("\n== 23. Weir and flume equations (no gaugings, no fitting at all) =\n")

# These four are standalone: discharge from the structure's own
# published equation and geometry, with GUM-style propagated
# uncertainty -- no rate_optimise() involved anywhere in this section.
print(weir_discharge_rectangular(
  head_m = c(0.1, 0.2, 0.3), width_m = 1.5, weir_height_m = 0.5,
  u_cd = 0.02, u_head_m = 0.003
))
print(weir_discharge_vnotch(
  head_m = c(0.1, 0.2), notch_angle_deg = 90, u_cd = 0.01, u_head_m = 0.002
))
print(weir_discharge_cipoletti(
  head_m = c(0.1, 0.2), crest_length_m = 1.0, u_cd = 0.02, u_head_m = 0.003
))
print(flume_discharge_parshall(
  head_m = c(0.15, 0.25), throat_width_m = 0.305, u_cd = 0.03, u_head_m = 0.003
))

cat("\n== 24. Which gaugings are quietly steering the fit? ============\n")

# Reuses `fit` from step 3. flag_influential_gaugings() adds leverage/
# Cook's distance columns to @gaugings; plot_rating_leverage() shows the
# same two quantities behind the influential flag, one facet per limb.
fit_flagged <- flag_influential_gaugings(fit)
cat("Gaugings flagged as influential:\n")
print(fit_flagged@gaugings[influential == TRUE])

plot_rating_leverage(fit)

cat("\n== 25. Age-based recency weighting =============================\n")

# A channel that has drifted: two full-range gauging campaigns a year
# apart, with the true C shifting from 4 to 6. Unweighted, the fit
# lands on the flat average of both eras; with age_halflife set, it
# pulls toward the more recent campaign instead.
set.seed(3)
stage_camp_m <- rep(seq(0.5, 3.0, by = 0.1), 2)
campaign_datetime <- rep(
  as.POSIXct(c("2025-01-01", "2026-01-01"), tz = "UTC"),
  each = length(seq(0.5, 3.0, by = 0.1))
)
true_C_camp <- ifelse(format(campaign_datetime, "%Y") == "2025", 4, 6)
discharge_camp_cms <- true_C_camp * stage_camp_m^1.5 * exp(rnorm(length(stage_camp_m), sd = 0.02))

fit_unweighted <- rate_optimise(discharge_camp_cms, stage_camp_m)
fit_weighted <- rate_optimise(
  discharge_camp_cms, stage_camp_m,
  gauging_datetime = campaign_datetime, age_halflife = 60
)
cat(sprintf(
  "Unweighted C: %.2f | Age-weighted C (60-day half-life): %.2f | True recent C: 6\n",
  fit_unweighted@limbs$C[1], fit_weighted@limbs$C[1]
))

cat("\n== 26. Inverting a rating: discharge back to stage =============\n")

# apply_rating_inverse() is apply_rating() run backwards, but needs a
# gap-free table -- step 9 showed rating_table itself still has junction
# gaps, so use aligned_result from step 11 instead. Round-trip step 13's
# hydrograph through the aligned equations and back.
flow_aligned_dt <- apply_rating(aligned_result, hydrograph_dt, stage_col = "stage", out_col = "discharge_cms")
inverted_dt <- apply_rating_inverse(aligned_result, flow_aligned_dt, discharge_col = "discharge_cms")
comparison_dt <- data.table(
  original_stage_m = hydrograph_dt$stage,
  recovered_stage_m = inverted_dt$stage,
  extrapolated = inverted_dt$extrapolated
)
cat("Original vs. recovered stage (should match, extrapolated tail flagged):\n")
print(comparison_dt[c(1, 10, 20, 30, 40)])

cat("\n== Done. ========================================================\n")

# WHERE TO GO NEXT
#
# Every function used above has its own roxygen documentation with a
# fuller @description and a runnable @examples block. flode_classes.R
# documents the class hierarchy itself (FlodeRatingBase, FlodeRating,
# FlodeSegmentedRating, FlodeRatingTable) and the three shared generics.
# The testthat files under tests/testthat/ are a second source of
# worked examples, each tied to a specific behaviour being checked.
