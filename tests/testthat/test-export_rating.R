# export_rating() and import_rating(): a folder a reviewer can read, and an
# exact way back into R.

sample_fit <- function(n = 30, seed = 1) {
  set.seed(seed)
  h <- round(seq(0.3, 3.2, length.out = n), 3)
  fit_rating(data.frame(stage_m = h, discharge_cms = 3 * h^1.6 * exp(rnorm(n, sd = 0.03))), quiet = TRUE)
}
fixed_time <- as.POSIXct("2025-01-01", tz = "UTC")
tmp_dir <- function() tempfile("export_")

test_that("an exported rating comes back as the same rating", {
  fit <- sample_fit()
  a <- assess_rating(fit, reference_time = fixed_time)
  p <- tmp_dir()
  out <- export_rating(fit, a, path = p)
  back <- import_rating(p)
  expect_equal(back$rating, fit, tolerance = 0)
  expect_equal(back$assessment, a, tolerance = 0)
  expect_equal(apply_rating(back$rating, c(0.5, 1.5, 2.5)), apply_rating(fit, c(0.5, 1.5, 2.5)))
  expect_equal(rating_limbs(back$rating), rating_limbs(fit))
  expect_equal(rating_coefficients(back$rating), rating_coefficients(fit))
  expect_equal(rating_history(back$rating), rating_history(fit))
  expect_equal(rating_provenance(back$rating), rating_provenance(fit))
  expect_equal(back$rating@lifecycle, fit@lifecycle)
  expect_equal(back$manifest$file, out$files[file != "manifest.csv"]$file)
})

test_that("the folder holds the record, the tables, a README and a manifest", {
  fit <- sample_fit()
  a <- assess_rating(fit, reference_time = fixed_time)
  p <- tmp_dir()
  out <- export_rating(fit, a, path = p)
  expect_setequal(list.files(p), c("rating.rds", "assessment.rds", "limbs.csv", "coefficients.csv", "evidence.csv",
                                   "history.csv", "support.csv", "assessment_checks.csv", "README.txt", "manifest.csv"))
  expect_true(all(c("file", "description", "bytes", "md5") %in% names(out$files)))
  mf <- data.table::fread(file.path(p, "manifest.csv"))
  expect_false("manifest.csv" %in% mf$file)
  expect_equal(mf$md5, unname(tools::md5sum(file.path(p, mf$file))))
})

test_that("the CSV tables match the accessors", {
  fit <- sample_fit()
  a <- assess_rating(fit, reference_time = fixed_time)
  p <- tmp_dir()
  export_rating(fit, a, path = p)
  ev <- data.table::fread(file.path(p, "evidence.csv"))
  expect_equal(nrow(ev), nrow(rating_evidence(fit)))
  expect_equal(ev$evidence_id, rating_evidence(fit)$evidence_id)
  expect_equal(ev$stage_m, rating_evidence(fit)$stage_m)
  expect_false("metadata" %in% names(ev))
  ck <- data.table::fread(file.path(p, "assessment_checks.csv"))
  expect_equal(nrow(ck), nrow(assessment_checks(a)))
  expect_equal(ck$check_id, assessment_checks(a)$check_id)
  lm <- data.table::fread(file.path(p, "limbs.csv"))
  expect_equal(nrow(lm), nrow(rating_limbs(fit)))
})

test_that("the README says what was dropped, the lifecycle and that export does not approve", {
  fit <- sample_fit()
  p <- tmp_dir()
  export_rating(fit, path = p)
  txt <- paste(readLines(file.path(p, "README.txt")), collapse = "\n")
  expect_match(txt, "Lifecycle:\\s+draft")
  expect_match(txt, "does not approve")
  expect_match(txt, "metadata")
  expect_match(txt, "no assessment was exported")
  expect_match(txt, "import_rating")
})

test_that("exporting does not change the rating or move its lifecycle", {
  fit <- sample_fit()
  before <- fit
  export_rating(fit, path = tmp_dir())
  expect_equal(fit, before, tolerance = 0)
  expect_equal(fit@lifecycle, "draft")
  reviewed <- fit
  reviewed@lifecycle <- "under_review"
  p <- tmp_dir()
  export_rating(reviewed, path = p)
  expect_equal(import_rating(p)$rating@lifecycle, "under_review")
})

test_that("without an assessment there is no assessment file and import returns NULL for it", {
  fit <- sample_fit()
  p <- tmp_dir()
  export_rating(fit, path = p)
  expect_false(any(c("assessment.rds", "assessment_checks.csv") %in% list.files(p)))
  expect_null(import_rating(p)$assessment)
})

test_that("a table and a segmented rating export, and a table says it holds no gaugings", {
  fit <- sample_fit()
  tab <- as_rating_table(fit)
  p <- tmp_dir()
  export_rating(tab, path = p)
  expect_false("evidence.csv" %in% list.files(p))
  expect_match(paste(readLines(file.path(p, "README.txt")), collapse = "\n"), "evidence.csv not written")
  back <- import_rating(p)$rating
  expect_equal(apply_rating(back, c(1, 2)), apply_rating(tab, c(1, 2)))

  set.seed(3)
  h <- round(seq(0.3, 3.4, length.out = 40), 3)
  q <- ifelse(h < 1.6, 3.2 * h^1.6, 3.2 * 1.6^1.6 * (h / 1.6)^2.1) * exp(rnorm(40, sd = 0.03))
  seg <- fit_rating(data.frame(stage_m = h, discharge_cms = q), controls = 1.6, model = "segmented", quiet = TRUE)
  p2 <- tmp_dir()
  export_rating(seg, path = p2)
  expect_equal(apply_rating(import_rating(p2)$rating, c(1, 2.5)), apply_rating(seg, c(1, 2.5)))
})

test_that("an existing export is not overwritten unless asked, and only our own files are replaced", {
  fit <- sample_fit()
  p <- tmp_dir()
  export_rating(fit, path = p)
  expect_error(export_rating(fit, path = p), "already holds files.*overwrite = TRUE")
  writeLines("mine", file.path(p, "my_notes.txt"))
  expect_no_error(export_rating(fit, path = p, overwrite = TRUE))
  expect_true(file.exists(file.path(p, "my_notes.txt")))
  expect_equal(readLines(file.path(p, "my_notes.txt")), "mine")
})

test_that("a changed file is reported by name and not read", {
  fit <- sample_fit()
  p <- tmp_dir()
  export_rating(fit, path = p)
  f <- file.path(p, "rating.rds")
  bytes <- readBin(f, "raw", file.size(f))
  bytes[length(bytes) %/% 2L] <- as.raw(bitwXor(as.integer(bytes[length(bytes) %/% 2L]), 255L))
  writeBin(bytes, f)
  expect_error(import_rating(p), "rating\\.rds does not match its checksum")
})

test_that("a missing listed file and a missing manifest are reported", {
  fit <- sample_fit()
  p <- tmp_dir()
  export_rating(fit, path = p)
  unlink(file.path(p, "limbs.csv"))
  expect_error(import_rating(p), "limbs\\.csv is listed in the manifest but missing")
  unlink(file.path(p, "manifest.csv"))
  expect_error(import_rating(p), "no manifest\\.csv")
  expect_error(import_rating(file.path(p, "nowhere")), "is not a folder")
})

test_that("a folder edited to a different object type is refused", {
  fit <- sample_fit()
  p <- tmp_dir()
  export_rating(fit, path = p)
  saveRDS(list(a = 1), file.path(p, "rating.rds"))
  expect_error(import_rating(p, verify = FALSE), "does not hold a FlodeRating")
})

test_that("a rating from a newer schema is refused, with the reason", {
  fit <- sample_fit()
  newer <- S7::`prop<-`(fit, "schema_version", check = FALSE, value = 99L)
  expect_error(S7::validate(newer), "newer than this reach.rate understands")
  expect_error(import_rating(local({
    q <- tmp_dir(); dir.create(q)
    saveRDS(newer, file.path(q, "rating.rds"))
    data.table::fwrite(data.table::data.table(file = "rating.rds", description = "x", bytes = 1,
                                              md5 = unname(tools::md5sum(file.path(q, "rating.rds")))),
                       file.path(q, "manifest.csv"))
    q
  })), "the saved rating is not valid: .*newer than this reach.rate understands")
})

test_that("an older schema with no migration is refused; with one it is migrated", {
  fit <- sample_fit()
  old <- fit
  old@schema_version <- 1L
  expect_error(.migrate_rating(old), "schema version 1.*No migration from 1")
  testthat::local_mocked_bindings(
    .rating_migrations = list("1" = function(x) { x@schema_version <- 2L; x })
  )
  expect_equal(.migrate_rating(old)@schema_version, 2L)
  testthat::local_mocked_bindings(
    .rating_migrations = list("1" = function(x) x)
  )
  expect_error(.migrate_rating(old), "did not advance")
})

test_that("arguments are checked", {
  fit <- sample_fit()
  expect_error(export_rating(1, path = tmp_dir()), "rating must be a FlodeRating")
  expect_error(export_rating(fit, assessment = 1, path = tmp_dir()), "assessment must be a FlodeAssessment")
  expect_error(export_rating(fit), "path must be")
  expect_error(export_rating(fit, path = NA_character_), "path must be")
  expect_error(export_rating(fit, path = tmp_dir(), overwrite = NA), "overwrite must be")
  f <- tempfile(); writeLines("x", f)
  expect_error(export_rating(fit, path = f), "is a file, not a folder")
  expect_error(import_rating(), "path must be")
  expect_error(import_rating(tempdir(), verify = NA), "verify must be")
})
