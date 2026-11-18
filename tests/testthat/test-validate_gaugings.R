# Each check has a pass test and a fail (technical) or warning (hydrometric)
# test. The baseline is a well-behaved set of dated gaugings that passes
# every check; each test spoils one thing.

ref_time <- as.POSIXct("2024-06-01", tz = "UTC")

good <- function(n = 20) {
  set.seed(11)
  stage_m <- seq(0.4, 3.2, length.out = n)
  data.table::data.table(
    stage_m = stage_m,
    discharge_cms = 3.2 * stage_m^1.7 * exp(rnorm(n, sd = 0.01)),
    gauging_datetime = as.POSIXct("2023-01-01", tz = "UTC") + (seq_len(n) - 1) * 86400 * 7
  )
}

with_notes <- function(dt, notes = NA_character_) {
  dt <- data.table::copy(dt)
  dt[, read_issue := notes]
  dt
}

run <- function(dt, ...) validate_gaugings(dt, reference_time = ref_time, ...)
row_of <- function(a, id) assessment_checks(a)[check_id == id]
status_of <- function(a, id) row_of(a, id)$status
ids_of <- function(a, id) row_of(a, id)$affected_evidence[[1]]

test_that("a well-behaved, dated, read set passes every check", {
  a <- run(with_notes(good()))
  expect_true(S7::S7_inherits(a, FlodeAssessment))
  expect_equal(unique(assessment_checks(a)$status), "pass")
  expect_equal(assessment_status(a), "pass")
  expect_equal(a@assessed_rows, 20L)
  expect_equal(nrow(assessment_checks(a)), 16L)
})

test_that("without dates or read notes the checks that need them are not assessed, never passed", {
  a <- run(good()[, gauging_datetime := NULL])
  expect_equal(status_of(a, "temporal_coverage"), "not_assessed")
  expect_equal(status_of(a, "read_issues"), "not_assessed")
  expect_equal(status_of(a, "times_assumed"), "not_assessed")
  expect_equal(assessment_status(a), "pass")
})

# ---- technical ---------------------------------------------------------------

test_that("stage_finite: passes, and fails on a missing or infinite stage", {
  expect_equal(status_of(run(good()), "stage_finite"), "pass")
  d <- good(); d$stage_m[c(3, 5)] <- c(NA, Inf)
  a <- run(d)
  expect_equal(status_of(a, "stage_finite"), "fail")
  expect_equal(ids_of(a, "stage_finite"), c("G003", "G005"))
  expect_equal(assessment_status(a), "fail")
})

test_that("discharge_finite: passes, and fails on a missing discharge", {
  expect_equal(status_of(run(good()), "discharge_finite"), "pass")
  d <- good(); d$discharge_cms[4] <- NA
  a <- run(d)
  expect_equal(status_of(a, "discharge_finite"), "fail")
  expect_equal(ids_of(a, "discharge_finite"), "G004")
})

test_that("discharge_not_negative: passes, and fails on a negative discharge", {
  expect_equal(status_of(run(good()), "discharge_not_negative"), "pass")
  d <- good(); d$discharge_cms[2] <- -1
  a <- run(d)
  expect_equal(status_of(a, "discharge_not_negative"), "fail")
  expect_equal(ids_of(a, "discharge_not_negative"), "G002")
  expect_equal(row_of(a, "discharge_not_negative")$affected_stage_min_m, d$stage_m[2])
})

test_that("enough_rows: passes with four usable rows, fails with three", {
  expect_equal(status_of(run(good(4)), "enough_rows"), "pass")
  a <- run(good(3))
  expect_equal(status_of(a, "enough_rows"), "fail")
  expect_match(row_of(a, "enough_rows")$message, "Only 3 usable gaugings")
})

test_that("evidence_id_unique: passes for generated ids, fails for a repeated one", {
  expect_equal(status_of(run(good()), "evidence_id_unique"), "pass")
  ev <- as_flode_evidence(good())
  data.table::set(ev, j = "evidence_id", value = c("a", "a", ev$evidence_id[-(1:2)]))
  a <- run(ev)
  expect_equal(status_of(a, "evidence_id_unique"), "fail")
  expect_equal(ids_of(a, "evidence_id_unique"), c("a", "a"))
})

test_that("read_issues: passes with clean notes, fails on a read problem, ignores an assumed midnight", {
  expect_equal(status_of(run(with_notes(good())), "read_issues"), "pass")
  notes <- rep(NA_character_, 20); notes[7] <- "stage not a number"
  a <- run(with_notes(good(), notes))
  expect_equal(status_of(a, "read_issues"), "fail")
  expect_equal(ids_of(a, "read_issues"), "G007")
  notes <- rep(NA_character_, 20); notes[7] <- "time missing, midnight assumed"
  expect_equal(status_of(run(with_notes(good(), notes)), "read_issues"), "pass")
})

# ---- hydrometric ---------------------------------------------------------------

test_that("zero_discharge: passes, and warns on a zero flow", {
  expect_equal(status_of(run(good()), "zero_discharge"), "pass")
  d <- good(); d$discharge_cms[1] <- 0
  a <- run(d)
  expect_equal(status_of(a, "zero_discharge"), "warning")
  expect_equal(ids_of(a, "zero_discharge"), "G001")
})

test_that("duplicate_gaugings: passes, and warns on an exact repeat", {
  expect_equal(status_of(run(good()), "duplicate_gaugings"), "pass")
  d <- rbind(good(), good()[5])
  a <- run(d)
  expect_equal(status_of(a, "duplicate_gaugings"), "warning")
  expect_equal(ids_of(a, "duplicate_gaugings"), c("G005", "G021"))
})

test_that("stage_discharge_inversion: passes, blames the higher-stage member of a pair", {
  expect_equal(status_of(run(good()), "stage_discharge_inversion"), "pass")
  d <- good(); d$discharge_cms[10] <- d$discharge_cms[9] * 0.5
  a <- run(d)
  expect_equal(status_of(a, "stage_discharge_inversion"), "warning")
  expect_equal(ids_of(a, "stage_discharge_inversion"), "G010")
})

test_that("one high gauging is blamed alone, not the gaugings above it", {
  d <- good(); d$discharge_cms[8] <- d$discharge_cms[8] * 3
  a <- run(d)
  expect_equal(ids_of(a, "stage_discharge_inversion"), "G008")
})

test_that("a small dip inside the tolerance is not an inversion, and the tolerance is an argument", {
  d <- good(); d$discharge_cms[10] <- d$discharge_cms[9] * 0.9
  expect_equal(status_of(run(d), "stage_discharge_inversion"), "pass")
  expect_equal(status_of(run(d, inversion_tolerance = 0.05), "stage_discharge_inversion"), "warning")
})

test_that("a set beyond the pairwise limit skips the inversion check and says so", {
  testthat::local_mocked_bindings(.inversion_max_rows = 5L)
  a <- run(good())
  expect_equal(status_of(a, "stage_discharge_inversion"), "not_assessed")
  expect_match(row_of(a, "stage_discharge_inversion")$message, "skipped")
})

test_that("outliers: passes, warns on a point far from the trend, not assessed with too few", {
  expect_equal(status_of(run(good()), "outliers"), "pass")
  d <- good(); d$discharge_cms[12] <- d$discharge_cms[12] * 1.6
  a <- run(d)
  expect_equal(status_of(a, "outliers"), "warning")
  expect_true("G012" %in% ids_of(a, "outliers"))
  expect_equal(status_of(run(good(6)), "outliers"), "not_assessed")
})

test_that("stage_coverage_gaps: passes, warns on a wide gap and names the gaugings at its edges", {
  expect_equal(status_of(run(good()), "stage_coverage_gaps"), "pass")
  d <- good()[-(8:14)]
  a <- run(d)
  expect_equal(status_of(a, "stage_coverage_gaps"), "warning")
  expect_length(ids_of(a, "stage_coverage_gaps"), 2L)
  expect_equal(row_of(a, "stage_coverage_gaps")$affected_stage_min_m, good()$stage_m[7])
  expect_equal(row_of(a, "stage_coverage_gaps")$affected_stage_max_m, good()$stage_m[15])
  expect_equal(status_of(run(good(2)), "stage_coverage_gaps"), "not_assessed")
})

test_that("upper_range_support: passes, warns when the top of the range is thin", {
  expect_equal(status_of(run(good()), "upper_range_support"), "pass")
  d <- good()
  d <- d[c(1:17, 20)]  # leave a single gauging in the top fifth
  a <- run(d)
  expect_equal(status_of(a, "upper_range_support"), "warning")
  expect_equal(status_of(run(good(3)), "upper_range_support"), "not_assessed")
})

test_that("few_gaugings: passes at the minimum, warns below it, and min_gaugings is an argument", {
  expect_equal(status_of(run(good(20)), "few_gaugings"), "pass")
  expect_equal(status_of(run(good(8)), "few_gaugings"), "warning")
  expect_equal(status_of(run(good(8), min_gaugings = 5), "few_gaugings"), "pass")
})

test_that("temporal_coverage: passes when recent, warns when old, not assessed without dates", {
  expect_equal(status_of(run(good()), "temporal_coverage"), "pass")
  a <- validate_gaugings(good(), reference_time = as.POSIXct("2040-01-01", tz = "UTC"))
  expect_equal(status_of(a, "temporal_coverage"), "warning")
  expect_equal(status_of(validate_gaugings(good(), reference_time = as.POSIXct("2040-01-01", tz = "UTC"),
                                           recent_years = 50), "temporal_coverage"), "pass")
  expect_equal(status_of(run(good()[, gauging_datetime := NULL]), "temporal_coverage"), "not_assessed")
})

test_that("excluded_rows: passes, and warns on rows marked excluded", {
  expect_equal(status_of(run(good()), "excluded_rows"), "pass")
  ev <- as_flode_evidence(good())
  data.table::set(ev, i = 3L, j = "included", value = FALSE)
  a <- run(ev)
  expect_equal(status_of(a, "excluded_rows"), "warning")
  expect_equal(ids_of(a, "excluded_rows"), "G003")
})

test_that("times_assumed: passes, and warns on an assumed midnight", {
  expect_equal(status_of(run(with_notes(good())), "times_assumed"), "pass")
  notes <- rep(NA_character_, 20); notes[2] <- "time missing, midnight assumed"
  a <- run(with_notes(good(), notes))
  expect_equal(status_of(a, "times_assumed"), "warning")
  expect_equal(ids_of(a, "times_assumed"), "G002")
})

# ---- behaviour that holds for every check -------------------------------------

test_that("no check changes or removes a row, and hydrometric checks never fail", {
  d <- good(); d$discharge_cms[1] <- 0; d$discharge_cms[10] <- d$discharge_cms[9] * 0.4
  ev <- as_flode_evidence(d)
  before <- data.table::copy(ev)
  a <- run(ev)
  expect_identical(as.data.frame(ev), as.data.frame(before))
  chk <- assessment_checks(a)
  expect_false(any(chk$domain == "hydrometric" & chk$status == "fail"))
  expect_false(any(chk$domain == "technical" & chk$status == "warning"))
})

test_that("severity follows the domain", {
  chk <- assessment_checks(run(good()))
  expect_equal(unique(chk[domain == "technical"]$severity), "error")
  expect_equal(unique(chk[domain == "hydrometric"]$severity), "warning")
})

test_that("a table from read_gaugings() is assessed with its read notes", {
  raw <- data.frame(
    `Station number` = rep("10250", 12),
    Date = sprintf("%02d/%02d/2023", 13:24 %% 28 + 1, 1),
    Time = c("", rep("12:00:00", 11)),
    Stage = c("---", sprintf("%.2f", seq(0.5, 2.7, length.out = 11))),
    Flow = c("5", sprintf("%.2f", 3 * seq(0.5, 2.7, length.out = 11)^1.7)),
    check.names = FALSE
  )
  out <- read_gaugings(raw, quiet = TRUE)
  a <- run(out)
  expect_equal(status_of(a, "read_issues"), "fail")
  expect_equal(ids_of(a, "read_issues"), "G001")
})

test_that("arguments are checked, and an empty table is refused", {
  expect_error(validate_gaugings(good(), min_gaugings = -1), "min_gaugings must be a single number")
  expect_error(validate_gaugings(good(), outlier_mad = "a"), "outlier_mad")
  expect_error(validate_gaugings(good()[0]), "no gaugings to check")
  expect_error(validate_gaugings(1:3), "data.frame")
})
