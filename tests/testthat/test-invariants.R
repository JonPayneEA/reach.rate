# Tranche A8: post-fit invariants. Every invariant has a passing case and a
# failing case, the gate on apply_rating() is tested for both operations,
# and a failure never changes a number silently.

tbl <- function(...) {
  base <- data.table::data.table(
    lower_level = c(0.2, 1.5), upper_level = c(1.5, 3),
    C = c(2.5, 2.5 * 1.5^1.5 / (1.5 - 0.1)^1.7 * 1), a = c(0, 0.1), n = c(1.5, 1.7)
  )
  # make limb 2 meet limb 1 exactly at 1.5
  base$C[2] <- base$C[1] * (1.5 - base$a[1])^base$n[1] / (1.5 - base$a[2])^base$n[2]
  over <- list(...)
  for (nm in names(over)) data.table::set(base, j = nm, value = over[[nm]])
  FlodeRatingTable(table = base)
}

# A table object whose contents bypass the class's own validation, so
# invalid states can be handed to the invariants.
unchecked_table <- function(dt) {
  obj <- tbl()
  S7::prop(obj, "table", check = FALSE) <- data.table::as.data.table(dt)
  obj
}

fit_data <- function() {
  set.seed(1)
  h <- seq(0.4, 3, by = 0.05)
  list(h = h, q = 3.2 * h^1.6 * exp(rnorm(length(h), sd = 0.03)))
}

chk <- function(x, id) assessment_checks(rating_invariants(x))[check_id == id]
status <- function(x, id) chk(x, id)$status

# ---- the assessment ----------------------------------------------------------------

test_that("a sound fit and a sound table pass every technical check", {
  d <- fit_data()
  fit <- rate_optimise(d$q, d$h, control = 1.5)
  for (x in list(fit, tbl())) {
    a <- rating_invariants(x)
    expect_true(S7::S7_inherits(a, FlodeAssessment))
    expect_equal(a@subject, "rating")
    expect_false(any(assessment_checks(a)[domain == "technical"]$status == "fail"))
    expect_false(assessment_status(a) == "fail")
  }
  expect_equal(unique(assessment_checks(rating_invariants(tbl()))[status != "not_assessed"]$status), "pass")
})

test_that("only a rating is accepted, and the tolerance is checked", {
  expect_error(rating_invariants(1), "must be a FlodeRating")
  expect_error(rating_invariants(data.frame(a = 1)), "must be a FlodeRating")
  expect_error(rating_invariants(tbl(), continuity_tol = -1), "continuity_tol")
  expect_error(rating_invariants(tbl(), continuity_tol = "a"), "continuity_tol")
})

# ---- technical: each can fail ----------------------------------------------------------

test_that("coefficients_finite fails for a missing, non-finite or non-positive coefficient", {
  expect_equal(status(tbl(), "coefficients_finite"), "pass")
  expect_equal(status(unchecked_table(tbl()@table[, C := c(NA, 2)]), "coefficients_finite"), "fail")
  expect_equal(status(unchecked_table(tbl()@table[, C := c(-1, 2)]), "coefficients_finite"), "fail")
  expect_equal(status(unchecked_table(tbl()@table[, n := c(0, 1.7)]), "coefficients_finite"), "fail")
  expect_equal(status(unchecked_table(tbl()@table[, a := c(0, Inf)]), "coefficients_finite"), "fail")
  expect_match(chk(unchecked_table(tbl()@table[, C := c(-1, 2)]), "coefficients_finite")$message, "limb 1")
})

test_that("limbs_ordered fails for an inverted range, a missing limit, or a break in contiguity", {
  expect_equal(status(tbl(), "limbs_ordered"), "pass")
  expect_equal(status(unchecked_table(data.table::data.table(lower_level = 1, upper_level = 0, C = 2, a = 0, n = 1.5)),
                      "limbs_ordered"), "fail")
  expect_equal(status(unchecked_table(tbl()@table[, upper_level := c(NA, 3)]), "limbs_ordered"), "fail")
  broken <- tbl()@table[, upper_level := c(1.4, 3)]
  expect_equal(status(unchecked_table(broken), "limbs_ordered"), "fail")
  expect_match(chk(unchecked_table(broken), "limbs_ordered")$message, "not contiguous")
})

test_that("predictions_finite fails when the equation overflows", {
  expect_equal(status(tbl(), "predictions_finite"), "pass")
  huge <- unchecked_table(data.table::data.table(lower_level = 0.5, upper_level = 3, C = 1, a = 0, n = 1e6))
  expect_equal(status(huge, "predictions_finite"), "fail")
})

test_that("monotone_discharge fails when discharge falls within a limb (mechanism, by mocking the equation)", {
  # With C and n positive the equation cannot fall, so the check is
  # unreachable through coefficients; the mechanism is shown by handing it a
  # falling curve.
  expect_equal(status(tbl(), "monotone_discharge"), "pass")
  testthat::local_mocked_bindings(.eval_limb = function(C, a, n, h) rev(seq_along(h)) * 1.0)
  expect_equal(status(tbl(), "monotone_discharge"), "fail")
  expect_match(chk(tbl(), "monotone_discharge")$message, "within limb")
})

test_that("monotone_across_junctions fails when a limb tops out below the one before, and blocks only the inverse", {
  expect_equal(status(tbl(), "monotone_across_junctions"), "pass")
  # Limb 1 reaches 10 at stage 1; limb 2 reaches only 2 at stage 2.
  falling <- unchecked_table(data.table::data.table(
    lower_level = c(0, 1), upper_level = c(1, 2), C = c(10, 1), a = c(0, 0), n = c(1, 1)))
  expect_equal(status(falling, "monotone_across_junctions"), "fail")
  expect_match(chk(falling, "monotone_across_junctions")$message, "top of limb 2")
  # Forward application is still well defined, so it proceeds.
  expect_no_error(apply_rating(falling, data.frame(stage = c(0.5, 1.5))))
  # The inverse is ambiguous, so it is refused.
  expect_error(apply_rating_inverse(falling, data.frame(discharge = 5)), "monotone_across_junctions")
})

test_that("inverse_consistent fails if the inverse errors or does not undo the forward rating", {
  expect_equal(status(tbl(), "inverse_consistent"), "pass")
  testthat::local_mocked_bindings(.kernel_inverse = function(rating_dt, discharge) stop("kernel says no"))
  expect_equal(status(tbl(), "inverse_consistent"), "fail")
  expect_match(chk(tbl(), "inverse_consistent")$message, "kernel says no")
})

test_that("inverse_consistent fails on a round trip that does not close", {
  testthat::local_mocked_bindings(.kernel_inverse = function(rating_dt, discharge) {
    list(stage = rep(1, length(discharge)), extrapolated = rep(FALSE, length(discharge)))
  })
  expect_equal(status(tbl(), "inverse_consistent"), "fail")
  expect_match(chk(tbl(), "inverse_consistent")$message, "differs by up to")
})

test_that("a check that needs a usable equation is not assessed, not passed, when the coefficients are broken", {
  broken <- unchecked_table(tbl()@table[, C := c(NA, 2)])
  for (id in c("predictions_finite", "monotone_discharge", "monotone_across_junctions", "inverse_consistent")) {
    expect_equal(status(broken, id), "not_assessed", info = id)
  }
})

test_that("interval_ordering fails if bootstrap bounds are out of order, and is not assessed without a bootstrap", {
  d <- fit_data()
  plain <- rate_optimise(d$q, d$h)
  expect_equal(status(plain, "interval_ordering"), "not_assessed")
  boot <- rate_optimise(d$q, d$h, n_boot = 40, boot_seed = 1)
  expect_equal(status(boot, "interval_ordering"), "pass")
  bad <- boot
  limbs <- data.table::copy(bad@limbs)
  limbs[, C_q025 := C_q975 + 1]
  bad@limbs <- limbs
  expect_equal(status(bad, "interval_ordering"), "fail")
})

test_that("bounds_respected fails when a fitted exponent is outside its bounds, and is not assessed once amended", {
  d <- fit_data()
  fit <- rate_optimise(d$q, d$h, n_bounds = c(1.2, 2.2))
  expect_equal(status(fit, "bounds_respected"), "pass")
  bad <- fit
  limbs <- data.table::copy(bad@limbs); limbs[, n := 3]
  bad@limbs <- limbs
  expect_equal(status(bad, "bounds_respected"), "fail")
  amended <- suppressWarnings(rate_optimise_constrained(d$q, d$h, control = 1.5))
  expect_equal(status(amended, "bounds_respected"), "not_assessed")
  expect_equal(status(tbl(), "bounds_respected"), NA_character_[0])  # tables have no such check
})

# ---- hydrometric: each can warn, none can block ------------------------------------------

test_that("stage_gaps_overlaps warns for a gap or an overlap between limbs", {
  expect_equal(status(tbl(), "stage_gaps_overlaps"), "pass")
  gap <- unchecked_table(tbl()@table[, lower_level := c(0.2, 1.6)])
  expect_equal(status(gap, "stage_gaps_overlaps"), "warning")
  expect_match(chk(gap, "stage_gaps_overlaps")$message, "gap in stage")
  overlap <- unchecked_table(tbl()@table[, lower_level := c(0.2, 1.4)])
  expect_match(chk(overlap, "stage_gaps_overlaps")$message, "overlap in stage")
})

test_that("limb_continuity warns for a step at a junction, and the tolerance is a visible choice", {
  expect_equal(status(tbl(), "limb_continuity"), "pass")
  step <- tbl()@table[, C := c(2.5, C[2] * 1.05)]
  expect_equal(status(FlodeRatingTable(table = step), "limb_continuity"), "warning")
  expect_match(chk(FlodeRatingTable(table = step), "limb_continuity")$message, "limb 1")
  loose <- assessment_checks(rating_invariants(FlodeRatingTable(table = step), continuity_tol = 0.1))
  expect_equal(loose[check_id == "limb_continuity"]$status, "pass")
})

test_that("domain_valid warns, and does not block, when a limb starts below its own zero-flow stage", {
  low <- FlodeRatingTable(table = data.table::data.table(lower_level = 0, upper_level = 3, C = 2, a = 0.5, n = 1.5))
  expect_equal(status(low, "domain_valid"), "warning")
  expect_equal(status(tbl(), "domain_valid"), "pass")
  out <- apply_rating(low, data.frame(stage = c(0.2, 0.5, 1.5)))
  expect_equal(out$discharge, c(0, 0, 2 * 1^1.5))
})

test_that("a single limb has no junction to check", {
  one <- FlodeRatingTable(table = data.table::data.table(lower_level = 0.2, upper_level = 3, C = 2, a = 0, n = 1.5))
  expect_equal(status(one, "limb_continuity"), "pass")
  expect_equal(status(one, "stage_gaps_overlaps"), "pass")
})

test_that("hydrometric checks never fail and technical checks never warn", {
  odd <- unchecked_table(data.table::data.table(lower_level = c(0, 1.6), upper_level = c(1.5, 3),
                                                C = c(2, 9), a = c(0.5, 0), n = c(1.5, 1.7)))
  chk_all <- assessment_checks(rating_invariants(odd))
  expect_false(any(chk_all$domain == "hydrometric" & chk_all$status == "fail"))
  expect_false(any(chk_all$domain == "technical" & chk_all$status == "warning"))
})

# ---- the segmented fit ---------------------------------------------------------------------

test_that("a segmented fit is checked on its joint equation", {
  set.seed(4)
  h <- seq(0.3, 3.5, by = 0.03)
  q <- ifelse(h < 1.5, 3 * h^1.6, 3 * 1.5^1.6 * (h / 1.5)^2.1) * exp(rnorm(length(h), sd = 0.03))
  fit <- rate_optimise_segmented(q, h, control = 1.5)
  a <- rating_invariants(fit)
  expect_equal(assessment_checks(a)[check_id == "coefficients_finite"]$status, "pass")
  expect_equal(assessment_checks(a)[check_id == "limb_continuity"]$status, "pass")
  expect_false(assessment_status(a) == "fail")
  bad <- fit
  co <- data.table::copy(bad@coefficients); co[, bp2 := bp1 - 1]
  bad@coefficients <- co
  expect_equal(status(bad, "limbs_ordered"), "fail")
  co2 <- data.table::copy(fit@coefficients); co2[, C := NA_real_]
  bad2 <- fit; S7::prop(bad2, "coefficients", check = FALSE) <- co2
  expect_equal(status(bad2, "coefficients_finite"), "fail")
  expect_equal(status(bad2, "predictions_finite"), "not_assessed")
})

# ---- the gate ---------------------------------------------------------------------------------

test_that("apply_rating refuses a rating that fails a technical check, naming the check", {
  bad <- unchecked_table(tbl()@table[, C := c(-1, 2)])
  expect_error(apply_rating(bad, data.frame(stage = 1)), "fails 1 post-fit check and will not be applied")
  expect_error(apply_rating(bad, data.frame(stage = 1)), "coefficients_finite")
  expect_error(apply_rating(bad, data.frame(stage = 1)), "rating_invariants")
  expect_error(apply_rating_inverse(bad, data.frame(discharge = 1)), "coefficients_finite")
})

test_that("a fit that fails an invariant is refused too, not only its table", {
  d <- fit_data()
  fit <- rate_optimise(d$q, d$h, n_boot = 40, boot_seed = 1)
  expect_no_error(apply_rating(fit, data.frame(stage = 1)))
  bad <- fit
  limbs <- data.table::copy(bad@limbs); limbs[, n_q025 := n_q975 + 1]
  bad@limbs <- limbs
  expect_error(apply_rating(bad, data.frame(stage = 1)), "interval_ordering")
})

test_that("a warning never blocks application, and the numbers are those of the equation", {
  step <- FlodeRatingTable(table = tbl()@table[, C := c(2.5, C[2] * 1.05)])
  expect_equal(status(step, "limb_continuity"), "warning")
  out <- apply_rating(step, data.frame(stage = c(1, 2)))
  expect_equal(out$discharge, c(step@table$C[1] * 1^1.5, step@table$C[2] * (2 - 0.1)^1.7))
})

test_that("the gate adds little time to a call", {
  d <- fit_data()
  fit <- rate_optimise(d$q, d$h, control = 1.5)
  stage <- data.frame(stage = c(0.5, 1, 2))
  elapsed <- system.time(for (i in 1:100) apply_rating(fit, stage))[["elapsed"]]
  expect_lt(elapsed / 100, 0.05)
})

# ---- print: converged and valid are separate lines -------------------------------------------

test_that("printing a fit shows converged and valid on separate lines", {
  d <- fit_data()
  out <- capture.output(print(rate_optimise(d$q, d$h, control = 1.5)))
  expect_match(out[1], "<FlodeRating> 2 limb\\(s\\)")
  expect_match(out[2], "^  converged: yes \\(2 of 2 limbs\\)")
  expect_match(out[3], "^  valid: yes")
})

test_that("a fit that did not converge says so on its converged line, and still reports validity", {
  d <- fit_data()
  testthat::local_mocked_bindings(.lm_control = function(maxiter) minpack.lm::nls.lm.control(maxiter = 2L))
  fit <- suppressWarnings(rate_optimise(d$q, d$h))
  out <- capture.output(print(fit))
  expect_match(out[2], "converged: no \\(limb 1: .*maxiter")
  expect_match(out[3], "valid: ")
})

test_that("a table has no optimiser record and says so; a failing table says which checks failed", {
  expect_match(capture.output(print(tbl()))[2], "converged: not assessed")
  expect_match(capture.output(print(tbl()))[3], "valid: yes")
  bad <- unchecked_table(tbl()@table[, C := c(-1, 2)])
  expect_match(capture.output(print(bad))[3], "valid: no \\(fails: coefficients_finite\\)")
})

test_that("valid reports warnings alongside yes", {
  step <- FlodeRatingTable(table = tbl()@table[, C := c(2.5, C[2] * 1.05)])
  expect_match(capture.output(print(step))[3], "valid: yes, with 1 warning \\(limb_continuity\\)")
})

test_that("a segmented fit prints both lines", {
  set.seed(4)
  h <- seq(0.3, 3.5, by = 0.03)
  q <- ifelse(h < 1.5, 3 * h^1.6, 3 * 1.5^1.6 * (h / 1.5)^2.1) * exp(rnorm(length(h), sd = 0.03))
  out <- capture.output(print(rate_optimise_segmented(q, h, control = 1.5)))
  expect_match(out[2], "converged: yes")
  expect_match(out[3], "valid: yes")
})

# ---- the constrained fitter's fallback is recorded -----------------------------------------

test_that("a limb that keeps its unconstrained fit is recorded in provenance and history, not only warned about", {
  d <- fit_data()
  clean <- suppressWarnings(rate_optimise_constrained(d$q, d$h, control = 1.5))
  expect_equal(nrow(rating_provenance(clean)$constrained_fallbacks), 0L)
  expect_true(is.na(rating_history(clean)$note[nrow(rating_history(clean))]))

  # Refuse only the constrained refit, whose start has no C; the unconstrained
  # fit that comes first must still work.
  # nlsLM reads `weights` as a bare column name, so the call is rebuilt and
  # evaluated in the caller's frame, not passed through `...`.
  testthat::local_mocked_bindings(nlsLM = function(...) {
    cl <- sys.call()
    cl[[1L]] <- quote(minpack.lm::nlsLM)
    start <- eval(cl$start, parent.frame())
    if ("C" %in% names(start)) eval(cl, parent.frame()) else stop("refit refused")
  })
  expect_warning(
    fb <- rate_optimise_constrained(d$q, d$h, control = 1.5),
    "failed to converge under the junction constraint"
  )
  rec <- rating_provenance(fb)$constrained_fallbacks
  expect_equal(rec$limb, 2L)
  expect_match(rec$reason, "failed to converge")
  hist <- rating_history(fb)
  expect_match(hist$note[nrow(hist)], "limb 2 kept the unconstrained fit")
  # The limb was not aligned, so it is the unconstrained coefficients.
  expect_false(fb@limbs$aligned[2] %in% TRUE)
})
