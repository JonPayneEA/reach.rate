build_table_fit <- function() {
  FlodeRatingTable(table = data.table::data.table(
    lower_level = c(0.30, 0.90, 1.70), upper_level = c(0.90, 1.70, 2.60),
    C = c(1.80000, 2.85549, 4.72355), a = c(0.10, 0.25, 0.55), n = c(1.60, 1.90, 1.45)
  ))
}

build_flode_rating <- function() {
  gaugings <- station_gaugings
  rate_optimise(gaugings$discharge_cms, gaugings$stage_m)
}

build_segmented_fit <- function() {
  set.seed(7)
  stage_m <- seq(0.3, 3.5, by = 0.03)
  q <- 4 * pmax(stage_m - 0.1, 0)^1.55 * (pmax(stage_m - 1.6, 0) + 1)^0.9 *
    (pmax(stage_m - 2.4, 0) + 1)^1.1 * exp(rnorm(length(stage_m), sd = 0.03))
  rate_optimise_segmented(q, stage_m, control = c(1.6, 2.4))
}

test_that("apply_rating accepts a FlodeRating directly and matches the table route", {
  fit <- build_flode_rating()
  stage_dt <- data.table::data.table(stage = c(0.8, 1.2, 2.0, 3.0))

  direct <- apply_rating(fit, stage_dt)
  via_table <- apply_rating(as_rating_table(fit), stage_dt)

  expect_equal(direct, via_table)
  expect_true(all(c("stage", "discharge", "extrapolated") %in% names(direct)))
})

test_that("a FlodeRating from rate_optimise_constrained works with stage_col", {
  # The call a user wrote against a constrained fit with a non-default
  # stage column name.
  gaugings <- station_gaugings
  fit_aligned <- rate_optimise_constrained(gaugings$discharge_cms, gaugings$stage_m)
  dt <- data.table::data.table(stage_n = c(0.9, 1.4, 2.0))

  out <- apply_rating(fit_aligned, dt, stage_col = "stage_n")
  expect_equal(names(out), c("stage_n", "discharge", "extrapolated"))
  expect_true(all(out$discharge > 0))
})

test_that("a numeric vector is accepted by all three methods", {
  stage <- c(0.5, 1.5, 2.2)

  for (fit in list(build_table_fit(), build_flode_rating(), build_segmented_fit())) {
    out <- apply_rating(fit, stage)
    expect_s3_class(out, "data.table")
    expect_equal(names(out), c("stage", "discharge", "extrapolated"))
    expect_equal(out$stage, stage)
    # Same answer as the equivalent one-column table
    expect_equal(out, apply_rating(fit, data.table::data.table(stage = stage)))
  }
})

test_that("with a vector, stage_col names the stage column of the result", {
  out <- apply_rating(build_table_fit(), c(0.5, 1.5), stage_col = "stage_n", out_col = "flow")
  expect_equal(names(out), c("stage_n", "flow", "extrapolated"))
})

test_that("a vector gives the same discharge as the hand calculation", {
  out <- apply_rating(build_table_fit(), c(0.5, 1.5))
  expect_equal(out$discharge, c(1.8 * (0.5 - 0.10)^1.6, 2.85549 * (1.5 - 0.25)^1.9))
})

test_that("an integer vector and a vector with NA behave", {
  fit <- build_table_fit()
  expect_equal(apply_rating(fit, 1L)$discharge, apply_rating(fit, 1)$discharge)

  out <- apply_rating(fit, c(1.0, NA, 2.0))
  expect_true(is.na(out$discharge[2]))
  expect_false(anyNA(out$discharge[c(1, 3)]))
})

test_that("unsupported stage_dt types are refused with a clear message", {
  fit <- build_table_fit()
  expect_error(apply_rating(fit, c("a", "b")), "numeric vector of stage values")
  expect_error(apply_rating(fit, matrix(c(1, 2), ncol = 1)), "numeric vector of stage values")
  expect_error(apply_rating(fit, list(stage = 1)), "numeric vector of stage values")
  expect_error(apply_rating(build_flode_rating(), "x"), "numeric vector of stage values")
})

test_that("a table without the stage column still errors on the default stage_col", {
  fit <- build_table_fit()
  expect_error(apply_rating(fit, data.table::data.table(stage_n = 1)), "stage_col must be a column")
})
