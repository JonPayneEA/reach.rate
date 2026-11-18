# Each test holds one statement in vignettes/mathematical_contract.Rmd. If
# the code and the document disagree, one of these fails.

contract_data <- function(n = 25, seed = 3) {
  set.seed(seed)
  stage_m <- seq(0.5, 3, length.out = n)
  list(stage_m = stage_m,
       discharge_cms = 3 * (stage_m - 0.2)^1.6 * exp(rnorm(n, sd = 0.04)),
       when = as.Date("2020-01-01") + seq(0, by = 150, length.out = n))
}

# The objectives exactly as the contract writes them.
absolute_objective <- function(par, H, Q, w) sum(w * (Q - par[1] * (H - par[2])^par[3])^2)
relative_objective <- function(par, H, Q, w) sum(w * (log(Q) - log(par[1]) - par[3] * log(H - par[2]))^2)

# TRUE when no step of the given size along any coefficient lowers the
# objective: a minimum, to within the step.
is_local_minimum <- function(objective, par, step = 1e-4) {
  base <- objective(par)
  all(vapply(seq_along(par), function(k) {
    up <- par; up[k] <- up[k] + step
    down <- par; down[k] <- down[k] - step
    min(objective(up), objective(down)) >= base - 1e-12
  }, logical(1)))
}

# ---- the equation and its printed form -----------------------------------------

test_that("the equations printed in provenance are the ones the contract states", {
  d <- contract_data()
  expect_equal(rating_provenance(rate_optimise(d$discharge_cms, d$stage_m))$fitting_equation, "Q = C(H - a)^n")
  expect_equal(
    rating_provenance(rate_optimise(d$discharge_cms, d$stage_m, objective = "relative"))$fitting_equation,
    "log(Q) = log(C) + n*log(H - a)"
  )
  skip_if_not(file.exists(testthat::test_path("..", "..", "vignettes", "mathematical_contract.Rmd")))
  text <- paste(readLines(testthat::test_path("..", "..", "vignettes", "mathematical_contract.Rmd")), collapse = "\n")
  expect_match(text, "Q = C\\,(H - a)^{n}", fixed = TRUE)
  expect_match(text, "\\ln Q_i - \\ln C - n\\,\\ln(H_i - a)", fixed = TRUE)
})

test_that("a fitted limb is applied as Q = C (H - a)^n, and zero at or below a", {
  d <- contract_data()
  fit <- rate_optimise(d$discharge_cms, d$stage_m)
  co <- rating_limbs(fit)
  out <- apply_rating(fit, data.frame(stage = c(co$a - 0.1, co$a, 1.5, 2.5)))
  expect_equal(out$discharge[1:2], c(0, 0))
  expect_equal(out$discharge[3:4], co$C * (c(1.5, 2.5) - co$a)^co$n)
})

test_that("the inverse is a + (Q / C)^(1 / n), and NA for zero, negative or missing discharge", {
  d <- contract_data()
  fit <- rate_optimise(d$discharge_cms, d$stage_m)
  co <- rating_limbs(fit)
  q <- c(2, 5, 0, -1, NA)
  expect_warning(out <- apply_rating_inverse(fit, data.frame(discharge = q)), "no unique inverse stage")
  expect_equal(out$stage[1:2], co$a + (q[1:2] / co$C)^(1 / co$n))
  expect_true(all(is.na(out$stage[3:5])))
})

test_that("a stage outside the limbs uses the nearest limb and is flagged extrapolated", {
  d <- contract_data()
  fit <- rate_optimise(d$discharge_cms, d$stage_m, control = 1.5)
  co <- rating_limbs(fit)
  out <- apply_rating(fit, data.frame(stage = c(0.3, 4)))
  expect_equal(out$extrapolated, c(TRUE, TRUE))
  expect_equal(out$discharge[2], co$C[2] * (4 - co$a[2])^co$n[2])
})

# ---- limb assignment at a breakpoint ---------------------------------------------

test_that("a gauging on a breakpoint is fitted into the lower limb, and a stage on it is applied with the upper", {
  d <- contract_data()
  stage_m <- d$stage_m
  breakpoint <- stage_m[13]
  fit <- rate_optimise(d$discharge_cms, stage_m, control = breakpoint)
  expect_equal(fit@gaugings$limb[13], 1L)
  expect_equal(fit@gaugings$limb[14], 2L)
  co <- rating_limbs(fit)
  out <- apply_rating(fit, data.frame(stage = breakpoint))
  expect_equal(out$discharge, co$C[2] * (breakpoint - co$a[2])^co$n[2])
})

# ---- the objectives, by hand -------------------------------------------------------

test_that("the contract's worked example: three gaugings, both objectives, by hand", {
  H <- c(1.5, 2.5, 3.5); Q <- c(2.1, 5.5, 10.6)
  par <- c(2, 0.5, 1.5)
  modelled <- 2 * c(1, 2, 3)^1.5
  expect_equal(modelled, c(2, 2 * 2^1.5, 2 * 3^1.5))
  expect_equal(absolute_objective(par, H, Q, 1), sum((Q - modelled)^2))
  expect_equal(absolute_objective(par, H, Q, 1), 0.01 + (5.5 - 5.656854)^2 + (10.6 - 10.392305)^2, tolerance = 1e-4)
  expect_equal(relative_objective(par, H, Q, 1), sum((log(Q) - log(modelled))^2))
  # Doubling every weight doubles either objective.
  expect_equal(absolute_objective(par, H, Q, 2), 2 * absolute_objective(par, H, Q, 1))
})

test_that("exact data give the same coefficients under either objective, with zero objective", {
  H <- seq(0.8, 3, length.out = 12)
  Q <- 2.5 * (H - 0.3)^1.7
  abs_fit <- rating_limbs(rate_optimise(Q, H))
  rel_fit <- rating_limbs(rate_optimise(Q, H, objective = "relative"))
  expect_equal(c(abs_fit$C, abs_fit$a, abs_fit$n), c(2.5, 0.3, 1.7), tolerance = 1e-5)
  expect_equal(c(rel_fit$C, rel_fit$a, rel_fit$n), c(2.5, 0.3, 1.7), tolerance = 1e-5)
})

test_that("the absolute fit is a minimum of the absolute objective, and the relative of the relative", {
  d <- contract_data()
  w <- rep(1, length(d$stage_m))
  abs_co <- rating_limbs(rate_optimise(d$discharge_cms, d$stage_m))
  rel_co <- rating_limbs(rate_optimise(d$discharge_cms, d$stage_m, objective = "relative"))
  abs_par <- c(abs_co$C, abs_co$a, abs_co$n)
  rel_par <- c(rel_co$C, rel_co$a, rel_co$n)
  expect_true(is_local_minimum(function(p) absolute_objective(p, d$stage_m, d$discharge_cms, w), abs_par))
  expect_true(is_local_minimum(function(p) relative_objective(p, d$stage_m, d$discharge_cms, w), rel_par))
  # And each is not the other's minimum: the objectives differ in practice.
  expect_false(isTRUE(all.equal(abs_par, rel_par, tolerance = 1e-4)))
})

test_that("with age weights, the fit minimises the weighted objective, not the unweighted one", {
  d <- contract_data()
  for (objective in c("absolute", "relative")) {
    fit <- rate_optimise(d$discharge_cms, d$stage_m, gauging_datetime = d$when,
                         age_halflife = 365, objective = objective)
    w <- fit@gaugings$age_weight
    co <- rating_limbs(fit)
    par <- c(co$C, co$a, co$n)
    f <- if (objective == "absolute") absolute_objective else relative_objective
    expect_true(is_local_minimum(function(p) f(p, d$stage_m, d$discharge_cms, w), par),
                info = paste(objective, "weighted"))
  }
})

test_that("diagnostics are on the discharge scale whichever objective was used", {
  d <- contract_data()
  fit <- rate_optimise(d$discharge_cms, d$stage_m, objective = "relative")
  co <- rating_limbs(fit, all_columns = TRUE)
  predicted <- co$C * (d$stage_m - co$a)^co$n
  expect_equal(co$rmse_cms, sqrt(mean((d$discharge_cms - predicted)^2)))
  expect_equal(co$rmse_pct, 100 * sqrt(mean(((d$discharge_cms - predicted) / d$discharge_cms)^2)))
})

# ---- weighting ---------------------------------------------------------------------

test_that("the age weight is w_min + (1 - w_min) * 0.5^(age / half-life), clamped, with the latest gauging as reference", {
  age <- c(0, 365, 730, 3650)
  expected <- 0.1 + 0.9 * 0.5^(age / 365)
  when <- as.Date("2020-01-01") + 3650 - age
  expect_equal(reach.rate:::.age_recency_weight(when, 365, 0.1, NULL), expected)
  # A gauging after the reference has weight 1, not more.
  expect_equal(reach.rate:::.age_recency_weight(as.Date("2021-01-01"), 365, 0.1, as.Date("2020-01-01")), 1)
  # An explicit reference moves every age.
  expect_equal(reach.rate:::.age_recency_weight(as.Date("2020-01-01"), 100, 0.2, as.Date("2020-04-10")),
               0.2 + 0.8 * 0.5^(100 / 100))
})

test_that("age weighting needs dates, and without a half-life dates change nothing", {
  d <- contract_data()
  expect_error(rate_optimise(d$discharge_cms, d$stage_m, age_halflife = 365), "requires gauging_datetime")
  plain <- rate_optimise(d$discharge_cms, d$stage_m)
  dated <- rate_optimise(d$discharge_cms, d$stage_m, gauging_datetime = d$when)
  expect_equal(rating_limbs(plain)[, .(C, a, n)], rating_limbs(dated)[, .(C, a, n)])
  expect_false("age_weight" %in% names(plain@gaugings))
})

# ---- zero and negative values --------------------------------------------------------

test_that("the table of accepted and refused values holds", {
  H <- seq(1, 4, length.out = 10); Q <- 2 * (H - 0.5)^1.5
  expect_error(rate_optimise(replace(Q, 2, -1), H), "non-negative")
  expect_error(rate_optimise(replace(Q, 2, -1), H, objective = "relative"), "non-negative")
  expect_error(rate_optimise(replace(Q, 2, NA), H), "NA, NaN, or infinite")
  expect_error(rate_optimise(Q, replace(H, 2, Inf)), "NA, NaN, or infinite")
  expect_error(rate_optimise(rep(1, 5), rep(2, 5)), "non-zero range")
  expect_error(rate_optimise(replace(Q, 1, 0), H, objective = "relative"), "strictly positive")
  expect_no_error(rate_optimise(replace(Q, 1, 0), H))
  expect_no_error(rate_optimise(Q, H - 5))  # a negative stage is a datum choice, not an error
})

test_that("a limb needs three gaugings", {
  expect_error(rate_optimise(c(1, 2), c(1, 2)), "at least 3")
})

# ---- bounds, starts and the selection rule -----------------------------------------

test_that("fitted parameters respect the bounds the contract states", {
  d <- contract_data()
  fit <- rate_optimise(d$discharge_cms, d$stage_m, control = 1.6)
  co <- rating_limbs(fit)
  limb_min <- fit@gaugings[, .(m = min(stage_m)), by = limb][order(limb)]$m
  expect_true(all(co$C >= 1e-6))
  expect_true(all(co$n >= 1e-6))
  expect_true(all(co$a <= limb_min - 1e-6 + 1e-12))
})

test_that("n_bounds replaces the bounds on the exponent, and lower == upper fixes it", {
  d <- contract_data()
  fit <- rate_optimise(d$discharge_cms, d$stage_m, n_bounds = c(1.2, 1.4))
  expect_true(rating_limbs(fit)$n >= 1.2 - 1e-9 && rating_limbs(fit)$n <= 1.4 + 1e-9)
  expect_equal(rating_limbs(rate_optimise(d$discharge_cms, d$stage_m, n_bounds = c(1.5, 1.5)))$n, 1.5)
})

test_that("the six starting points are the ones the contract lists", {
  d <- contract_data()
  limb <- data.table::data.table(stage_m = d$stage_m, discharge_cms = d$discharge_cms)
  lo <- c(C = 1e-6, a = -Inf, n = 1e-6)
  hi <- c(C = Inf, a = min(d$stage_m) - 1e-6, n = Inf)
  s <- reach.rate:::.generate_starts(limb, lo, hi)
  expect_length(s, 6L)
  H <- d$stage_m; a0 <- 0
  expect_equal(c(s[[1]]$C, s[[1]]$n), c(1, 1))
  expect_equal(c(s[[2]]$C, s[[2]]$n), c(1, 1.5))
  expect_equal(c(s[[3]]$C, s[[3]]$n), c(1, 2))
  expect_equal(s[[4]]$C, median(d$discharge_cms) / (median(H) - a0)^1.5)
  expect_equal(s[[5]]$a, a0 - 0.25 * diff(range(H)))
  expect_equal(s[[6]]$a, min(H) - 0.1)
  expect_true(all(vapply(s, function(x) x$a <= hi[["a"]], logical(1))))
})

test_that("each attempt's rss is the weighted objective at its own coefficients, and the winner has the least", {
  d <- contract_data()
  for (objective in c("absolute", "relative")) {
    fit <- rate_optimise(d$discharge_cms, d$stage_m, gauging_datetime = d$when,
                         age_halflife = 365, objective = objective)
    w <- fit@gaugings$age_weight
    f <- if (objective == "absolute") absolute_objective else relative_objective
    at <- fit@fit_starts[!is.na(rss)]
    for (i in seq_len(nrow(at))) {
      par <- c(at$C_fit[i], at$a_fit[i], at$n_fit[i])
      expect_equal(at$rss[i], f(par, d$stage_m, d$discharge_cms, w), tolerance = 1e-6, info = paste(objective, i))
    }
    co <- rating_limbs(fit)
    expect_equal(f(c(co$C, co$a, co$n), d$stage_m, d$discharge_cms, w), min(at$rss), tolerance = 1e-6)
  }
})

test_that("the segmented fit ranks its attempts on the weighted sum of squares too", {
  d <- contract_data(40)
  fit <- rate_optimise_segmented(d$discharge_cms, d$stage_m, gauging_datetime = d$when,
                                 age_halflife = 365, control = 1.6)
  w <- fit@gaugings$age_weight
  co <- as.list(fit@coefficients)
  predicted <- reach.rate:::.segmented_predict_cms(co, 2L, d$stage_m)
  weighted <- sum(w * (d$discharge_cms - predicted)^2)
  expect_equal(weighted, min(fit@fit_starts$rss, na.rm = TRUE), tolerance = 1e-6)
})

test_that("an attempt whose equation decreases across the limb is not valid", {
  expect_equal(formals(reach.rate:::.fit_limb_multi_start)$maxiter, 100L)
  d <- contract_data()
  fit <- rate_optimise(d$discharge_cms, d$stage_m)
  expect_true(all(fit@fit_starts[valid == TRUE]$n_fit > 0))
  expect_true(all(is.na(fit@fit_starts[valid == FALSE]$rss)))
})

# ---- convergence ---------------------------------------------------------------------

test_that("the optimiser's default tolerances are the ones the contract quotes", {
  ctl <- minpack.lm::nls.lm.control()
  expect_equal(ctl$ftol, sqrt(.Machine$double.eps))
  expect_equal(ctl$ptol, sqrt(.Machine$double.eps))
  expect_equal(formals(reach.rate:::.fit_segmented_multi_start)$maxiter, 300L)
})

# ---- intervals -------------------------------------------------------------------------

test_that("apply_rating_interval is the percentile of the per-draw discharges, by hand", {
  d <- contract_data()
  fit <- rate_optimise(d$discharge_cms, d$stage_m, n_boot = 60, boot_seed = 1)
  draws <- rating_bootstrap(fit)
  out <- apply_rating_interval(data.frame(stage = 2), draws, conf_level = 0.9)
  q <- draws$C * (2 - draws$a)^draws$n
  expect_equal(out$discharge_lower, quantile(q, 0.05, names = FALSE))
  expect_equal(out$discharge_upper, quantile(q, 0.95, names = FALSE))
  expect_equal(out$discharge_median, median(q))
  expect_equal(out$discharge_mean, mean(q))
  expect_equal(out$discharge_gse, exp(sd(log(q))))
})

test_that("bootstrap standard errors and percentiles come from the successful draws", {
  d <- contract_data()
  fit <- rate_optimise(d$discharge_cms, d$stage_m, n_boot = 60, boot_seed = 1)
  ok <- rating_bootstrap(fit)
  co <- rating_limbs(fit, all_columns = TRUE)
  expect_equal(co$C_se, sd(ok$C))
  expect_equal(co$n_q025, quantile(ok$n, 0.025, names = FALSE))
  expect_equal(co$a_q975, quantile(ok$a, 0.975, names = FALSE))
})

# ---- the segmented model -------------------------------------------------------------

test_that("the segmented equation is the product the contract writes", {
  co <- list(C = 2, bp1 = 0.4, bp2 = 1.5, n1 = 1.3, n2 = 0.6)
  H <- c(0.3, 0.4, 1.0, 1.5, 2.5)
  expected <- 2 * pmax(H - 0.4, 0)^1.3 * (pmax(H - 1.5, 0) + 1)^0.6
  expect_equal(reach.rate:::.segmented_predict_cms(co, 2L, H), expected)
  # Each later factor is exactly 1 at and below its breakpoint, so the curve is continuous there.
  below <- reach.rate:::.segmented_predict_cms(co, 2L, 1.5 - 1e-9)
  at <- reach.rate:::.segmented_predict_cms(co, 2L, 1.5)
  expect_equal(below, at, tolerance = 1e-6)
})

# ---- the offset convention --------------------------------------------------------------

test_that("converting the offset round-trips in both directions and keeps the curve", {
  ext <- data.frame(lower_level = c(0.5, 1.5), upper_level = c(1.5, 3), C = c(4.1, 3), a = c(-0.35, -0.2), n = c(1.6, 1.8))
  internal <- convert_offset_convention(ext, from = "add", to = "subtract")
  expect_equal(internal$a, c(0.35, 0.2))
  expect_equal(internal$C, ext$C)
  expect_equal(internal$n, ext$n)
  expect_equal(internal$lower_level, ext$lower_level)
  # add -> subtract -> add
  expect_equal(convert_offset_convention(internal, from = "subtract", to = "add")$a, ext$a)
  # subtract -> add -> subtract
  there <- convert_offset_convention(internal, from = "subtract", to = "add")
  expect_equal(convert_offset_convention(there, from = "add", to = "subtract")$a, internal$a)
  # One curve: H + a_ext equals H - a_internal.
  H <- c(1.0, 1.4)
  expect_equal(ext$C[1] * (H + ext$a[1])^ext$n[1], internal$C[1] * (H - internal$a[1])^internal$n[1])
})

test_that("same convention in and out returns the table unchanged, and the input is never modified", {
  ext <- data.frame(lower_level = 0.5, upper_level = 3, C = 4.1, a = -0.35, n = 1.6)
  expect_equal(convert_offset_convention(ext, from = "add", to = "add")$a, -0.35)
  before <- data.table::copy(ext)
  convert_offset_convention(ext)
  expect_identical(ext, before)
})

test_that("ratings are read in either convention, and what cannot convert is refused", {
  d <- contract_data()
  fit <- rate_optimise(d$discharge_cms, d$stage_m)
  co <- rating_limbs(fit)
  expect_equal(convert_offset_convention(fit, to = "subtract")$a, co$a)
  expect_equal(convert_offset_convention(fit, to = "add")$a, -co$a)
  expect_equal(convert_offset_convention(as_rating_table(fit), to = "add")$a, -co$a)
  seg <- rate_optimise_segmented(d$discharge_cms, d$stage_m, control = 1.6)
  expect_error(convert_offset_convention(seg), "no per-limb offset")
  expect_error(convert_offset_convention(1:3), "data.frame")
  expect_error(convert_offset_convention(data.frame(x = 1)), "no column named 'a'")
  expect_error(convert_offset_convention(data.frame(a = "x")), "numeric")
})
