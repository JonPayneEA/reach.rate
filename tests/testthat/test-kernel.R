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
