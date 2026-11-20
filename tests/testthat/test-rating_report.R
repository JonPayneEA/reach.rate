# rating_report(): a page a reviewer can read, drawn from stored objects only.

skip_if_no_pandoc <- function() {
  testthat::skip_if_not_installed("rmarkdown")
  testthat::skip_if_not_installed("knitr")
  testthat::skip_if_not(rmarkdown::pandoc_available(), "pandoc is not available")
}
report_fit <- function() {
  set.seed(1)
  h <- round(seq(0.3, 3.2, length.out = 30), 3)
  q <- 3 * h^1.6 * exp(rnorm(30, sd = 0.03))
  q[5] <- 0
  fit_rating(data.frame(stage_m = h, discharge_cms = q), quiet = TRUE)
}
fixed_time <- as.POSIXct("2025-01-01", tz = "UTC")
page_text <- function(file) {
  raw <- paste(readLines(file, warn = FALSE), collapse = "\n")
  raw <- gsub("(?s)<script.*?</script>", "", raw, perl = TRUE)
  raw <- gsub("(?s)<style.*?</style>", "", raw, perl = TRUE)
  raw <- gsub("<img[^>]*>", "[IMG]", raw, perl = TRUE)
  gsub("\\s+", " ", gsub("<[^>]+>", " ", raw))
}

test_that("a report is written and says what it is not", {
  skip_if_no_pandoc()
  fit <- report_fit()
  a <- assess_rating(fit, reference_time = fixed_time)
  f <- tempfile(fileext = ".html")
  out <- rating_report(fit, a, path = f)
  expect_true(file.exists(f))
  expect_equal(out, normalizePath(f))
  txt <- page_text(f)
  expect_match(txt, "does not approve it")
  expect_match(txt, "nothing was refitted")
  expect_match(txt, "Lifecycle draft")
})

test_that("the report carries the rating's own numbers, evidence, and every check that did not pass", {
  skip_if_no_pandoc()
  fit <- report_fit()
  a <- assess_rating(fit, reference_time = fixed_time)
  f <- tempfile(fileext = ".html")
  rating_report(fit, a, path = f)
  txt <- page_text(f)
  limb <- rating_limbs(fit)
  expect_match(txt, format(round(limb$C[1L], 4), nsmall = 4), fixed = TRUE)
  ck <- assessment_checks(a)
  for (id in ck$check_id[ck$status != "pass"]) expect_match(txt, id, fixed = TRUE)
  expect_match(txt, "30 observations read; 29 used in the fit; 1 left out")
  ex <- rating_provenance(fit)$fit_rating$excluded
  expect_match(txt, ex$evidence_id[1L], fixed = TRUE)
  expect_match(txt, "zero discharge")
  expect_match(txt, "no overall score")
  expect_match(txt, "best-endeavours defaults, not Environment Agency policy")
  expect_match(txt, "\\[IMG\\]")
})

test_that("without an assessment it says so, and the lifecycle is reported as it is", {
  skip_if_no_pandoc()
  fit <- report_fit()
  fit@lifecycle <- "under_review"
  f <- tempfile(fileext = ".html")
  rating_report(fit, path = f)
  txt <- page_text(f)
  expect_match(txt, "No assessment was supplied")
  expect_match(txt, "no assessment supplied")
  expect_match(txt, "Lifecycle under_review")
})

test_that("the same report comes from an exported folder as from the live session", {
  skip_if_no_pandoc()
  fit <- report_fit()
  a <- assess_rating(fit, reference_time = fixed_time)
  folder <- tempfile("exp_")
  export_rating(fit, a, path = folder)
  f1 <- tempfile(fileext = ".html"); f2 <- tempfile(fileext = ".html")
  rating_report(fit, a, path = f1)
  rating_report(folder, path = f2)
  expect_equal(page_text(f2), page_text(f1))
})

test_that("reporting does not change the rating", {
  skip_if_no_pandoc()
  fit <- report_fit()
  before <- fit
  rating_report(fit, path = tempfile(fileext = ".html"))
  expect_equal(fit, before, tolerance = 0)
  expect_equal(fit@lifecycle, "draft")
})

test_that("an equation table reports, and says it holds no gaugings", {
  skip_if_no_pandoc()
  tab <- as_rating_table(report_fit())
  f <- tempfile(fileext = ".html")
  rating_report(tab, path = f)
  expect_match(page_text(f), "holds no gaugings")
})

test_that("the support table does not print the numerical range as a huge number", {
  skip_if_no_pandoc()
  f <- tempfile(fileext = ".html")
  rating_report(report_fit(), path = f)
  expect_match(page_text(f), "no practical limit")
  expect_no_match(page_text(f), "e\\+181")
})

test_that("an existing file is kept unless overwrite is TRUE", {
  skip_if_no_pandoc()
  fit <- report_fit()
  f <- tempfile(fileext = ".html")
  rating_report(fit, path = f)
  expect_error(rating_report(fit, path = f), "already exists")
  expect_no_error(rating_report(fit, path = f, overwrite = TRUE))
})

test_that("arguments are checked", {
  skip_if_no_pandoc()
  fit <- report_fit()
  expect_error(rating_report(1), "x must be a FlodeRating")
  expect_error(rating_report(fit, assessment = 1), "assessment must be a FlodeAssessment")
  expect_error(rating_report(fit, path = NA_character_), "path must be")
  expect_error(rating_report(fit, title = 1), "title must be")
  expect_error(rating_report(fit, overwrite = NA), "overwrite must be")
  expect_error(rating_report(file.path(tempdir(), "nowhere")), "is not a folder")
  expect_error(rating_report(c("a", "b")), "single path")
})
