# rating_uncertainty(): each source on its own, and what it refuses to claim.

unc_fit <- function(n = 24L, seed = 1L, extra = NULL) {
  set.seed(seed)
  h <- seq(0.4, 3, length.out = n)
  g <- data.frame(stage_m = h, discharge_cms = 3.2 * h^1.6 * exp(rnorm(n, sd = 0.03)))
  if (!is.null(extra)) g <- cbind(g, extra)
  fit_rating(g, quiet = TRUE)
}
unc_run <- function(fit, ...) {
  suppressWarnings(suppressMessages(rating_uncertainty(fit, stage = c(0.8, 1.5, 2.5), n_draws = 100, seed = 1, ...)))
}

test_that("a rating table, a non-rating and a thin rating are refused", {
  fit <- unc_fit()
  expect_error(rating_uncertainty(as_rating_table(fit)), "no gaugings to resample")
  expect_error(rating_uncertainty(data.frame(a = 1)), "must be a FlodeRating")
  thin <- unc_fit(n = 8L)
  expect_error(rating_uncertainty(thin), "at least 10")
})

test_that("bad arguments say what is wrong", {
  fit <- unc_fit()
  expect_error(rating_uncertainty(fit, n_draws = 50), "at least 100")
  expect_error(rating_uncertainty(fit, level = 1), "between 0 and 1")
  expect_error(rating_uncertainty(fit, gauging_uncertainty = 0), "above 0 and at most 0.5")
  expect_error(rating_uncertainty(fit, gauging_uncertainty = 0.9), "above 0 and at most 0.5")
  expect_error(rating_uncertainty(fit, seed = "a"), "seed")
  amended <- fit
  S7::prop(amended, "fit_origin", check = FALSE) <- "aligned"
  expect_error(rating_uncertainty(amended), "changed since it was fitted")
})

test_that("without a stated uncertainty the gauging source is not assessed, and is never zero", {
  u <- unc_run(unc_fit())
  s <- uncertainty_summary(u)
  expect_false(s[source == "gauging"]$assessed)
  expect_match(s[source == "gauging"]$reason, "does not supply one")
  expect_false("gauging" %in% uncertainty_bands(u)$source)
  expect_false(s[source == "combined"]$assessed)
  expect_true(s[source == "sampling"]$assessed)
  expect_output(print(u), "Not assessed")
  expect_output(print(u), "not a complete uncertainty budget")
})

test_that("the gauging source reads the evidence column, then the argument", {
  fit <- unc_fit(extra = data.frame(discharge_uncertainty = rep(0.05, 24)))
  expect_true("discharge_uncertainty" %in% names(fit@gaugings))
  u <- unc_run(fit)
  expect_equal(u@settings$uncertainty_source, "evidence column")
  expect_true(uncertainty_summary(u)[source == "gauging"]$assessed)

  partial <- unc_fit(extra = data.frame(discharge_uncertainty = c(rep(0.05, 12), rep(NA_real_, 12))))
  expect_false(uncertainty_summary(unc_run(partial))[source == "gauging"]$assessed)
  filled <- unc_run(partial, gauging_uncertainty = 0.05)
  expect_true(uncertainty_summary(filled)[source == "gauging"]$assessed)

  bad <- unc_fit(extra = data.frame(discharge_uncertainty = c(0.9, rep(0.05, 23))))
  expect_error(rating_uncertainty(bad, n_draws = 100), "Check gauging")
})

test_that("structure is a range, with no interval and no probability", {
  u <- unc_run(unc_fit(), sources = c("sampling", "structure"))
  b <- uncertainty_bands(u)
  st <- b[source == "structure"]
  expect_true(nrow(st) == 3L)
  expect_true(all(is.na(st$lower) & is.na(st$upper) & is.na(st$median)))
  expect_true(all(st$min <= st$base_cms + 1e-9 & st$max >= st$base_cms - 1e-9))
  expect_true(nrow(u@variants) >= 1L)
  expect_output(print(u), "a range, not an interval")
})

test_that("sources can be chosen, and the combination needs both intervals", {
  u <- unc_run(unc_fit(), sources = "sampling")
  expect_identical(sort(unique(uncertainty_bands(u)$source)), "sampling")
  expect_false(uncertainty_summary(u)[source == "combined"]$assessed)
  both <- unc_run(unc_fit(), gauging_uncertainty = 0.05, sources = c("sampling", "gauging"))
  expect_true("combined" %in% uncertainty_bands(both)$source)
})

test_that("shared gauging error widens the band far more than sampling alone", {
  u <- unc_run(unc_fit(), gauging_uncertainty = 0.05)
  s <- uncertainty_summary(u)
  expect_gt(s[source == "combined"]$median_half_width_pct, 3 * s[source == "sampling"]$median_half_width_pct)
  b <- uncertainty_bands(u)[source == "combined"]
  expect_true(all(b$lower <= b$median & b$median <= b$upper))
})

test_that("independent error is labelled as already in the sampling interval", {
  u <- unc_run(unc_fit(), gauging_uncertainty = 0.05, error_structure = "independent")
  expect_equal(u@settings$error_structure, "independent")
  expect_output(print(u), "already in the sampling interval")
})

test_that("a seed repeats the result and leaves the caller's random numbers alone", {
  fit <- unc_fit()
  set.seed(99); before <- runif(1)
  set.seed(99)
  a <- unc_run(fit, gauging_uncertainty = 0.05)
  after <- runif(1)
  expect_equal(before, after)
  b <- unc_run(fit, gauging_uncertainty = 0.05)
  expect_equal(uncertainty_bands(a), uncertainty_bands(b))
})

test_that("an interval built from mostly failed refits is withheld with a warning", {
  fit <- unc_fit()
  local_mocked_bindings(.sens_refit = function(...) "no refit", .package = "reach.rate")
  expect_warning(
    u <- rating_uncertainty(fit, stage = c(1, 2), n_draws = 100, sources = "sampling", seed = 1),
    "withheld"
  )
  s <- uncertainty_summary(u)
  expect_false(s[source == "sampling"]$assessed)
  expect_match(s[source == "sampling"]$reason, "biased towards easy data")
  expect_equal(unname(s[source == "sampling"]$draws_failed), 100L)
})

test_that("a segmented rating gets the intervals", {
  set.seed(3)
  h <- seq(0.3, 3.2, length.out = 30)
  q <- ifelse(h < 1.6, 3.2 * h^1.6, 3.2 * 1.6^1.6 * (h / 1.6)^2.9) * exp(rnorm(30, sd = 0.03))
  fit <- fit_rating(data.frame(stage_m = h, discharge_cms = q), controls = 1.6, model = "segmented", quiet = TRUE)
  u <- suppressWarnings(suppressMessages(rating_uncertainty(fit, stage = c(1, 2, 3), n_draws = 100,
                                                            gauging_uncertainty = 0.05, sources = c("sampling", "gauging"), seed = 1)))
  expect_true(uncertainty_summary(u)[source == "sampling"]$assessed)
})

test_that("it plots, and the accessors refuse other objects", {
  u <- unc_run(unc_fit(), gauging_uncertainty = 0.05)
  expect_s3_class(autoplot(u), "ggplot")
  expect_s3_class(plot(u), "ggplot")
  expect_error(uncertainty_bands(1), "FlodeUncertainty")
  expect_error(uncertainty_summary(1), "FlodeUncertainty")
})

test_that("existing fits and the bootstrap are unchanged by this module", {
  fit <- unc_fit()
  expect_false("discharge_uncertainty" %in% names(fit@gaugings))
  expect_identical(rating_schema_version(), 2L)
})
