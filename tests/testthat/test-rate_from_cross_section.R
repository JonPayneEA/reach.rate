trapezoidal_xs <- function() {
  data.table(distance_m = c(-6, -3, 3, 6), elevation_m = c(2.4, 0, 0, 2.4))
}

test_that(".xs_area_perimeter matches a hand-computed trapezoid at full bank", {
  xs <- trapezoidal_xs()
  g <- .xs_area_perimeter(xs$distance_m, xs$elevation_m, 2.4)
  # 6 m flat bed * 2.4 m depth, plus two 3:2.4 side triangles
  expect_equal(unname(g["area"]), 6 * 2.4 + 2 * (0.5 * 3 * 2.4), tolerance = 1e-8)
  expect_equal(unname(g["perimeter"]), 6 + 2 * sqrt(3^2 + 2.4^2), tolerance = 1e-8)
})

test_that(".xs_area_perimeter clips a segment straddling the water surface", {
  xs <- trapezoidal_xs()
  g <- .xs_area_perimeter(xs$distance_m, xs$elevation_m, 1.2)
  # side slope reaches z = 1.2 halfway along each 3 m side segment
  expect_equal(unname(g["area"]), 6 * 1.2 + 2 * (0.5 * 1.5 * 1.2), tolerance = 1e-8)
  expect_equal(unname(g["perimeter"]), 6 + 2 * sqrt(1.5^2 + 1.2^2), tolerance = 1e-8)
})

test_that("rate_from_cross_section returns a valid FlodeRating with theoretical provenance", {
  xs <- trapezoidal_xs()
  fit <- rate_from_cross_section(xs, slope = 0.001, roughness = 0.035, n_points = 30)

  expect_s3_class(fit, "reach.rate::FlodeRating")
  expect_equal(fit@provenance$source, "cross_section_theoretical")
  expect_equal(fit@provenance$slope, 0.001)
  expect_equal(fit@provenance$roughness, 0.035)
  expect_true(all(fit@limbs$C > 0))
  expect_true(all(fit@limbs$n > 0))
  expect_true(all(fit@limbs$r_squared > 0.99))
})

test_that("rate_from_cross_section's fit reproduces Manning discharge at a known stage", {
  xs <- trapezoidal_xs()
  fit <- rate_from_cross_section(xs, slope = 0.001, roughness = 0.035, n_points = 60)

  g <- .xs_area_perimeter(xs$distance_m, xs$elevation_m, 2.0)
  q_manning <- (1 / 0.035) * g["area"] * (g["area"] / g["perimeter"])^(2 / 3) * sqrt(0.001)

  limb <- fit@limbs[1]
  q_fit <- limb$C * (2.0 - limb$a)^limb$n
  expect_equal(unname(q_fit), unname(q_manning), tolerance = 0.01 * unname(q_manning))
})

test_that("rate_from_cross_section composes with plot_rating_cross_section on its own geometry", {
  xs <- trapezoidal_xs()
  fit <- rate_from_cross_section(xs, slope = 0.001, roughness = 0.035, n_points = 30)
  p <- plot_rating_cross_section(fit, xs)
  expect_s3_class(p, "ggplot")
})

test_that("rate_from_cross_section validates its inputs", {
  xs <- trapezoidal_xs()

  expect_error(rate_from_cross_section(list(a = 1), slope = 0.001, roughness = 0.035), "data.frame")
  expect_error(
    rate_from_cross_section(data.frame(x = 1:3, y = 1:3), slope = 0.001, roughness = 0.035),
    "missing column"
  )
  expect_error(rate_from_cross_section(xs, slope = -1, roughness = 0.035), "slope")
  expect_error(rate_from_cross_section(xs, slope = 0.001, roughness = 0), "roughness")
  expect_error(
    rate_from_cross_section(xs, slope = 0.001, roughness = 0.035, stage_seq = 0),
    "lowest surveyed"
  )
  expect_error(
    rate_from_cross_section(xs, slope = 0.001, roughness = 0.035, stage_seq = 3),
    "highest surveyed"
  )
  expect_error(
    rate_from_cross_section(
      data.frame(distance_m = c(1, 1), elevation_m = c(0, 1)),
      slope = 0.001, roughness = 0.035
    ),
    "unique"
  )
  expect_error(
    rate_from_cross_section(
      data.frame(distance_m = c(0, 1), elevation_m = c(1, 1)),
      slope = 0.001, roughness = 0.035
    ),
    "identical"
  )
})

test_that("rate_from_cross_section respects custom column names", {
  xs <- data.table(x = c(-6, -3, 3, 6), z = c(2.4, 0, 0, 2.4))
  fit <- rate_from_cross_section(
    xs, slope = 0.001, roughness = 0.035,
    distance_col = "x", elevation_col = "z", n_points = 20
  )
  expect_s3_class(fit, "reach.rate::FlodeRating")
})
