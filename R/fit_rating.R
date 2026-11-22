# ============================================================ #
# Tool:         fit_rating
# Description:  The guided entry point (tranche B1). Takes evidence, fits a
#               rating with sensible defaults, and records how: the call,
#               the seed, what was used and what was left out and why,
#               where any breakpoints came from, and the range the rating
#               may be applied over. Orchestrates rate_optimise() and
#               rate_optimise_segmented(); an expert can still call those
#               directly.
# Author:       Jonathan Payne
# Created:      2026-11-18
# Tier:         3
# Inputs:       A FlodeEvidence, or a table as_flode_evidence() accepts
#               (including the output of read_gaugings()).
# Outputs:      A FlodeRating or FlodeSegmentedRating.
# Dependencies: data.table
# ============================================================ #

#' @include flode_evidence.R flode_classes.R invariants.R
NULL

# Why a row of evidence is not used in a fit, or NA if it is.
.fit_exclusions <- function(ev, objective) {
  st <- ev$stage_m
  q <- ev$discharge_cms
  inc <- ev$included
  reason <- rep(NA_character_, nrow(ev))
  marked <- !inc
  reason[marked] <- ifelse(is.na(ev$exclusion_reason[marked]), "marked as excluded in the evidence",
                           paste0("marked as excluded: ", ev$exclusion_reason[marked]))
  open <- is.na(reason)
  bad <- open & (!is.finite(st) | !is.finite(q))
  reason[bad] <- "stage or discharge missing or not finite"
  open <- is.na(reason)
  neg <- open & q < 0
  reason[neg] <- "negative discharge"
  open <- is.na(reason)
  if (objective == "relative") {
    zero <- open & q == 0
    reason[zero] <- "zero discharge: the relative objective needs positive discharge (use objective = \"absolute\" to keep it)"
  }
  reason
}

# Where an adopted breakpoint came from. A breakpoint is a modelling decision,
# and what it rests on differs a great deal: a surveyed change of control is
# not the same kind of reason as a better AIC.
.breakpoint_origins <- c("field_evidence", "cross_section", "structure_geometry", "user_judgement",
                         "statistical_candidate", "existing_rating", "other")

#' Where a breakpoint can come from
#'
#' @description
#' The controlled vocabulary for the origin of a breakpoint, recorded by
#' [fit_rating()]. A breakpoint is a modelling decision, and what it rests on
#' matters to anyone who reviews the rating:
#'
#' * `field_evidence`: observed at the site, for example a change of control
#'   seen during a gauging visit;
#' * `cross_section`: read from a surveyed cross-section (bankfull, a change in
#'   channel shape);
#' * `structure_geometry`: from the geometry of a structure (a weir crest, an
#'   overtopping level);
#' * `user_judgement`: the analyst's decision, without a recorded basis;
#' * `statistical_candidate`: put forward by [suggest_breakpoints()] and not
#'   otherwise supported;
#' * `existing_rating`: carried over from a rating already in use;
#' * `other`.
#'
#' @return A character vector.
#'
#' @seealso [fit_rating()], [suggest_breakpoints()]
#'
#' @examples
#' breakpoint_origins()
#'
#' @export
breakpoint_origins <- function() .breakpoint_origins

#' Fit a rating from evidence
#'
#' @description
#' The guided way to a rating. Give it evidence and it fits one, with
#' defaults chosen so that a careful analyst would not argue, and it records
#' what it did. An expert who wants more control can still call
#' [rate_optimise()] or [rate_optimise_segmented()] directly; this
#' function calls them.
#'
#' What it decides for you, and where to change it:
#'
#' * **One limb.** A single equation \eqn{Q = C(H - a)^n} across the whole
#'   range, unless you supply `controls` (breakpoint stages) or ask for
#'   `limbs = "suggest"`. A rating with several limbs is a modelling
#'   decision and is never made silently.
#' * **Suggested breakpoints are advisory.** With `limbs = "suggest"` the
#'   function uses [suggest_breakpoints()], records that the breakpoints
#'   came from a statistical search and not from field evidence, and says
#'   so each time the rating is printed. They are candidates for a person
#'   to review. Breakpoints you give in `controls` are recorded with the
#'   origin you state in `breakpoint_origin` (`"user_judgement"` if you do
#'   not), so a reviewer can tell a surveyed change of control from a
#'   better AIC. See [breakpoint_origins()].
#' * **The relative objective.** Gauging error is typically proportional to
#'   the reading, so the fit minimises error in log discharge. Use
#'   `objective = "absolute"` for [rate_optimise()]'s own default. See
#'   `vignette("mathematical_contract")` for both.
#' * **What is used.** Rows marked `included = FALSE`, rows with a missing
#'   or non-finite stage or discharge, negative discharge, and (for the
#'   relative objective) zero discharge are not used. Each is listed with
#'   its reason in the rating's provenance, and none is deleted from your
#'   evidence.
#' * **Where it may be applied.** A rating made here can be applied only
#'   within the stage range it was gauged over until you state the range it
#'   may be used over, with `operational_limits` or
#'   [set_operational_limits()]. That states the decision, and its basis, to
#'   use the rating there.
#'
#' The rating stores the call, the seed, every starting point tried, and
#' the evidence it used with each row's `evidence_id`, so it can be
#' reproduced and checked.
#'
#' @param evidence A [FlodeEvidence], or a `data.frame` or `data.table` that
#'   [as_flode_evidence()] accepts, including the table [read_gaugings()]
#'   returns.
#' @param controls Numeric vector of breakpoint stages, or `NULL` (default)
#'   for one limb. Each must lie inside the stage range of the evidence
#'   used.
#' @param breakpoint_origin Where the breakpoints in `controls` came from:
#'   one value from [breakpoint_origins()] for all of them, or one per
#'   breakpoint. Default `"user_judgement"`. Ignored for `limbs = "suggest"`,
#'   whose breakpoints are always `"statistical_candidate"`.
#' @param limbs `"one"` (default) or `"suggest"`. `"suggest"` finds
#'   breakpoints with [suggest_breakpoints()] and uses those it selects,
#'   marked as advisory. Not allowed together with `controls`.
#' @param model `"independent"` (default) fits each limb separately with
#'   [rate_optimise()]. `"segmented"` fits one joint equation with
#'   [rate_optimise_segmented()].
#' @param objective `"relative"` (default) or `"absolute"`.
#' @param age_halflife,age_min_weight,reference_time Optional recency
#'   weighting, as in [rate_optimise()]: a half-life in days, the weight
#'   floor, and the time ages are measured from (`NULL` is the latest
#'   gauging). Needs an `observation_time` on every row used.
#' @param n_boot Number of bootstrap refits per limb for coefficient
#'   uncertainty. Default 0. Only for `model = "independent"`.
#' @param seed Integer or `NULL`. Used for the bootstrap, and recorded so a
#'   fit can be repeated.
#' @param operational_limits `NULL` (default) or `c(lower, upper)`: the stage
#'   range, in metres, over which the rating may be applied.
#' @param operational_basis Character. Why that range: for example the
#'   gauged range, a structure's limit, or a review decision.
#' @param quiet Logical. `TRUE` suppresses the summary message.
#'
#' @return A [FlodeRating] (or [FlodeSegmentedRating] for
#'   `model = "segmented"`) whose `@gaugings` is the evidence that was used,
#'   with each row's `evidence_id`, and whose provenance records the call,
#'   seed, exclusions, breakpoint origin and operational limits (read it with
#'   [rating_provenance()]). Its lifecycle is `"draft"`.
#'
#' @seealso [read_gaugings()], [validate_gaugings()], [set_operational_limits()],
#'   [rate_optimise()], [rating_provenance()]
#'
#' @examples
#' set.seed(1)
#' gaugings <- data.frame(stage_m = round(seq(0.4, 3, length.out = 20), 3))
#' gaugings$discharge_cms <- round(3.2 * gaugings$stage_m^1.6 * exp(rnorm(20, sd = 0.03)), 3)
#' fit <- fit_rating(gaugings)
#' fit
#'
#' # The rating can be applied within the range it was gauged over.
#' apply_rating(fit, c(0.8, 1.5, 2.5))
#'
#' # To apply it more widely, state the range and why.
#' wider <- set_operational_limits(fit, 0.2, 3.5, basis = "channel control confirmed to 3.5 m")
#' apply_rating(wider, c(0.3, 3.4))
#'
#' # What the fit recorded.
#' str(rating_provenance(fit)$fit_rating[c("call", "model", "objective", "n_used")])
#'
#' @export
fit_rating <- function(evidence, controls = NULL, breakpoint_origin = "user_judgement", limbs = c("one", "suggest"),
                       model = c("independent", "segmented"), objective = c("relative", "absolute"),
                       age_halflife = NULL, age_min_weight = 0.1, reference_time = NULL,
                       n_boot = 0L, seed = NULL, operational_limits = NULL,
                       operational_basis = NA_character_, quiet = FALSE) {
  cl <- match.call()
  limbs <- match.arg(limbs)
  model <- match.arg(model)
  objective <- match.arg(objective)
  fn <- "fit_rating()"
  ev <- as_flode_evidence(evidence)
  if (nrow(ev) == 0L) stop(fn, ": there is no evidence to fit", call. = FALSE)

  if (!is.null(controls) && limbs == "suggest") {
    stop(fn, ": give breakpoints in `controls` or ask for limbs = \"suggest\", not both. ",
         "Breakpoints you supply are recorded as yours; suggested ones as advisory.", call. = FALSE)
  }
  if (!is.null(controls) && (!is.numeric(controls) || any(!is.finite(controls)) || anyDuplicated(controls))) {
    stop(fn, ": controls must be a vector of distinct, finite stages, or NULL", call. = FALSE)
  }
  if (model == "segmented" && n_boot > 0) {
    stop(fn, ": n_boot is only available for model = \"independent\"", call. = FALSE)
  }
  if (!is.null(seed) && (!is.numeric(seed) || length(seed) != 1L)) stop(fn, ": seed must be NULL or one number", call. = FALSE)
  .check_limits(operational_limits, fn)
  if (!is.null(controls)) {
    bad <- setdiff(breakpoint_origin, .breakpoint_origins)
    if (length(bad) || !length(breakpoint_origin) || !(length(breakpoint_origin) %in% c(1L, length(controls)))) {
      stop(sprintf("%s: breakpoint_origin must be one value, or one per breakpoint, from: %s.%s", fn,
                   paste(.breakpoint_origins, collapse = ", "),
                   if (length(bad)) sprintf(" Not recognised: %s.", paste(bad, collapse = ", ")) else ""), call. = FALSE)
    }
  }

  reason <- .fit_exclusions(ev, objective)
  used <- which(is.na(reason))
  if (length(used) < 4L) {
    counts <- table(reason[!is.na(reason)])
    why <- if (length(counts)) paste(sprintf("%d %s", as.integer(counts), names(counts)), collapse = "; ") else "none excluded"
    stop(sprintf(
      "%s: only %d usable gauging%s of %d, and a limb needs more than 3. Rows not used: %s. Check the evidence with validate_gaugings().",
      fn, length(used), if (length(used) == 1L) "" else "s", nrow(ev), why
    ), call. = FALSE)
  }
  h <- ev$stage_m[used]
  q <- ev$discharge_cms[used]
  obs <- ev$observation_time[used]

  if (!is.null(age_halflife) && anyNA(obs)) {
    stop(sprintf("%s: age_halflife needs an observation_time for every gauging used; %d %s missing.",
                 fn, sum(is.na(obs)), if (sum(is.na(obs)) == 1L) "is" else "are"), call. = FALSE)
  }
  obs_arg <- if (!is.null(age_halflife) || !anyNA(obs)) obs else NULL

  source <- "none"
  stages <- numeric(0)
  origin <- character(0)
  candidates <- NULL
  if (!is.null(controls)) {
    ord <- order(controls)
    stages <- controls[ord]
    origin <- rep_len(breakpoint_origin, length(controls))[ord]
    source <- "user"
    if (any(stages <= min(h) | stages >= max(h))) {
      stop(sprintf("%s: controls must lie strictly inside the stage range of the evidence used (%.3g to %.3g m).",
                   fn, min(h), max(h)), call. = FALSE)
    }
  } else if (limbs == "suggest") {
    candidates <- suggest_breakpoints(q, h)
    stages <- sort(candidates[preferred == TRUE]$candidate_stage)
    source <- if (length(stages)) "statistical_candidate" else "none"
    origin <- rep("statistical_candidate", length(stages))
  }
  ctl <- if (length(stages)) stages else NULL

  fit <- if (model == "independent") {
    rate_optimise(q, h, gauging_datetime = obs_arg, control = ctl, n_boot = n_boot, boot_seed = seed,
                  objective = objective, age_halflife = age_halflife, age_min_weight = age_min_weight,
                  reference_datetime = reference_time)
  } else {
    rate_optimise_segmented(q, h, gauging_datetime = obs_arg, control = ctl, objective = objective,
                            age_halflife = age_halflife, age_min_weight = age_min_weight,
                            reference_datetime = reference_time)
  }

  # Carry the evidence ids through. The fitter works on bare vectors, in the
  # order given and without reordering, so its gaugings table lines up with
  # the rows used; its own extra columns (limb, age weight) are attached to
  # the evidence rows, which keep their ids, sources and notes.
  fit_g <- as.data.table(fit@gaugings)
  kept <- ev[used]
  if (!isTRUE(all.equal(as.numeric(fit_g$stage_m), as.numeric(kept$stage_m)))) {
    stop(fn, ": internal error: the fitted gaugings no longer line up with the evidence used.", call. = FALSE)
  }
  carried <- intersect(c("limb", "age_weight", "gauging_datetime"), names(fit_g))
  for (col in carried) set(kept, j = col, value = fit_g[[col]])
  fit@gaugings <- kept

  # The values of the rows left out are kept with the reason, so they can be
  # shown (muted) on a plot and checked later; they are no longer in @gaugings.
  left_out <- !is.na(reason)
  excluded <- data.table(evidence_id = ev$evidence_id[left_out], reason = reason[left_out],
                         stage_m = ev$stage_m[left_out], discharge_cms = ev$discharge_cms[left_out],
                         source_type = ev$source_type[left_out])
  limits <- if (is.null(operational_limits)) NULL else list(
    lower_stage_m = operational_limits[1L], upper_stage_m = operational_limits[2L], basis = operational_basis
  )
  guided <- list(
    call = paste(deparse(cl), collapse = " "), version = .tool_version(), seed = seed,
    model = model, objective = objective, n_evidence = nrow(ev), n_used = length(used),
    excluded = excluded, gauged_range = range(h),
    breakpoints = list(stages = stages, origin = origin, source = source, advisory = any(origin == "statistical_candidate")),
    candidates = candidates
  )
  fit@provenance <- c(fit@provenance, list(fit_rating = guided, operational_limits = limits))

  if (!quiet) {
    message(sprintf("fit_rating(): %d of %d rows used; %s objective, %s model, %s.",
                    length(used), nrow(ev), objective, model,
                    if (!length(stages)) "one limb" else sprintf("%d limbs (breakpoints %s, %s)", length(stages) + 1L,
                      paste(format(stages, digits = 4), collapse = ", "),
                      paste(unique(origin), collapse = ", "))))
    if (nrow(excluded)) {
      short <- sub(":.*$", "", sub("^marked as excluded: ", "", excluded$reason))
      tab <- sort(table(short), decreasing = TRUE)
      message("  Not used: ", paste(sprintf("%d (%s)", as.integer(tab), names(tab)), collapse = "; "), ".")
    }
    if (is.null(limits)) {
      message("  No operational limits set: stages beyond the gauged range are returned and flagged as extrapolation. See set_operational_limits().")
    }
  }
  fit
}

.check_limits <- function(limits, fn) {
  if (is.null(limits)) return(invisible(TRUE))
  if (!is.numeric(limits) || length(limits) != 2L || any(!is.finite(limits)) || limits[1L] >= limits[2L]) {
    stop(fn, ": operational_limits must be c(lower, upper) in metres, finite, with lower below upper", call. = FALSE)
  }
  invisible(TRUE)
}

#' State the stage range a rating may be applied over
#'
#' @description
#' A rating made by [fit_rating()] may be applied beyond the stage range it
#' was gauged over, because forecast models need discharge above the highest
#' gauging. Without limits, such stages are returned, flagged `extrapolation`
#' and warned about. Stating limits here turns that into a boundary: the range
#' is a decision, not a property of the data. It might be the gauged range, a
#' structure's limit, a hydraulic argument for extrapolating to a stated
#' stage, or a review outcome. Saying it, and saying why, is what makes the
#' application defensible.
#'
#' The rating is returned as a new version. Its earlier state is kept in
#' [rating_history()], and its lifecycle goes back to `"draft"`, since a
#' change to where a rating may be used is a change a reviewer should see.
#' Stages outside the limits are refused by [apply_rating()]; stages inside
#' them but beyond the gauged range are computed and flagged `extrapolated`.
#'
#' @param x A [FlodeRating] or [FlodeSegmentedRating].
#' @param lower_stage_m,upper_stage_m The stage range in metres, lower below
#'   upper.
#' @param basis Character. Why this range.
#'
#' @return A copy of `x` with the limits in its provenance.
#'
#' @seealso [fit_rating()], [rating_provenance()], [rating_history()]
#'
#' @examples
#' set.seed(2)
#' stage_m <- seq(0.5, 3, length.out = 15)
#' fit <- fit_rating(
#'   data.frame(stage_m = stage_m, discharge_cms = 3 * stage_m^1.6 * exp(rnorm(15, sd = 0.03))),
#'   quiet = TRUE
#' )
#' limited <- set_operational_limits(fit, 0.4, 3.2, basis = "gauged range plus 0.2 m of judgement")
#' rating_provenance(limited)$operational_limits
#' rating_history(limited)[, .(class, lifecycle, note)]
#'
#' @export
set_operational_limits <- function(x, lower_stage_m, upper_stage_m, basis = NA_character_) {
  if (!(S7_inherits(x, FlodeRating) || S7_inherits(x, FlodeSegmentedRating))) {
    stop("set_operational_limits(): x must be a FlodeRating or FlodeSegmentedRating", call. = FALSE)
  }
  .check_limits(c(lower_stage_m, upper_stage_m), "set_operational_limits()")
  old <- x
  prov <- x@provenance
  prov$operational_limits <- list(lower_stage_m = lower_stage_m, upper_stage_m = upper_stage_m, basis = basis)
  prov$amendment_note <- sprintf("operational limits set to %.4g to %.4g m%s", lower_stage_m, upper_stage_m,
                                 if (is.na(basis)) "" else paste0(" (", basis, ")"))
  x@provenance <- prov
  x@lifecycle <- "draft"
  x@previous <- old
  x
}

# A guided rating with no limits stated may be applied beyond its gauged range
# (forecast models need that): the values are returned, flagged as
# extrapolation in the support column, with one warning per call. One with
# limits stated is refused beyond them: the analyst chose that range.
# Plain fits from rate_optimise() are not restricted.
.require_operational_range <- function(fit, stage_dt, stage_col) {
  guided <- fit@provenance$fit_rating
  if (is.null(guided)) return(invisible(TRUE))
  st <- .coerce_stage_input(stage_dt, stage_col)[[stage_col]]
  if (is.null(st)) return(invisible(TRUE))
  st <- st[is.finite(st)]
  if (!length(st)) return(invisible(TRUE))
  lim <- fit@provenance$operational_limits
  if (is.null(lim)) {
    g <- guided$gauged_range
    outside <- sum(st < g[1L] | st > g[2L])
    if (outside) {
      warning(sprintf(
        paste0("apply_rating(): %d of %d stage value(s) lie beyond the gauged range (%.4g to %.4g m; stages %.4g to %.4g m) and are ",
               "extrapolated. They are flagged 'extrapolation' in the support column. This rating has no operational limits: ",
               "state the range it may be used over, and why, with set_operational_limits(x, lower, upper, basis)."),
        outside, length(st), g[1L], g[2L], min(st), max(st)
      ), call. = FALSE)
    }
  } else {
    outside <- sum(st < lim$lower_stage_m | st > lim$upper_stage_m)
    if (outside) {
      stop(sprintf(
        paste0("apply_rating(): %d of %d stage value(s) fall outside this rating's operational limits (%.4g to %.4g m%s). ",
               "Values range from %.4g to %.4g m. Widen the limits with set_operational_limits() if that is a decision you can state."),
        outside, length(st), lim$lower_stage_m, lim$upper_stage_m,
        if (is.na(lim$basis)) "" else paste0("; basis: ", lim$basis), min(st), max(st)
      ), call. = FALSE)
    }
  }
  invisible(TRUE)
}

# The extra lines a guided rating prints: where its breakpoints came from
# and what range it may be applied over.
.guided_lines <- function(x) {
  guided <- x@provenance$fit_rating
  if (is.null(guided)) return(character(0))
  bp <- guided$breakpoints
  bp_line <- if (!length(bp$stages)) "one limb" else sprintf(
    "%s (%s)", paste(format(bp$stages, digits = 4), collapse = ", "),
    paste(ifelse(bp$origin == "statistical_candidate", "statistical_candidate: advisory, needs review", bp$origin), collapse = "; ")
  )
  lim <- x@provenance$operational_limits
  lim_line <- if (is.null(lim)) {
    sprintf("not set; stages beyond the gauged range %.4g to %.4g m are flagged as extrapolation", guided$gauged_range[1L], guided$gauged_range[2L])
  } else {
    sprintf("%.4g to %.4g m%s", lim$lower_stage_m, lim$upper_stage_m, if (is.na(lim$basis)) "" else paste0(" (", lim$basis, ")"))
  }
  c(sprintf("  breakpoints: %s", bp_line),
    sprintf("  evidence: %d of %d rows used", guided$n_used, guided$n_evidence),
    sprintf("  operational limits: %s", lim_line))
}
