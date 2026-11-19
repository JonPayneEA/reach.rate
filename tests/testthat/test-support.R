# Tranche B3: what a rating rests on, by stage.

# Gaugings from 0.5 to 2, modelled high-flow points from 2.2 to 3.4.
mixed_evidence <- function() {
  set.seed(2)
  h_obs <- seq(0.5, 2, length.out = 16)
  h_mod <- seq(2.2, 3.4, length.out = 5)
  h <- c(h_obs, h_mod)
  ev <- as_flode_evidence(data.frame(stage_m = h, discharge_cms = 3.2 * h^1.6 * exp(rnorm(length(h), sd = 0.02))))
  data.table::set(ev, j = "source_type", value = c(rep("gauging", 16), rep("modelled", 5)))
  FlodeEvidence(ev)
}

mixed_fit <- function(...) fit_rating(mixed_evidence(), quiet = TRUE, ...)
rng <- function(x, name) { r <- rating_support(x); c(r[range == name]$lower_stage_m, r[range == name]$upper_stage_m) }
cls <- function(x, stage) .support_class(x, stage)

# ---- the five ranges -----------------------------------------------------------------------------

test_that("rating_support gives five ranges, in a fixed order, with their evidence counts", {
  r <- rating_support(mixed_fit())
  expect_equal(r$range, c("observed", "modelled", "fitted", "operational", "numerical"))
  expect_equal(names(r), c("range", "lower_stage_m", "upper_stage_m", "n_evidence", "basis"))
  expect_equal(r[range == "observed"]$n_evidence, 16L)
  expect_equal(r[range == "modelled"]$n_evidence, 5L)
  expect_true(all(is.na(r[range %in% c("fitted", "operational", "numerical")]$n_evidence)))
  expect_true(all(nzchar(r$basis)))
})

test_that("observed comes from gaugings and modelled from every other source type, by hand", {
  fit <- mixed_fit()
  expect_equal(rng(fit, "observed"), c(0.5, 2))
  expect_equal(rng(fit, "modelled"), c(2.2, 3.4))
  expect_equal(rng(fit, "fitted"), c(0.5, 3.4))
  # Cross-section, structure and operational-rating points are not observations.
  ev <- mixed_evidence()
  data.table::set(ev, i = 17:21, j = "source_type", value = c("cross_section", "structure_equation", "operational_rating", "other", "modelled"))
  expect_equal(rng(fit_rating(ev, quiet = TRUE), "modelled"), c(2.2, 3.4))
  expect_equal(rating_support(fit_rating(ev, quiet = TRUE))[range == "modelled"]$n_evidence, 5L)
})

test_that("rows excluded from the fit do not count as evidence", {
  ev <- mixed_evidence()
  data.table::set(ev, i = 1:2, j = "included", value = FALSE)
  data.table::set(ev, i = 1:2, j = "exclusion_reason", value = "wading")
  expect_equal(rng(fit_rating(ev, quiet = TRUE), "observed")[1], ev$stage_m[3])
})

test_that("a rating with no modelled evidence has an NA modelled range and no count", {
  set.seed(1)
  h <- seq(0.4, 3, length.out = 15)
  fit <- fit_rating(data.frame(stage_m = h, discharge_cms = 3 * h^1.6 * exp(rnorm(15, sd = 0.02))), quiet = TRUE)
  m <- rating_support(fit)[range == "modelled"]
  expect_true(is.na(m$lower_stage_m) && is.na(m$upper_stage_m))
  expect_equal(m$n_evidence, 0L)
})

test_that("the operational range is NA until stated, then the stated range with its basis", {
  fit <- mixed_fit()
  op <- rating_support(fit)[range == "operational"]
  expect_true(is.na(op$lower_stage_m))
  expect_match(op$basis, "set_operational_limits")
  limited <- set_operational_limits(fit, 0.3, 3.6, basis = "control confirmed")
  op <- rating_support(limited)[range == "operational"]
  expect_equal(c(op$lower_stage_m, op$upper_stage_m), c(0.3, 3.6))
  expect_equal(op$basis, "control confirmed")
})

test_that("the numerical range ends where the top limb would overflow, by hand", {
  C <- 2; a <- 0.5; n <- 2
  up <- reach.rate:::.numerical_upper(C, a, n)
  expect_true(is.finite(C * (up - a)^n))
  expect_true(!is.finite(C * (up * 1.001 - a)^n))
  expect_true(is.na(reach.rate:::.numerical_upper(-1, 0, 1)))
  expect_true(is.na(reach.rate:::.numerical_upper(1, 0, NA)))
  tab <- FlodeRatingTable(table = data.table::data.table(lower_level = 0.6, upper_level = 3, C = 2, a = 0.5, n = 2))
  expect_equal(rating_support(tab)[range == "numerical"]$upper_stage_m, up)
  expect_equal(rating_support(tab)[range == "numerical"]$lower_stage_m, -Inf)
})

test_that("a table has the equation ranges only, and by = 'limb' still refuses it", {
  tab <- FlodeRatingTable(table = data.table::data.table(lower_level = c(0.2, 1.5), upper_level = c(1.5, 3),
                                                          C = c(2.5, 2.5 * 1.5^1.5 / 1.4^1.7), a = c(0, 0.1), n = c(1.5, 1.7)))
  r <- rating_support(tab)
  expect_equal(r[range == "fitted"]$lower_stage_m, 0.2)
  expect_equal(r[range == "fitted"]$upper_stage_m, 3)
  expect_true(is.na(r[range == "observed"]$lower_stage_m))
  expect_equal(r[range == "observed"]$n_evidence, 0L)
  expect_error(rating_support(tab, by = "limb"), "no gaugings to measure support against")
})

test_that("by = 'limb' is the earlier per-limb table, unchanged, and by is checked", {
  fit <- mixed_fit()
  limb <- rating_support(fit, by = "limb")
  expect_true(all(c("limb", "n_gaugings", "gauged_min_stage_m", "upper_unsupported_frac") %in% names(limb)))
  expect_error(rating_support(fit, by = "sideways"), "should be one of")
  expect_error(rating_support(1), "not a rating|must be a")
})

test_that("a segmented fit has the same five ranges, with no numerical range to give", {
  set.seed(4)
  h <- seq(0.3, 3.5, by = 0.03)
  q <- ifelse(h < 1.5, 3 * h^1.6, 3 * 1.5^1.6 * (h / 1.5)^2.1) * exp(rnorm(length(h), sd = 0.03))
  r <- rating_support(rate_optimise_segmented(q, h, control = 1.5))
  expect_equal(r$range, c("observed", "modelled", "fitted", "operational", "numerical"))
  expect_equal(r[range == "observed"]$lower_stage_m, min(h))
  expect_true(is.na(r[range == "numerical"]$upper_stage_m))
})

# ---- the support class of a stage -------------------------------------------------------------------

test_that("every support class appears where the ranges say it should", {
  fit <- mixed_fit()
  # observed 0.5-2; modelled 2.2-3.4; fitted 0.5-3.4
  expect_equal(cls(fit, c(0.5, 1, 2)), rep("interpolation_observed", 3))
  expect_equal(cls(fit, c(2.1, 3, 3.4)), rep("interpolation_mixed", 3))
  expect_equal(cls(fit, c(0.3, 3.5, 5)), rep("extrapolation", 3))
  # A fitted range wider than the evidence, as after extend_rating_low().
  wide <- fit
  limbs <- data.table::copy(wide@limbs); limbs[, lower_stage_m := 0.2]
  wide@limbs <- limbs
  expect_equal(cls(wide, c(0.3, 0.45)), rep("model_supported", 2))
  expect_equal(cls(wide, 0.1), "extrapolation")
  limited <- set_operational_limits(fit, 0.4, 3.6)
  expect_equal(cls(limited, c(0.3, 3.7)), rep("outside_operational_range", 2))
  expect_equal(cls(limited, c(1, 2.5)), c("interpolation_observed", "interpolation_mixed"))
})

test_that("outside the operational limits outranks every other class, and a missing stage has no class", {
  fit <- set_operational_limits(mixed_fit(), 1, 1.5)
  expect_equal(cls(fit, c(0.6, 1.2, 1.6, NA)), c("outside_operational_range", "interpolation_observed",
                                                 "outside_operational_range", NA))
})

test_that("a table holds equations only: within its range the stage is model supported, beyond it an extrapolation", {
  tab <- FlodeRatingTable(table = data.table::data.table(lower_level = 0.4, upper_level = 3, C = 2, a = 0.1, n = 1.6))
  expect_equal(cls(tab, c(0.3, 1, 3, 3.1)), c("extrapolation", "model_supported", "model_supported", "extrapolation"))
})

test_that("a plain fit with no evidence of any kind in range is an extrapolation, never silently supported", {
  set.seed(1)
  h <- seq(0.5, 2.5, by = 0.05)
  fit <- rate_optimise(5 * h^1.6 + rnorm(length(h), sd = 0.02), h)
  expect_equal(cls(fit, c(0.2, 1, 3)), c("extrapolation", "interpolation_observed", "extrapolation"))
})

# ---- apply_rating ------------------------------------------------------------------------------------------

test_that("apply_rating adds a support column for a fit, a table and a segmented fit", {
  fit <- mixed_fit(operational_limits = c(0.3, 3.6), operational_basis = "x")
  out <- apply_rating(fit, c(1, 2.5, 0.35, 3.55))
  expect_equal(out$support, c("interpolation_observed", "interpolation_mixed", "extrapolation", "extrapolation"))
  expect_true(all(c("extrapolated", "support") %in% names(out)))
  tab <- apply_rating(as_rating_table(fit), c(1, 5))
  expect_equal(tab$support, c("model_supported", "extrapolation"))
  expect_equal(apply_rating(fit, c(NA, 1))$support, c(NA, "interpolation_observed"))
})

test_that("a plain fit applied beyond its limits is flagged outside_operational_range, not refused", {
  set.seed(1)
  h <- seq(0.5, 2.5, by = 0.05)
  fit <- rate_optimise(5 * h^1.6 + rnorm(length(h), sd = 0.02), h)
  limited <- set_operational_limits(fit, 0.4, 2.6, basis = "b")
  expect_equal(apply_rating(limited, c(1, 3))$support, c("interpolation_observed", "outside_operational_range"))
})

test_that("a guided rating is still refused outside its limits, as before", {
  fit <- mixed_fit(operational_limits = c(0.3, 3.6), operational_basis = "x")
  expect_error(apply_rating(fit, 4), "outside this rating's operational limits")
})

test_that("a stage beyond the numerical range fails, and says why", {
  tab <- FlodeRatingTable(table = data.table::data.table(lower_level = 0.6, upper_level = 3, C = 2, a = 0.5, n = 2))
  expect_no_error(apply_rating(tab, c(1, 1e100)))
  expect_error(apply_rating(tab, c(1, 1e200)), "beyond the numerical range.*overflows.*unit or datum error")
  expect_error(apply_rating(tab, 1e200), "1 stage value \\(largest 1e\\+200\\)")
})

test_that("the extrapolated flag from before is unchanged beside the new classes", {
  fit <- mixed_fit(operational_limits = c(0.2, 4), operational_basis = "x")
  out <- apply_rating(fit, c(0.3, 1, 3.5))
  expect_equal(out$extrapolated, c(TRUE, FALSE, TRUE))
})

# ---- the segmented fit is gated like the others -----------------------------------------------------------------

test_that("a guided segmented rating extrapolates with a warning, and gets a support class", {
  set.seed(3)
  h <- round(seq(0.3, 3.4, length.out = 40), 3)
  q <- ifelse(h < 1.6, 3.2 * h^1.6, 3.2 * 1.6^1.6 * (h / 1.6)^2.1) * exp(rnorm(40, sd = 0.03))
  seg <- fit_rating(data.frame(stage_m = h, discharge_cms = q), controls = 1.6, model = "segmented", quiet = TRUE)
  expect_warning(out <- apply_rating(seg, c(1, 4)), "no operational limits")
  expect_equal(out$support, c("interpolation_observed", "extrapolation"))
  expect_equal(apply_rating(seg, c(1, 2))$support, rep("interpolation_observed", 2))
  wide <- set_operational_limits(seg, 0.2, 4, basis = "b")
  expect_equal(apply_rating(wide, c(0.25, 3.9))$support, rep("extrapolation", 2))
})

test_that("a segmented rating that fails an invariant is refused, as a limb-based one is", {
  set.seed(4)
  h <- seq(0.3, 3.5, by = 0.03)
  q <- ifelse(h < 1.5, 3 * h^1.6, 3 * 1.5^1.6 * (h / 1.5)^2.1) * exp(rnorm(length(h), sd = 0.03))
  seg <- rate_optimise_segmented(q, h, control = 1.5)
  expect_no_error(apply_rating(seg, 1))
  co <- data.table::copy(seg@coefficients); co[, C := NA_real_]
  S7::prop(seg, "coefficients", check = FALSE) <- co
  expect_error(apply_rating(seg, 1), "coefficients_finite")
})
