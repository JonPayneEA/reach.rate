# demo_cross_section_rating() used to be a self-contained script
# (cross_section_rating_dual_plot.R) tested by sourcing it end to end and
# inspecting the objects it left in an environment. As a package function
# it's tested the ordinary way: call it and inspect what it returns.

test_that("demo_cross_section_rating runs cleanly and returns a combined grob", {
  pdf(NULL)
  on.exit(dev.off())

  result <- demo_cross_section_rating(plot = TRUE)

  expect_true(is.data.table(result$cross_section))
  expect_true(all(c("distance_m", "elevation_maod") %in% names(result$cross_section)))
  expect_true(is.data.table(result$rating_curve))
  expect_true(all(result$rating_curve$discharge_cms >= 0))

  expect_s3_class(result$p_xs, "ggplot")
  expect_s3_class(result$p_rc, "ggplot")
  expect_true(inherits(result$combined, "gtable") || inherits(result$combined, "grob"))
})

test_that("demo_cross_section_rating(plot = FALSE) does not require a graphics device", {
  result <- demo_cross_section_rating(plot = FALSE)
  expect_true(inherits(result$combined, "gtable") || inherits(result$combined, "grob"))
})
