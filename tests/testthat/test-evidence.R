plain_gaugings <- function(n = 5) {
  data.table::data.table(stage_m = seq(0.5, by = 0.4, length.out = n),
                         discharge_cms = seq(1, by = 2.5, length.out = n))
}

canonical <- c("evidence_id", "site_id", "stage_m", "discharge_cms", "observation_time",
               "source_type", "source_name", "source_version", "quality_code", "included",
               "exclusion_reason", "weight", "notes", "source_row", "metadata")

expect_is_s7 <- function(x, class) testthat::expect_true(S7::S7_inherits(x, class))

# Set a property without validating, so the validator can be tested on its own.
unchecked <- function(x, name, value) { S7::prop(x, name, check = FALSE) <- value; x }

make_fit <- function() {
  set.seed(3)
  stage_m <- seq(0.4, 3, by = 0.05)
  rate_optimise(3 * stage_m^1.7 * exp(rnorm(length(stage_m), sd = 0.03)), stage_m)
}

# ---- conversion -------------------------------------------------------------

test_that("a plain table converts with generated ids, canonical columns first, and a note", {
  ev <- as_flode_evidence(plain_gaugings(5))
  expect_is_s7(ev, FlodeEvidence)
  expect_s3_class(ev, "data.table")
  expect_equal(names(ev), canonical)
  expect_equal(ev$evidence_id, c("G001", "G002", "G003", "G004", "G005"))
  expect_true(all(ev$included))
  expect_equal(ev$weight, rep(1, 5))
  expect_equal(ev$source_row, 1:5)
  expect_equal(unique(ev$source_type), "gauging")
  expect_true(all(is.na(ev$site_id)))
  expect_match(ev@conversion_note, "Converted from a plain table")
  expect_match(ev@conversion_note, "evidence_id")
})

test_that("extra columns are kept after the canonical ones, and gauging_datetime feeds observation_time", {
  dt <- plain_gaugings(3)
  dt[, gauging_datetime := as.Date("2020-01-01") + 0:2]
  dt[, my_flag := c("a", "b", "c")]
  ev <- as_flode_evidence(dt)
  expect_equal(names(ev), c(canonical, "gauging_datetime", "my_flag"))
  expect_equal(ev$observation_time, dt$gauging_datetime)
})

test_that("conversion does not change its input", {
  dt <- plain_gaugings(3)
  before <- data.table::copy(dt)
  as_flode_evidence(dt)
  expect_identical(dt, before)
})

test_that("id width grows with the table so ids stay sortable", {
  ev <- as_flode_evidence(plain_gaugings(1200))
  expect_equal(ev$evidence_id[c(1, 1200)], c("G0001", "G1200"))
  expect_false(anyDuplicated(ev$evidence_id) > 0)
})

test_that("an existing id column is respected and a FlodeEvidence passes through unchanged", {
  dt <- plain_gaugings(3)
  dt[, evidence_id := c("a", "b", "c")]
  ev <- as_flode_evidence(dt)
  expect_equal(ev$evidence_id, c("a", "b", "c"))
  expect_identical(as_flode_evidence(ev), ev)
})

test_that("conversion refuses what is not a table or lacks the two required columns", {
  expect_error(as_flode_evidence(1:3), "data.frame")
  expect_error(as_flode_evidence(data.frame(stage_m = 1)), "discharge_cms")
  expect_error(as_flode_evidence(data.frame(x = 1)), "stage_m. and .discharge_cms")
})

# ---- validation -------------------------------------------------------------

test_that("the validator names each way a table can be wrong", {
  ev <- as_flode_evidence(plain_gaugings(4))
  bad <- function(f) { x <- data.table::copy(ev); f(x); S7::validate(x) }

  expect_error(bad(function(x) data.table::set(x, j = "weight", value = NULL)), "missing column.*weight")
  expect_error(bad(function(x) data.table::set(x, j = "evidence_id", value = c("a", "a", "b", "c"))), "unique")
  expect_error(bad(function(x) data.table::set(x, j = "evidence_id", value = c("a", NA, "b", "c"))), "never be missing")
  expect_error(bad(function(x) data.table::set(x, j = "source_type", value = "banana")), "source_type must be one of")
  expect_error(bad(function(x) data.table::set(x, j = "source_type", value = NA_character_)), "source_type must be one of")
  expect_error(bad(function(x) data.table::set(x, j = "included", value = c(TRUE, NA, TRUE, TRUE))), "included")
  expect_error(bad(function(x) data.table::set(x, j = "stage_m", value = as.character(x$stage_m))), "stage_m must be of class numeric")
  expect_error(bad(function(x) data.table::set(x, j = "observation_time", value = 1:4)), "Date or POSIXct")
  expect_error(bad(function(x) data.table::set(x, j = "source_row", value = c(1, 2, 3, 4))), "source_row must be of class integer")
})

test_that("every source type in the vocabulary is accepted, and the vocabulary is exported", {
  expect_true(all(c("gauging", "operational_rating", "modelled", "cross_section",
                    "structure_equation", "other") %in% evidence_source_types()))
  ev <- as_flode_evidence(plain_gaugings(length(evidence_source_types())))
  ev[, source_type := evidence_source_types()]
  expect_silent(S7::validate(ev))
})

test_that("ordinary data.table use still works on evidence", {
  ev <- as_flode_evidence(plain_gaugings(5))
  expect_equal(ev$stage_m, plain_gaugings(5)$stage_m)
  expect_equal(nrow(ev[stage_m > 1]), sum(plain_gaugings(5)$stage_m > 1))
  expect_is_s7(ev[stage_m > 1], FlodeEvidence)
  expect_equal(ncol(ev), length(canonical))
})

# ---- the rating holds evidence ---------------------------------------------

test_that("a plain table given to a rating is converted, and a FlodeEvidence is kept as it is", {
  fit <- make_fit()
  expect_is_s7(fit@gaugings, FlodeEvidence)
  expect_match(fit@gaugings@conversion_note, "Converted from a plain table")

  gauged <- as_flode_evidence(plain_gaugings(8))
  gauged[, source_name := "my_file.csv"]
  gauged <- FlodeEvidence(gauged)  # built deliberately, so no conversion note
  rating <- FlodeRating(limbs = fit@limbs, gaugings = gauged)
  expect_identical(rating@gaugings$source_name, rep("my_file.csv", 8))
  expect_length(rating@gaugings@conversion_note, 0L)
})

test_that("evidence ids survive the fit, flagging, diagnostics and an RDS round trip", {
  fit <- make_fit()
  ids <- fit@gaugings$evidence_id
  expect_equal(length(ids), nrow(fit@gaugings))
  expect_false(anyDuplicated(ids) > 0)

  flagged <- flag_extrapolated_limbs(fit)
  expect_equal(rating_evidence(flagged)$evidence_id, ids)

  influence <- flag_influential_gaugings(fit)
  expect_true("evidence_id" %in% names(influence@gaugings))
  expect_setequal(influence@gaugings$evidence_id, ids)

  path <- tempfile(fileext = ".rds")
  saveRDS(fit, path)
  back <- readRDS(path)
  expect_silent(S7::validate(back))
  expect_is_s7(back@gaugings, FlodeEvidence)
  expect_equal(back@gaugings$evidence_id, ids)
  expect_equal(back@gaugings@conversion_note, fit@gaugings@conversion_note)
})

test_that("segmented fits keep their evidence ids too", {
  set.seed(4)
  stage_m <- seq(0.3, 3.5, by = 0.03)
  fit <- rate_optimise_segmented(
    ifelse(stage_m < 1.5, 3 * stage_m^1.6, 3 * 1.5^1.6 * (stage_m / 1.5)^2.1) * exp(rnorm(length(stage_m), sd = 0.03)),
    stage_m, control = 1.5
  )
  expect_is_s7(fit@gaugings, FlodeEvidence)
  expect_equal(rating_evidence(fit)$evidence_id, fit@gaugings$evidence_id)
})

# ---- status split and schema version ----------------------------------------

test_that("fit_origin and lifecycle are separate, lifecycle starts as draft, and @status still reads", {
  fit <- make_fit()
  expect_equal(fit@fit_origin, "independently_fitted")
  expect_equal(fit@lifecycle, "draft")
  expect_equal(fit@status, fit@fit_origin)
  expect_error(fit@status <- "x", "read-only|cannot|getter|setter", ignore.case = TRUE)
})

test_that("every lifecycle value is accepted, anything else is refused", {
  fit <- make_fit()
  for (v in c("draft", "under_review", "approved", "superseded", "withdrawn")) {
    fit@lifecycle <- v
    expect_equal(fit@lifecycle, v)
  }
  expect_error(fit@lifecycle <- "rubber_stamped", "lifecycle must be one of")
})

test_that("the package never approves a rating on its own", {
  fit <- make_fit()
  expect_equal(fit@lifecycle, "draft")
  expect_equal(suppressWarnings(align_limb_equations(fit))@lifecycle, "draft")
  fit@lifecycle <- "approved"
  expect_equal(suppressWarnings(align_limb_equations(fit))@lifecycle, "draft")
})

test_that("fit_origin on a fit keeps its three values; a table also allows extension and graft", {
  fit <- make_fit()
  expect_error(fit@fit_origin <- "whatever", "fit_origin must be one of")
  expect_silent(FlodeRatingTable(
    table = data.table::data.table(lower_level = 0, upper_level = 3, C = 2, a = 0, n = 1.5),
    fit_origin = "grafted"
  ))
})

test_that("provenance reports the schema version, fit origin and lifecycle", {
  prov <- rating_provenance(make_fit())
  expect_equal(prov$schema_version, rating_schema_version())
  expect_equal(prov$fit_origin, "independently_fitted")
  expect_equal(prov$lifecycle, "draft")
})

test_that("a missing or future schema version fails validation with a plain message", {
  fit <- make_fit()
  newer <- unchecked(fit, "schema_version", rating_schema_version() + 1L)
  expect_error(S7::validate(newer), "newer than this reach.rate understands")

  missing <- fit
  attr(missing, "schema_version") <- NULL
  expect_error(S7::validate(missing), "schema_version")

  na <- unchecked(fit, "schema_version", NA_integer_)
  expect_error(S7::validate(na), "schema_version is missing")
})

test_that("a rating table carries the same state and checks", {
  tab <- FlodeRatingTable(table = data.table::data.table(
    lower_level = 0, upper_level = 3, C = 2, a = 0, n = 1.5))
  expect_equal(tab@lifecycle, "draft")
  expect_equal(tab@schema_version, rating_schema_version())
  expect_equal(tab@status, "independently_fitted")
  expect_error(tab@schema_version <- 99L, "newer than")
})

test_that("printing a rating shows origin and lifecycle", {
  expect_output(print(make_fit()), "origin: independently_fitted, lifecycle: draft")
})

test_that("printing evidence shows the count and the conversion note", {
  expect_output(print(as_flode_evidence(plain_gaugings(3))), "3 row\\(s\\), 3 included")
  expect_output(print(as_flode_evidence(plain_gaugings(3))), "Converted from a plain table")
})
