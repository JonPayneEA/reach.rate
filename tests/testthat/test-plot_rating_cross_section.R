build_fit <- function() {
  set.seed(1)
  stage_m <- seq(0.3, 3, by = 0.05)
  discharge_cms <- 4 * stage_m^1.6 + rnorm(length(stage_m), sd = 0.05)
  rate_optimise(discharge_cms, stage_m)
}

build_xs <- function() {
  data.table::data.table(
    distance_m = c(-6, -3, 3, 6),
    elevation_m = c(2.4, 0, 0, 2.4)
  )
}

test_that("plot_rating_cross_section overlays gaugings for a FlodeRating", {
  fit <- build_fit()
  xs <- build_xs()

  pdf(NULL)
  on.exit(dev.off())

  p <- plot_rating_cross_section(fit, xs)

  expect_s3_class(p, "ggplot")
  layer_geoms <- vapply(p$layers, function(l) class(l$geom)[1], character(1))
  expect_true("GeomPoint" %in% layer_geoms)
})

test_that("plot_rating_cross_section has no gaugings layer for a FlodeRatingTable", {
  fit <- build_fit()
  tbl <- as_rating_table(fit)
  xs <- build_xs()

  pdf(NULL)
  on.exit(dev.off())

  p <- plot_rating_cross_section(tbl, xs)

  layer_geoms <- vapply(p$layers, function(l) class(l$geom)[1], character(1))
  expect_false("GeomPoint" %in% layer_geoms)
})

test_that("plot_rating_cross_section rescales distance onto the curve's discharge range", {
  fit <- build_fit()
  xs <- build_xs()

  pdf(NULL)
  on.exit(dev.off())

  p <- plot_rating_cross_section(fit, xs)

  curve_dt <- reach.rate:::.rating_curve_points(fit, 200L)
  xs_layer <- p$layers[[1]]$data
  expect_equal(min(xs_layer$discharge_scaled), min(curve_dt$discharge), tolerance = 1e-8)
  expect_equal(max(xs_layer$discharge_scaled), max(curve_dt$discharge), tolerance = 1e-8)
})

test_that("plot_rating_cross_section validates cross_section shape", {
  fit <- build_fit()

  expect_error(
    plot_rating_cross_section(fit, data.frame(x = 1:3, y = 1:3)),
    "missing column"
  )
  expect_error(
    plot_rating_cross_section(fit, data.frame(distance_m = 1, elevation_m = 1)),
    "at least 2 rows"
  )
  expect_error(
    plot_rating_cross_section(fit, data.frame(distance_m = c(5, 5, 5), elevation_m = c(1, 2, 3))),
    "all identical"
  )
})

test_that("plot_rating_cross_section rejects an unsupported fit class", {
  xs <- build_xs()
  expect_error(
    plot_rating_cross_section("not a fit", xs),
    "FlodeRating"
  )
})
