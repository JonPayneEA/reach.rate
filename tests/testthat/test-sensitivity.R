# Tranche B4: rating_sensitivity(). Each variant is checked against a refit made by hand
# with the same settings, so the function is held to what it says it does.

sens_data <- function(n = 20, seed = 1) {
  set.seed(seed)
  h <- seq(0.4, 3, length.out = n)
  data.frame(stage_m = h, discharge_cms = 3.2 * h^1.6 * exp(rnorm(n, sd = 0.04)))
}

two_limb_data <- function(n = 40, seed = 3) {
  set.seed(seed)
  h <- round(seq(0.3, 3.4, length.out = n), 3)
  q <- ifelse(h < 1.6, 3.2 * h^1.6, 3.2 * 1.6^1.6 * (h / 1.6)^2.1) * exp(rnorm(n, sd = 0.03))
  data.frame(stage_m = h, discharge_cms = q)
}

stages4 <- c(0.8, 1.5, 2.5, 3)

# The discharge a refit gives at `stages`, made by hand.
by_hand <- function(g, stages, ...) {
  fit <- suppressWarnings(rate_optimise(g$discharge_cms, g$stage_m, ...))
  .kernel_forward(.invariant_table(fit), stages)$discharge
}

# ---- structure -------------------------------------------------------------------------------------

test_that("the result is a FlodeSensitivity with results and a summary, linked by test and variant", {
  fit <- fit_rating(sens_data(), quiet = TRUE)
  s <- rating_sensitivity(fit, stages = stages4)
  expect_true(S7::S7_inherits(s, FlodeSensitivity))
  res <- sensitivity_results(s); sm <- sensitivity_summary(s)
  expect_true(all(c("test", "variant", "evidence_ids", "stage_m", "base_cms", "variant_cms", "change_cms", "change_pct",
                    "status", "note") %in% names(res)))
  expect_equal(nrow(res), nrow(sm) * length(stages4))
  expect_equal(sort(unique(res$stage_m)), stages4)
  expect_setequal(paste(sm$test, sm$variant), unique(paste(res$test, res$variant)))
})

test_that("the base discharge is the rating's own, and change is variant minus base, in cms and in percent", {
  fit <- fit_rating(sens_data(), quiet = TRUE)
  res <- sensitivity_results(rating_sensitivity(fit, tests = "leave_high_out", stages = stages4))
  expect_equal(res[variant == res$variant[1]]$base_cms, apply_rating(fit, stages4)$discharge)
  expect_equal(res$change_cms, res$variant_cms - res$base_cms)
  expect_equal(res$change_pct, 100 * res$change_cms / res$base_cms)
})

test_that("stages default to 25 across the fitted range and can be named", {
  fit <- fit_rating(sens_data(), quiet = TRUE)
  s <- rating_sensitivity(fit, tests = "leave_high_out")
  expect_length(s@stages, 25L)
  expect_equal(range(s@stages), c(0.4, 3))
  expect_equal(rating_sensitivity(fit, tests = "leave_high_out", stages = c(2, 1, 1))@stages, c(1, 2))
})

# ---- leave one out --------------------------------------------------------------------------------------

test_that("each leave-one-out variant equals a refit without that gauging, made by hand", {
  g <- sens_data()
  fit <- fit_rating(g, quiet = TRUE)
  res <- sensitivity_results(rating_sensitivity(fit, tests = "leave_one_out", stages = stages4))
  expect_equal(length(unique(res$variant)), 20L)
  for (i in c(1, 7, 20)) {
    v <- res[variant == paste("without", sprintf("G%03d", i))]
    expect_equal(v$variant_cms, by_hand(g[-i, ], stages4, objective = "relative"), tolerance = 1e-8)
    expect_equal(v$evidence_ids[[1]], sprintf("G%03d", i))
  }
})

test_that("leave-one-out can be restricted to named gaugings, refuses unknown ids, and guards the number of refits", {
  fit <- fit_rating(sens_data(), quiet = TRUE)
  s <- rating_sensitivity(fit, tests = "leave_one_out", evidence_ids = c("G003", "G009"), stages = stages4)
  expect_equal(sort(sensitivity_summary(s)$variant), c("without G003", "without G009"))
  expect_error(rating_sensitivity(fit, tests = "leave_one_out", evidence_ids = "G999"), "unknown evidence id.*G999")
  expect_error(rating_sensitivity(fit, tests = "leave_one_out", max_refits = 5), "20 refits, more than max_refits \\(5\\)")
})

test_that("the summary gives each gauging's leverage and Cook's distance, matching the influence on the fit's scale", {
  g <- sens_data()
  fit <- fit_rating(g, quiet = TRUE)
  sm <- sensitivity_summary(rating_sensitivity(fit, stages = stages4))
  infl <- .fit_scale_influence(fit, .rating_frame(fit))
  loo <- sm[test == "leave_one_out"]
  ids <- vapply(loo$evidence_ids, `[`, "", 1)
  expect_equal(loo$cooks_distance, infl$cooks_distance[match(ids, infl$evidence_id)])
  expect_equal(loo$leverage, infl$leverage[match(ids, infl$evidence_id)])
  expect_true(all(is.na(sm[test != "leave_one_out"]$cooks_distance)))
})

test_that("the gauging that moves discharge most is among those the influence measure ranks highest", {
  fit <- fit_rating(sens_data(seed = 5), quiet = TRUE)
  loo <- sensitivity_summary(rating_sensitivity(fit, tests = "leave_one_out", stages = c(0.5, 1, 2, 3)))
  top_effect <- loo[which.max(max_abs_change_pct)]
  expect_true(top_effect$cooks_distance >= sort(loo$cooks_distance, decreasing = TRUE)[5])
})

# ---- leave high out ---------------------------------------------------------------------------------------

test_that("leave-high-out drops the top gaugings by stage, each at least one, and equals a hand refit", {
  g <- sens_data()
  fit <- fit_rating(g, quiet = TRUE)
  s <- rating_sensitivity(fit, tests = "leave_high_out", stages = stages4)
  sm <- sensitivity_summary(s)
  expect_equal(nrow(sm), 3L)                     # 1, 2 and 4 of 20
  ids <- sm$evidence_ids
  expect_equal(lengths(ids), c(1L, 2L, 4L))
  expect_equal(sort(ids[[3]]), sprintf("G%03d", 17:20))
  keep <- 1:16
  expect_equal(sensitivity_results(s)[variant == sm$variant[3]]$variant_cms,
               by_hand(g[keep, ], stages4, objective = "relative"), tolerance = 1e-8)
  expect_equal(nrow(sensitivity_summary(rating_sensitivity(fit, tests = "leave_high_out", high_out = 0.01))), 1L)
})

test_that("removing the top gaugings moves the top of the curve more than the bottom", {
  fit <- fit_rating(sens_data(), quiet = TRUE)
  res <- sensitivity_results(rating_sensitivity(fit, tests = "leave_high_out", stages = c(0.5, 3)))
  worst <- res[variant == unique(variant)[3]]
  expect_gt(abs(worst[stage_m == 3]$change_pct), abs(worst[stage_m == 0.5]$change_pct))
})

# ---- starting values ---------------------------------------------------------------------------------------

test_that("starting-value variants are the other valid attempts, with their coefficients swapped into the curve", {
  fit <- fit_rating(sens_data(), quiet = TRUE)
  s <- rating_sensitivity(fit, tests = "starting_values", stages = stages4)
  sm <- sensitivity_summary(s)
  fs <- fit@fit_starts[valid == TRUE & start_id != fit@limbs$selected_start_id]
  expect_equal(nrow(sm), nrow(fs))
  r <- fs[1]
  v <- sensitivity_results(s)[variant == sm$variant[1]]
  expect_equal(v$variant_cms, r$C_fit * pmax(stages4 - r$a_fit, 0)^r$n_fit, tolerance = 1e-8)
  expect_equal(lengths(sm$evidence_ids), rep(0L, nrow(sm)))
})

test_that("a single-start fit has no other starts to compare", {
  g <- sens_data()
  fit <- suppressWarnings(rate_optimise(g$discharge_cms, g$stage_m, multi_start = FALSE))
  s <- rating_sensitivity(fit, tests = "starting_values", stages = stages4)
  expect_equal(nrow(sensitivity_summary(s)), 0L)
  expect_output(print(s), "nothing to test")
})

# ---- boundary shift ---------------------------------------------------------------------------------------

test_that("each breakpoint is moved both ways and refitted with the new breakpoint, by hand", {
  g <- two_limb_data()
  fit <- fit_rating(g, controls = 1.6, quiet = TRUE)
  s <- rating_sensitivity(fit, tests = "boundary_shift", stages = stages4, shift = 0.05)
  sm <- sensitivity_summary(s)
  expect_equal(nrow(sm), 2L)
  span <- diff(range(g$stage_m))
  expect_setequal(sm$variant, c(sprintf("breakpoint 1.6 moved to %.4g", 1.6 - 0.05 * span),
                                sprintf("breakpoint 1.6 moved to %.4g", 1.6 + 0.05 * span)))
  down <- sensitivity_results(s)[grepl("moved to 1.445", variant)]
  expect_equal(down$variant_cms, by_hand(g, stages4, objective = "relative", control = 1.6 - 0.05 * span), tolerance = 1e-8)
})

test_that("a single limb has no breakpoint to move, and a shift that leaves the gauged range is reported, not dropped", {
  expect_equal(nrow(sensitivity_summary(rating_sensitivity(fit_rating(sens_data(), quiet = TRUE), tests = "boundary_shift"))), 0L)
  fit <- fit_rating(two_limb_data(), controls = 3.0, quiet = TRUE)
  s <- rating_sensitivity(fit, tests = "boundary_shift", stages = stages4, shift = 0.4)
  sm <- sensitivity_summary(s)
  expect_true("refit_failed" %in% sm$status)
  expect_match(sm[status == "refit_failed"]$note[1], "outside the gauged range|crosses a neighbour|at least 3")
})

# ---- failures are reported with a reason -----------------------------------------------------------------

test_that("a refit that cannot be made is reported with its reason, and the rest still run", {
  g <- two_limb_data()
  g2 <- g[g$stage_m < 0.6 | g$stage_m > 1.4, ]
  fit <- fit_rating(g2, controls = 0.5, quiet = TRUE)         # limb 1 holds exactly 3 gaugings
  expect_equal(sum(g2$stage_m <= 0.5), 3L)
  s <- rating_sensitivity(fit, tests = "leave_one_out", stages = stages4)
  sm <- sensitivity_summary(s)
  failed <- sm[status == "refit_failed"]
  expect_equal(nrow(failed), 3L)
  expect_match(failed$note[1], "at least 3 gaugings")
  expect_true(all(is.na(sensitivity_results(s)[status == "refit_failed"]$variant_cms)))
  expect_gt(sum(sm$status == "ok"), 10L)
  expect_output(print(s), "3 could not be refitted")
})

# ---- settings are reproduced -----------------------------------------------------------------------------------

test_that("recency weighting, bounds and the objective are reproduced in every refit", {
  g <- sens_data()
  g$gauging_datetime <- as.Date("2020-01-01") + seq(0, by = 120, length.out = 20)
  fit <- fit_rating(g, age_halflife = 365, quiet = TRUE)
  res <- sensitivity_results(rating_sensitivity(fit, tests = "leave_one_out", evidence_ids = "G005", stages = stages4))
  ref <- fit@provenance$reference_datetime
  expected <- by_hand(transform(g[-5, ], gauging_datetime = g$gauging_datetime[-5]), stages4, objective = "relative",
                      gauging_datetime = g$gauging_datetime[-5], age_halflife = 365, reference_datetime = ref)
  expect_equal(res$variant_cms, expected, tolerance = 1e-8)
  # An absolute-objective fit is refitted on the absolute objective.
  fa <- fit_rating(sens_data(), objective = "absolute", quiet = TRUE)
  ra <- sensitivity_results(rating_sensitivity(fa, tests = "leave_one_out", evidence_ids = "G002", stages = stages4))
  expect_equal(ra$variant_cms, by_hand(sens_data()[-2, ], stages4, objective = "absolute"), tolerance = 1e-8)
})

# ---- a segmented fit --------------------------------------------------------------------------------------------

test_that("a segmented fit supports leave-one-out, leave-high-out and boundary shift, and skips starting values", {
  g <- two_limb_data()
  fit <- fit_rating(g, controls = 1.6, model = "segmented", quiet = TRUE)
  s <- rating_sensitivity(fit, stages = stages4, evidence_ids = c("G003", "G030"))
  sm <- sensitivity_summary(s)
  expect_setequal(unique(sm$test), c("leave_one_out", "leave_high_out", "boundary_shift"))
  expect_equal(nrow(sm[test == "boundary_shift"]), 2L)
  expect_true(all(is.na(sm[test != "leave_one_out"]$cooks_distance)))
  hand <- suppressWarnings(rate_optimise_segmented(g$discharge_cms[-3], g$stage_m[-3], control = 1.6, objective = "relative"))
  expect_equal(sensitivity_results(s)[variant == "without G003"]$variant_cms,
               .segmented_predict_cms(as.list(hand@coefficients), 2L, stages4), tolerance = 1e-8)
})

# ---- what is refused ------------------------------------------------------------------------------------------------

test_that("a table, an amended rating, a non-rating and bad arguments are refused with a reason", {
  fit <- fit_rating(two_limb_data(), controls = 1.6, quiet = TRUE)
  expect_error(rating_sensitivity(as_rating_table(fit)), "equations only")
  expect_error(rating_sensitivity(1), "must be a FlodeRating")
  amended <- suppressWarnings(align_limb_equations(fit))
  expect_error(rating_sensitivity(amended), "changed since it was fitted")
  expect_error(rating_sensitivity(fit, tests = "everything"), "should be one of")
  expect_error(rating_sensitivity(fit, high_out = 2), "between 0 and 1")
  expect_error(rating_sensitivity(fit, shift = 0.9), "between 0 and 0.5")
  expect_error(rating_sensitivity(fit, stages = c(1, NA)), "finite")
  expect_error(sensitivity_summary(1), "FlodeSensitivity")
  expect_error(sensitivity_results("a"), "FlodeSensitivity")
})

test_that("the input rating is not changed", {
  fit <- fit_rating(sens_data(), quiet = TRUE)
  before <- data.table::copy(fit@limbs)
  rating_sensitivity(fit, tests = c("leave_one_out", "leave_high_out"), stages = stages4)
  expect_equal(fit@limbs, before)
})

# ---- print and plot -----------------------------------------------------------------------------------------------

test_that("printing gives the worst case of each test in words, with its stage", {
  fit <- fit_rating(two_limb_data(), controls = 1.6, quiet = TRUE)
  out <- paste(capture.output(print(rating_sensitivity(fit, stages = stages4, evidence_ids = c("G005", "G020")))), collapse = "\n")
  expect_match(out, "<FlodeSensitivity> \\d+ variant\\(s\\) over 4 stage\\(s\\)")
  expect_match(out, "leave_one_out:\\s+2 variant\\(s\\); worst: without G\\d+ changes discharge by [0-9.]+%")
  expect_match(out, "boundary_shift:\\s+2 variant\\(s\\); worst: breakpoint 1.6 moved")
})

test_that("plot draws the change in discharge against stage, one panel per test", {
  fit <- fit_rating(two_limb_data(), controls = 1.6, quiet = TRUE)
  p <- plot(rating_sensitivity(fit, stages = stages4, evidence_ids = c("G005", "G020")))
  expect_s3_class(p, "ggplot")
  expect_equal(length(unique(p$data$test)), 4L)
  grDevices::pdf(NULL); on.exit(grDevices::dev.off())
  expect_no_error(print(p))
})
