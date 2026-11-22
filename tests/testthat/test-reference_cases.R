# The ten reference cases: synthetic stations with a known true rating.

ids <- names(reach.rate:::.reference_case_specs())

test_that("the catalogue lists ten cases, each saying what it tests and what it does not", {
  cs <- reference_cases()
  expect_equal(nrow(cs), 10L)
  expect_named(cs, c("id", "title", "purpose", "not_tested", "envelope", "designed_check"))
  expect_equal(cs$id, ids)
  expect_true(all(nzchar(cs$purpose)) && all(nzchar(cs$not_tested)) && all(nzchar(cs$title)))
  expect_true(all(cs$envelope > 0 & cs$envelope < 1))
  expect_equal(sum(!is.na(cs$designed_check)), 5L)
})

test_that("every reference case passes: inside its envelope, converged, valid, and the designed check raised", {
  res <- check_reference_cases()
  expect_equal(res$id, ids)
  for (i in seq_len(nrow(res))) {
    r <- res[i]
    expect_true(r$within_envelope, info = sprintf("%s: error %.3f against envelope %.3f", r$id, r$max_rel_error, r$envelope))
    expect_true(r$converged, info = r$id)
    expect_true(r$valid, info = r$id)
    expect_true(r$parameters_ok, info = r$id)
    expect_true(isTRUE(r$check_raised) || is.na(r$check_raised), info = r$id)
    expect_true(isTRUE(r$contrast_ok) || is.na(r$contrast_ok), info = r$id)
    expect_true(r$passed, info = r$id)
  }
})

test_that("each envelope leaves room: the error is at most half of it, so a small platform difference cannot tip a case", {
  res <- check_reference_cases()
  expect_true(all(res$max_rel_error <= 0.5 * res$envelope), info = paste(res$id[res$max_rel_error > 0.5 * res$envelope], collapse = ", "))
})

test_that("the designed checks are the ones the cases say, and each is a real assessment check", {
  cs <- reference_cases()
  fit <- fit_rating(reference_case("single_limb")$data, quiet = TRUE)
  known <- assessment_checks(assess_rating(fit, reference_time = as.POSIXct("2025-01-01", tz = "UTC")))$check_id
  v <- assessment_checks(validate_gaugings(reference_case("few_gaugings")$data))$check_id
  designed <- stats::na.omit(cs$designed_check)
  expect_true(all(designed %in% c(known, v, "limb_continuity", "residual_spread", "influential_gaugings", "few_gaugings", "upper_range_support")))
  expect_equal(designed[cs$id[!is.na(cs$designed_check)] == "heavy_noise"], "residual_spread")
})

test_that("case data are identical on every call, and building a case leaves the caller's seed alone", {
  a <- reference_case("two_limbs")$data
  b <- reference_case("two_limbs")$data
  expect_identical(a, b)
  set.seed(99); x <- stats::runif(1)
  set.seed(99); invisible(reference_case("heavy_noise")); invisible(check_reference_cases("few_gaugings")); y <- stats::runif(1)
  expect_identical(x, y)
})

test_that("each case has the shape and size it claims, and its truth is a positive function of stage", {
  n <- c(single_limb = 30, two_limbs = 50, heavy_noise = 40, sparse_top = 32, isolated_high = 29, rating_shift = 38,
         zero_flow_offset = 30, steep_exponent = 30, wide_exponent = 30, few_gaugings = 6)
  for (id in ids) {
    case <- reference_case(id)
    expect_equal(nrow(case$data), unname(n[id]), info = id)
    expect_true(all(c("stage_m", "discharge_cms") %in% names(case$data)), info = id)
    expect_true(is.function(case$truth), info = id)
    s <- seq(case$range[1L], case$range[2L], length.out = 20)
    expect_true(all(is.finite(case$truth(s)) & case$truth(s) > 0), info = id)
    expect_false(isTRUE(all.equal(case$data$discharge_cms, case$truth(case$data$stage_m), tolerance = 1e-12)), info = paste(id, "has scatter"))
  }
  expect_equal(reference_case("single_limb")$truth(1.1), 3.2)
  expect_equal(reference_case("isolated_high")$range, c(0.3, 2.0))
  expect_equal(reference_case("two_limbs")$fit_args$controls, 1.6)
  expect_true("observation_time" %in% names(reference_case("rating_shift")$data))
})

test_that("the channel-shift case really needs weighting: the flat fit is far worse than the weighted fit", {
  case <- reference_case("rating_shift")
  w <- do.call(fit_rating, c(list(case$data, quiet = TRUE), case$fit_args))
  flat <- fit_rating(case$data, quiet = TRUE)
  s <- seq(0.3, 3, length.out = 100)
  err <- function(f) max(abs(suppressWarnings(apply_rating(f, s)$discharge) / case$truth(s) - 1))
  expect_lt(err(w), 0.10)
  expect_gt(err(flat), 0.10)
})

test_that("the checker can fail: a tighter envelope, a missing check, a wrong parameter and a weak contrast each fail a case", {
  specs <- reach.rate:::.reference_case_specs()
  tweak <- function(id, ...) { s <- specs; s[[id]][names(list(...))] <- list(...); s }
  testthat::local_mocked_bindings(.reference_case_specs = function() tweak("single_limb", envelope = 1e-6))
  r <- check_reference_cases("single_limb")
  expect_false(r$within_envelope); expect_false(r$passed)

  testthat::local_mocked_bindings(.reference_case_specs = function() tweak("single_limb", designed_check = "bound_hits"))
  r <- check_reference_cases("single_limb")
  expect_false(r$check_raised); expect_false(r$passed)

  testthat::local_mocked_bindings(.reference_case_specs = function() tweak("steep_exponent", params = list(n = c(2.0, 0.05))))
  r <- check_reference_cases("steep_exponent")
  expect_false(r$parameters_ok); expect_false(r$passed)

  testthat::local_mocked_bindings(.reference_case_specs = function() tweak("rating_shift", contrast_ratio = 1000))
  r <- check_reference_cases("rating_shift")
  expect_false(r$contrast_ok); expect_false(r$passed)
})

test_that("a subset can be run, and bad ids and arguments are refused", {
  r <- check_reference_cases(c("wide_exponent", "single_limb"))
  expect_equal(r$id, c("wide_exponent", "single_limb"))
  expect_error(check_reference_cases("nonsense"), "ids must be NULL or some of")
  expect_error(check_reference_cases(character(0)), "ids must be")
  expect_error(check_reference_cases(NA_character_), "ids must be")
  expect_error(reference_case("nonsense"), "id must be one of")
  expect_error(reference_case(1), "id must be one of")
  expect_error(reference_case(c("single_limb", "two_limbs")), "id must be one of")
})

test_that("running the cases changes nothing it should not: no lifecycle moves and no random state is left set", {
  had <- exists(".Random.seed", envir = globalenv(), inherits = FALSE)
  invisible(check_reference_cases("sparse_top"))
  expect_equal(exists(".Random.seed", envir = globalenv(), inherits = FALSE), had)
  fit <- fit_rating(reference_case("single_limb")$data, quiet = TRUE)
  expect_equal(fit@lifecycle, "draft")
})
