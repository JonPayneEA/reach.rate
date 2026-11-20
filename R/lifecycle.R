# ============================================================ #
# Tool:         set_lifecycle / rating_lifecycle
# Description:  Record who changed a rating's lifecycle, when and why (Release
#               C). A rating starts as a draft and the package never moves it
#               on by itself: every change is made by a named person, with a
#               reason, and is kept in the rating's history. Approval has its
#               own rules: it must follow a review, by someone other than the
#               person who submitted it (unless that is explicitly allowed),
#               and it is refused for a rating that fails its own validity
#               checks.
# Author:       Jonathan Payne, Environment Agency Flood Forecasting
# Created:      20/11/2026
# Inputs:       A FlodeRating or FlodeSegmentedRating.
# Outputs:      A new rating (set_lifecycle) or the record of changes
#               (rating_lifecycle).
# Dependencies: S7, data.table
# Tier:         3 (operational forecasting support; see the project governance
#               notes before live use)
# ============================================================ #

#' @include flode_classes.R invariants.R
NULL

# Where a rating may go from each state. Superseded and withdrawn are final: a
# rating that has been replaced or pulled is not brought back, a new one is made.
.lifecycle_transitions <- list(
  draft        = c("under_review", "withdrawn"),
  under_review = c("approved", "draft", "withdrawn"),
  approved     = c("under_review", "superseded", "withdrawn"),
  superseded   = character(0),
  withdrawn    = character(0)
)

.lifecycle_log_columns <- c("from", "to", "by", "reason", "at")

.empty_lifecycle_log <- function() {
  data.table::data.table(from = character(), to = character(), by = character(),
                         reason = character(), at = as.POSIXct(character(), tz = "UTC"))
}

.single_text <- function(v, name, fn) {
  if (!is.character(v) || length(v) != 1L || is.na(v) || !nzchar(trimws(v))) {
    stop(fn, ": ", name, " must be a single, non-empty piece of text", call. = FALSE)
  }
  trimws(v)
}

#' Record a change to a rating's lifecycle
#'
#' @description
#' A rating starts as a `"draft"`. This is how a person moves it on, and it is
#' the only way: nothing in the package changes a lifecycle by itself, and
#' nothing sets `"approved"` except this function called by a named person.
#' Each change records **who** made it, **when** and **why**, in the rating's
#' provenance and as a step in [rating_history()]. The earlier version is kept,
#' so the rating can be checked against what it was.
#'
#' The states and where each may go next:
#'
#' | From | May go to |
#' |---|---|
#' | `draft` | `under_review`, `withdrawn` |
#' | `under_review` | `approved`, `draft` (returned for rework), `withdrawn` |
#' | `approved` | `under_review` (re-review), `superseded`, `withdrawn` |
#' | `superseded`, `withdrawn` | nowhere: make a new rating |
#'
#' **Approval has three extra conditions.** It must come from `under_review`,
#' so no rating is approved without having been put up for review. It is refused
#' for a rating that fails its own validity checks ([rating_invariants()]). And
#' it must be by someone other than the person who put it under review, unless
#' you set `allow_self_approval = TRUE`, in which case that is recorded in the
#' reason. The last rule is a proposal, not a decision made for you: whether
#' self-approval should ever be allowed is for the owner of the process to say.
#'
#' Amending a rating (setting its operational limits, aligning its limbs)
#' makes a new draft, because what was reviewed is no longer what exists. That
#' shows in [rating_history()]; the records here stay.
#'
#' @param x A [FlodeRating] or [FlodeSegmentedRating]. A [FlodeRatingTable]
#'   has nowhere to keep who, when and why, and is refused.
#' @param to The lifecycle to move to: one of `"draft"`, `"under_review"`,
#'   `"approved"`, `"superseded"`, `"withdrawn"`.
#' @param by Character. Who is making the change. A name, not a role.
#' @param reason Character. Why. Required for every change.
#' @param at The time of the change. Default now.
#' @param allow_self_approval Logical. If `FALSE` (default), the person who put
#'   a rating under review cannot also approve it. Names are compared ignoring
#'   case and surrounding spaces.
#'
#' @return A new rating with its lifecycle changed. The original is not altered.
#'
#' @seealso [rating_lifecycle()] for the record, [rating_history()],
#'   [rating_invariants()].
#'
#' @examples
#' set.seed(1)
#' stage <- seq(0.3, 3, length.out = 25)
#' gaugings <- data.frame(stage_m = stage,
#'                        discharge_cms = 3 * stage^1.6 * exp(rnorm(25, sd = 0.03)))
#' fit <- fit_rating(gaugings, quiet = TRUE)
#'
#' reviewed <- set_lifecycle(fit, "under_review", by = "A. Analyst",
#'                           reason = "Fitted from the 2024 gaugings; ready for review")
#' approved <- set_lifecycle(reviewed, "approved", by = "B. Reviewer",
#'                           reason = "Checked the assessment and the sensitivity tests")
#' rating_lifecycle(approved)[, c("from", "to", "by")]
#' rating_history(approved)[, c("step", "lifecycle", "note")]
#' @export
set_lifecycle <- function(x, to, by, reason, at = Sys.time(), allow_self_approval = FALSE) {
  fn <- "set_lifecycle()"
  if (S7_inherits(x, FlodeRatingTable)) {
    stop(fn, ": a FlodeRatingTable has nowhere to record who changed its lifecycle, when and why. ",
         "Use a rating from fit_rating() or rate_optimise().", call. = FALSE)
  }
  if (!(S7_inherits(x, FlodeRating) || S7_inherits(x, FlodeSegmentedRating))) {
    stop(fn, ": x must be a FlodeRating or FlodeSegmentedRating, not ", class(x)[1L], call. = FALSE)
  }
  if (missing(to) || !is.character(to) || length(to) != 1L || is.na(to) || !to %in% names(.lifecycle_transitions)) {
    stop(fn, ": to must be one of ", paste(names(.lifecycle_transitions), collapse = ", "), call. = FALSE)
  }
  if (missing(by)) stop(fn, ": by must be a single, non-empty piece of text: who is making this change", call. = FALSE)
  if (missing(reason)) stop(fn, ": reason must be a single, non-empty piece of text: why", call. = FALSE)
  by <- .single_text(by, "by", fn)
  reason <- .single_text(reason, "reason", fn)
  if (!inherits(at, "POSIXct") || length(at) != 1L || is.na(at)) {
    stop(fn, ": at must be a single time (POSIXct)", call. = FALSE)
  }
  if (!is.logical(allow_self_approval) || length(allow_self_approval) != 1L || is.na(allow_self_approval)) {
    stop(fn, ": allow_self_approval must be TRUE or FALSE", call. = FALSE)
  }

  from <- x@lifecycle
  if (identical(from, to)) stop(fn, ": the rating is already ", from, call. = FALSE)
  allowed <- .lifecycle_transitions[[from]]
  if (!to %in% allowed) {
    stop(fn, ": a rating that is ", from, " cannot go to ", to, ". ",
         if (length(allowed)) paste0("From ", from, " it may go to: ", paste(allowed, collapse = ", "), ".")
         else paste0("A ", from, " rating is final: make a new rating."), call. = FALSE)
  }

  log <- rating_lifecycle(x)
  if (to == "approved") {
    failed <- assessment_checks(rating_invariants(x))
    failed <- failed[failed$status == "fail", ]
    if (nrow(failed)) {
      stop(fn, ": a rating that fails its own validity checks cannot be approved (",
           paste(failed$check_id, collapse = ", "), "). See rating_invariants().", call. = FALSE)
    }
    submitted <- log[log$to == "under_review", ]
    submitter <- if (nrow(submitted)) submitted$by[nrow(submitted)] else NA_character_
    if (!allow_self_approval && !is.na(submitter) && identical(tolower(trimws(submitter)), tolower(by))) {
      stop(fn, ": ", submitter, " put this rating under review, so cannot also approve it. ",
           "Another person must. If self-approval is acceptable here, set allow_self_approval = TRUE; ",
           "it will be recorded.", call. = FALSE)
    }
    if (allow_self_approval && !is.na(submitter) && identical(tolower(trimws(submitter)), tolower(by))) {
      reason <- paste0(reason, " [self-approval allowed: the same person put it under review]")
    }
  }

  old <- x
  record <- data.table::data.table(from = from, to = to, by = by, reason = reason,
                                   at = as.POSIXct(format(at, tz = "UTC"), tz = "UTC"))
  prov <- x@provenance
  prov$lifecycle_log <- rbind(log, record)
  prov$amendment_note <- sprintf("lifecycle: %s to %s by %s on %s (%s)", from, to, by,
                                 format(at, "%Y-%m-%d", tz = "UTC"), reason)
  x@provenance <- prov
  x@lifecycle <- to
  x@previous <- old
  x
}

#' The record of lifecycle changes for a rating
#'
#' @description
#' Who changed a rating's lifecycle, from what to what, when and why, oldest
#' first. A rating that has never been moved on from `"draft"` has no records.
#'
#' Only changes made with [set_lifecycle()] are here. A rating that was
#' amended after it was reviewed (its limits set, its limbs aligned) is back to
#' `draft` without a record, since no person said so: see [rating_history()],
#' where its lifecycle column shows the step.
#'
#' @param x A [FlodeRating], [FlodeSegmentedRating] or [FlodeRatingTable].
#'   A table has no record to keep, so it always returns an empty one.
#'
#' @return A `data.table` with `from`, `to`, `by`, `reason` and `at` (UTC).
#'
#' @seealso [set_lifecycle()], [rating_history()].
#'
#' @examples
#' set.seed(1)
#' stage <- seq(0.3, 3, length.out = 25)
#' gaugings <- data.frame(stage_m = stage,
#'                        discharge_cms = 3 * stage^1.6 * exp(rnorm(25, sd = 0.03)))
#' fit <- fit_rating(gaugings, quiet = TRUE)
#' rating_lifecycle(fit)
#' @export
rating_lifecycle <- function(x) {
  if (S7_inherits(x, FlodeRatingTable)) return(.empty_lifecycle_log())
  if (!(S7_inherits(x, FlodeRating) || S7_inherits(x, FlodeSegmentedRating))) {
    stop("rating_lifecycle(): x must be a FlodeRating, FlodeSegmentedRating or FlodeRatingTable, not ",
         class(x)[1L], call. = FALSE)
  }
  log <- x@provenance$lifecycle_log
  if (is.null(log)) .empty_lifecycle_log() else data.table::copy(data.table::as.data.table(log))
}

# The one printed line that says who last moved the rating's lifecycle. Silent
# when there is no record, or when an amendment has since put the rating back to
# draft so that the last record no longer describes it.
.lifecycle_line <- function(x) {
  if (S7_inherits(x, FlodeRatingTable)) return(character(0))
  log <- x@provenance$lifecycle_log
  if (is.null(log) || !nrow(log)) return(character(0))
  last <- log[nrow(log), ]
  if (!identical(last$to, x@lifecycle)) return(character(0))
  sprintf("  %s by %s on %s", x@lifecycle, last$by, format(last$at, "%Y-%m-%d", tz = "UTC"))
}
