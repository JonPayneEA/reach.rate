build_base_table <- function() {
  data.table::data.table(
    lower_level = c(0.20, 1.2), upper_level = c(1.2, 2.5),
    C = c(2.5, 2.410481), a = c(0, 0), n = c(1.5, 1.7)
  )
}

test_that("the new limb matches discharge and gradient at the junction", {
  ext <- extend_rating_low(build_base_table())
  tbl <- ext@table

  expect_true(S7::S7_inherits(ext, FlodeRatingTable))
  expect_equal(ext@status, "extended_low")
  expect_equal(nrow(tbl), 3L)
  expect_equal(tbl$linear_extension, c(TRUE, FALSE, FALSE))
  expect_equal(tbl$n[1], 1)

  h <- 0.20
  q_pow <- function(H) 2.5 * H^1.5
  q_lin <- function(H) tbl$C[1] * (H - tbl$a[1])
  expect_equal(q_lin(h), q_pow(h), tolerance = 1e-10)

  dq_pow <- 1.5 * 2.5 * h^0.5
  expect_equal(tbl$C[1], dq_pow, tolerance = 1e-10)

  # Contiguous end to end
  expect_true(all(abs(tbl$upper_level[-3] - tbl$lower_level[-1]) < 1e-8))
})

test_that("zero-flow stage has the closed form h - (h - a)/n", {
  ext <- extend_rating_low(build_base_table())
  expect_equal(ext@table$a[1], 0.20 - 0.20 / 1.5, tolerance = 1e-12)
  expect_equal(ext@table$lower_level[1], ext@table$a[1])
})

test_that("apply_rating uses the linear limb below the old bottom, including negative stage", {
  tbl <- build_base_table()
  ext <- extend_rating_low(tbl)
  stage <- data.table::data.table(stage = c(-0.5, 0.0, 0.1, 0.2, 0.6))

  before <- apply_rating(FlodeRatingTable(table = tbl), stage)
  after <- apply_rating(ext, stage)

  # Stages at or above the old bottom are unchanged
  expect_equal(after$discharge[4:5], before$discharge[4:5])
  # Below the zero-flow stage (0.0667) discharge is exactly zero
  expect_equal(after$discharge[1:2], c(0, 0))
  # Inside the linear limb, on the line and not flagged as extrapolated
  expect_equal(after$discharge[3], ext@table$C[1] * (0.1 - ext@table$a[1]), tolerance = 1e-12)
  expect_false(after$extrapolated[3])
  # n > 1 so the tangent lies below the power law
  expect_lt(after$discharge[3], 2.5 * 0.1^1.5)
})

test_that("apply_rating_inverse round-trips through the linear limb", {
  ext <- extend_rating_low(build_base_table())
  stage <- data.table::data.table(stage = c(0.1, 0.15, 0.5, 1.8))
  q <- apply_rating(ext, stage)
  inv <- apply_rating_inverse(ext, q[, .(discharge)])
  expect_equal(inv$stage, stage$stage, tolerance = 1e-9)
})

test_that("a negative datum on the lowest limb gives a sensible limb at negative stage", {
  tbl <- data.table::data.table(
    lower_level = -0.30, upper_level = 1.0,
    C = 3, a = -1.2, n = 1.4
  )
  ext <- extend_rating_low(tbl)
  expect_lt(ext@table$a[1], -0.30)
  out <- apply_rating(ext, data.table::data.table(stage = c(-0.5, -0.31)))
  expect_true(all(out$discharge > 0))
  expect_equal(out$discharge[2], 3 * (-0.30 - -1.2)^1.4 -
    ext@table$C[1] * 0.01, tolerance = 1e-9)
})

test_that("n = 1 reproduces the power law exactly", {
  tbl <- data.table::data.table(lower_level = 0.5, upper_level = 2, C = 4, a = 0.1, n = 1)
  ext <- extend_rating_low(tbl)
  expect_equal(ext@table$a[1], 0.1, tolerance = 1e-12)
  expect_equal(ext@table$C[1], 4, tolerance = 1e-12)
})

test_that("lower_stage is honoured and validated", {
  tbl <- build_base_table()
  ext <- extend_rating_low(tbl, lower_stage = 0.1)
  expect_equal(ext@table$lower_level[1], 0.1)
  expect_error(extend_rating_low(tbl, lower_stage = 0.2), "below the lowest limb")
  expect_error(extend_rating_low(tbl, lower_stage = 0.0), "reaches zero discharge")
  expect_error(extend_rating_low(tbl, lower_stage = c(0.1, 0.05)), "single finite number")
})

test_that("a lowest limb with lower_level at or below a is rejected", {
  tbl <- data.table::data.table(lower_level = 0.5, upper_level = 2, C = 4, a = 0.5, n = 1.5)
  expect_error(extend_rating_low(tbl), "at or below its a")
})

test_that("FlodeRating and FlodeRatingTable inputs keep an audit chain", {
  rt <- FlodeRatingTable(table = build_base_table())
  ext <- extend_rating_low(rt)
  expect_identical(ext@previous, rt)
  expect_null(extend_rating_low(build_base_table())@previous)
})

test_that("non-contiguous or malformed input errors clearly", {
  bad <- build_base_table()
  bad[2, lower_level := 1.5]
  expect_error(extend_rating_low(bad), "contiguous")
  expect_error(extend_rating_low(bad[, .(lower_level, upper_level, C, a)]), "missing column")
  expect_error(extend_rating_low("x"), "must be a")
})

test_that("extra columns on the input are tolerated", {
  tbl <- build_base_table()
  tbl[, source := "new"]
  ext <- extend_rating_low(tbl)
  expect_true(is.na(ext@table$source[1]))
  expect_equal(ext@table$source[2:3], c("new", "new"))
})
