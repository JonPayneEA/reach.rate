chk_row <- function(id, domain, status) {
  data.table::data.table(
    check_id = id, domain = domain,
    severity = if (domain == "technical") "error" else "warning",
    status = status, message = "m", affected_evidence = list(character(0)),
    affected_stage_min_m = NA_real_, affected_stage_max_m = NA_real_,
    recommendation = NA_character_
  )
}

test_that("an assessment holds checks, a subject and a row count", {
  a <- FlodeAssessment(checks = rbind(chk_row("a", "technical", "pass"), chk_row("b", "hydrometric", "warning")),
                       subject = "ratings", assessed_rows = 3L)
  expect_equal(a@subject, "ratings")
  expect_equal(nrow(assessment_checks(a)), 2L)
  expect_equal(assessment_status(a), "warning")
})

test_that("a technical check cannot warn and a hydrometric check cannot fail", {
  expect_error(FlodeAssessment(checks = chk_row("a", "technical", "warning")), "technical check can pass or fail")
  expect_error(FlodeAssessment(checks = chk_row("a", "hydrometric", "fail")), "hydrometric check can warn")
})

test_that("the validator names each other way a check table can be wrong", {
  ok <- chk_row("a", "technical", "pass")
  bad <- function(f) { x <- data.table::copy(ok); f(x); FlodeAssessment(checks = x) }
  expect_error(bad(function(x) x[, status := "great"]), "status must be one of")
  expect_error(bad(function(x) x[, domain := "other"]), "domain must be one of")
  expect_error(bad(function(x) x[, severity := "warning"]), "severity must be")
  expect_error(FlodeAssessment(checks = rbind(ok, ok)), "unique")
  expect_error(bad(function(x) x[, message := NULL]), "missing column")
  expect_error(bad(function(x) x[, affected_stage_min_m := "a"]), "numeric")
  expect_error(bad(function(x) data.table::set(x, j = "affected_evidence", value = list(list(1L)))),
               "character vector of evidence ids")
})

test_that("overall status is the worst one, and not_assessed only when nothing ran", {
  mk <- function(...) FlodeAssessment(checks = data.table::rbindlist(list(...)))
  expect_equal(assessment_status(mk(chk_row("a", "technical", "pass"), chk_row("b", "technical", "fail"),
                                    chk_row("c", "hydrometric", "warning"))), "fail")
  expect_equal(assessment_status(mk(chk_row("a", "technical", "pass"), chk_row("c", "hydrometric", "warning"))), "warning")
  expect_equal(assessment_status(mk(chk_row("a", "technical", "pass"), chk_row("c", "hydrometric", "not_assessed"))), "pass")
  expect_equal(assessment_status(mk(chk_row("c", "hydrometric", "not_assessed"))), "not_assessed")
})

test_that("accessors refuse anything that is not an assessment, and return copies", {
  expect_error(assessment_checks(1), "FlodeAssessment")
  expect_error(assessment_status("x"), "FlodeAssessment")
  a <- FlodeAssessment(checks = chk_row("a", "technical", "pass"))
  out <- assessment_checks(a)
  out[, status := "fail"]
  expect_equal(assessment_status(a), "pass")
})

test_that("print lists what did not pass, worst first, and counts the rest", {
  a <- FlodeAssessment(
    checks = rbind(chk_row("fine", "technical", "pass"), chk_row("odd", "hydrometric", "warning"),
                   chk_row("broken", "technical", "fail")),
    assessed_rows = 5L
  )
  out <- capture.output(print(a))
  expect_match(out[1], "5 row\\(s\\) assessed. Overall: fail")
  expect_match(out[2], "1 pass, 1 warning, 1 fail, 0 not assessed")
  expect_match(out[3], "\\[fail\\] broken")
  expect_match(out[4], "\\[warning\\] odd")
  expect_length(out, 4L)
})

test_that("plot gives one tile per check, with the status written in it", {
  a <- FlodeAssessment(checks = rbind(chk_row("fine", "technical", "pass"), chk_row("odd", "hydrometric", "warning")))
  p <- plot(a)
  expect_s3_class(p, "ggplot")
  expect_equal(nrow(p$data), 2L)
  expect_true(all(c("pass", "warning") %in% as.character(p$data$tile_label)))
  expect_error(plot(FlodeAssessment()), "no checks")
  expect_pdf_renders <- function(code) { grDevices::pdf(NULL); on.exit(grDevices::dev.off()); force(code) }
  expect_no_error(expect_pdf_renders(print(p)))
})

test_that("the empty default is a valid assessment with no checks", {
  a <- FlodeAssessment()
  expect_equal(nrow(assessment_checks(a)), 0L)
  expect_equal(assessment_status(a), "not_assessed")
})
