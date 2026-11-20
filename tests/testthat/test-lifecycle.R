# set_lifecycle() and rating_lifecycle(): who, when and why, and the rules.

lc_fit <- function() {
  set.seed(1)
  st <- seq(0.3, 3, length.out = 25)
  fit_rating(data.frame(stage_m = st, discharge_cms = 3 * st^1.6 * exp(rnorm(25, sd = 0.03))), quiet = TRUE)
}
to_review <- function(x, by = "A. Analyst") set_lifecycle(x, "under_review", by = by, reason = "ready for review")

test_that("a rating moves draft to under review to approved, recording who, when and why", {
  fit <- lc_fit()
  expect_equal(fit@lifecycle, "draft")
  expect_equal(nrow(rating_lifecycle(fit)), 0L)
  at <- as.POSIXct("2026-11-20 10:30:00", tz = "UTC")
  r <- set_lifecycle(fit, "under_review", by = "A. Analyst", reason = "fitted from the 2024 gaugings", at = at)
  a <- set_lifecycle(r, "approved", by = "B. Reviewer", reason = "checked assessment and sensitivity")
  expect_equal(a@lifecycle, "approved")
  log <- rating_lifecycle(a)
  expect_named(log, c("from", "to", "by", "reason", "at"))
  expect_equal(log$from, c("draft", "under_review"))
  expect_equal(log$to, c("under_review", "approved"))
  expect_equal(log$by, c("A. Analyst", "B. Reviewer"))
  expect_equal(log$at[1L], at)
  expect_s3_class(log$at, "POSIXct")
  expect_match(log$reason[1L], "2024 gaugings")
})

test_that("the original rating is not altered, and each change is a step in the history", {
  fit <- lc_fit()
  before <- fit
  r <- to_review(fit)
  expect_equal(fit, before, tolerance = 0)
  expect_equal(fit@lifecycle, "draft")
  a <- set_lifecycle(r, "approved", by = "B. Reviewer", reason = "ok")
  h <- rating_history(a)
  expect_equal(h$lifecycle, c("draft", "under_review", "approved"))
  expect_match(h$note[2L], "lifecycle: draft to under_review by A. Analyst")
  expect_match(h$note[3L], "under_review to approved by B. Reviewer")
})

test_that("nothing in the package approves a rating by itself", {
  fit <- lc_fit()
  a <- assess_rating(fit, reference_time = as.POSIXct("2025-01-01", tz = "UTC"))
  f <- tempfile("lc_")
  export_rating(fit, a, path = f)
  back <- import_rating(f)$rating
  invisible(compare_ratings(as_rating_table(fit), as_rating_table(back)))
  invisible(set_operational_limits(fit, 0.25, 3.5, basis = "b"))
  expect_equal(fit@lifecycle, "draft")
  expect_equal(back@lifecycle, "draft")
  expect_equal(set_operational_limits(fit, 0.25, 3.5, basis = "b")@lifecycle, "draft")
})

test_that("approval must follow a review", {
  expect_error(set_lifecycle(lc_fit(), "approved", by = "B. Reviewer", reason = "x"),
               "draft cannot go to approved.*under_review")
})

test_that("the person who put a rating under review cannot approve it, however the name is written", {
  r <- to_review(lc_fit(), by = "A. Analyst")
  expect_error(set_lifecycle(r, "approved", by = "A. Analyst", reason = "ok"), "cannot also approve it")
  expect_error(set_lifecycle(r, "approved", by = "  a. analyst ", reason = "ok"), "cannot also approve it")
})

test_that("self-approval can be allowed, and is then written into the record", {
  r <- to_review(lc_fit(), by = "A. Analyst")
  a <- set_lifecycle(r, "approved", by = "A. Analyst", reason = "only person available", allow_self_approval = TRUE)
  expect_equal(a@lifecycle, "approved")
  expect_match(rating_lifecycle(a)$reason[2L], "self-approval allowed")
  # a different person needs no such note
  b <- set_lifecycle(r, "approved", by = "B. Reviewer", reason = "ok")
  expect_no_match(rating_lifecycle(b)$reason[2L], "self-approval")
})

test_that("a rating that fails its own validity checks cannot be approved", {
  fit <- lc_fit()
  bad <- S7::`prop<-`(fit, "limbs", check = FALSE, value = data.table::copy(fit@limbs)[, C := -1])
  expect_gt(sum(assessment_checks(rating_invariants(bad))$status == "fail"), 0L)
  r <- S7::`prop<-`(set_lifecycle(fit, "under_review", by = "A", reason = "r"), "limbs", check = FALSE,
                    value = data.table::copy(fit@limbs)[, C := -1])
  expect_error(set_lifecycle(r, "approved", by = "B", reason = "ok"), "fails its own validity checks")
})

test_that("only the permitted transitions work, and final states are final", {
  fit <- lc_fit()
  expect_error(set_lifecycle(fit, "draft", by = "A", reason = "r"), "already draft")
  expect_error(set_lifecycle(fit, "superseded", by = "A", reason = "r"), "draft cannot go to superseded")
  r <- to_review(fit)
  expect_equal(set_lifecycle(r, "draft", by = "B", reason = "returned for rework")@lifecycle, "draft")
  a <- set_lifecycle(r, "approved", by = "B", reason = "ok")
  expect_error(set_lifecycle(a, "draft", by = "B", reason = "r"), "approved cannot go to draft")
  expect_equal(set_lifecycle(a, "under_review", by = "C", reason = "re-review after 12 months")@lifecycle, "under_review")
  s <- set_lifecycle(a, "superseded", by = "B", reason = "replaced by the 2025 rating")
  expect_error(set_lifecycle(s, "approved", by = "B", reason = "r"), "superseded rating is final")
  w <- set_lifecycle(fit, "withdrawn", by = "A", reason = "wrong station")
  expect_error(set_lifecycle(w, "draft", by = "A", reason = "r"), "withdrawn rating is final")
})

test_that("who and why are required for every change", {
  fit <- lc_fit()
  expect_error(set_lifecycle(fit, "under_review", reason = "r"), "by must be")
  expect_error(set_lifecycle(fit, "under_review", by = "A"), "reason must be")
  expect_error(set_lifecycle(fit, "under_review", by = "", reason = "r"), "by must be")
  expect_error(set_lifecycle(fit, "under_review", by = "A", reason = "   "), "reason must be")
  expect_error(set_lifecycle(fit, "under_review", by = NA_character_, reason = "r"), "by must be")
  expect_error(set_lifecycle(fit, "under_review", by = c("A", "B"), reason = "r"), "by must be")
})

test_that("other arguments and inputs are checked", {
  fit <- lc_fit()
  expect_error(set_lifecycle(fit, "finished", by = "A", reason = "r"), "to must be one of")
  expect_error(set_lifecycle(fit, by = "A", reason = "r"), "to must be one of")
  expect_error(set_lifecycle(fit, "under_review", by = "A", reason = "r", at = "yesterday"), "at must be a single time")
  expect_error(set_lifecycle(fit, "under_review", by = "A", reason = "r", allow_self_approval = NA), "allow_self_approval")
  expect_error(set_lifecycle(1, "under_review", by = "A", reason = "r"), "x must be a FlodeRating")
  expect_error(set_lifecycle(as_rating_table(fit), "under_review", by = "A", reason = "r"), "nowhere to record")
  expect_error(rating_lifecycle(1), "x must be a FlodeRating")
  expect_equal(nrow(rating_lifecycle(as_rating_table(fit))), 0L)
})

test_that("a segmented rating can be moved on too", {
  set.seed(3)
  h <- round(seq(0.3, 3.4, length.out = 40), 3)
  q <- ifelse(h < 1.6, 3.2 * h^1.6, 3.2 * 1.6^1.6 * (h / 1.6)^2.1) * exp(rnorm(40, sd = 0.03))
  seg <- fit_rating(data.frame(stage_m = h, discharge_cms = q), controls = 1.6, model = "segmented", quiet = TRUE)
  r <- set_lifecycle(seg, "under_review", by = "A", reason = "r")
  expect_equal(r@lifecycle, "under_review")
  expect_equal(rating_lifecycle(r)$by, "A")
})

test_that("amending an approved rating makes a new draft, and the records stay", {
  a <- set_lifecycle(to_review(lc_fit()), "approved", by = "B. Reviewer", reason = "ok")
  amended <- set_operational_limits(a, 0.25, 3.5, basis = "survey")
  expect_equal(amended@lifecycle, "draft")
  expect_equal(nrow(rating_lifecycle(amended)), 2L)
  h <- rating_history(amended)
  expect_equal(h$lifecycle[(nrow(h) - 1L):nrow(h)], c("approved", "draft"))
})

test_that("printing says who last moved the lifecycle, and stays quiet otherwise", {
  fit <- lc_fit()
  expect_no_match(paste(capture.output(print(fit)), collapse = "\n"), " by ")
  a <- set_lifecycle(to_review(fit), "approved", by = "B. Reviewer", reason = "ok",
                     at = as.POSIXct("2026-11-20", tz = "UTC"))
  expect_match(paste(capture.output(print(a)), collapse = "\n"), "approved by B. Reviewer on 2026-11-20")
  amended <- set_operational_limits(a, 0.25, 3.5, basis = "survey")
  expect_no_match(paste(capture.output(print(amended)), collapse = "\n"), "approved by")
})

test_that("an export carries the record, a draft's export carries none, and import returns it intact", {
  fit <- lc_fit()
  f0 <- tempfile("lc_"); export_rating(fit, path = f0)
  expect_false("lifecycle.csv" %in% list.files(f0))
  a <- set_lifecycle(to_review(fit), "approved", by = "B. Reviewer", reason = "ok")
  f1 <- tempfile("lc_"); export_rating(a, path = f1)
  expect_true("lifecycle.csv" %in% list.files(f1))
  csv <- data.table::fread(file.path(f1, "lifecycle.csv"))
  expect_equal(csv$by, c("A. Analyst", "B. Reviewer"))
  back <- import_rating(f1)$rating
  expect_equal(rating_lifecycle(back), rating_lifecycle(a), tolerance = 0)
  expect_equal(back@lifecycle, "approved")
})

test_that("the report names who changed the lifecycle", {
  testthat::skip_if_not_installed("rmarkdown")
  testthat::skip_if_not_installed("knitr")
  testthat::skip_if_not(rmarkdown::pandoc_available(), "pandoc is not available")
  page <- function(x) {
    f <- tempfile(fileext = ".html"); rating_report(x, path = f)
    raw <- paste(readLines(f, warn = FALSE), collapse = "\n")
    raw <- gsub("(?s)<script.*?</script>", "", raw, perl = TRUE); raw <- gsub("(?s)<style.*?</style>", "", raw, perl = TRUE)
    gsub("\\s+", " ", gsub("<[^>]+>", " ", raw))
  }
  fit <- lc_fit()
  expect_no_match(page(fit), "Who changed the lifecycle")
  a <- set_lifecycle(to_review(fit), "approved", by = "B. Reviewer", reason = "checked the sensitivity tests")
  txt <- page(a)
  expect_match(txt, "Who changed the lifecycle")
  expect_match(txt, "B. Reviewer")
  expect_match(txt, "checked the sensitivity tests")
  expect_match(txt, "Lifecycle approved")
})
