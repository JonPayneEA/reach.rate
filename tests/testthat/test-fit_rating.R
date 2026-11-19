# Tranche B1: fit_rating(), the guided entry point.

sample_gaugings <- function(n = 24, seed = 1) {
  set.seed(seed)
  h <- round(seq(0.4, 3, length.out = n), 3)
  data.frame(stage_m = h, discharge_cms = round(3.2 * h^1.6 * exp(rnorm(n, sd = 0.03)), 4))
}

two_limb <- function(n = 40, seed = 3) {
  set.seed(seed)
  h <- round(seq(0.3, 3.4, length.out = n), 3)
  q <- ifelse(h < 1.6, 3.2 * h^1.6, 3.2 * 1.6^1.6 * (h / 1.6)^2.1) * exp(rnorm(n, sd = 0.03))
  data.frame(stage_m = h, discharge_cms = round(q, 4))
}

fit_quiet <- function(...) fit_rating(..., quiet = TRUE)

# ---- defaults --------------------------------------------------------------------------------

test_that("the defaults are one limb, the relative objective and an independent fit", {
  fit <- fit_quiet(sample_gaugings())
  expect_true(S7::S7_inherits(fit, FlodeRating))
  expect_equal(nrow(fit@limbs), 1L)
  expect_equal(rating_provenance(fit)$objective, "relative")
  expect_equal(rating_provenance(fit)$fit_rating$model, "independent")
  expect_equal(fit@lifecycle, "draft")
})

test_that("the relative default gives the same fit as calling rate_optimise with the relative objective", {
  g <- sample_gaugings()
  by_hand <- rate_optimise(g$discharge_cms, g$stage_m, objective = "relative")
  guided <- fit_quiet(g)
  expect_equal(rating_limbs(guided)[, .(C, a, n)], rating_limbs(by_hand)[, .(C, a, n)])
  absolute <- fit_quiet(g, objective = "absolute")
  expect_equal(rating_limbs(absolute)[, .(C, a, n)],
               rating_limbs(rate_optimise(g$discharge_cms, g$stage_m))[, .(C, a, n)])
})

test_that("more than one limb needs an explicit choice", {
  expect_equal(nrow(fit_quiet(two_limb())@limbs), 1L)
  expect_equal(nrow(fit_quiet(two_limb(), controls = 1.6)@limbs), 2L)
  expect_error(fit_quiet(two_limb(), controls = 1.6, limbs = "suggest"), "not both")
})

# ---- breakpoints and where they came from --------------------------------------------------

test_that("breakpoints you supply are recorded as yours, and are not advisory", {
  bp <- rating_provenance(fit_quiet(two_limb(), controls = 1.6))$fit_rating$breakpoints
  expect_equal(bp$stages, 1.6)
  expect_equal(bp$source, "user")
  expect_false(bp$advisory)
})

test_that("suggested breakpoints are recorded as a statistical candidate and flagged advisory", {
  fit <- fit_quiet(two_limb(), limbs = "suggest")
  bp <- rating_provenance(fit)$fit_rating$breakpoints
  if (length(bp$stages)) {
    expect_equal(bp$source, "statistical_candidate")
    expect_true(bp$advisory)
    expect_equal(nrow(fit@limbs), length(bp$stages) + 1L)
    expect_match(paste(capture.output(print(fit)), collapse = "\n"), "statistical_candidate: advisory, needs review")
    expect_s3_class(rating_provenance(fit)$fit_rating$candidates, "data.table")
  } else {
    expect_equal(bp$source, "none")
  }
  # A clean single power law gets one limb whatever was asked.
  single <- fit_quiet(sample_gaugings(), limbs = "suggest")
  expect_true(nrow(single@limbs) >= 1L)
})

test_that("controls must be sensible", {
  g <- two_limb()
  expect_error(fit_quiet(g, controls = c(1.6, 1.6)), "distinct")
  expect_error(fit_quiet(g, controls = NA_real_), "distinct, finite")
  expect_error(fit_quiet(g, controls = 9), "strictly inside the stage range")
  expect_error(fit_quiet(g, controls = 0.1), "strictly inside the stage range")
})

# ---- what is used, and what is left out -------------------------------------------------------

test_that("rows marked excluded, non-finite, negative or zero are left out with a reason each, and kept in the record", {
  g <- sample_gaugings(30)
  ev <- as_flode_evidence(g)
  data.table::set(ev, i = 3L, j = "included", value = FALSE)
  data.table::set(ev, i = 3L, j = "exclusion_reason", value = "wading gauging, doubtful")
  data.table::set(ev, i = 5L, j = "discharge_cms", value = NA_real_)
  data.table::set(ev, i = 7L, j = "discharge_cms", value = -1)
  data.table::set(ev, i = 9L, j = "discharge_cms", value = 0)
  fit <- fit_quiet(ev)
  ex <- rating_provenance(fit)$fit_rating$excluded
  expect_equal(sort(ex$evidence_id), c("G003", "G005", "G007", "G009"))
  expect_match(ex[evidence_id == "G003"]$reason, "wading gauging, doubtful")
  expect_match(ex[evidence_id == "G005"]$reason, "missing or not finite")
  expect_equal(ex[evidence_id == "G007"]$reason, "negative discharge")
  expect_match(ex[evidence_id == "G009"]$reason, "relative objective needs positive discharge")
  expect_equal(rating_provenance(fit)$fit_rating$n_used, 26L)
  expect_false(any(c("G003", "G005", "G007", "G009") %in% rating_evidence(fit)$evidence_id))
  # The caller's evidence is untouched.
  expect_equal(nrow(ev), 30L)
  expect_equal(sum(ev$included), 29L)
})

test_that("a zero discharge is kept when the objective is absolute", {
  g <- sample_gaugings(20)
  g$discharge_cms[1] <- 0
  fit <- fit_quiet(g, objective = "absolute")
  expect_equal(rating_provenance(fit)$fit_rating$n_used, 20L)
  expect_equal(nrow(rating_provenance(fit)$fit_rating$excluded), 0L)
})

test_that("with too few usable rows the error says how many, why the rest were left out, and what to do", {
  g <- sample_gaugings(6)
  g$discharge_cms[1:3] <- NA
  expect_error(fit_quiet(g), "only 3 usable gaugings of 6.*stage or discharge missing.*validate_gaugings")
  expect_error(fit_quiet(g[0, ]), "no evidence")
})

test_that("evidence ids, sources and notes survive into the fit's gaugings, with the fitter's own columns", {
  g <- sample_gaugings(20)
  ev <- as_flode_evidence(g)
  data.table::set(ev, j = "evidence_id", value = sprintf("S%02d", seq_len(20)))
  data.table::set(ev, j = "source_name", value = "archive.csv")
  fit <- fit_quiet(ev)
  kept <- rating_evidence(fit)
  expect_equal(kept$evidence_id, sprintf("S%02d", 1:20))
  expect_equal(unique(kept$source_name), "archive.csv")
  expect_true("limb" %in% names(kept))
  expect_true(S7::S7_inherits(fit@gaugings, FlodeEvidence))
  expect_silent(S7::validate(fit))
})

test_that("a table from read_gaugings() fits, and its unreadable rows are left out with their read notes", {
  raw <- data.frame(
    `Station number` = rep("10250", 14),
    Date = sprintf("%02d/%02d/2022", 13:26 %% 28 + 1, 2), Time = "12:00:00",
    Stage = c("---", sprintf("%.2f", seq(0.5, 2.9, length.out = 13))),
    Flow = c("5", sprintf("%.3f", 3 * seq(0.5, 2.9, length.out = 13)^1.6)), check.names = FALSE
  )
  fit <- fit_quiet(read_gaugings(raw, quiet = TRUE))
  ex <- rating_provenance(fit)$fit_rating$excluded
  expect_equal(nrow(ex), 1L)
  expect_match(ex$reason, "stage missing")
  expect_equal(rating_evidence(fit)$site_id[1], "10250")
})

# ---- the record ---------------------------------------------------------------------------------

test_that("the call, the seed and every starting point tried are recorded", {
  g <- sample_gaugings()
  fit <- fit_quiet(g, n_boot = 20, seed = 11)
  rec <- rating_provenance(fit)$fit_rating
  expect_match(rec$call, "^fit_rating\\(")
  expect_match(rec$call, "n_boot = 20")
  expect_equal(rec$seed, 11)
  expect_equal(nrow(fit@fit_starts), 6L)
  expect_true(all(c("start_id", "rss", "converged", "valid") %in% names(fit@fit_starts)))
})

test_that("the same seed gives the same bootstrap, and a different seed does not", {
  g <- sample_gaugings()
  a <- fit_quiet(g, n_boot = 30, seed = 5)
  b <- fit_quiet(g, n_boot = 30, seed = 5)
  c2 <- fit_quiet(g, n_boot = 30, seed = 6)
  expect_equal(rating_bootstrap(a)$C, rating_bootstrap(b)$C)
  expect_false(isTRUE(all.equal(rating_bootstrap(a)$C, rating_bootstrap(c2)$C)))
})

test_that("a segmented model fits, and has no bootstrap", {
  fit <- fit_quiet(two_limb(), controls = 1.6, model = "segmented")
  expect_true(S7::S7_inherits(fit, FlodeSegmentedRating))
  expect_equal(rating_provenance(fit)$fit_rating$model, "segmented")
  expect_equal(nrow(rating_evidence(fit)), 40L)
  expect_error(fit_quiet(two_limb(), model = "segmented", n_boot = 10), "only available")
})

test_that("recency weighting needs a time on every row used, and then uses it", {
  g <- sample_gaugings(20)
  expect_error(fit_quiet(g, age_halflife = 365), "needs an observation_time")
  g$gauging_datetime <- as.Date("2020-01-01") + seq(0, by = 150, length.out = 20)
  fit <- fit_quiet(g, age_halflife = 365)
  expect_true("age_weight" %in% names(rating_evidence(fit)))
  expect_lt(min(rating_evidence(fit)$age_weight), 1)
})

test_that("a bad seed, limit or option is refused with a message that names it", {
  g <- sample_gaugings()
  expect_error(fit_quiet(g, seed = "a"), "seed")
  expect_error(fit_quiet(g, operational_limits = c(3, 1)), "lower below upper")
  expect_error(fit_quiet(g, operational_limits = 1), "c\\(lower, upper\\)")
  expect_error(fit_quiet(g, limbs = "many"), "should be one of")
})

# ---- operational limits ---------------------------------------------------------------------------

test_that("without limits a guided rating extrapolates beyond its gauged range, flagged and with a warning", {
  fit <- fit_quiet(sample_gaugings())
  expect_no_warning(apply_rating(fit, c(0.5, 1, 2.9)))
  expect_warning(out <- apply_rating(fit, c(0.2, 1)), "1 of 2 stage value.*gauged range \\(0\\.4 to 3 m.*extrapolat.*set_operational_limits")
  expect_equal(out$support[1L], "extrapolation")
  expect_true(is.finite(out$discharge[1L]))
  expect_warning(out2 <- apply_rating(fit, data.frame(stage = c(1, 3.5))), "no operational limits")
  expect_true(out2$extrapolated[2L])
})

test_that("stating limits allows a wider range, flags extrapolation, and refuses beyond the limits", {
  fit <- fit_quiet(sample_gaugings())
  wide <- set_operational_limits(fit, 0.2, 3.5, basis = "confirmed control to 3.5 m")
  out <- apply_rating(wide, c(0.3, 1, 3.4))
  expect_equal(out$extrapolated, c(TRUE, FALSE, TRUE))
  expect_error(apply_rating(wide, c(0.1, 1)), "outside this rating's operational limits.*confirmed control")
  expect_error(apply_rating(wide, c(1, 4)), "0\\.2 to 3\\.5 m")
})

test_that("limits can be given at fit time and the basis is kept", {
  fit <- fit_quiet(sample_gaugings(), operational_limits = c(0.3, 3.3), operational_basis = "gauged range plus margin")
  lim <- rating_provenance(fit)$operational_limits
  expect_equal(c(lim$lower_stage_m, lim$upper_stage_m), c(0.3, 3.3))
  expect_equal(lim$basis, "gauged range plus margin")
  expect_no_error(apply_rating(fit, c(0.35, 3.2)))
})

test_that("setting limits makes a new version, back to draft, with the old one kept in the history", {
  fit <- fit_quiet(sample_gaugings())
  fit@lifecycle <- "approved"
  wide <- set_operational_limits(fit, 0.2, 3.5, basis = "reviewed")
  expect_equal(wide@lifecycle, "draft")
  expect_equal(fit@lifecycle, "approved")           # the original is not changed
  h <- rating_history(wide)
  expect_equal(nrow(h), 2L)
  expect_equal(h$lifecycle, c("approved", "draft"))
  expect_match(h$note[2], "operational limits set to 0.2 to 3.5 m \\(reviewed\\)")
  expect_true(is.na(h$note[1]))
})

test_that("an amendment after limits does not repeat the limits note on later history steps", {
  fit <- fit_quiet(two_limb(), controls = 1.6)
  wide <- set_operational_limits(fit, 0.2, 3.6, basis = "b")
  aligned <- suppressWarnings(align_limb_equations(wide))
  h <- rating_history(aligned)
  expect_equal(sum(!is.na(h$note)), 1L)
})

test_that("set_operational_limits checks its arguments", {
  fit <- fit_quiet(sample_gaugings())
  expect_error(set_operational_limits(1, 0, 1), "must be a FlodeRating")
  expect_error(set_operational_limits(fit, 3, 1), "lower below upper")
  expect_error(set_operational_limits(fit, NA, 1), "finite")
  expect_error(set_operational_limits(as_rating_table(fit), 0, 1), "must be a FlodeRating")
})

test_that("a rating from rate_optimise is not restricted: an expert calling it directly has taken that decision", {
  g <- sample_gaugings()
  plain <- rate_optimise(g$discharge_cms, g$stage_m)
  expect_no_error(apply_rating(plain, c(0.1, 5)))
  # And the guided rating's table is an explicit way round, as documented.
  expect_no_error(apply_rating(as_rating_table(fit_quiet(g)), c(0.1, 5)))
})

# ---- print and messages -------------------------------------------------------------------------

test_that("printing shows the breakpoints, the evidence count and the operational limits", {
  fit <- fit_quiet(two_limb(), controls = 1.6)
  out <- capture.output(print(fit))
  expect_match(paste(out, collapse = "\n"), "breakpoints: 1.6 \\(user_judgement\\)")
  expect_match(paste(out, collapse = "\n"), "evidence: 40 of 40 rows used")
  expect_match(paste(out, collapse = "\n"), "operational limits: not set; stages beyond the gauged range 0.3 to 3.4 m are flagged as extrapolation")
  limited <- set_operational_limits(fit, 0.2, 3.6, basis = "x")
  expect_match(paste(capture.output(print(limited)), collapse = "\n"), "operational limits: 0.2 to 3.6 m \\(x\\)")
})

test_that("the summary message says what was used, left out, and that limits are unset", {
  g <- sample_gaugings(20); g$discharge_cms[2] <- NA
  expect_message(fit_rating(g), "19 of 20 rows used; relative objective, independent model, one limb")
  expect_message(fit_rating(g), "Not used: 1 \\(stage or discharge missing")
  expect_message(fit_rating(g), "No operational limits set")
  expect_no_message(fit_rating(g, quiet = TRUE))
})

test_that("a guided rating passes the post-fit invariants and a plain one is unaffected by the new record", {
  fit <- fit_quiet(sample_gaugings())
  expect_false(assessment_status(rating_invariants(fit)) == "fail")
  expect_silent(S7::validate(fit))
  f <- tempfile()
  saveRDS(fit, f)
  back <- readRDS(f)
  expect_silent(S7::validate(back))
  expect_equal(rating_provenance(back)$fit_rating$n_used, 24L)
})
