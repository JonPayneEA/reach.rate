# The C kernel (src/reach_core.c) against the pure-R arithmetic it replaced
# (tests/testthat/helper-reference-rating.R).

random_rating <- function(n_limbs, continuous = TRUE) {
  edges <- cumsum(c(runif(1, 0, 1), runif(n_limbs, 0.1, 1)))
  lower <- edges[-length(edges)]
  upper <- edges[-1]
  a <- lower - runif(n_limbs, 0.05, 0.9)          # offset below each limb's lower edge
  n <- runif(n_limbs, 0.4, 3)
  n[sample(n_limbs, 1L)] <- 2                      # R computes x^2 as x * x
  C <- runif(n_limbs, 0.5, 5)
  if (continuous && n_limbs > 1L) {
    for (i in 2:n_limbs) {
      q_prev <- C[i - 1L] * (lower[i] - a[i - 1L])^n[i - 1L]
      C[i] <- q_prev / (lower[i] - a[i])^n[i]
    }
  }
  data.table::data.table(lower_level = lower, upper_level = upper, C = C, a = a, n = n)
}

stage_probe <- function(rating, k = 300) {
  lo <- rating$lower_level[1]; hi <- rating$upper_level[nrow(rating)]
  c(
    runif(k, lo - 0.7, hi + 0.7),
    rating$lower_level, rating$upper_level, rating$a,        # every edge and offset exactly
    rating$a + 1e-12, rating$upper_level + 1e-12,
    NA_real_, NaN, Inf, -Inf, 0
  )
}

test_that("forward: discharge, limb and extrapolation flag match the R reference on random ratings", {
  set.seed(101)
  for (i in 1:60) {
    rating <- random_rating(sample(1:8, 1L), continuous = i %% 2 == 0)
    stage <- stage_probe(rating)
    ref <- reference_forward(rating, stage)
    got <- .kernel_forward(rating, stage)

    expect_equal(got$discharge, ref$discharge, tolerance = 1e-14)
    expect_identical(is.na(got$discharge), is.na(ref$discharge))
    ok <- !is.na(stage)
    expect_identical(got$limb[ok], ref$limb[ok])
    expect_identical(got$extrapolated[ok], ref$extrapolated[ok])
    expect_true(all(is.na(got$limb[!ok])) && all(is.na(got$extrapolated[!ok])))
  }
})

test_that("forward: boundaries follow the documented convention", {
  rating <- data.table::data.table(lower_level = c(0.5, 1, 2), upper_level = c(1, 2, 3),
                                   C = 2, a = 0, n = 1.5)
  got <- .kernel_forward(rating, c(0.4, 0.5, 1, 2, 3, 3.1))
  expect_identical(got$limb, c(1L, 1L, 2L, 3L, 3L, 3L))
  expect_identical(got$extrapolated, c(TRUE, FALSE, FALSE, FALSE, FALSE, TRUE))
})

test_that("forward: missing values keep R's NA and NaN apart", {
  rating <- random_rating(3)
  got <- .kernel_forward(rating, c(1, NA, NaN, Inf, -Inf))
  expect_true(is.na(got$discharge[2]) && !is.nan(got$discharge[2]))
  expect_true(is.nan(got$discharge[3]))
  expect_identical(got$discharge[4], Inf)
  expect_identical(got$discharge[5], 0)
  expect_identical(got$limb[2:3], c(NA_integer_, NA_integer_))
})

test_that("forward: stage at or below the offset is exactly zero, including negative stage", {
  rating <- data.table::data.table(lower_level = -0.3, upper_level = 1, C = 3, a = -1.2, n = 1.4)
  got <- .kernel_forward(rating, c(-5, -1.2, -1.19, -0.3))
  expect_identical(got$discharge[1:2], c(0, 0))
  expect_gt(got$discharge[3], 0)
  expect_equal(got$discharge[4], 3 * (-0.3 + 1.2)^1.4)
})

test_that("forward: empty and long inputs", {
  rating <- random_rating(4)
  expect_length(.kernel_forward(rating, numeric(0))$discharge, 0L)
  big <- runif(2e5, rating$lower_level[1] - 1, rating$upper_level[4] + 1)
  expect_equal(.kernel_forward(rating, big)$discharge, reference_forward(rating, big)$discharge, tolerance = 1e-14)
})

test_that("inverse: matches the R reference, and inverts the forward on a continuous rating", {
  set.seed(102)
  for (i in 1:60) {
    rating <- random_rating(sample(1:8, 1L), continuous = TRUE)
    q_hi <- rating$C[nrow(rating)] * (rating$upper_level[nrow(rating)] - rating$a[nrow(rating)])^rating$n[nrow(rating)]
    discharge <- c(runif(300, 0, q_hi * 1.3), -1, 0, NA_real_, NaN, Inf)
    ref <- reference_inverse(rating, discharge)
    got <- .kernel_inverse(rating, discharge)

    expect_equal(got$stage, ref$stage, tolerance = 1e-12)
    expect_identical(is.na(got$stage), is.na(ref$stage))
    expect_identical(got$extrapolated, ref$extrapolated)

    inside <- seq_len(300)
    inside <- inside[!got$extrapolated[inside] %in% TRUE]
    again <- .kernel_forward(rating, got$stage[inside])$discharge
    expect_equal(again, discharge[inside], tolerance = 1e-9)
  }
})

test_that("inverse: refuses a rating that is not single valued", {
  falling <- data.table::data.table(lower_level = c(0, 1), upper_level = c(1, 2), C = c(5, 1), a = 0, n = 1)
  expect_error(.kernel_inverse(falling, 1), "does not increase")
  negative <- data.table::data.table(lower_level = 0, upper_level = 1, C = -1, a = 0, n = 1)
  expect_error(.kernel_inverse(negative, 1), "not positive")
})

test_that("junctions: match the R reference, including a deliberate gap and a NaN", {
  set.seed(103)
  for (i in 1:30) {
    rating <- random_rating(sample(2:8, 1L), continuous = i %% 2 == 0)
    ref <- reference_junctions(rating)
    got <- .kernel_junctions(rating)
    expect_equal(got$below, ref$below, tolerance = 1e-14)
    expect_equal(got$above, ref$above, tolerance = 1e-14)
  }
  # A limb whose offset lies above the junction gives NaN, as the R arithmetic did
  odd <- data.table::data.table(lower_level = c(0, 1), upper_level = c(1, 2), C = 2, a = c(0, 1.5), n = 1.5)
  expect_true(is.nan(.kernel_junctions(odd)$above))
  expect_length(.kernel_junctions(random_rating(1))$below, 0L)
})

test_that("tangent: matches the R arithmetic and is tangent to the curve", {
  set.seed(104)
  for (i in 1:50) {
    C <- runif(1, 0.5, 5); a <- runif(1, -1, 0.5); n <- runif(1, 0.4, 3); h <- a + runif(1, 0.05, 2)
    expect_equal(.kernel_tangent(C, a, n, h), reference_tangent(C, a, n, h), tolerance = 1e-14)
    t <- .kernel_tangent(C, a, n, h)
    expect_equal(t[1] * (h - t[2]), C * (h - a)^n, tolerance = 1e-12)
  }
  expect_error(.kernel_tangent(2, 1, 1.5, 1), "not positive|not finite")
  expect_error(.kernel_tangent(-2, 0, 1.5, 1), "not positive|not finite")
})

test_that("a malformed rating is refused with a message that says what is wrong", {
  gap <- data.table::data.table(lower_level = c(0, 1.5), upper_level = c(1, 2), C = 2, a = 0, n = 1.5)
  expect_error(.kernel_forward(gap, 1), "contiguous")
  flat <- data.table::data.table(lower_level = 1, upper_level = 1, C = 2, a = 0, n = 1.5)
  expect_error(.kernel_forward(flat, 1), "upper_level above lower_level")
  bad <- data.table::data.table(lower_level = 0, upper_level = 1, C = NA_real_, a = 0, n = 1.5)
  expect_error(.kernel_forward(bad, 1), "missing or not finite")
  many <- data.table::data.table(lower_level = 0:256, upper_level = 1:257, C = 1, a = 0, n = 1)
  expect_error(.kernel_forward(many, 1), "more than 256")
  expect_error(.kernel_forward(data.table::data.table(lower_level = numeric(0), upper_level = numeric(0),
                                                       C = numeric(0), a = numeric(0), n = numeric(0)), 1),
               "no limbs")
})

test_that("apply_rating and apply_rating_inverse still agree with the reference end to end", {
  set.seed(105)
  rating <- random_rating(5, continuous = TRUE)
  stage <- data.table::data.table(stage = stage_probe(rating), label = "x")
  out <- suppressMessages(apply_rating(FlodeRatingTable(table = rating), stage))
  ref <- reference_forward(rating, stage$stage)
  expect_equal(out$discharge, ref$discharge, tolerance = 1e-14)
  expect_identical(out$extrapolated, ref$extrapolated)
  expect_identical(out$label, rep("x", nrow(stage)))

  q <- out$discharge[!is.na(out$discharge) & out$discharge > 0 & is.finite(out$discharge) & !out$extrapolated]
  back <- suppressMessages(apply_rating_inverse(FlodeRatingTable(table = rating), data.table::data.table(discharge = q)))
  expect_equal(back$stage, reference_inverse(rating, q)$stage, tolerance = 1e-12)
})

test_that("the kernel reports its ABI version", {
  expect_identical(.kernel_abi_version(), 1L)
})

# ---- limb crossing ---------------------------------------------------------

test_that("crossing: agrees with the uniroot() it replaced, and the curves meet at the root", {
  set.seed(201)
  found <- 0L
  for (i in 1:300) {
    C1 <- runif(1, 0.3, 5); a1 <- runif(1, -1, 0.5); n1 <- runif(1, 0.5, 4)
    C2 <- runif(1, 0.3, 5); a2 <- runif(1, -1, 0.5); n2 <- runif(1, 0.5, 4)
    lo <- runif(1, 0.6, 2); hi <- lo + runif(1, 0.5, 5)
    ref <- reference_intersection(C1, a1, n1, C2, a2, n2, lo, hi)
    got <- .kernel_crossing(C1, a1, n1, C2, a2, n2, lo, hi)

    expect_identical(is.na(got), is.na(ref))
    if (!is.na(got)) {
      found <- found + 1L
      expect_equal(got, ref, tolerance = 1e-7)
      f <- C1 * (got - a1)^n1 - C2 * (got - a2)^n2
      expect_lt(abs(f), 1e-6 * max(1, abs(C1 * (got - a1)^n1)))
    }
  }
  expect_gt(found, 50L)   # the draw really did produce crossings, not just refusals
})

test_that("crossing: ends, no crossing, unevaluable curves and bad input", {
  # 2 H = H^2 meets at H = 2
  expect_equal(.kernel_crossing(2, 0, 1, 1, 0, 2, 1, 3), 2, tolerance = 1e-8)
  expect_identical(.kernel_crossing(2, 0, 1, 1, 0, 2, 2, 3), 2)     # the root is the lower end
  expect_identical(.kernel_crossing(2, 0, 1, 1, 0, 2, 1, 2), 2)     # the root is the upper end
  expect_true(is.na(.kernel_crossing(2, 0, 1, 1, 0, 2, 2.5, 3)))    # same order throughout
  expect_true(is.na(.kernel_crossing(2, 0, 1.5, 1, 5, 1.5, 1, 3)))  # (H - 5)^1.5 is NaN
  expect_true(is.na(.kernel_crossing(2, 0, 1, 1, 0, 2, 3, 1)))      # lo not below hi
  expect_true(is.na(.kernel_crossing(NA, 0, 1, 1, 0, 2, 1, 3)))
  expect_true(is.na(.kernel_crossing(2, 0, 1, 1, 0, 2, 1, 3, tol = 0)))
})

test_that("crossing: graft_rating and align_limb_boundaries still find the same joins", {
  limbs <- data.table::data.table(lower_level = c(0, 1.5), upper_level = c(1.5, 3.41),
                                  C = c(2.5, 2.831), a = c(0, -0.886), n = c(1.5, 1.935))
  existing <- data.table::data.table(lower_level = 3.41, upper_level = 6, C = 0.3128, a = 0, n = 4.095)
  joined <- graft_rating(limbs, existing)@table
  expected <- reference_intersection(2.831, -0.886, 1.935, 0.3128, 0, 4.095, 3.41, 6)
  expect_equal(joined$upper_level[2], expected, tolerance = 1e-7)
})

# ---- cross-section geometry and Manning -------------------------------------

random_section <- function(n_points) {
  x <- cumsum(c(0, runif(n_points - 1L, 0.2, 3)))
  z <- 0.05 * (x - mean(x))^2 + runif(n_points, 0, 0.4)
  list(distance = x, elevation = z)
}

test_that("cross-section: area and perimeter match the R reference on random sections", {
  set.seed(202)
  for (i in 1:60) {
    s <- random_section(sample(3:60, 1L))
    stages <- c(
      seq(min(s$elevation) - 0.5, max(s$elevation) + 0.5, length.out = 120),
      s$elevation,                              # exactly on every survey point
      s$elevation + 1e-9, s$elevation - 1e-9,
      NaN
    )
    got <- .kernel_xs(s$distance, s$elevation, stages)
    ref <- vapply(stages, function(h) {
      if (is.nan(h)) c(area = NaN, perimeter = NaN) else reference_xs_area_perimeter(s$distance, s$elevation, h)
    }, numeric(2))
    expect_equal(got$area, unname(ref["area", ]), tolerance = 1e-12)
    expect_equal(got$perimeter, unname(ref["perimeter", ]), tolerance = 1e-12)
  }
})

test_that("cross-section: hand-computed trapezoid, bank full, above the banks and below the bed", {
  x <- c(0, 1, 9, 10); z <- c(3, 0, 0, 3)
  g <- .kernel_xs(x, z, c(-1, 0, 2, 3, 5))
  expect_equal(g$area, c(0, 0, 2 * (8 + 2 / 3), 27, 47))
  expect_equal(g$perimeter, c(0, 0, 8 + 2 * sqrt(4 + 4 / 9), 8 + 2 * sqrt(10), 8 + 2 * sqrt(10)))
})

test_that("cross-section: .xs_area_perimeter keeps its named-vector form", {
  g <- .xs_area_perimeter(c(0, 1, 9, 10), c(3, 0, 0, 3), 2)
  expect_named(g, c("area", "perimeter"))
  expect_equal(g[["area"]], 2 * (8 + 2 / 3))
})

test_that("cross-section: a malformed survey is refused with a message that says what is wrong", {
  expect_error(.kernel_xs(c(0, 1, 1), c(1, 0, 1), 0.5), "strictly increasing")
  expect_error(.kernel_xs(c(0, 2, 1), c(1, 0, 1), 0.5), "strictly increasing")
  expect_error(.kernel_xs(c(0, 1, 2), c(1, NA, 1), 0.5), "must be finite")
  expect_error(.kernel_xs(0, 1, 0.5), "at least 2 points")
  expect_error(.kernel_xs(c(0, 1), c(1, 0, 1), 0.5), "same length")
})

test_that("manning: matches the R reference, including zero perimeter and NaN", {
  set.seed(203)
  area <- c(runif(100, 0.1, 80), 0, 5, NaN)
  perimeter <- c(runif(100, 1, 40), 0, 0, 3)
  for (i in 1:20) {
    n <- runif(1, 0.01, 0.1); s <- runif(1, 1e-4, 0.02)
    ref <- suppressWarnings(reference_manning(area, perimeter, n, s))
    got <- .kernel_manning(area, perimeter, n, s)
    expect_equal(got, ref, tolerance = 1e-12)
    expect_identical(is.nan(got), is.nan(ref))
  }
  expect_error(.kernel_manning(1, 1, 0, 0.001), "must be positive")
  expect_error(.kernel_manning(1, 1, 0.03, -1), "must be positive")
  expect_error(.kernel_manning(c(1, 2), 1, 0.03, 0.001), "same length")
  expect_identical(.kernel_manning(10, 8, 0.03, 0), 0)
})

test_that("rate_from_cross_section: its synthetic points match the R reference end to end", {
  set.seed(204)
  s <- random_section(25)
  xs <- data.table::data.table(distance_m = s$distance, elevation_m = s$elevation)
  stage_seq <- seq(min(s$elevation) + 0.05, max(s$elevation), length.out = 40)
  fit <- suppressWarnings(suppressMessages(
    rate_from_cross_section(xs, slope = 0.002, roughness = 0.035, stage_seq = stage_seq)
  ))

  ref_geom <- vapply(stage_seq, function(h) reference_xs_area_perimeter(s$distance, s$elevation, h), numeric(2))
  ref_q <- reference_manning(ref_geom["area", ], ref_geom["perimeter", ], 0.035, 0.002)
  keep <- ref_q > 0
  g <- fit@gaugings
  expect_equal(g$stage_m, stage_seq[keep])
  expect_equal(g$discharge_cms, ref_q[keep], tolerance = 1e-12)
})
