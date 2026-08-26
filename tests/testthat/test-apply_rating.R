build_two_limb_rating_table <- function() {
  FlodeRatingTable(table = data.table(
    lower_level = c(0.0, 1.2),
    upper_level = c(1.2, 3.0),
    C = c(2.5, 4.1),
    a = c(0.0, 0.0),
    n = c(1.50, 1.70)
  ))
}

test_that("apply_rating computes discharge correctly within a single limb", {
  rating_table <- build_two_limb_rating_table()
  rating_dt <- rating_table@table
  stage_dt <- data.table(stage = c(0.5, 1.0))

  out_dt <- apply_rating(rating_table, stage_dt)

  expect_true(is.data.table(out_dt))
  expect_equal(out_dt$discharge, rating_dt$C[1] * (stage_dt$stage - rating_dt$a[1])^rating_dt$n[1])
  expect_false(any(out_dt$extrapolated))
})

test_that("apply_rating picks the correct limb across a boundary", {
  rating_table <- build_two_limb_rating_table()
  rating_dt <- rating_table@table
  stage_dt <- data.table(stage = c(0.9, 1.5))

  out_dt <- apply_rating(rating_table, stage_dt)

  expect_equal(out_dt$discharge[1], rating_dt$C[1] * (0.9 - rating_dt$a[1])^rating_dt$n[1])
  expect_equal(out_dt$discharge[2], rating_dt$C[2] * (1.5 - rating_dt$a[2])^rating_dt$n[2])
})

test_that("apply_rating flags and extrapolates stage values outside every limb", {
  rating_table <- build_two_limb_rating_table()
  rating_dt <- rating_table@table
  stage_dt <- data.table(stage = c(-0.5, 5.0))

  out_dt <- apply_rating(rating_table, stage_dt)

  expect_true(all(out_dt$extrapolated))
  # Below-range: limb 1's own a is 0, so stage -0.5 is also at-or-below
  # the zero-flow datum -- apply_rating()'s datum clip (stage <= a gives
  # exactly 0) applies before the extrapolated equation would otherwise
  # go complex/NaN raising a negative depth to a fractional power n.
  expect_equal(out_dt$discharge[1], 0)
  # Above-range value extrapolated using limb 2's equation
  expect_equal(out_dt$discharge[2], rating_dt$C[2] * (5.0 - rating_dt$a[2])^rating_dt$n[2])
})

test_that("apply_rating preserves extra columns and respects stage_col/out_col", {
  rating_table <- build_two_limb_rating_table()
  stage_dt <- data.table(timestamp = 1:3, level = c(0.5, 1.5, 2.5))

  out_dt <- apply_rating(rating_table, stage_dt, stage_col = "level", out_col = "flow")

  expect_true(all(c("timestamp", "level", "flow", "extrapolated") %in% names(out_dt)))
  expect_equal(nrow(out_dt), 3L)
})

test_that("apply_rating returns zero discharge at or below the zero-flow datum", {
  rating_table <- FlodeRatingTable(table = data.table(
    lower_level = 0.0, upper_level = 2.0, C = 5, a = 1.0, n = 1.5
  ))
  stage_dt <- data.table(stage = c(0.5, 1.0, 1.5))

  out_dt <- apply_rating(rating_table, stage_dt)
  expect_equal(out_dt$discharge, c(0, 0, 5 * (1.5 - 1.0)^1.5))
})

test_that("apply_rating validates stage_dt and its stage column", {
  rating_table <- build_two_limb_rating_table()
  expect_error(apply_rating(rating_table, data.table(x = 1)), "stage_col")
  expect_error(apply_rating(rating_table, list(stage = 1)), "data.frame or data.table")
})

test_that("FlodeRatingTable's validator rejects malformed tables at construction", {
  # These checks lived inside apply_rating() before the S7 conversion;
  # they now live in the class validator, so a malformed table can never
  # exist as a FlodeRatingTable at all, let alone reach apply_rating().
  expect_error(FlodeRatingTable(table = data.table()), "missing required column")
  expect_error(
    FlodeRatingTable(table = data.table(lower_level = 0, upper_level = 1)),
    "missing required column"
  )
  expect_error(
    FlodeRatingTable(table = data.table(
      lower_level = numeric(0), upper_level = numeric(0),
      C = numeric(0), a = numeric(0), n = numeric(0)
    )),
    "at least one row"
  )
  expect_error(
    FlodeRatingTable(table = data.table(
      lower_level = c(0.0, 1.5), upper_level = c(1.2, 2.5), # gap: not contiguous
      C = c(2.5, 4.1), a = c(0, 0), n = c(1.5, 1.7)
    )),
    "contiguous"
  )
})

build_rating_boot_dt <- function(n_draw = 50L, C_mean = 3, C_sd = 0.05, seed = 1L) {
  set.seed(seed)
  data.table(
    limb = rep(1L, n_draw), draw = seq_len(n_draw),
    lower_level = 0.0, upper_level = 3.0,
    C = rnorm(n_draw, C_mean, C_sd), a = 0, n = 1.6
  )
}

test_that("apply_rating_interval returns a mean close to the point estimate", {
  rating_boot_dt <- build_rating_boot_dt()
  stage_dt <- data.table(stage = c(0.5, 1.5, 2.5))

  out_dt <- apply_rating_interval(stage_dt, rating_boot_dt)

  expect_true(is.data.table(out_dt))
  expect_true(all(c(
    "discharge_mean", "discharge_median", "discharge_gse",
    "discharge_lower", "discharge_upper", "extrapolated"
  ) %in% names(out_dt)))
  expected_mean <- 3 * stage_dt$stage^1.6
  expect_equal(out_dt$discharge_mean, expected_mean, tolerance = 0.05)
  expect_true(all(out_dt$discharge_lower <= out_dt$discharge_mean))
  expect_true(all(out_dt$discharge_upper >= out_dt$discharge_mean))
})

test_that("apply_rating_interval flags extrapolated stage values", {
  rating_boot_dt <- build_rating_boot_dt()
  stage_dt <- data.table(stage = c(-1, 5))

  out_dt <- apply_rating_interval(stage_dt, rating_boot_dt)
  expect_true(all(out_dt$extrapolated))
})

test_that("apply_rating_interval validates its inputs", {
  rating_boot_dt <- build_rating_boot_dt()
  expect_error(apply_rating_interval(data.table(x = 1), rating_boot_dt), "stage_col")
  expect_error(apply_rating_interval(data.table(stage = 1), data.table()), "at least one row")
  expect_error(apply_rating_interval(data.table(stage = 1), rating_boot_dt, conf_level = 1.5), "between 0 and 1")
  bad_boot_dt <- data.table(limb = 1, C = 3)
  expect_error(apply_rating_interval(data.table(stage = 1), bad_boot_dt), "missing column")
})

build_rating_history_dt <- function() {
  data.table(
    version = c("v1", "v2"),
    effective_from = as.POSIXct(c("2024-01-01", "2025-06-01"), tz = "UTC"),
    effective_to = as.POSIXct(c("2025-06-01", NA), tz = "UTC"),
    lower_level = c(0.0, 0.0), upper_level = c(3.0, 3.0),
    C = c(3.0, 3.4), a = c(0, 0), n = c(1.6, 1.6)
  )
}

test_that("apply_rating_versioned selects the correct version per timestamp", {
  rating_history_dt <- build_rating_history_dt()
  stage_dt <- data.table(
    datetime = as.POSIXct(c("2024-06-01", "2025-12-01"), tz = "UTC"),
    stage = c(1.5, 1.5)
  )

  out_dt <- apply_rating_versioned(stage_dt, rating_history_dt)

  expect_equal(out_dt$version, c("v1", "v2"))
  expect_equal(out_dt$discharge[1], 3.0 * 1.5^1.6, tolerance = 1e-8)
  expect_equal(out_dt$discharge[2], 3.4 * 1.5^1.6, tolerance = 1e-8)
})

test_that("apply_rating_versioned handles a timestamp before any version starts", {
  rating_history_dt <- build_rating_history_dt()
  stage_dt <- data.table(
    datetime = as.POSIXct("2020-01-01", tz = "UTC"),
    stage = 1.5
  )

  expect_warning(out_dt <- apply_rating_versioned(stage_dt, rating_history_dt), "fall outside")
  expect_true(is.na(out_dt$version))
  expect_true(is.na(out_dt$discharge))
})

test_that("apply_rating_versioned rejects overlapping version ranges", {
  bad_history_dt <- data.table(
    version = c("v1", "v2"),
    effective_from = as.POSIXct(c("2024-01-01", "2024-06-01"), tz = "UTC"),
    effective_to = as.POSIXct(c("2024-12-01", NA), tz = "UTC"), # v1 overlaps v2
    lower_level = c(0.0, 0.0), upper_level = c(3.0, 3.0),
    C = c(3.0, 3.4), a = c(0, 0), n = c(1.6, 1.6)
  )
  stage_dt <- data.table(datetime = as.POSIXct("2024-07-01", tz = "UTC"), stage = 1.5)
  expect_error(apply_rating_versioned(stage_dt, bad_history_dt), "overlapping")
})

test_that("apply_rating_versioned rejects an open-ended version that isn't the most recent", {
  bad_history_dt <- data.table(
    version = c("v1", "v2"),
    effective_from = as.POSIXct(c("2024-01-01", "2025-01-01"), tz = "UTC"),
    effective_to = as.POSIXct(c(NA, "2026-01-01"), tz = "UTC"), # v1 is NA but not last
    lower_level = c(0.0, 0.0), upper_level = c(3.0, 3.0),
    C = c(3.0, 3.4), a = c(0, 0), n = c(1.6, 1.6)
  )
  stage_dt <- data.table(datetime = as.POSIXct("2024-07-01", tz = "UTC"), stage = 1.5)
  expect_error(apply_rating_versioned(stage_dt, bad_history_dt), "most recent")
})

test_that("apply_rating_versioned validates its inputs", {
  rating_history_dt <- build_rating_history_dt()
  expect_error(apply_rating_versioned(data.table(x = 1), rating_history_dt), "stage_col")
  bad_history_dt <- data.table(version = "v1")
  expect_error(
    apply_rating_versioned(data.table(stage = 1, datetime = Sys.time()), bad_history_dt),
    "missing column"
  )
})
