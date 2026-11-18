build_fit <- function(n_boot = 0L, control = NULL) {
  set.seed(1)
  stage_m <- seq(0.5, 3, by = 0.05)
  discharge_cms <- 5 * stage_m^1.6 * exp(rnorm(length(stage_m), sd = 0.03))
  if (n_boot > 0L) {
    rate_optimise(discharge_cms, stage_m, control = control, n_boot = n_boot, boot_seed = 1L)
  } else {
    rate_optimise(discharge_cms, stage_m, control = control)
  }
}

build_segmented <- function() {
  set.seed(7)
  stage_m <- seq(0.3, 3.5, by = 0.03)
  q <- 4 * pmax(stage_m - 0.1, 0)^1.55 * (pmax(stage_m - 1.6, 0) + 1)^0.9 *
    (pmax(stage_m - 2.4, 0) + 1)^1.1 * exp(rnorm(length(stage_m), sd = 0.03))
  rate_optimise_segmented(q, stage_m, control = c(1.6, 2.4))
}

# A two-limb fit with every number known, so support can be checked by hand.
hand_fit <- function() {
  FlodeRating(
    limbs = data.table::data.table(
      limb = 1:2, lower_stage_m = c(0, 1), upper_stage_m = c(1, 3),
      C = c(2, 3), a = c(0, 0.5), n = c(1.5, 1.2), rmse_cms = c(0.1, 0.2), r_squared = c(0.99, 0.98)
    ),
    gaugings = data.table::data.table(
      discharge_cms = c(1, 2, 5, 7), stage_m = c(0.2, 0.8, 1.5, 2.0), limb = c(1L, 1L, 2L, 2L)
    )
  )
}

table_rating <- function() {
  FlodeRatingTable(table = data.table::data.table(
    lower_level = c(0, 1), upper_level = c(1, 3), C = c(2, 3), a = c(0, 0.5), n = c(1.5, 1.2)
  ))
}

all_accessors <- list(
  rating_limbs = rating_limbs, rating_coefficients = rating_coefficients,
  rating_evidence = rating_evidence, rating_diagnostics = rating_diagnostics,
  rating_history = rating_history, rating_provenance = rating_provenance,
  rating_support = rating_support, rating_bootstrap = rating_bootstrap
)

test_that("every accessor refuses something that is not a rating, and says what it needs", {
  for (name in names(all_accessors)) {
    expect_error(all_accessors[[name]]("x"), paste0(name, "\\(\\): x must be a FlodeRating"))
    expect_error(all_accessors[[name]](data.frame(a = 1)), "not data.frame")
    expect_error(all_accessors[[name]](NULL), "must be a FlodeRating")
  }
})

# ---- rating_limbs -----------------------------------------------------------

test_that("rating_limbs gives the stage range and equation of each limb", {
  fit <- hand_fit()
  out <- rating_limbs(fit)
  expect_equal(names(out), c("limb", "lower_stage_m", "upper_stage_m", "C", "a", "n"))
  expect_equal(out$limb, 1:2)
  expect_equal(out$C, c(2, 3))
  expect_equal(out$upper_stage_m, c(1, 3))

  tbl <- rating_limbs(table_rating())
  expect_equal(names(tbl), names(out))
  expect_equal(tbl$lower_stage_m, c(0, 1))
  expect_equal(tbl$a, c(0, 0.5))
})

test_that("rating_limbs on a real fit matches the stored limbs", {
  fit <- build_fit(control = 1.5)
  out <- rating_limbs(fit)
  expect_equal(out$C, fit@limbs$C)
  expect_equal(out$lower_stage_m, fit@limbs$lower_stage_m)
  expect_type(out$limb, "integer")
})

test_that("rating_limbs explains why a segmented rating has none", {
  expect_error(rating_limbs(build_segmented()), "joint model.*rating_coefficients")
})

test_that("an accessor returns a copy, so editing it cannot change the rating", {
  fit <- hand_fit()
  out <- rating_limbs(fit)
  out$C <- 999
  expect_equal(fit@limbs$C, c(2, 3))
  ev <- rating_evidence(fit)
  ev$stage_m <- -1
  expect_equal(fit@gaugings$stage_m, c(0.2, 0.8, 1.5, 2.0))
  prov <- rating_provenance(build_fit())
  prov$objective <- "changed"
  expect_equal(rating_provenance(build_fit())$objective, "absolute")
})

# ---- rating_coefficients ----------------------------------------------------

test_that("rating_coefficients is long, one row per limb and parameter, in a fixed order", {
  out <- rating_coefficients(hand_fit())
  expect_equal(names(out), c("limb", "parameter", "estimate", "unit", "se_asymptotic", "se_bootstrap",
                             "q025", "q50", "q975"))
  expect_equal(out$limb, rep(1:2, each = 3))
  expect_equal(out$parameter, rep(c("C", "a", "n"), 2))
  expect_equal(out$estimate, c(2, 0, 1.5, 3, 0.5, 1.2))
  expect_equal(out$unit, rep(c("cms per m^n", "m", "1"), 2))
})

test_that("uncertainty that was not computed is NA, never zero; bootstrap fills it in", {
  plain <- rating_coefficients(hand_fit())
  expect_true(all(is.na(plain$se_bootstrap)) && all(is.na(plain$q50)))

  fit <- build_fit(n_boot = 30L)
  out <- rating_coefficients(fit)
  expect_false(anyNA(out$se_bootstrap))
  expect_false(anyNA(out$se_asymptotic))
  expect_true(all(out$q025 <= out$q50 & out$q50 <= out$q975))
  expect_equal(out$se_asymptotic[out$parameter == "C"], fit@limbs$C_se_asymp)
  expect_equal(out$se_bootstrap[out$parameter == "n"], fit@limbs$n_se)
})

test_that("rating_coefficients of a rating table carries no uncertainty", {
  out <- rating_coefficients(table_rating())
  expect_equal(nrow(out), 6L)
  expect_true(all(is.na(out$se_asymptotic)))
})

test_that("rating_coefficients of a segmented rating lists C, then each breakpoint and exponent", {
  seg <- build_segmented()
  out <- rating_coefficients(seg)
  expect_equal(out$parameter, c("C", "bp1", "n1", "bp2", "n2", "bp3", "n3"))
  expect_true(all(is.na(out$limb)))
  expect_equal(out$estimate[out$parameter == "bp2"], 1.6)
  expect_equal(out$unit[out$parameter %in% c("bp1", "bp2")], c("m", "m"))
  expect_equal(out$unit[out$parameter == "n2"], "1")
})

# ---- rating_evidence --------------------------------------------------------

test_that("rating_evidence returns the gaugings with the leading columns in a fixed order", {
  out <- rating_evidence(hand_fit())
  canonical <- c("evidence_id", "site_id", "stage_m", "discharge_cms", "observation_time",
                 "source_type", "source_name", "source_version", "quality_code", "included",
                 "exclusion_reason", "weight", "notes", "source_row", "metadata")
  expect_equal(names(out), c(canonical, "limb"))
  expect_equal(out$stage_m, c(0.2, 0.8, 1.5, 2.0))

  fit <- build_fit()
  expect_equal(nrow(rating_evidence(fit)), nrow(fit@gaugings))
})

test_that("rating_evidence carries a gauging date into observation_time", {
  set.seed(2)
  stage_m <- seq(0.5, 2.5, by = 0.05)
  fit <- rate_optimise(5 * stage_m^1.6, stage_m,
                       gauging_datetime = as.Date("2020-01-01") + seq_along(stage_m))
  out <- rating_evidence(fit)
  expect_equal(out$observation_time, fit@gaugings$gauging_datetime)
  expect_false(anyNA(out$observation_time))
})

test_that("rating_evidence works for a segmented fit and is refused for a table", {
  expect_equal(nrow(rating_evidence(build_segmented())), length(seq(0.3, 3.5, by = 0.03)))
  expect_error(rating_evidence(table_rating()), "holds equations only, with no gaugings")
})

# ---- rating_diagnostics -----------------------------------------------------

test_that("rating_diagnostics returns only the diagnostic columns the fit has", {
  out <- rating_diagnostics(hand_fit())
  expect_equal(names(out), c("limb", "rmse_cms", "r_squared"))
  expect_equal(out$rmse_cms, c(0.1, 0.2))

  full <- rating_diagnostics(build_fit(n_boot = 10L))
  expect_true(all(c("limb", "rmse_cms", "rmse_pct", "r_squared", "n_obs", "n_starts_converged",
                    "near_bound", "n_boot_success") %in% names(full)))
  expect_false(any(c("C", "a", "n", "C_se", "lower_stage_m") %in% names(full)))
})

test_that("rating_diagnostics of a segmented fit is one row, and a table has none", {
  out <- rating_diagnostics(build_segmented())
  expect_equal(nrow(out), 1L)
  expect_equal(out$n_segments, 3L)
  expect_true(all(c("rmse_cms", "r_squared", "n_obs") %in% names(out)))
  expect_error(rating_diagnostics(table_rating()), "no fit to diagnose")
})

# ---- rating_history ---------------------------------------------------------

test_that("a rating with no earlier version has a one-row history", {
  out <- rating_history(build_fit())
  expect_equal(out$step, 1L)
  expect_equal(out$class, "FlodeRating")
  expect_equal(out$fit_origin, "independently_fitted")
  expect_equal(out$lifecycle, "draft")
  expect_equal(out$n_limbs, 1L)
})

test_that("history follows the chain of amended versions, oldest first", {
  gap <- FlodeRatingTable(table = data.table::data.table(
    lower_level = c(0, 1), upper_level = c(1, 3), C = c(2, 3), a = 0, n = 1.5
  ))
  aligned <- align_limb_equations(gap)
  out <- rating_history(aligned)
  expect_equal(out$step, 1:2)
  expect_equal(out$fit_origin, c("independently_fitted", "post_fit_aligned"))
  expect_equal(out$class, c("FlodeRatingTable", "FlodeRatingTable"))

  again <- align_limb_equations(aligned)
  expect_equal(nrow(rating_history(again)), 3L)
})

test_that("history of a grafted rating records the rating it was grafted onto", {
  new <- data.table::data.table(lower_level = c(0, 1.5), upper_level = c(1.5, 3.41),
                                C = c(2.5, 2.831), a = c(0, -0.886), n = c(1.5, 1.935))
  old <- data.table::data.table(lower_level = 3.41, upper_level = 6, C = 0.3128, a = 0, n = 4.095)
  out <- rating_history(graft_rating(FlodeRatingTable(table = new), old))
  expect_equal(nrow(out), 2L)
  expect_equal(out$fit_origin[2], "grafted")
})

test_that("history works for a segmented fit and counts its segments", {
  out <- rating_history(build_segmented())
  expect_equal(out$class, "FlodeSegmentedRating")
  expect_equal(out$n_limbs, 3L)
})

# ---- rating_provenance ------------------------------------------------------

test_that("rating_provenance returns the recorded settings as a list", {
  out <- rating_provenance(build_fit())
  expect_type(out, "list")
  expect_true(all(c("fitting_equation", "objective", "tool_version") %in% names(out)))
  expect_equal(out$fitting_equation, "Q = C(H - a)^n")
  expect_type(rating_provenance(build_segmented()), "list")
})

test_that("rating_provenance of a table says only what it knows", {
  expect_equal(
    rating_provenance(table_rating()),
    list(fit_origin = "independently_fitted", lifecycle = "draft",
         schema_version = rating_schema_version(), has_previous = FALSE)
  )
  amended <- align_limb_equations(table_rating())
  expect_true(rating_provenance(amended)$has_previous)
})

# ---- rating_support ---------------------------------------------------------

test_that("rating_support is correct by hand", {
  out <- rating_support(hand_fit(), by = "limb")
  expect_equal(out$n_gaugings, c(2L, 2L))
  expect_equal(out$gauged_min_stage_m, c(0.2, 1.5))
  expect_equal(out$gauged_max_stage_m, c(0.8, 2.0))
  # limb 1 spans 0 to 1: unsupported 0.2 below and 0.2 above; limb 2 spans 1 to 3
  expect_equal(out$lower_unsupported_m, c(0.2, 0.5))
  expect_equal(out$upper_unsupported_m, c(0.2, 1.0))
  expect_equal(out$lower_unsupported_frac, c(0.2, 0.25))
  expect_equal(out$upper_unsupported_frac, c(0.2, 0.5))
})

test_that("a limb with no gaugings is reported as such, not hidden", {
  fit <- hand_fit()
  fit <- FlodeRating(limbs = fit@limbs, gaugings = fit@gaugings[fit@gaugings$limb == 1L])
  out <- rating_support(fit, by = "limb")
  expect_equal(out$n_gaugings, c(2L, 0L))
  expect_true(all(is.na(out[2, c("gauged_min_stage_m", "gauged_max_stage_m", "lower_unsupported_m")])))
})

test_that("rating_support agrees with flag_extrapolated_limbs on a real fit", {
  fit <- build_fit(control = 1.5)
  flagged <- flag_extrapolated_limbs(fit)@limbs
  out <- rating_support(fit, by = "limb")
  expect_equal(out$gauged_min_stage_m, flagged$gauged_min_stage_m)
  expect_equal(out$upper_unsupported_m, flagged$upper_unsupported_m)
  expect_equal(out$lower_unsupported_frac, flagged$lower_unsupported_frac)
})

test_that("rating_support of a segmented fit is one row, and a table cannot give one", {
  out <- rating_support(build_segmented(), by = "limb")
  expect_equal(out$gauged_min_stage_m, 0.3)
  expect_equal(out$gauged_max_stage_m, 3.48)
  expect_error(rating_support(table_rating(), by = "limb"), "no gaugings to measure support against")
})

# ---- rating_bootstrap -------------------------------------------------------

test_that("rating_bootstrap returns one row per successful draw and limb, with the limb's range", {
  fit <- build_fit(n_boot = 25L)
  out <- rating_bootstrap(fit)
  ok <- fit@bootstrap[fit@bootstrap$success == TRUE]
  expect_equal(names(out), c("limb", "draw", "lower_stage_m", "upper_stage_m", "C", "a", "n"))
  expect_equal(nrow(out), nrow(ok))
  expect_true(all(out$lower_stage_m == fit@limbs$lower_stage_m[1]))
  expect_false(is.unsorted(out$draw))
})

test_that("successful_only = FALSE returns every requested draw with what became of it", {
  fit <- build_fit(n_boot = 25L)
  all_draws <- rating_bootstrap(fit, successful_only = FALSE)
  expect_equal(nrow(all_draws), nrow(fit@bootstrap))
  expect_true(all(c("success", "reason") %in% names(all_draws)))
})

test_that("rating_bootstrap says how to get draws, and when none succeeded", {
  expect_error(rating_bootstrap(build_fit()), "no bootstrap draws.*n_boot")
  fit <- build_fit(n_boot = 10L)
  failed <- data.table::copy(fit@bootstrap)
  failed[, success := FALSE]
  none <- FlodeRating(limbs = fit@limbs, gaugings = fit@gaugings, bootstrap = failed)
  expect_error(rating_bootstrap(none), "no successful bootstrap draws.*successful_only = FALSE")
  expect_equal(nrow(rating_bootstrap(none, successful_only = FALSE)), nrow(failed))
})

test_that("other rating classes carry no bootstrap", {
  expect_error(rating_bootstrap(build_segmented()), "carries no bootstrap draws")
  expect_error(rating_bootstrap(table_rating()), "no bootstrap draws")
})

test_that("apply_rating_interval accepts rating_bootstrap() output, and gives the same answer", {
  fit <- build_fit(n_boot = 30L)
  stage <- data.table::data.table(stage = c(0.8, 1.5, 2.5))
  via_accessor <- suppressMessages(apply_rating_interval(stage, rating_bootstrap(fit)))
  via_old <- suppressMessages(apply_rating_interval(stage, suppressWarnings(bootstrap_to_table(fit))))
  expect_equal(via_accessor, via_old)

  boot <- rating_bootstrap(fit)
  before <- data.table::copy(boot)
  suppressMessages(apply_rating_interval(stage, boot))
  expect_equal(boot, before)     # the caller's table is not renamed or modified
})

test_that("bootstrap_to_table still works but warns that it is deprecated", {
  fit <- build_fit(n_boot = 10L)
  expect_warning(old <- bootstrap_to_table(fit), "deprecated.*rating_bootstrap")
  expect_equal(old$lower_level, rating_bootstrap(fit)$lower_stage_m)
})

# ---- rating_limbs(all_columns = TRUE) ---------------------------------------

test_that("all_columns returns the stable six first, then everything else the rating carries", {
  fit <- hand_fit()
  out <- rating_limbs(fit, all_columns = TRUE)
  expect_equal(names(out)[1:6], c("limb", "lower_stage_m", "upper_stage_m", "C", "a", "n"))
  expect_equal(names(out)[7:8], c("rmse_cms", "r_squared"))
  expect_equal(out$rmse_cms, c(0.1, 0.2))
  expect_equal(names(rating_limbs(fit)), names(out)[1:6])

  real <- build_fit(n_boot = 10L)
  wide <- rating_limbs(real, all_columns = TRUE)
  expect_true(all(c("rmse_cms", "r_squared", "n_obs", "C_se", "near_bound") %in% names(wide)))
  expect_equal(nrow(wide), nrow(real@limbs))
})

test_that("all_columns shows what amendment steps add, for a fit and for a table", {
  fit <- build_fit(control = 1.5)
  flagged <- flag_extrapolated_limbs(fit)
  expect_true("doubtful" %in% names(rating_limbs(flagged, all_columns = TRUE)))
  expect_false("doubtful" %in% names(rating_limbs(flagged)))

  grafted <- graft_rating(
    FlodeRatingTable(table = data.table::data.table(lower_level = c(0, 1.5), upper_level = c(1.5, 3.41),
                                                    C = c(2.5, 2.831), a = c(0, -0.886), n = c(1.5, 1.935))),
    data.table::data.table(lower_level = 3.41, upper_level = 6, C = 0.3128, a = 0, n = 4.095)
  )
  out <- rating_limbs(grafted, all_columns = TRUE)
  expect_true("source" %in% names(out))
  expect_equal(names(out)[1:6], c("limb", "lower_stage_m", "upper_stage_m", "C", "a", "n"))
})

test_that("all_columns changes nothing for a rating that carries nothing extra, and returns a copy", {
  tbl <- table_rating()
  expect_equal(rating_limbs(tbl, all_columns = TRUE), rating_limbs(tbl))
  out <- rating_limbs(hand_fit(), all_columns = TRUE)
  out$rmse_cms <- 0
  expect_equal(hand_fit()@limbs$rmse_cms, c(0.1, 0.2))
})

test_that("provenance records this package's name and version, for both fit types", {
  expect_match(rating_provenance(build_fit())$tool_version, "^reach\\.rate [0-9]+\\.[0-9]+")
  expect_match(rating_provenance(build_segmented())$tool_version, "^reach\\.rate [0-9]+\\.[0-9]+")
  expect_false(grepl("rating_curves", rating_provenance(build_fit())$tool_version))
})
