test_that("compare_ratings produces a per-limb coefficient diff when limb counts match", {
  rating_old_dt <- data.table(
    lower_level = c(0.0, 1.2), upper_level = c(1.2, 3.0),
    C = c(2.5, 4.1), a = c(0, 0), n = c(1.5, 1.7)
  )
  rating_new_dt <- data.table(
    lower_level = c(0.0, 1.2), upper_level = c(1.2, 3.0),
    C = c(2.6, 4.0), a = c(0, 0), n = c(1.5, 1.7)
  )

  cmp <- compare_ratings(rating_old_dt, rating_new_dt)

  expect_true(is.data.table(cmp$coefficients))
  expect_equal(nrow(cmp$coefficients), 2L)
  expect_equal(cmp$coefficients$C_diff, c(0.1, -0.1), tolerance = 1e-8)
  expect_equal(cmp$coefficients$a_diff, c(0, 0))
  expect_equal(cmp$coefficients$n_diff, c(0, 0))
})

test_that("compare_ratings skips the coefficient diff when limb counts differ", {
  rating_old_dt <- data.table(
    lower_level = 0.0, upper_level = 3.0, C = 3, a = 0, n = 1.6
  )
  rating_new_dt <- data.table(
    lower_level = c(0.0, 1.5), upper_level = c(1.5, 3.0),
    C = c(3, 5), a = c(0, 0), n = c(1.6, 1.8)
  )

  cmp <- compare_ratings(rating_old_dt, rating_new_dt)

  expect_null(cmp$coefficients)
  expect_true(is.data.table(cmp$discharge))
})

test_that("compare_ratings computes discharge diffs identical to zero for identical ratings", {
  rating_dt <- data.table(
    lower_level = 0.0, upper_level = 3.0, C = 3, a = 0, n = 1.6
  )

  cmp <- compare_ratings(rating_dt, rating_dt)

  expect_true(all(abs(cmp$discharge$discharge_diff) < 1e-8))
  expect_true(all(is.na(cmp$discharge$discharge_pct_diff) | abs(cmp$discharge$discharge_pct_diff) < 1e-6))
})

test_that("compare_ratings computes a known discharge difference correctly", {
  rating_old_dt <- data.table(lower_level = 0.0, upper_level = 3.0, C = 3, a = 0, n = 1.6)
  rating_new_dt <- data.table(lower_level = 0.0, upper_level = 3.0, C = 6, a = 0, n = 1.6)

  cmp <- compare_ratings(rating_old_dt, rating_new_dt, step = 0.5)

  # C doubled with a and n unchanged -> discharge should exactly double
  expect_equal(cmp$discharge$discharge_new, cmp$discharge$discharge_old * 2, tolerance = 1e-8)
  expect_equal(cmp$discharge$discharge_pct_diff[cmp$discharge$stage > 0], rep(100, sum(cmp$discharge$stage > 0)), tolerance = 1e-6)
})

test_that("compare_ratings errors when stage ranges do not overlap", {
  rating_old_dt <- data.table(lower_level = 0.0, upper_level = 1.0, C = 3, a = 0, n = 1.6)
  rating_new_dt <- data.table(lower_level = 2.0, upper_level = 3.0, C = 3, a = 0, n = 1.6)

  expect_error(compare_ratings(rating_old_dt, rating_new_dt), "do not overlap")
})

test_that("compare_ratings validates its inputs", {
  rating_dt <- data.table(lower_level = 0.0, upper_level = 1.0, C = 3, a = 0, n = 1.6)
  expect_error(compare_ratings(list(), rating_dt), "data.frame, or data.table")
  expect_error(compare_ratings(rating_dt, rating_dt, step = -1), "positive number")
})

test_that("plot_rating_comparison returns a grob without error", {
  rating_old_dt <- data.table(
    lower_level = c(0.0, 1.2), upper_level = c(1.2, 3.0),
    C = c(2.5, 4.1), a = c(0, 0), n = c(1.5, 1.7)
  )
  rating_new_dt <- data.table(
    lower_level = c(0.0, 1.2), upper_level = c(1.2, 3.0),
    C = c(2.6, 4.0), a = c(0, 0), n = c(1.5, 1.7)
  )
  cmp <- compare_ratings(rating_old_dt, rating_new_dt)

  combined <- expect_pdf_renders(plot_rating_comparison(cmp))
  expect_true(inherits(combined, "gtable") || inherits(combined, "grob"))
})

test_that("plot_rating_comparison rejects a malformed cmp argument", {
  expect_error(plot_rating_comparison(list()), "discharge")
  expect_error(plot_rating_comparison(data.table(a = 1)), "discharge")
})

# ---- evidence and support (Release C) -------------------------------------------------------------------------

cmp_data <- function(n = 25, seed = 1) {
  set.seed(seed)
  st <- seq(0.3, 3, length.out = n)
  data.frame(stage_m = st, discharge_cms = 3 * st^1.6 * exp(rnorm(n, sd = 0.03)))
}
cmp_fit <- function(g) fit_rating(g, quiet = TRUE)

test_that("comparing two fits adds support and evidence, and leaves coefficients and discharge as before", {
  g <- cmp_data()
  old <- cmp_fit(g[1:20, ]); new <- cmp_fit(g)
  cmp <- compare_ratings(old, new)
  expect_named(cmp, c("coefficients", "discharge", "support", "evidence"))
  tab <- compare_ratings(as_rating_table(old), as_rating_table(new))
  expect_equal(cmp$discharge, tab$discharge)
  expect_equal(cmp$coefficients, tab$coefficients)
})

test_that("the evidence summary counts what was added, removed, shared and changed", {
  g <- cmp_data()
  cmp <- compare_ratings(cmp_fit(g[1:20, ]), cmp_fit(g))
  s <- cmp$evidence$summary
  expect_equal(c(s$n_old, s$n_new, s$n_shared, s$n_changed, s$n_added, s$n_removed), c(20, 25, 20, 0, 5, 0))
  expect_equal(s$gauged_max_old_m, max(g$stage_m[1:20]))
  expect_equal(s$gauged_max_new_m, max(g$stage_m))
  rows <- cmp$evidence$rows
  expect_equal(sort(rows[change == "added"]$evidence_id), sprintf("G%03d", 21:25))
  expect_equal(nrow(rows), 25L)

  back <- compare_ratings(cmp_fit(g), cmp_fit(g[1:20, ]))
  expect_equal(back$evidence$summary$n_removed, 5L)
  expect_equal(sum(back$evidence$rows$change == "removed"), 5L)
})

test_that("a gauging whose value changed is reported as changed, not shared", {
  g <- cmp_data()
  g2 <- g
  g2$discharge_cms[3] <- g2$discharge_cms[3] * 1.2
  cmp <- compare_ratings(cmp_fit(g), cmp_fit(g2))
  expect_equal(cmp$evidence$summary$n_changed, 1L)
  expect_equal(cmp$evidence$summary$n_shared, 24L)
  ch <- cmp$evidence$rows[change == "changed"]
  expect_equal(ch$evidence_id, "G003")
  expect_equal(ch$discharge_cms_new / ch$discharge_cms_old, 1.2)
})

test_that("two unrelated datasets that happen to share positional ids do not read as shared", {
  a <- cmp_data(seed = 1); b <- cmp_data(seed = 2)
  b$stage_m <- b$stage_m + 0.01
  cmp <- compare_ratings(cmp_fit(a), cmp_fit(b))
  expect_equal(cmp$evidence$summary$n_shared, 0L)
  expect_equal(cmp$evidence$summary$n_changed, 25L)
})

test_that("support shows how far each range moved, and leaves absent ranges and the numerical range as NA", {
  g <- cmp_data()
  cmp <- compare_ratings(cmp_fit(g[1:20, ]), cmp_fit(g))
  sup <- cmp$support
  expect_equal(sup$range, c("observed", "modelled", "fitted", "operational", "numerical"))
  obs <- sup[range == "observed"]
  expect_equal(obs$upper_moved_m, max(g$stage_m) - max(g$stage_m[1:20]))
  expect_equal(obs$lower_moved_m, 0)
  expect_equal(c(obs$n_evidence_old, obs$n_evidence_new), c(20L, 25L))
  expect_true(is.na(sup[range == "modelled"]$lower_moved_m))
  expect_true(is.na(sup[range == "numerical"]$upper_moved_m))
})

test_that("operational limits moving shows in support", {
  g <- cmp_data()
  a <- set_operational_limits(cmp_fit(g), 0.25, 3.0, basis = "b")
  b <- set_operational_limits(cmp_fit(g), 0.25, 3.5, basis = "b")
  op <- compare_ratings(a, b)$support[range == "operational"]
  expect_equal(op$upper_moved_m, 0.5)
  expect_equal(op$lower_moved_m, 0)
})

test_that("tables have support but no evidence, and a fit against a table still compares", {
  g <- cmp_data()
  fit <- cmp_fit(g)
  tab <- as_rating_table(fit)
  both <- compare_ratings(tab, tab)
  expect_null(both$evidence)
  expect_true(is.data.frame(both$support))
  expect_equal(both$support[range %in% c("observed", "modelled")]$n_evidence_old, c(0L, 0L))
  expect_true(all(is.na(both$support[!range %in% c("observed", "modelled")]$n_evidence_old)))
  mixed <- compare_ratings(fit, tab)
  expect_null(mixed$evidence)
  expect_equal(mixed$discharge$discharge_diff, rep(0, nrow(mixed$discharge)))
  plain <- data.table(lower_level = 0.3, upper_level = 3, C = 3, a = 0, n = 1.6)
  expect_null(compare_ratings(fit, plain)$evidence)
})

test_that("a segmented rating is refused, saying why, and other inputs still error clearly", {
  set.seed(3)
  h <- round(seq(0.3, 3.4, length.out = 40), 3)
  q <- ifelse(h < 1.6, 3.2 * h^1.6, 3.2 * 1.6^1.6 * (h / 1.6)^2.1) * exp(rnorm(40, sd = 0.03))
  seg <- fit_rating(data.frame(stage_m = h, discharge_cms = q), controls = 1.6, model = "segmented", quiet = TRUE)
  fit <- cmp_fit(cmp_data())
  expect_error(compare_ratings(seg, fit), "rating_old_dt is a FlodeSegmentedRating.*no per-limb coefficients")
  expect_error(compare_ratings(fit, seg), "rating_new_dt is a FlodeSegmentedRating")
  expect_error(compare_ratings(1, fit), "rating_old_dt must be a FlodeRating")
})

test_that("a comparison of two fits plots", {
  g <- cmp_data()
  cmp <- compare_ratings(cmp_fit(g[1:20, ]), cmp_fit(g))
  combined <- expect_pdf_renders(plot_rating_comparison(cmp, old_label = "20 gaugings", new_label = "25 gaugings"))
  expect_true(inherits(combined, "gtable") || inherits(combined, "grob"))
})
