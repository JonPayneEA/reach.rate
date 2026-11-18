# Tranche B2: assess_rating(). Six domains, no score, both fit classes alike.

ref_time <- as.POSIXct("2026-01-01", tz = "UTC")

clean_evidence <- function(n = 24, seed = 1) {
  set.seed(seed)
  h <- round(seq(0.4, 3, length.out = n), 3)
  df <- data.frame(stage_m = h, discharge_cms = round(3.2 * h^1.6 * exp(rnorm(n, sd = 0.02)), 4),
                   gauging_datetime = as.Date("2024-01-01") + seq(0, by = 20, length.out = n),
                   read_issue = NA_character_)
  ev <- as_flode_evidence(df)
  data.table::set(ev, j = "source_name", value = "archive.csv")
  FlodeEvidence(ev)   # built deliberately: no conversion note
}

good_fit <- function(...) {
  fit_rating(clean_evidence(), n_boot = 20, seed = 3, operational_limits = c(0.4, 3), operational_basis = "gauged range",
             quiet = TRUE, ...)
}

assess <- function(x, ...) assess_rating(x, reference_time = ref_time, ...)
ck <- function(a, id) assessment_checks(a)[check_id == id]
st <- function(a, id) ck(a, id)$status

# ---- the assessment ----------------------------------------------------------------------------

test_that("a clean, well-documented fit passes everything that can be assessed", {
  a <- assess(good_fit())
  expect_true(S7::S7_inherits(a, FlodeAssessment))
  expect_equal(a@subject, "rating")
  chk <- assessment_checks(a)
  expect_equal(sort(unique(chk$domain)),
               sort(c("data", "numerical", "statistical", "hydraulic", "operational", "provenance")))
  expect_false(any(chk$status %in% c("fail", "warning")), info = paste(chk[status %in% c("fail", "warning")]$check_id, collapse = ", "))
  expect_false(assessment_status(a) == "fail")
})

test_that("there is no summary score: the overall result is a status word, and no column holds a number to rank by", {
  a <- assess(good_fit())
  expect_true(assessment_status(a) %in% c("pass", "warning", "fail", "not_assessed"))
  expect_false(any(grepl("score|grade|rank|rating_quality", names(assessment_checks(a)), ignore.case = TRUE)))
  expect_false(any(vapply(assessment_checks(a), is.numeric, logical(1)) & !grepl("stage", names(assessment_checks(a)))))
})

test_that("every check has a stable id, unique across domains", {
  chk <- assessment_checks(assess(good_fit()))
  expect_equal(anyDuplicated(chk$check_id), 0L)
  expect_true(all(c("residual_bias", "residual_spread", "residual_trend", "limb_support", "parameter_identifiability",
                    "exponent_plausible", "zero_flow_stage", "operational_limits_stated", "fit_recorded",
                    "convergence", "coefficients_finite", "limb_continuity", "stage_finite") %in% chk$check_id))
})

test_that("domains map as documented: data from the gaugings, numerical and hydraulic from the invariants", {
  chk <- assessment_checks(assess(good_fit()))
  expect_equal(chk[check_id == "stage_finite"]$domain, "data")
  expect_equal(chk[check_id == "coefficients_finite"]$domain, "numerical")
  expect_equal(chk[check_id == "limb_continuity"]$domain, "hydraulic")
  expect_equal(chk[check_id == "domain_valid"]$domain, "hydraulic")
  expect_equal(chk[check_id == "operational_limits_stated"]$domain, "operational")
  expect_equal(chk[check_id == "fit_recorded"]$domain, "provenance")
})

test_that("severity decides what a check can do: a data check can fail and a data check can warn", {
  chk <- assessment_checks(assess(good_fit()))
  expect_true("error" %in% chk[domain == "data"]$severity)
  expect_true("warning" %in% chk[domain == "data"]$severity)
  expect_false(any(chk$severity == "error" & chk$status == "warning"))
  expect_false(any(chk$severity == "warning" & chk$status == "fail"))
})

# ---- both fit classes, and a table -----------------------------------------------------------------

test_that("an independent fit and a segmented fit are assessed with the same checks", {
  set.seed(4)
  h <- seq(0.3, 3.5, by = 0.03)
  q <- ifelse(h < 1.5, 3 * h^1.6, 3 * 1.5^1.6 * (h / 1.5)^2.1) * exp(rnorm(length(h), sd = 0.03))
  ind <- assess(rate_optimise(q, h, control = 1.5))
  seg <- assess(rate_optimise_segmented(q, h, control = 1.5))
  expect_setequal(assessment_checks(ind)$check_id, assessment_checks(seg)$check_id)
  # The statistical checks that need only residuals work for the segmented fit.
  for (id in c("residual_bias", "residual_spread", "residual_trend", "limb_support", "parameter_identifiability", "convergence")) {
    expect_true(st(seg, id) %in% c("pass", "warning"), info = id)
  }
  # And those that cannot say so, rather than passing.
  for (id in c("exponent_plausible", "influential_gaugings", "zero_flow_stage", "bound_hits", "inverse_consistent",
               "interval_ordering", "bounds_respected", "domain_valid")) {
    expect_equal(st(seg, id), "not_assessed", info = id)
  }
  expect_match(ck(seg, "exponent_plausible")$message, "factors of one joint equation")
})

test_that("a table holds only equations, so its data checks are not assessed, and its equation checks are", {
  tab <- assess(as_rating_table(good_fit()))
  chk <- assessment_checks(tab)
  expect_equal(st(tab, "evidence_available"), "not_assessed")
  expect_equal(st(tab, "residual_bias"), "not_assessed")
  expect_equal(st(tab, "coefficients_finite"), "pass")
  expect_equal(st(tab, "exponent_plausible"), "pass")
  expect_equal(tab@assessed_rows, 0L)
  expect_false(any(chk$status == "pass" & chk$domain %in% c("data", "statistical", "provenance")))
})

test_that("only a rating is accepted, and each threshold is validated", {
  expect_error(assess_rating(1), "must be a FlodeRating")
  expect_error(assess_rating(data.frame(a = 1)), "must be a FlodeRating")
  fit <- good_fit()
  expect_error(assess_rating(fit, bias_tol = -1), "bias_tol")
  expect_error(assess_rating(fit, n_range = c(3, 1)), "n_range")
  expect_error(assess_rating(fit, n_range = 1), "n_range")
  expect_error(assess_rating(fit, spread_tol = "a"), "spread_tol")
})

# ---- statistical: each can warn ---------------------------------------------------------------------

test_that("residual_bias warns when the curve sits off the gaugings, and says which way", {
  fit <- good_fit()
  limbs <- data.table::copy(fit@limbs); limbs[, C := C * 1.25]
  fit@limbs <- limbs
  expect_equal(st(assess(fit), "residual_bias"), "warning")
  expect_match(ck(assess(fit), "residual_bias")$message, "above the gaugings")
  expect_gt(length(ck(assess(fit), "residual_bias")$affected_evidence[[1]]), 0L)
  expect_equal(st(assess(fit, bias_tol = 0.5), "residual_bias"), "pass")
  expect_equal(st(assess(good_fit()), "residual_bias"), "pass")
})

test_that("residual_spread warns for noisy gaugings and the tolerance is an argument", {
  set.seed(8)
  h <- seq(0.4, 3, length.out = 30)
  noisy <- fit_rating(data.frame(stage_m = h, discharge_cms = 3.2 * h^1.6 * exp(rnorm(30, sd = 0.4))), quiet = TRUE)
  expect_equal(st(assess(noisy), "residual_spread"), "warning")
  expect_equal(st(assess(noisy, spread_tol = 5), "residual_spread"), "pass")
})

test_that("residual_trend warns when the equation form does not suit the limb", {
  fit <- good_fit()
  limbs <- data.table::copy(fit@limbs); limbs[, n := n * 1.15]
  fit@limbs <- limbs
  expect_equal(st(assess(fit), "residual_trend"), "warning")
  expect_match(ck(assess(fit), "residual_trend")$message, "rank correlation")
  expect_equal(st(assess(good_fit()), "residual_trend"), "pass")
})

test_that("limb_support warns for a limb with too few gaugings", {
  set.seed(3)
  h <- round(seq(0.3, 3.4, length.out = 40), 3)
  q <- ifelse(h < 1.6, 3.2 * h^1.6, 3.2 * 1.6^1.6 * (h / 1.6)^2.1) * exp(rnorm(40, sd = 0.03))
  fit <- fit_rating(data.frame(stage_m = h, discharge_cms = q), controls = 0.5, quiet = TRUE)
  a <- assess(fit)
  expect_equal(st(a, "limb_support"), "warning")
  expect_match(ck(a, "limb_support")$message, "limb 1 has fewer than 5 gaugings")
  expect_equal(st(assess(fit, min_limb_gaugings = 2), "limb_support"), "pass")
})

test_that("parameter_identifiability warns when stage barely varies", {
  h <- c(2.00, 2.01, 2.02, 2.03, 2.04, 2.05, 2.06)
  q <- 5 * (h - 0.5)^1.6 * c(1.001, 0.999, 1.002, 0.998, 1.001, 0.999, 1.000)
  fit <- suppressWarnings(fit_rating(data.frame(stage_m = h, discharge_cms = q), quiet = TRUE))
  expect_equal(st(assess(fit), "parameter_identifiability"), "warning")
  expect_equal(st(assess(good_fit()), "parameter_identifiability"), "pass")
})

test_that("multi_start_agreement warns when near-optimal starts disagree (mechanism, by setting the recorded spread)", {
  fit <- good_fit()
  limbs <- data.table::copy(fit@limbs); limbs[, multi_start_spread := 0.2]
  fit@limbs <- limbs
  expect_equal(st(assess(fit), "multi_start_agreement"), "warning")
  expect_equal(st(assess(good_fit()), "multi_start_agreement"), "pass")
})

test_that("bound_hits warns when a parameter is on a bound", {
  set.seed(1)
  h <- seq(0.4, 3, by = 0.1)
  q <- 3.2 * h^1.6 * exp(rnorm(length(h), sd = 0.03))
  fit <- suppressWarnings(rate_optimise(q, h, n_bounds = c(2.4, 3)))
  a <- assess(fit)
  expect_equal(st(a, "bound_hits"), "warning")
  expect_match(ck(a, "bound_hits")$message, "n_lower")
})

test_that("influential_gaugings warns only for a strongly influential gauging, and names it", {
  set.seed(1)
  h <- round(seq(0.4, 3, length.out = 24), 3)
  q <- round(3.2 * h^1.6 * exp(rnorm(24, sd = 0.03)), 3)
  fit <- fit_rating(data.frame(stage_m = h, discharge_cms = q), quiet = TRUE)
  # The usual 4/n rule flags a point in healthy data; the assessment does not warn on it.
  expect_equal(st(assess(fit), "influential_gaugings"), "pass")
  expect_match(ck(assess(fit), "influential_gaugings")$message, "the usual 4/n rule flags [1-9]")
  # A lower bar reports it, with its evidence id.
  strict <- assess(fit, cooks_warn = 0.01)
  expect_equal(st(strict, "influential_gaugings"), "warning")
  expect_true(all(grepl("^G", ck(strict, "influential_gaugings")$affected_evidence[[1]])))
  expect_error(assess(fit, cooks_warn = -1), "cooks_warn")
})

# ---- hydraulic ----------------------------------------------------------------------------------------

test_that("exponent_plausible warns outside the range, and the range is an argument", {
  fit <- good_fit()
  limbs <- data.table::copy(fit@limbs); limbs[, n := 0.5]
  fit@limbs <- limbs
  expect_equal(st(assess(fit), "exponent_plausible"), "warning")
  expect_equal(st(assess(fit, n_range = c(0.1, 4)), "exponent_plausible"), "pass")
  tab <- FlodeRatingTable(table = data.table::data.table(lower_level = 0, upper_level = 3, C = 1, a = 0, n = 5))
  expect_equal(st(assess(tab), "exponent_plausible"), "warning")
})

test_that("zero_flow_stage warns when the zero-flow stage is far below the lowest gauging", {
  fit <- good_fit()
  limbs <- data.table::copy(fit@limbs); limbs[, a := -5]
  fit@limbs <- limbs
  expect_equal(st(assess(fit), "zero_flow_stage"), "warning")
  expect_equal(st(assess(good_fit()), "zero_flow_stage"), "pass")
})

test_that("the hydrometric invariants appear as hydraulic checks and can warn", {
  step <- FlodeRatingTable(table = data.table::data.table(
    lower_level = c(0.2, 1.5), upper_level = c(1.5, 3), C = c(2.5, 5.5), a = c(0, 0.1), n = c(1.5, 1.7)))
  a <- assess(step)
  expect_equal(st(a, "limb_continuity"), "warning")
  expect_equal(ck(a, "limb_continuity")$domain, "hydraulic")
})

# ---- numerical -------------------------------------------------------------------------------------------

test_that("a failed invariant is a failed numerical check, and fails the whole assessment", {
  bad <- FlodeRatingTable(table = data.table::data.table(lower_level = 0, upper_level = 3, C = 2, a = 0, n = 1.5))
  S7::prop(bad, "table", check = FALSE) <- data.table::data.table(lower_level = 0, upper_level = 3, C = -1, a = 0, n = 1.5)
  a <- assess(bad)
  expect_equal(st(a, "coefficients_finite"), "fail")
  expect_equal(ck(a, "coefficients_finite")$domain, "numerical")
  expect_equal(assessment_status(a), "fail")
})

test_that("convergence warns when the optimiser stopped at its limit", {
  set.seed(1)
  h <- seq(0.4, 3, by = 0.1)
  q <- 3.2 * h^1.6 * exp(rnorm(length(h), sd = 0.03))
  good <- assess(good_fit())              # built before the optimiser is limited
  testthat::local_mocked_bindings(.lm_control = function(maxiter) minpack.lm::nls.lm.control(maxiter = 2L))
  fit <- suppressWarnings(rate_optimise(q, h))
  a <- assess(fit)
  expect_equal(st(a, "convergence"), "warning")
  expect_match(ck(a, "convergence")$message, "maxiter")
  expect_equal(st(good, "convergence"), "pass")
})

# ---- data ------------------------------------------------------------------------------------------------

test_that("the data domain is validate_gaugings() on the rating's own evidence", {
  fit <- good_fit()
  direct <- assessment_checks(validate_gaugings(fit@gaugings, reference_time = ref_time))
  mine <- assessment_checks(assess(fit))[domain == "data"]
  expect_setequal(mine$check_id, direct$check_id)
  expect_equal(mine[order(check_id)]$status, direct[order(check_id)]$status)
})

test_that("a data problem in the evidence surfaces in the data domain, and a technical one fails", {
  fit <- good_fit()
  # Changed in place on this fit's own evidence, bypassing the class's checks,
  # to hand the assessment a state the class would not build.
  ev <- fit@gaugings
  data.table::set(ev, i = 1:2, j = "evidence_id", value = "a")
  a <- assess(fit)
  expect_equal(st(a, "evidence_id_unique"), "fail")
  expect_equal(ck(a, "evidence_id_unique")$domain, "data")
  expect_equal(assessment_status(a), "fail")
})

# ---- operational -----------------------------------------------------------------------------------------

test_that("operational limits must be stated, and how far they reach beyond the gauged range is judged", {
  unset <- fit_rating(clean_evidence(), quiet = TRUE)
  expect_equal(st(assess(unset), "operational_limits_stated"), "warning")
  expect_equal(st(assess(unset), "extrapolation_extent"), "not_assessed")
  expect_equal(st(assess(good_fit()), "operational_limits_stated"), "pass")
  expect_equal(st(assess(good_fit()), "extrapolation_extent"), "pass")
  wide <- set_operational_limits(unset, 0.1, 6, basis = "hopeful")
  expect_equal(st(assess(wide), "extrapolation_extent"), "warning")
  expect_match(ck(assess(wide), "extrapolation_extent")$message, "more than 20.0%")
  expect_equal(st(assess(wide, extrapolation_tol = 5), "extrapolation_extent"), "pass")
})

test_that("a rating changed since it was fitted is flagged, and its fit-only checks are not assessed", {
  set.seed(1)
  h <- seq(0.4, 3, by = 0.05)
  q <- 3.2 * h^1.6 * exp(rnorm(length(h), sd = 0.03))
  amended <- suppressWarnings(rate_optimise_constrained(q, h, control = 1.5))
  a <- assess(amended)
  expect_equal(st(a, "fit_unchanged"), "warning")
  expect_equal(st(a, "bounds_respected"), "not_assessed")
  expect_equal(st(a, "convergence"), "not_assessed")
  expect_equal(st(assess(good_fit()), "fit_unchanged"), "pass")
})

# ---- provenance ------------------------------------------------------------------------------------------

test_that("provenance warns for unrecorded sources, unstated assumptions, an unrecorded fit and a missing seed", {
  g <- data.frame(stage_m = clean_evidence()$stage_m, discharge_cms = clean_evidence()$discharge_cms)
  plain <- fit_rating(g, quiet = TRUE)                       # converted from a plain table
  a <- assess(plain)
  expect_equal(st(a, "evidence_sources"), "warning")
  expect_equal(st(a, "evidence_assumptions"), "warning")
  expect_match(ck(a, "evidence_assumptions")$message, "^Converted from a plain table")
  expect_equal(st(assess(good_fit()), "evidence_sources"), "pass")
  expect_equal(st(assess(good_fit()), "evidence_assumptions"), "pass")

  expert <- rate_optimise(g$discharge_cms, g$stage_m)
  expect_equal(st(assess(expert), "fit_recorded"), "warning")
  expect_equal(st(assess(good_fit()), "fit_recorded"), "pass")

  unseeded <- fit_rating(clean_evidence(), n_boot = 20, quiet = TRUE)
  expect_equal(st(assess(unseeded), "seed_recorded"), "warning")
  expect_equal(st(assess(good_fit()), "seed_recorded"), "pass")
  expect_match(ck(assess(good_fit()), "seed_recorded")$message, "seed \\(3\\)")
  expect_match(ck(assess(fit_rating(clean_evidence(), quiet = TRUE)), "seed_recorded")$message, "no seed is needed")
})

test_that("the tool version and schema version are reported", {
  expect_match(ck(assess(good_fit()), "tool_version")$message, "reach.rate [0-9.]+, schema version 2")
})

# ---- the class holds mixed severities, and printing shows the domains ----------------------------------------

test_that("FlodeAssessment accepts the six new domains and holds each check to its severity", {
  row <- function(domain, severity, status) data.table::data.table(
    check_id = paste(domain, severity, status), domain = domain, severity = severity, status = status,
    message = "m", affected_evidence = list(character(0)), affected_stage_min_m = NA_real_,
    affected_stage_max_m = NA_real_, recommendation = NA_character_)
  for (d in c("data", "numerical", "statistical", "hydraulic", "operational", "provenance")) {
    expect_silent(FlodeAssessment(checks = data.table::rbindlist(list(row(d, "error", "fail"), row(d, "warning", "warning")))))
    expect_error(FlodeAssessment(checks = row(d, "error", "warning")), "severity 'error' can pass or fail")
    expect_error(FlodeAssessment(checks = row(d, "warning", "fail")), "severity 'warning' can warn")
  }
  expect_error(FlodeAssessment(checks = row("data", "fatal", "pass")), "severity must be 'error' or 'warning'")
  expect_error(FlodeAssessment(checks = row("technical", "warning", "warning")), "severity must be 'error' for a technical")
  expect_error(FlodeAssessment(checks = row("sideways", "error", "pass")), "domain must be one of")
})

test_that("printing shows each domain's counts, and what did not pass", {
  out <- capture.output(print(assess(fit_rating(clean_evidence(), quiet = TRUE))))
  expect_match(paste(out, collapse = "\n"), "data:\\s+\\d+ pass")
  expect_match(paste(out, collapse = "\n"), "provenance:\\s+\\d+ pass")
  expect_match(paste(out, collapse = "\n"), "\\[warning\\] operational_limits_stated")
})

test_that("plotting an assessment of a rating works", {
  p <- plot(assess(good_fit()))
  expect_s3_class(p, "ggplot")
  expect_gt(length(unique(p$data$domain)), 5L)
  grDevices::pdf(NULL); on.exit(grDevices::dev.off())
  expect_no_error(print(p))
})
