# Tranche B7: one plot grammar. autoplot() and plot() return ggplot objects.

plot_data <- function(n = 24, seed = 1) {
  set.seed(seed)
  h <- seq(0.4, 3, length.out = n)
  data.frame(stage_m = h, discharge_cms = 3.2 * h^1.6 * exp(rnorm(n, sd = 0.04)))
}

mixed_evidence <- function() {
  g <- plot_data()
  h <- c(g$stage_m, 3.2, 3.5, 3.8)
  ev <- as_flode_evidence(data.frame(stage_m = h, discharge_cms = c(g$discharge_cms, 3.2 * c(3.2, 3.5, 3.8)^1.6)))
  data.table::set(ev, j = "source_type", value = c(rep("gauging", 24), rep("modelled", 3)))
  data.table::set(ev, i = c(3L, 9L), j = "included", value = FALSE)
  data.table::set(ev, i = c(3L, 9L), j = "exclusion_reason", value = "wading")
  FlodeEvidence(ev)
}

layers <- function(p) vapply(p$layers, function(l) class(l$geom)[1], "")
n_layer <- function(p, geom) sum(layers(p) == geom)

# ---- every class, both verbs ------------------------------------------------------------------------

test_that("autoplot and plot return a ggplot for every rating class", {
  fit <- fit_rating(plot_data(), quiet = TRUE)
  set.seed(4)
  h <- seq(0.3, 3.5, by = 0.03)
  q <- ifelse(h < 1.5, 3 * h^1.6, 3 * 1.5^1.6 * (h / 1.5)^2.1) * exp(rnorm(length(h), sd = 0.03))
  seg <- rate_optimise_segmented(q, h, control = 1.5)
  tab <- as_rating_table(fit)
  for (x in list(fit, seg, tab)) {
    expect_s3_class(ggplot2::autoplot(x), "ggplot")
    expect_s3_class(plot(x), "ggplot")
  }
})

test_that("plot() and autoplot() give the same plot", {
  fit <- fit_rating(plot_data(), n_boot = 20, seed = 1, quiet = TRUE)
  a <- autoplot(fit); b <- plot(fit)
  expect_equal(layers(a), layers(b))
  expect_equal(a$labels$caption, b$labels$caption)
  expect_equal(a$layers[[length(a$layers)]]$data, b$layers[[length(b$layers)]]$data)
})

test_that("autoplot is re-exported, so it works without attaching ggplot2", {
  expect_identical(reach.rate::autoplot, ggplot2::autoplot)
  expect_true("autoplot" %in% getNamespaceExports("reach.rate"))
})

test_that("it can be added to like any ggplot, and printed to a device", {
  fit <- fit_rating(plot_data(), quiet = TRUE)
  p <- autoplot(fit) + ggplot2::labs(title = "Station 10250")
  expect_equal(p$labels$title, "Station 10250")
  grDevices::pdf(NULL); on.exit(grDevices::dev.off())
  expect_no_error(print(p))
})

# ---- the evidence ---------------------------------------------------------------------------------------

test_that("gaugings are shaped by source type, and excluded rows are drawn muted, not hidden", {
  fit <- suppressWarnings(fit_rating(mixed_evidence(), quiet = TRUE))
  p <- autoplot(fit)
  pts <- p$layers[[which(layers(p) == "GeomPoint")]]$data
  expect_equal(nrow(pts), 27L)                                   # 25 used + 2 excluded
  expect_equal(sum(pts$use == "excluded"), 2L)
  expect_equal(sort(unique(as.character(pts$source_type))), c("gauging", "modelled"))
  expect_equal(sum(pts$source_type == "modelled"), 3L)
  # The excluded rows keep their values, from the record of what was left out.
  ex <- pts[use == "excluded"]
  expect_equal(sort(ex$stage_m), sort(mixed_evidence()$stage_m[c(3, 9)]))
  # Mapped to shape and to colour, so the plot does not rely on colour alone.
  expect_true(all(c("shape", "colour") %in% names(p$layers[[which(layers(p) == "GeomPoint")]]$mapping)))
})

test_that("a guided fit keeps the values of what it left out, with the reason", {
  fit <- suppressWarnings(fit_rating(mixed_evidence(), quiet = TRUE))
  ex <- rating_provenance(fit)$fit_rating$excluded
  expect_true(all(c("evidence_id", "reason", "stage_m", "discharge_cms", "source_type") %in% names(ex)))
  expect_equal(nrow(ex), 2L)
  expect_match(ex$reason[1], "wading")
})

test_that("a plain fit with no exclusions draws every gauging as used", {
  g <- plot_data()
  fit <- rate_optimise(g$discharge_cms, g$stage_m)
  p <- autoplot(fit)
  pts <- p$layers[[which(layers(p) == "GeomPoint")]]$data
  expect_equal(nrow(pts), 24L)
  expect_true(all(pts$use == "used in the fit"))
})

test_that("an equation table has no evidence, so only the curve and the status are drawn", {
  tab <- as_rating_table(fit_rating(plot_data(), quiet = TRUE))
  p <- autoplot(tab)
  expect_equal(n_layer(p, "GeomPoint"), 0L)
  expect_equal(n_layer(p, "GeomLine"), 1L)
  expect_match(p$labels$caption, "converged: not assessed")
})

# ---- the band, the support, the limits ---------------------------------------------------------------------

test_that("the bootstrap band is drawn when the fit has one, and the subtitle says so", {
  with_b <- autoplot(fit_rating(plot_data(), n_boot = 30, seed = 2, quiet = TRUE))
  without <- autoplot(fit_rating(plot_data(), quiet = TRUE))
  expect_equal(n_layer(with_b, "GeomRibbon"), 1L)
  expect_match(with_b$labels$subtitle, "95% bootstrap band")
  expect_equal(n_layer(without, "GeomRibbon"), 0L)
  expect_false(grepl("bootstrap", without$labels$subtitle))
  expect_equal(n_layer(autoplot(fit_rating(plot_data(), n_boot = 30, seed = 2, quiet = TRUE), band = FALSE), "GeomRibbon"), 0L)
  b <- with_b$layers[[which(layers(with_b) == "GeomRibbon")]]$data
  expect_true(all(b$upper >= b$lower))
})

test_that("the band is the 2.5 and 97.5 percentiles of the draws, by hand", {
  fit <- fit_rating(plot_data(), n_boot = 30, seed = 2, quiet = TRUE)
  b <- autoplot(fit, n_points = 5)$layers
  band <- b[[which(vapply(b, function(l) class(l$geom)[1], "") == "GeomRibbon")]]$data
  d <- rating_bootstrap(fit)
  s <- band$stage[3]
  q <- d$C * pmax(s - d$a, 0)^d$n
  expect_equal(band$lower[3], quantile(q, 0.025, names = FALSE))
  expect_equal(band$upper[3], quantile(q, 0.975, names = FALSE))
})

test_that("the stage ranges the rating rests on are shaded, and only where they exist", {
  mixed <- autoplot(suppressWarnings(fit_rating(mixed_evidence(), quiet = TRUE)))
  rect <- mixed$layers[[which(layers(mixed) == "GeomRect")]]$data
  expect_equal(rect$kind, "Modelled evidence")
  expect_equal(c(rect$ymin, rect$ymax), c(3.2, 3.8))
  none <- autoplot(fit_rating(plot_data(), quiet = TRUE))
  expect_equal(n_layer(none, "GeomRect"), 0L)
  expect_equal(n_layer(autoplot(suppressWarnings(fit_rating(mixed_evidence(), quiet = TRUE)), support = FALSE), "GeomRect"), 0L)
  # A fitted range wider than the evidence is shaded as fitted with no evidence.
  fit <- fit_rating(plot_data(), quiet = TRUE)
  limbs <- data.table::copy(fit@limbs); limbs[, lower_stage_m := 0.2]
  fit@limbs <- limbs
  r <- autoplot(fit)$layers
  rd <- r[[which(vapply(r, function(l) class(l$geom)[1], "") == "GeomRect")]]$data
  expect_equal(rd$kind, "Fitted, no evidence")
  expect_equal(c(rd$ymin, rd$ymax), c(0.2, 0.4))
})

test_that("operational limits are drawn as dashed lines when stated", {
  fit <- fit_rating(plot_data(), operational_limits = c(0.3, 3.4), operational_basis = "x", quiet = TRUE)
  p <- autoplot(fit)
  h <- p$layers[vapply(p$layers, function(l) class(l$geom)[1] == "GeomHline" && identical(l$aes_params$linetype, "longdash"), logical(1))]
  expect_length(h, 1L)
  yi <- if (!is.null(h[[1]]$data$yintercept)) h[[1]]$data$yintercept else h[[1]]$geom_params$yintercept
  expect_equal(sort(yi), c(0.3, 3.4))
  expect_equal(n_layer(autoplot(fit_rating(plot_data(), quiet = TRUE)), "GeomHline"), 0L)
})

test_that("interior breakpoints are marked, one fewer than the limbs", {
  set.seed(3)
  h <- round(seq(0.3, 3.4, length.out = 40), 3)
  q <- ifelse(h < 1.6, 3.2 * h^1.6, 3.2 * 1.6^1.6 * (h / 1.6)^2.1) * exp(rnorm(40, sd = 0.03))
  p <- autoplot(fit_rating(data.frame(stage_m = h, discharge_cms = q), controls = 1.6, quiet = TRUE))
  expect_equal(n_layer(p, "GeomHline"), 1L)
  expect_match(p$labels$subtitle, "2 limbs")
})

# ---- labels, units and status ----------------------------------------------------------------------------------

test_that("the axes carry units, with discharge horizontal and stage vertical", {
  p <- autoplot(fit_rating(plot_data(), quiet = TRUE))
  expect_equal(p$labels$y, "Stage (m)")
  expect_match(paste(deparse(p$labels$x), collapse = ""), "Discharge")
  expect_match(paste(deparse(p$labels$x), collapse = ""), "m\"\\^3")
  m <- p$layers[[which(layers(p) == "GeomLine")]]$mapping
  expect_equal(rlang::as_label(m$x), "discharge")
  expect_equal(rlang::as_label(m$y), "stage")
})

test_that("the caption gives the rating's status: origin, lifecycle, converged and valid", {
  fit <- fit_rating(plot_data(), quiet = TRUE)
  expect_equal(autoplot(fit)$labels$caption, "origin: independently_fitted | lifecycle: draft | converged: yes (1 of 1 limb) | valid: yes")
  fit@lifecycle <- "under_review"
  expect_match(autoplot(fit)$labels$caption, "lifecycle: under_review")
  amended <- suppressWarnings(align_limb_equations(fit_rating(plot_data(), controls = 1.5, quiet = TRUE)))
  expect_match(autoplot(amended)$labels$caption, "origin: post_fit_aligned")
  expect_match(autoplot(amended)$labels$caption, "converged: not assessed")
})

test_that("a rating that fails its invariants can still be drawn, and its caption says so", {
  bad <- FlodeRatingTable(table = data.table::data.table(lower_level = 0.3, upper_level = 3, C = 2, a = 0, n = 1.5))
  S7::prop(bad, "table", check = FALSE) <- data.table::data.table(lower_level = 0.3, upper_level = 3, C = 2, a = 0, n = -1)
  p <- autoplot(bad)
  expect_s3_class(p, "ggplot")
  expect_match(p$labels$caption, "valid: no \\(fails: coefficients_finite")
  grDevices::pdf(NULL); on.exit(grDevices::dev.off())
  expect_no_error(suppressWarnings(print(p)))
})

test_that("a segmented fit draws its joint curve over the gauged range", {
  set.seed(4)
  h <- seq(0.3, 3.5, by = 0.03)
  q <- ifelse(h < 1.5, 3 * h^1.6, 3 * 1.5^1.6 * (h / 1.5)^2.1) * exp(rnorm(length(h), sd = 0.03))
  p <- autoplot(rate_optimise_segmented(q, h, control = 1.5), n_points = 50)
  curve <- p$layers[[which(layers(p) == "GeomLine")]]$data
  expect_equal(nrow(curve), 50L)
  expect_match(p$labels$subtitle, "2 segments")
})

test_that("n_points is checked", {
  fit <- fit_rating(plot_data(), quiet = TRUE)
  expect_error(autoplot(fit, n_points = 1), "n_points")
  expect_error(autoplot(fit, n_points = "a"), "n_points")
  expect_equal(nrow(autoplot(fit, n_points = 11)$layers[[which(layers(autoplot(fit, n_points = 11)) == "GeomLine")]]$data), 11L)
})

# ---- the other results answer autoplot too ------------------------------------------------------------------------

test_that("assessments and sensitivity analyses answer autoplot as they answer plot", {
  fit <- fit_rating(plot_data(), quiet = TRUE)
  a <- assess_rating(fit, reference_time = as.POSIXct("2026-01-01", tz = "UTC"))
  expect_s3_class(autoplot(a), "ggplot")
  expect_equal(autoplot(a)$labels$title, plot(a)$labels$title)
  s <- rating_sensitivity(fit, tests = "leave_high_out", stages = c(1, 2, 3))
  expect_s3_class(autoplot(s), "ggplot")
  expect_equal(layers(autoplot(s)), layers(plot(s)))
})
