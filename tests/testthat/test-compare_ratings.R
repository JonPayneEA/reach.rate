test_that("compare_ratings produces a per-limb coefficient diff when limb counts match", {
  rating_old_dt <- data.table(
    lower_level = c(0.0, 1.2), upper_level = c(1.2, 3.0),
    C = c(2.5, 4.1), A = c(0, 0), B = c(1.5, 1.7)
  )
  rating_new_dt <- data.table(
    lower_level = c(0.0, 1.2), upper_level = c(1.2, 3.0),
    C = c(2.6, 4.0), A = c(0, 0), B = c(1.5, 1.7)
  )

  cmp <- compare_ratings(rating_old_dt, rating_new_dt)

  expect_true(is.data.table(cmp$coefficients))
  expect_equal(nrow(cmp$coefficients), 2L)
  expect_equal(cmp$coefficients$C_diff, c(0.1, -0.1), tolerance = 1e-8)
  expect_equal(cmp$coefficients$A_diff, c(0, 0))
  expect_equal(cmp$coefficients$B_diff, c(0, 0))
})

test_that("compare_ratings skips the coefficient diff when limb counts differ", {
  rating_old_dt <- data.table(
    lower_level = 0.0, upper_level = 3.0, C = 3, A = 0, B = 1.6
  )
  rating_new_dt <- data.table(
    lower_level = c(0.0, 1.5), upper_level = c(1.5, 3.0),
    C = c(3, 5), A = c(0, 0), B = c(1.6, 1.8)
  )

  cmp <- compare_ratings(rating_old_dt, rating_new_dt)

  expect_null(cmp$coefficients)
  expect_true(is.data.table(cmp$discharge))
})

test_that("compare_ratings computes discharge diffs identical to zero for identical ratings", {
  rating_dt <- data.table(
    lower_level = 0.0, upper_level = 3.0, C = 3, A = 0, B = 1.6
  )

  cmp <- compare_ratings(rating_dt, rating_dt)

  expect_true(all(abs(cmp$discharge$discharge_diff) < 1e-8))
  expect_true(all(is.na(cmp$discharge$discharge_pct_diff) | abs(cmp$discharge$discharge_pct_diff) < 1e-6))
})

test_that("compare_ratings computes a known discharge difference correctly", {
  rating_old_dt <- data.table(lower_level = 0.0, upper_level = 3.0, C = 3, A = 0, B = 1.6)
  rating_new_dt <- data.table(lower_level = 0.0, upper_level = 3.0, C = 6, A = 0, B = 1.6)

  cmp <- compare_ratings(rating_old_dt, rating_new_dt, step = 0.5)

  # C doubled with A and B unchanged -> discharge should exactly double
  expect_equal(cmp$discharge$discharge_new, cmp$discharge$discharge_old * 2, tolerance = 1e-8)
  expect_equal(cmp$discharge$discharge_pct_diff[cmp$discharge$stage > 0], rep(100, sum(cmp$discharge$stage > 0)), tolerance = 1e-6)
})

test_that("compare_ratings errors when stage ranges do not overlap", {
  rating_old_dt <- data.table(lower_level = 0.0, upper_level = 1.0, C = 3, A = 0, B = 1.6)
  rating_new_dt <- data.table(lower_level = 2.0, upper_level = 3.0, C = 3, A = 0, B = 1.6)

  expect_error(compare_ratings(rating_old_dt, rating_new_dt), "do not overlap")
})

test_that("compare_ratings validates its inputs", {
  rating_dt <- data.table(lower_level = 0.0, upper_level = 1.0, C = 3, A = 0, B = 1.6)
  expect_error(compare_ratings(list(), rating_dt), "data.frame, or data.table")
  expect_error(compare_ratings(rating_dt, rating_dt, step = -1), "positive number")
})

test_that("plot_rating_comparison returns a grob without error", {
  rating_old_dt <- data.table(
    lower_level = c(0.0, 1.2), upper_level = c(1.2, 3.0),
    C = c(2.5, 4.1), A = c(0, 0), B = c(1.5, 1.7)
  )
  rating_new_dt <- data.table(
    lower_level = c(0.0, 1.2), upper_level = c(1.2, 3.0),
    C = c(2.6, 4.0), A = c(0, 0), B = c(1.5, 1.7)
  )
  cmp <- compare_ratings(rating_old_dt, rating_new_dt)

  pdf(NULL)
  on.exit(dev.off())

  combined <- plot_rating_comparison(cmp)
  expect_true(inherits(combined, "gtable") || inherits(combined, "grob"))
})

test_that("plot_rating_comparison rejects a malformed cmp argument", {
  expect_error(plot_rating_comparison(list()), "discharge")
  expect_error(plot_rating_comparison(data.table(a = 1)), "discharge")
})
