# Tranche B5: breakpoint candidates, and where an adopted breakpoint came from.

bp_data <- function(n = 50, seed = 7) {
  set.seed(seed)
  h <- seq(0.3, 3.5, length.out = n)
  q <- 4 * pmax(h - 0.1, 0)^1.55 * (pmax(h - 1.6, 0) + 1)^0.9 * (pmax(h - 2.4, 0) + 1)^1.1 * exp(rnorm(n, sd = 0.03))
  data.frame(stage_m = h, discharge_cms = q)
}

# ---- the candidate table -----------------------------------------------------------------------------------

test_that("each candidate carries the evidence on each side, by hand", {
  g <- bp_data()
  cand <- suggest_breakpoints(g$discharge_cms, g$stage_m, max_breaks = 1L)
  expect_true(all(c("candidate_stage", "score", "improvement", "n_obs_lower", "n_obs_upper", "lower_min_m", "lower_max_m",
                    "upper_min_m", "upper_max_m", "fit_status", "failure_reason", "round", "rank", "selected") %in% names(cand)))
  ok <- cand[fit_status == "ok"]
  expect_gt(nrow(ok), 10L)
  for (i in c(1, nrow(ok) %/% 2, nrow(ok))) {
    bp <- ok$candidate_stage[i]
    # A gauging exactly on the candidate belongs to the lower limb, as when fitting.
    lower <- g$stage_m[g$stage_m <= bp]
    upper <- g$stage_m[g$stage_m > bp]
    expect_equal(ok$n_obs_lower[i], length(lower))
    expect_equal(ok$n_obs_upper[i], length(upper))
    expect_equal(c(ok$lower_min_m[i], ok$lower_max_m[i]), range(lower))
    expect_equal(c(ok$upper_min_m[i], ok$upper_max_m[i]), range(upper))
  }
  expect_true(all(is.na(ok$failure_reason)))
})

test_that("a candidate with too few gaugings on a side is listed with the numbers, not dropped", {
  g <- bp_data()
  cand <- suggest_breakpoints(g$discharge_cms, g$stage_m, max_breaks = 1L, min_obs_per_side = 8L)
  few <- cand[fit_status == "insufficient_obs"]
  expect_gt(nrow(few), 0L)
  expect_match(few$failure_reason[1], "^fewer than 8 gaugings on a side \\(\\d+ below, \\d+ above\\)$")
  expect_false(any(few$selected))
  # The evidence ranges are still reported for it.
  expect_false(anyNA(few$lower_min_m[!is.na(few$n_obs_lower)]))
})

test_that("a candidate whose fit cannot be made is listed with the error, and the rest are still scored", {
  g <- bp_data()
  real <- rate_optimise
  testthat::local_mocked_bindings(rate_optimise = function(discharge_cms, stage_m, ..., control = NULL) {
    if (!is.null(control) && any(control > 2.9)) stop("the fit would not run")
    real(discharge_cms, stage_m, ..., control = control)
  })
  cand <- suggest_breakpoints(g$discharge_cms, g$stage_m, max_breaks = 1L)
  failed <- cand[fit_status == "failed"]
  # Every failure carries a reason. Those at the top are the mocked error; any
  # others are the fitter's own (a limb left with fewer than three gaugings).
  expect_false(anyNA(failed$failure_reason))
  expect_equal(unique(failed[candidate_stage > 2.9]$failure_reason), "the fit would not run")
  expect_true(any(grepl("each limb needs at least 3 gaugings", failed$failure_reason)))
  expect_true(all(is.na(failed$score)) && all(is.na(failed$lower_min_m)))
  expect_gt(sum(cand$fit_status == "ok"), 10L)
})

test_that("the table is documented as candidates, not findings", {
  src <- testthat::test_path("..", "..", "R", "rate_optimise.R")
  skip_if_not(file.exists(src), "source not available (installed package)")
  txt <- paste(readLines(src, warn = FALSE), collapse = "\n")
  flat <- gsub("\\s+", " ", gsub("#'", " ", txt))
  skip_if(!grepl("Puts forward \\*\\*candidates\\*\\*", flat), "source not available")
  expect_match(flat, "It is not a finding")
  expect_match(flat, "it cannot know where a channel control changes")
})

# ---- origins ----------------------------------------------------------------------------------------------------

test_that("the vocabulary is the seven origins, exported", {
  expect_equal(breakpoint_origins(), c("field_evidence", "cross_section", "structure_geometry", "user_judgement",
                                       "statistical_candidate", "existing_rating", "other"))
})

test_that("a breakpoint you supply is recorded as user_judgement unless you say otherwise", {
  g <- bp_data()
  bp <- rating_provenance(fit_rating(g, controls = 1.6, quiet = TRUE))$fit_rating$breakpoints
  expect_equal(bp$origin, "user_judgement")
  expect_false(bp$advisory)
  bp2 <- rating_provenance(fit_rating(g, controls = 1.6, breakpoint_origin = "field_evidence", quiet = TRUE))$fit_rating$breakpoints
  expect_equal(bp2$origin, "field_evidence")
})

test_that("each breakpoint can have its own origin, kept with its stage when the stages are reordered", {
  g <- bp_data()
  fit <- fit_rating(g, controls = c(2.4, 1.6), breakpoint_origin = c("structure_geometry", "cross_section"), quiet = TRUE)
  bp <- rating_provenance(fit)$fit_rating$breakpoints
  expect_equal(bp$stages, c(1.6, 2.4))
  expect_equal(bp$origin, c("cross_section", "structure_geometry"))
  out <- paste(capture.output(print(fit)), collapse = "\n")
  expect_match(out, "breakpoints: 1.6, 2.4 \\(cross_section; structure_geometry\\)")
})

test_that("suggested breakpoints are always statistical candidates, and a mixed set is advisory", {
  g <- bp_data()
  sug <- fit_rating(g, limbs = "suggest", quiet = TRUE)
  bp <- rating_provenance(sug)$fit_rating$breakpoints
  expect_true(length(bp$stages) >= 1L)
  expect_true(all(bp$origin == "statistical_candidate"))
  expect_true(bp$advisory)
  # Adopting a candidate on field evidence changes its recorded origin.
  stage <- bp$stages[1]
  adopted <- fit_rating(g, controls = stage, breakpoint_origin = "field_evidence", quiet = TRUE)
  expect_false(rating_provenance(adopted)$fit_rating$breakpoints$advisory)
  # One statistical candidate among others still makes the rating advisory.
  mixed <- fit_rating(g, controls = c(1.6, 2.4), breakpoint_origin = c("field_evidence", "statistical_candidate"), quiet = TRUE)
  expect_true(rating_provenance(mixed)$fit_rating$breakpoints$advisory)
})

test_that("an unknown origin, or the wrong number of them, is refused with the list of valid ones", {
  g <- bp_data()
  expect_error(fit_rating(g, controls = 1.6, breakpoint_origin = "hunch", quiet = TRUE),
               "must be one value, or one per breakpoint, from: field_evidence.*Not recognised: hunch")
  expect_error(fit_rating(g, controls = c(1.6, 2.4), breakpoint_origin = c("other", "other", "other"), quiet = TRUE),
               "one per breakpoint")
  expect_error(fit_rating(g, controls = 1.6, breakpoint_origin = character(0), quiet = TRUE), "one per breakpoint")
})

test_that("the origin appears in the fit message, and a plain one-limb fit records none", {
  g <- bp_data()
  expect_message(fit_rating(g, controls = 1.6, breakpoint_origin = "cross_section"), "breakpoints 1.6, cross_section")
  # A single limb fitted to three-regime data stops at its iteration limit, and says so.
  expect_length(rating_provenance(suppressWarnings(fit_rating(g, quiet = TRUE)))$fit_rating$breakpoints$origin, 0L)
})

test_that("the assessment still reports on a rating whose breakpoints have origins", {
  g <- bp_data()
  a <- assess_rating(fit_rating(g, controls = 1.6, breakpoint_origin = "field_evidence", quiet = TRUE),
                     reference_time = as.POSIXct("2026-01-01", tz = "UTC"))
  expect_equal(assessment_checks(a)[check_id == "fit_recorded"]$status, "pass")
})
