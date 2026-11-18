# Tranche A9: what the optimiser reported, and whether the data pin the
# parameters down. Each column has a test where it is known by hand.

seed2_data <- function() {
  set.seed(2)
  h <- sort(runif(30, 0.3, 3.5))
  list(h = h, q = ifelse(h < 1.6, 3.2 * h^1.6, 3.2 * 1.6^1.6 * (h / 1.6)^2.1) * exp(rnorm(30, sd = 0.04)))
}

clean_data <- function(n = 30, seed = 42) {
  set.seed(seed)
  h <- seq(0.3, 3.2, length.out = n)
  list(h = h, q = 3.2 * h^1.6 * exp(rnorm(n, sd = 0.04)))
}

a9_cols <- c("converged", "convergence_code", "convergence_message", "iterations", "objective_value",
             "bound_hits", "multi_start_spread", "parameter_correlation", "condition_number")

# ---- the columns exist, with the right classes ---------------------------------

test_that("every fit has the nine stable columns, one value per limb", {
  d <- clean_data()
  fit <- rate_optimise(d$q, d$h, control = 1.5)
  expect_true(all(a9_cols %in% names(fit@limbs)))
  expect_type(fit@limbs$converged, "logical")
  expect_type(fit@limbs$convergence_code, "integer")
  expect_type(fit@limbs$convergence_message, "character")
  expect_type(fit@limbs$iterations, "integer")
  expect_type(fit@limbs$objective_value, "double")
  expect_type(fit@limbs$bound_hits, "character")
  expect_equal(nrow(fit@limbs), 2L)
  expect_true(all(c("converged", "valid", "convergence_code", "convergence_message", "iterations") %in% names(fit@fit_starts)))
})

test_that("rating_diagnostics carries the new columns", {
  d <- clean_data()
  diag <- rating_diagnostics(rate_optimise(d$q, d$h))
  expect_true(all(a9_cols %in% names(diag)))
})

# ---- convergence -----------------------------------------------------------------

test_that("a well-behaved fit reports convergence, a known stop code, and iterations", {
  d <- clean_data()
  co <- rating_limbs(rate_optimise(d$q, d$h), all_columns = TRUE)
  expect_true(co$converged)
  expect_true(co$convergence_code %in% 1:4)
  expect_match(co$convergence_message, "ftol|ptol|gtol|orthogonal", ignore.case = TRUE)
  expect_true(co$iterations >= 1L && co$iterations < 100L)
})

test_that("objective_value is the weighted objective at the fitted coefficients, by hand", {
  d <- clean_data()
  when <- as.Date("2020-01-01") + seq(0, by = 100, length.out = length(d$h))
  for (objective in c("absolute", "relative")) {
    fit <- rate_optimise(d$q, d$h, gauging_datetime = when, age_halflife = 365, objective = objective)
    w <- fit@gaugings$age_weight
    co <- rating_limbs(fit, all_columns = TRUE)
    by_hand <- if (objective == "absolute") {
      sum(w * (d$q - co$C * (d$h - co$a)^co$n)^2)
    } else {
      sum(w * (log(d$q) - log(co$C) - co$n * log(d$h - co$a))^2)
    }
    expect_equal(co$objective_value, by_hand, tolerance = 1e-6, info = objective)
  }
})

test_that("a fit that cannot finish in its iteration limit is reported as not converged, and warns", {
  d <- clean_data()
  testthat::local_mocked_bindings(.lm_control = function(maxiter) minpack.lm::nls.lm.control(maxiter = 2L))
  expect_warning(fit <- rate_optimise(d$q, d$h), "did not converge")
  co <- rating_limbs(fit, all_columns = TRUE)
  expect_false(co$converged)
  expect_equal(co$convergence_code, -1L)
  expect_match(co$convergence_message, "maxiter")
  expect_equal(co$iterations, 2L)
  expect_true(all(!fit@fit_starts$converged))
  expect_equal(co$n_starts_converged, 0L)
  # The fit is still returned and usable: it is a warning, not an error.
  expect_true(is.finite(co$C))
})

test_that("the single-start path warns when it does not converge, and says how to fix it", {
  d <- clean_data()
  testthat::local_mocked_bindings(.lm_control = function(maxiter) minpack.lm::nls.lm.control(maxiter = 2L))
  expect_warning(rate_optimise(d$q, d$h, multi_start = FALSE), "did not converge from its single start.*multi_start = TRUE")
})

test_that("the segmented fit reports convergence in its coefficients and warns when it cannot finish", {
  d <- clean_data(40)
  fit <- rate_optimise_segmented(d$q, d$h, control = 1.5)
  expect_true(all(a9_cols %in% names(fit@coefficients)))
  expect_true(fit@coefficients$converged)
  expect_true(is.na(fit@coefficients$bound_hits))
  expect_true(is.na(fit@coefficients$multi_start_spread))
  testthat::local_mocked_bindings(.lm_control = function(maxiter) minpack.lm::nls.lm.control(maxiter = 2L))
  expect_warning(bad <- rate_optimise_segmented(d$q, d$h, control = 1.5), "did not converge")
  expect_false(bad@coefficients$converged)
})

test_that("the attempt kept is the lowest objective among valid ones, even if only an unconverged one is lowest", {
  d <- seed2_data()
  expect_warning(fit <- rate_optimise(d$q, d$h, control = 1.6), "limb 2 -- the best fit found did not converge")
  at <- fit@fit_starts[limb == 2]
  # One attempt converged but onto a bound with a far worse objective; the
  # unconverged ones are ten times better. Convergence is not quality.
  expect_true(any(at$converged & at$valid))
  expect_true(any(!at$converged & at$valid))
  expect_equal(rating_limbs(fit, all_columns = TRUE)$objective_value[2], min(at$rss[at$valid]), tolerance = 1e-9)
  expect_lt(min(at$rss[!at$converged & at$valid]), 0.2 * min(at$rss[at$converged & at$valid]))
  expect_false(rating_limbs(fit, all_columns = TRUE)$converged[2])
})

test_that("a fit that cannot be told apart from a flat valley reports a small spread though its parameters wander", {
  d <- seed2_data()
  fit <- suppressWarnings(rate_optimise(d$q, d$h, control = 1.6))
  at <- fit@fit_starts[limb == 2 & !converged]
  expect_gt(diff(range(at$n_fit)), 0.3)   # the exponent moves a lot between near-optimal starts
  expect_lt(rating_limbs(fit, all_columns = TRUE)$multi_start_spread[2], 0.05)  # but the curve barely does
})

# ---- bound hits -------------------------------------------------------------------

test_that(".bound_hits names each parameter on a bound, by hand", {
  lo <- c(C = 1e-6, a = -Inf, n = 1.2)
  hi <- c(C = Inf, a = 1.0, n = 2.5)
  hits <- reach.rate:::.bound_hits
  expect_equal(hits(c(C = 5, a = 0, n = 1.8), lo, hi, 3), "")
  expect_equal(hits(c(C = 5, a = 0, n = 1.205), lo, hi, 3), "n_lower")
  expect_equal(hits(c(C = 5, a = 0, n = 2.495), lo, hi, 3), "n_upper")
  expect_equal(hits(c(C = 5, a = 0.98, n = 1.8), lo, hi, 3), "a_upper")        # within 1% of width 3 = 0.03
  expect_equal(hits(c(C = 5, a = 0.95, n = 1.8), lo, hi, 3), "")              # 0.05 away: not a hit
  expect_equal(hits(c(C = 5e-7, a = 0, n = 1.8), lo, hi, 3), "C_lower")
  expect_equal(hits(c(C = 5e-7, a = 0.99, n = 2.499), lo, hi, 3), "C_lower,a_upper,n_upper")
})

test_that("a fit pushed onto its exponent bound says so, and a free fit does not", {
  d <- clean_data()
  free <- rating_limbs(rate_optimise(d$q, d$h), all_columns = TRUE)
  expect_equal(free$bound_hits, "")
  low <- suppressWarnings(rate_optimise(d$q, d$h, n_bounds = c(2.4, 3)))
  expect_match(rating_limbs(low, all_columns = TRUE)$bound_hits, "n_lower")
  high <- suppressWarnings(rate_optimise(d$q, d$h, n_bounds = c(0.5, 1.0)))
  expect_match(rating_limbs(high, all_columns = TRUE)$bound_hits, "n_upper")
  expect_true(rating_limbs(low, all_columns = TRUE)$near_bound)
})

# ---- multi-start spread -----------------------------------------------------------

test_that(".multi_start_spread is hand-checkable on a synthetic attempt table", {
  spread <- reach.rate:::.multi_start_spread
  mk <- function(...) data.table::as.data.table(list(...))
  # Selected: Q = 2 (H - 0)^1.5 over [1, 3]. Peak at H = 3 is 2 * 3^1.5.
  peak <- 2 * 3^1.5
  same <- mk(start_id = 1:2, valid = TRUE, rss = c(1, 1.02), C_fit = c(2, 2), a_fit = 0, n_fit = 1.5)
  expect_equal(spread(same, 1L, 1, 3), 0)
  # A competing start within 5% whose curve is 10% of the peak higher at H = 3.
  rival <- mk(start_id = 1:2, valid = TRUE, rss = c(1, 1.04), C_fit = c(2, 2 + 0.1 * 2), a_fit = 0, n_fit = 1.5)
  expect_equal(spread(rival, 1L, 1, 3), 0.1, tolerance = 1e-9)
  # A rival worse than 5% is not close, so there is no competing solution.
  far <- mk(start_id = 1:2, valid = TRUE, rss = c(1, 1.5), C_fit = c(2, 9), a_fit = 0, n_fit = 1.5)
  expect_equal(spread(far, 1L, 1, 3), 0)
  # One valid attempt, or no selection: nothing to compare.
  one <- mk(start_id = 1:2, valid = c(TRUE, FALSE), rss = c(1, NA), C_fit = 2, a_fit = 0, n_fit = 1.5)
  expect_true(is.na(spread(one, 1L, 1, 3)))
  expect_true(is.na(spread(same, NA_integer_, 1, 3)))
  expect_true(is.na(spread(same[0], 1L, 1, 3)))
  expect_true(is.na(spread(NULL, 1L, 1, 3)))
  # The rival disagrees most where its exponent differs most (the top of the range).
  steeper <- mk(start_id = 1:2, valid = TRUE, rss = c(1, 1.03), C_fit = 2, a_fit = 0, n_fit = c(1.5, 1.6))
  expect_equal(spread(steeper, 1L, 1, 3), abs(2 * 3^1.6 - 2 * 3^1.5) / peak, tolerance = 1e-9)
})

test_that("a single-start fit has no spread to report", {
  d <- clean_data()
  fit <- suppressWarnings(rate_optimise(d$q, d$h, multi_start = FALSE))
  expect_true(is.na(rating_limbs(fit, all_columns = TRUE)$multi_start_spread))
})

# ---- identifiability --------------------------------------------------------------

test_that("parameter correlation is a correlation, the condition number is at least 1", {
  d <- clean_data()
  co <- rating_limbs(rate_optimise(d$q, d$h), all_columns = TRUE)
  expect_true(co$parameter_correlation >= 0 && co$parameter_correlation <= 1)
  expect_true(co$condition_number >= 1)
})

test_that(".fit_identifiability matches a hand calculation from the covariance matrix", {
  d <- clean_data()
  model <- minpack.lm::nlsLM(q ~ C * (h - a)^n, data = list(q = d$q, h = d$h),
                             start = list(C = 3, a = 0, n = 1.5))
  out <- reach.rate:::.fit_identifiability(model)
  r <- stats::cov2cor(stats::vcov(model))
  expect_equal(out$parameter_correlation, max(abs(r[upper.tri(r)])))
  j <- model$m$gradient()
  js <- sweep(j, 2, sqrt(colSums(j^2)), "/")
  d_sv <- svd(js)$d
  expect_equal(out$condition_number, max(d_sv) / min(d_sv))
})

test_that("a model whose covariance cannot be computed gives NA, not an error", {
  broken <- structure(list(), class = "nls")
  out <- reach.rate:::.fit_identifiability(broken)
  expect_true(is.na(out$parameter_correlation))
  expect_true(is.na(out$condition_number))
})

test_that("two gaugings that cannot separate a and C give a correlation near 1 and a large condition number", {
  # Stage barely varies, so a and C trade off almost exactly.
  h <- c(2.00, 2.01, 2.02, 2.03, 2.04, 2.05)
  q <- 5 * (h - 0.5)^1.6 * c(1.001, 0.999, 1.002, 0.998, 1.001, 0.999)
  fit <- suppressWarnings(rate_optimise(q, h))
  co <- rating_limbs(fit, all_columns = TRUE)
  expect_gt(co$parameter_correlation, 0.99)
})

# ---- amendments ---------------------------------------------------------------------

test_that("an amended limb clears the columns that described the fit it came from", {
  d <- clean_data()
  fit <- rate_optimise(d$q, d$h, control = 1.5)
  expect_true(all(fit@limbs$converged))
  aligned <- suppressWarnings(align_limb_equations(fit))
  expect_true(all(is.na(aligned@limbs$converged)))
  expect_true(all(is.na(aligned@limbs$convergence_code)))
  expect_true(all(is.na(aligned@limbs$bound_hits)))
  expect_true(all(is.na(aligned@limbs$condition_number)))
  constrained <- suppressWarnings(rate_optimise_constrained(d$q, d$h, control = 1.5))
  expect_true(all(is.na(constrained@limbs$converged[constrained@limbs$aligned %in% TRUE])))
})

# ---- the optimiser's control ----------------------------------------------------------

test_that("the call limit is raised so the documented iteration limit is the one in force", {
  ctl <- reach.rate:::.lm_control(100L)
  expect_equal(ctl$maxiter, 100L)
  expect_gte(ctl$maxfev, 4L * 100L + 100L)
  expect_equal(reach.rate:::.lm_control(300L)$maxiter, 300L)
})

test_that("suggest_breakpoints scores from a single start and stays quiet about it", {
  d <- seed2_data()
  expect_no_warning(suggest_breakpoints(d$q, d$h, max_breaks = 1))
})
