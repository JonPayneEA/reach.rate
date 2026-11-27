# The reference examples of design/E2_separated_uncertainty.md, as amended. The
# honest test of an uncertainty method is whether its intervals cover the truth as
# often as they claim, so example 1 is a simulation over stations with a known
# curve. It runs a modest number here; the design note reports a larger run.

truth <- function(h) 3 * (h - 0.1)^1.6

station <- function(s, bias_sd, scatter = 0.05) {
  set.seed(1000 + s)
  h <- sort(runif(25, 0.3, 3))
  bias <- rnorm(1, 0, bias_sd)
  data.frame(stage_m = h, discharge_cms = truth(h) * exp(bias + rnorm(25, 0, scatter)))
}

coverage <- function(u_obj) {
  b <- u_obj@bands
  vapply(c("sampling", "gauging", "combined"), function(src) {
    x <- b[b$source == src]
    t <- truth(x$stage_m)
    mean(t >= x$lower & t <= x$upper)
  }, numeric(1))
}

quiet_fit <- function(g, ...) suppressWarnings(fit_rating(g, quiet = TRUE, ...))

test_that("with a shared gauging bias, sampling alone under-covers and the combined band does not", {
  skip_on_cran()
  # Each station's gaugings carry 5% random scatter and one shared bias from
  # Normal(0, 0.05^2), as a meter reading high or low for all of them. Sampling cannot
  # see a shared bias, so its 95% band covers the true curve far less often; with the
  # shared error stated (u = 0.05), the combined band covers close to 95%. A run of 30
  # stations gave 0.53 and 0.94; these twelve are the first of them, with the same seeds.
  cov <- sapply(1:12, function(s) {
    u <- suppressWarnings(rating_uncertainty(quiet_fit(station(s, 0.05)), n_draws = 100,
                                             gauging_uncertainty = 0.05,
                                             sources = c("sampling", "gauging"), seed = s))
    coverage(u)
  })
  mean_cov <- rowMeans(cov)
  expect_lt(mean_cov[["sampling"]], 0.75)
  expect_gt(mean_cov[["combined"]], 0.85)
  expect_gt(mean_cov[["combined"]], mean_cov[["sampling"]] + 0.2)
})

test_that("with negligible shared error the gauging band is narrow and combined is sampling", {
  # No shared bias and u = 0.001: the gauging band is exp(+-1.96 x 0.001), about
  # +-0.2%, and the combined band is the sampling band to within its draws' noise.
  fit <- quiet_fit(station(1, 0))
  u <- rating_uncertainty(fit, n_draws = 200, gauging_uncertainty = 0.001,
                          sources = c("sampling", "gauging"), seed = 1)
  b <- u@bands
  gb <- b[b$source == "gauging"]
  expect_lt(max(abs(gb$upper / gb$rating_cms - 1)), 0.005)
  s <- b[b$source == "sampling"]
  cmb <- b[b$source == "combined"]
  expect_equal(mean((cmb$upper - cmb$lower) / cmb$rating_cms),
               mean((s$upper - s$lower) / s$rating_cms), tolerance = 0.15)
})

test_that("one shared factor scales the fitted curve exactly, so the gauging band is the rating times a constant", {
  # Q -> k Q on every gauging gives C -> k C with a and n unchanged, under the
  # relative objective: the closed form the fast path rests on.
  g <- station(2, 0)
  fit <- quiet_fit(g)
  g2 <- g
  g2$discharge_cms <- 1.1 * g2$discharge_cms
  fit2 <- quiet_fit(g2)
  expect_equal(fit2@limbs$C / fit@limbs$C, 1.1, tolerance = 1e-5)
  expect_equal(fit2@limbs$a, fit@limbs$a, tolerance = 1e-5)
  expect_equal(fit2@limbs$n, fit@limbs$n, tolerance = 1e-5)
  u <- rating_uncertainty(fit, n_draws = 100, gauging_uncertainty = 0.05, sources = "gauging", seed = 3)
  gb <- u@bands[u@bands$source == "gauging"]
  expect_true(u@settings$exact_scaling)
  expect_lt(diff(range(gb$lower / gb$rating_cms)), 1e-10)
  expect_lt(diff(range(gb$upper / gb$rating_cms)), 1e-10)
})

test_that("structure is a range, with the variant behind each edge, and never an interval", {
  # A two-limb station with a real break at 1.2 m: above it the true curve is steeper.
  # Fitted with that breakpoint, the structural variants include one limb fewer, which
  # cannot follow the break: the range is wide, and the variant behind its widest edge
  # is the one without it.
  set.seed(7)
  h <- sort(runif(30, 0.3, 3))
  q <- ifelse(h <= 1.2, 3 * (h - 0.1)^1.6, 3 * 1.1^1.6 * ((h - 0.1) / 1.1)^2.4)
  fit <- quiet_fit(data.frame(stage_m = h, discharge_cms = q * exp(rnorm(30, 0, 0.03))),
                   controls = 1.2)
  u <- rating_uncertainty(fit, n_draws = 100, sources = "structure", seed = 1)
  s <- u@bands[u@bands$source == "structure"]
  expect_true(all(is.na(s$lower) & is.na(s$upper) & is.na(s$median)))
  expect_true(all(s$min <= s$rating_cms + 1e-12 & s$max >= s$rating_cms - 1e-12))
  rel <- (s$max - s$min) / s$rating_cms
  widest <- s[which.max(rel)]
  expect_gt(max(rel), 0.05)
  expect_true("without the breakpoint at 1.2 m" %in% c(widest$variant_min, widest$variant_max))
  # The class refuses an interval on structure.
  bad <- u@bands
  bad$lower[bad$source == "structure"] <- 1
  expect_error(FlodeUncertainty(bands = bad, assessed = u@assessed), "structure is a range")
})

test_that("without a stated uncertainty the gauging source is not assessed, never zero", {
  fit <- quiet_fit(station(3, 0))
  u <- rating_uncertainty(fit, n_draws = 100, sources = c("sampling", "gauging"), seed = 1)
  a <- u@assessed
  expect_false(a$assessed[a$source == "gauging"])
  expect_match(a$reason[a$source == "gauging"], "does not assume one")
  expect_false(a$assessed[a$source == "combined"])
  expect_false(any(u@bands$source %in% c("gauging", "combined")))
  expect_output(print(u), "Not a complete budget")
})

test_that("a per-gauging uncertainty column and groups are used, the groups refitted", {
  # Two methods, each with its own shared error: with groups the shortcut does not
  # hold, and every draw is refitted.
  g <- station(4, 0)
  g$discharge_uncertainty <- 0.04
  g$method <- rep(c("ADCP", "wading"), length.out = nrow(g))
  fit <- quiet_fit(g)
  u <- rating_uncertainty(fit, n_draws = 100, group_by = "method", sources = "gauging", seed = 1)
  expect_false(u@settings$exact_scaling)
  expect_identical(nrow(u@settings$u), 2L)
  expect_equal(u@settings$u$u, c(0.04, 0.04))
  expect_true(u@assessed$assessed[u@assessed$source == "gauging"])
})

test_that("bad inputs are refused with the reason", {
  fit <- quiet_fit(station(5, 0))
  expect_error(rating_uncertainty(as_rating_table(fit)), "no gaugings to resample")
  expect_error(rating_uncertainty(fit, n_draws = 50), "100 or more")
  expect_error(rating_uncertainty(fit, gauging_uncertainty = 0.7), "\\(0, 0.5\\]")
  expect_error(rating_uncertainty(fit, group_by = "nope"), "group_by must name")
  few <- quiet_fit(station(6, 0)[1:8, ])
  expect_error(rating_uncertainty(few), "Below 10")
  g <- station(7, 0)
  g$discharge_uncertainty <- c(-0.1, rep(0.05, nrow(g) - 1))
  expect_error(rating_uncertainty(quiet_fit(g), n_draws = 100), "must be a fraction in")
})
