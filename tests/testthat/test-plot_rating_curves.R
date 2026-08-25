build_fits <- function() {
  set.seed(1)
  stage_m <- seq(0.5, 3.5, by = 0.05)
  discharge_cms <- 5 * stage_m^1.6 + rnorm(length(stage_m), sd = 0.05)
  list(
    plain = rate_optimise(discharge_cms, stage_m, control = c(1.6, 2.5)),
    constrained = rate_optimise_constrained(discharge_cms, stage_m, control = c(1.6, 2.5))
  )
}

test_that("plot_rating_curves uses supplied names as legend labels", {
  fits <- build_fits()

  pdf(NULL)
  on.exit(dev.off())

  p <- plot_rating_curves(Independent = fits$plain, Constrained = fits$constrained)

  expect_s3_class(p, "ggplot")
  expect_equal(levels(p$data$rating), c("Independent", "Constrained"))
  expect_true(all(c("stage", "discharge", "rating") %in% names(p$data)))
})

test_that("plot_rating_curves auto-labels unnamed arguments in order", {
  fits <- build_fits()

  pdf(NULL)
  on.exit(dev.off())

  p <- plot_rating_curves(fits$plain, fits$constrained)
  expect_equal(levels(p$data$rating), c("Rating 1", "Rating 2"))
})

test_that("plot_rating_curves accepts a mix of FlodeRating, FlodeSegmentedRating, and FlodeRatingTable", {
  fits <- build_fits()
  rating_table <- as_rating_table(fits$plain)

  set.seed(7)
  stage_seg_m <- seq(0.3, 3.5, by = 0.03)
  q1 <- 4 * pmax(stage_seg_m - 0.1, 0)^1.55
  q2 <- (pmax(stage_seg_m - 1.6, 0) + 1)^0.9
  q3 <- (pmax(stage_seg_m - 2.4, 0) + 1)^1.1
  discharge_seg_cms <- q1 * q2 * q3 * exp(rnorm(length(stage_seg_m), sd = 0.03))
  fit_seg <- rate_optimise_segmented(discharge_seg_cms, stage_seg_m, control = c(1.6, 2.4))

  pdf(NULL)
  on.exit(dev.off())

  p <- plot_rating_curves(Independent = fits$plain, Segmented = fit_seg, Table = rating_table)

  expect_s3_class(p, "ggplot")
  expect_equal(levels(p$data$rating), c("Independent", "Segmented", "Table"))
  expect_equal(nrow(p$data[rating == "Segmented"]), 200L)
})

test_that("plot_rating_curves requires at least one rating", {
  expect_error(plot_rating_curves(), "at least one fitted rating")
})

test_that("plot_rating_curves rejects duplicate labels", {
  fits <- build_fits()
  expect_error(
    plot_rating_curves(Fit = fits$plain, Fit = fits$constrained),
    "labels must be unique"
  )
})

test_that("plot_rating_curves validates n_points", {
  fits <- build_fits()
  expect_error(plot_rating_curves(fits$plain, n_points = -1), "positive integer")
  expect_error(plot_rating_curves(fits$plain, n_points = c(10, 20)), "positive integer")
})

test_that("plot_rating_curves rejects an object that isn't a recognised rating class", {
  expect_error(
    plot_rating_curves(data.table::data.table(a = 1)),
    "FlodeRating, FlodeSegmentedRating, or FlodeRatingTable"
  )
})
