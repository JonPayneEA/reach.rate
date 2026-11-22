# ============================================================ #
# Tool:         reference_cases / reference_case / check_reference_cases
# Description:  Ten synthetic cases, each with a KNOWN true rating, that the
#               guided workflow is checked against (Release C). A case passes
#               when the fitted curve stays inside a stated envelope around the
#               truth, the fit converged and is valid, and the assessment raises
#               the check the case was designed to trigger. They are exported so
#               that the same check can be run on any installation, such as a
#               target machine, and not only in the package's own tests.
# Author:       Jonathan Payne, Environment Agency Flood Forecasting
# Created:      22/11/2026
# Inputs:       None (the data are generated, with fixed seeds).
# Outputs:      Case descriptions, case data and truth, and a pass/fail table.
# Dependencies: data.table
# Tier:         3 (operational forecasting support; see the project governance
#               notes before live use)
# ============================================================ #

#' @include fit_rating.R assess_rating.R invariants.R
NULL

# Run `code` under a fixed seed and put the caller's random number state back,
# so that building a case never disturbs the user's own seed.
.with_seed <- function(seed, code) {
  had <- exists(".Random.seed", envir = globalenv(), inherits = FALSE)
  old <- if (had) get(".Random.seed", envir = globalenv(), inherits = FALSE) else NULL
  on.exit({
    if (had) assign(".Random.seed", old, envir = globalenv())
    else if (exists(".Random.seed", envir = globalenv(), inherits = FALSE)) rm(".Random.seed", envir = globalenv())
  }, add = TRUE)
  set.seed(seed)
  force(code)
}

.rc_power <- function(C, a, n) function(h) C * pmax(h - a, 0)^n
.rc_obs <- function(h, truth, sd) data.frame(stage_m = h, discharge_cms = truth(h) * exp(stats::rnorm(length(h), sd = sd)))

# The ten cases. Each returns its data, the true rating, and how it is judged.
.reference_case_specs <- function() {
  t1 <- .rc_power(3.2, 0.1, 1.6)
  t2 <- function(h) ifelse(h < 1.6, 3.2 * h^1.6, 3.2 * 1.6^1.6 * (h / 1.6)^2.9)
  t_old <- .rc_power(3, 0, 1.5); t_new <- .rc_power(4, 0, 1.5)
  list(
    single_limb = list(
      title = "One limb, clean data", seed = 101L, envelope = 0.03, designed_check = NA_character_,
      purpose = "The ordinary case: one control, 30 well-spread gaugings, 2% scatter. The baseline everything else is read against.",
      not_tested = "Anything about real stations: no shifts, no outliers, no structure.",
      truth = t1, fit_args = list(),
      data = function() .rc_obs(seq(0.3, 3, length.out = 30), t1, 0.02)),
    two_limbs = list(
      title = "Two limbs with a real break at 1.6 m", seed = 102L, envelope = 0.10, designed_check = "limb_continuity",
      purpose = "A control that changes (exponent 1.6 to 2.9). The fit uses the break as given. Independently fitted limbs rarely meet exactly, and the assessment says so.",
      not_tested = "Finding the break: suggest_breakpoints() is not used. A statistical search can miss a real break.",
      truth = t2, fit_args = list(controls = 1.6),
      data = function() .rc_obs(round(seq(0.3, 3.4, length.out = 50), 3), t2, 0.03)),
    heavy_noise = list(
      title = "Heavy scatter, 20%", seed = 103L, envelope = 0.35, designed_check = "residual_spread",
      purpose = "Gauging error far above what a good station has. The curve is recovered only loosely, and the assessment must say the scatter is high.",
      not_tested = "That the loose envelope is acceptable for any use. It is the most the method promises at this noise.",
      truth = t1, fit_args = list(),
      data = function() .rc_obs(seq(0.3, 3, length.out = 40), t1, 0.20)),
    sparse_top = list(
      title = "Only two gaugings in the top fifth", seed = 104L, envelope = 0.06, designed_check = "upper_range_support",
      purpose = "Dense gaugings to 2 m and two above. The fit still tracks the truth, but the assessment must warn that the top is thinly supported.",
      not_tested = "Whether a different truth above the top gaugings would be caught: nothing can.",
      truth = t1, fit_args = list(),
      data = function() .rc_obs(c(seq(0.3, 2, length.out = 30), 2.6, 3.2), t1, 0.02)),
    isolated_high = list(
      title = "One isolated gauging 22% high at 3.4 m", seed = 105L, envelope = 0.08, designed_check = "influential_gaugings",
      purpose = "A single high gauging far from the rest drags the top of the curve. Judged only below 2 m, where the data are dense; the assessment must flag the influence.",
      not_tested = "The curve above 2 m, which this gauging controls. Whether the gauging is right is a question for a person.",
      truth = t1, fit_args = list(), range = c(0.3, 2.0),
      data = function() { d <- .rc_obs(c(seq(0.3, 2, length.out = 28), 3.4), t1, 0.025); d$discharge_cms[29L] <- t1(3.4) * 1.22; d }),
    rating_shift = list(
      title = "Channel shift, old and recent gaugings", seed = 106L, envelope = 0.10, designed_check = NA_character_,
      purpose = "Gaugings from 2008 follow C = 3 and from 2024 follow C = 4. With a three-year half-life the fit follows today's channel. The flat fit must be clearly worse.",
      not_tested = "Detecting the shift. Recency weighting acts on a judgement that the channel moved; it does not make it.",
      truth = t_new,
      fit_args = list(age_halflife = 365 * 3, reference_time = as.POSIXct("2025-01-01", tz = "UTC")),
      contrast_ratio = 2,
      data = function() {
        st <- seq(0.3, 3, by = 0.15)
        rbind(data.frame(.rc_obs(st, t_old, 0.02), observation_time = as.POSIXct("2008-06-01", tz = "UTC")),
              data.frame(.rc_obs(st, t_new, 0.02), observation_time = as.POSIXct("2024-06-01", tz = "UTC")))
      }),
    zero_flow_offset = list(
      title = "Zero-flow stage at 0.8 m", seed = 107L, envelope = 0.03, designed_check = NA_character_,
      purpose = "A datum far from zero, with gaugings only above it. The zero-flow stage a must be recovered, not assumed to be zero.",
      not_tested = "A zero-flow stage below the lowest gauging by a long way, which no data can pin down.",
      truth = .rc_power(4.1, 0.8, 1.8), fit_args = list(), params = list(a = c(0.8, 0.1)),
      data = function() .rc_obs(seq(0.9, 3.5, length.out = 30), .rc_power(4.1, 0.8, 1.8), 0.02)),
    steep_exponent = list(
      title = "Steep control, exponent 3", seed = 108L, envelope = 0.03, designed_check = NA_character_,
      purpose = "A V-notch-like control. The exponent must be recovered near 3, inside the range the assessment treats as usual.",
      not_tested = "Exponents outside 1 to 3.5, which the assessment flags as hydraulically unusual.",
      truth = .rc_power(2.0, 0.2, 3.0), fit_args = list(), params = list(n = c(3.0, 0.2)),
      data = function() .rc_obs(seq(0.4, 2.6, length.out = 30), .rc_power(2.0, 0.2, 3.0), 0.02)),
    wide_exponent = list(
      title = "Wide control, exponent 1.05", seed = 109L, envelope = 0.06, designed_check = NA_character_,
      purpose = "An exponent at the bottom of the usual range. The fit must not be pushed off it by the lower bound.",
      not_tested = "Exponents below 1.",
      truth = .rc_power(6.0, 0.05, 1.05), fit_args = list(), params = list(n = c(1.05, 0.2)),
      data = function() .rc_obs(seq(0.3, 3, length.out = 30), .rc_power(6.0, 0.05, 1.05), 0.02)),
    few_gaugings = list(
      title = "Six gaugings", seed = 110L, envelope = 0.12, designed_check = "few_gaugings",
      purpose = "Barely enough to fit three parameters. The curve is still close, with a wider envelope, and the assessment must say the evidence is thin.",
      not_tested = "Whether six gaugings are enough for any use. The envelope is for this one realisation.",
      truth = t1, fit_args = list(),
      data = function() .rc_obs(c(0.35, 0.7, 1.1, 1.7, 2.3, 2.9), t1, 0.03))
  )
}

.rc_get <- function(id) {
  specs <- .reference_case_specs()
  if (!is.character(id) || length(id) != 1L || is.na(id) || !id %in% names(specs)) {
    stop("reference_case(): id must be one of ", paste(names(specs), collapse = ", "), call. = FALSE)
  }
  spec <- specs[[id]]
  spec$id <- id
  spec$data <- .with_seed(spec$seed, spec$data())
  if (is.null(spec$range)) spec$range <- range(spec$data$stage_m)
  spec
}

#' The reference cases
#'
#' @description
#' Ten synthetic stations, each with a rating that is **known**, so that a fit
#' can be judged against the truth, which real gaugings never allow. Each case
#' says what it tests and, as importantly, what it does not.
#'
#' **These ten were written by the package's author.** They are not the ten
#' cases of any external brief, which was never supplied. They are a starting
#' point for a reviewer to extend, and passing them is necessary, not
#' sufficient: ten tidy synthetic stations say nothing about a real one.
#'
#' A case passes when the fitted curve stays inside a stated **envelope** of the
#' truth over its gauged range (a maximum relative error, not exact
#' coefficients), the fit converged and is valid, and the assessment raises the
#' one check the case was built to trigger. Run them with
#' [check_reference_cases()].
#'
#' @return `reference_cases()`: a `data.table`, one row per case, with `id`,
#'   `title`, `purpose`, `not_tested`, `envelope` and `designed_check` (the
#'   assessment check the case should raise, `NA` where none).
#'
#' @seealso [reference_case()] for one case's data and truth,
#'   [check_reference_cases()] to run them, [assess_rating()].
#'
#' @examples
#' reference_cases()[, c("id", "title", "envelope")]
#' @export
reference_cases <- function() {
  specs <- .reference_case_specs()
  data.table::data.table(
    id = names(specs),
    title = vapply(specs, `[[`, "", "title"),
    purpose = vapply(specs, `[[`, "", "purpose"),
    not_tested = vapply(specs, `[[`, "", "not_tested"),
    envelope = vapply(specs, `[[`, 0, "envelope"),
    designed_check = vapply(specs, function(s) s$designed_check, "")
  )
}

#' One reference case: its data and its truth
#'
#' @param id The case, one of `reference_cases()$id`.
#'
#' @return A list: `id`, `title`, `purpose`, `not_tested`; `data`, a
#'   `data.frame` of `stage_m` and `discharge_cms` (with an `observation_time`
#'   column where the case needs one), identical on every call; `truth`, a
#'   function from stage to the true discharge; `fit_args`, the extra arguments
#'   the case is fitted with; `range`, the stage range it is judged over;
#'   `envelope`, the largest relative error allowed there; and `designed_check`.
#'
#' @seealso [reference_cases()], [check_reference_cases()].
#'
#' @examples
#' case <- reference_case("two_limbs")
#' fit <- do.call(fit_rating, c(list(case$data, quiet = TRUE), case$fit_args))
#' stage <- seq(case$range[1], case$range[2], length.out = 5)
#' round(apply_rating(fit, stage)$discharge / case$truth(stage), 3)
#' @export
reference_case <- function(id) .rc_get(id)

#' Run the reference cases
#'
#' @description
#' Fits each case with [fit_rating()], assesses it with [assess_rating()], and
#' judges it against the known truth. Use it to check that an installation
#' behaves as the package's own tests say it should, for example on a machine
#' the package is about to be used on. It takes a few seconds.
#'
#' For each case it reports the largest relative error of the fitted curve
#' against the truth over the case's range, whether that is inside the
#' envelope, whether the optimiser converged and the rating is valid, any
#' parameters the case checks, whether the assessment raised the designed
#' check, and, for the channel-shift case, whether the flat fit is clearly
#' worse than the weighted one.
#'
#' @param ids Which cases to run: a character vector of `reference_cases()$id`,
#'   or `NULL` (default) for all ten.
#'
#' @return A `data.table`, one row per case: `id`, `title`, `max_rel_error`,
#'   `envelope`, `within_envelope`, `converged`, `valid`, `parameters_ok`,
#'   `designed_check`, `check_raised`, `contrast_ok` and `passed`.
#'
#' @seealso [reference_cases()], [reference_case()].
#'
#' @examples
#' res <- check_reference_cases(c("single_limb", "few_gaugings"))
#' res[, c("id", "max_rel_error", "envelope", "passed")]
#' @export
check_reference_cases <- function(ids = NULL) {
  all_ids <- names(.reference_case_specs())
  if (is.null(ids)) ids <- all_ids
  if (!is.character(ids) || !length(ids) || anyNA(ids) || !all(ids %in% all_ids)) {
    stop("check_reference_cases(): ids must be NULL or some of ", paste(all_ids, collapse = ", "), call. = FALSE)
  }
  ref_time <- as.POSIXct("2025-01-01", tz = "UTC")
  rel_error <- function(fit, case) {
    stage <- seq(case$range[1L], case$range[2L], length.out = 200L)
    est <- suppressWarnings(apply_rating(fit, stage)$discharge)
    max(abs(est / case$truth(stage) - 1))
  }
  rows <- lapply(ids, function(id) {
    case <- .rc_get(id)
    fit <- do.call(fit_rating, c(list(case$data, quiet = TRUE), case$fit_args))
    err <- rel_error(fit, case)
    limbs <- rating_limbs(fit, all_columns = TRUE)
    converged <- all(limbs$converged %in% TRUE)
    checks <- data.table::as.data.table(assessment_checks(assess_rating(fit, reference_time = ref_time)))
    valid <- !any(assessment_checks(rating_invariants(fit))$status == "fail")
    params_ok <- if (is.null(case$params)) TRUE else all(vapply(names(case$params), function(p) {
      abs(limbs[[p]][1L] - case$params[[p]][1L]) <= case$params[[p]][2L]
    }, logical(1)))
    raised <- if (is.na(case$designed_check)) NA else any(checks$check_id == case$designed_check & checks$status != "pass")
    contrast_ok <- if (is.null(case$contrast_ratio)) NA else {
      flat_args <- case$fit_args[setdiff(names(case$fit_args), c("age_halflife", "age_min_weight", "reference_time"))]
      flat <- do.call(fit_rating, c(list(case$data, quiet = TRUE), flat_args))
      rel_error(flat, case) >= case$contrast_ratio * err
    }
    data.table::data.table(
      id = id, title = case$title, max_rel_error = err, envelope = case$envelope,
      within_envelope = err <= case$envelope, converged = converged, valid = valid, parameters_ok = params_ok,
      designed_check = case$designed_check, check_raised = raised, contrast_ok = contrast_ok,
      passed = err <= case$envelope && converged && valid && params_ok && isTRUE(raised %in% c(TRUE, NA)) &&
        isTRUE(contrast_ok %in% c(TRUE, NA))
    )
  })
  data.table::rbindlist(rows)
}
