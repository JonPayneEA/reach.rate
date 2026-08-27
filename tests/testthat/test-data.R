test_that("station_gaugings loads with the expected shape", {
  expect_true(data.table::is.data.table(station_gaugings))
  expect_named(station_gaugings, c("gauging_datetime", "discharge_cms", "stage_m"))
  expect_s3_class(station_gaugings$gauging_datetime, "POSIXct")
  expect_type(station_gaugings$discharge_cms, "double")
  expect_type(station_gaugings$stage_m, "double")
  expect_gt(nrow(station_gaugings), 0)
  expect_false(anyNA(station_gaugings$gauging_datetime))
  expect_false(anyNA(station_gaugings$discharge_cms))
  expect_false(anyNA(station_gaugings$stage_m))
})

test_that("rate_optimise() fits station_gaugings without error", {
  dt <- station_gaugings[station_gaugings$stage_m > 0, ]
  fit <- expect_no_error(rate_optimise(dt$discharge_cms, dt$stage_m))
  expect_true(S7::S7_inherits(fit, FlodeRating))
  expect_equal(nrow(fit@limbs), 1L)
  expect_true(fit@limbs$r_squared > 0.5)
})
