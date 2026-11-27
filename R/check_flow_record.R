# ============================================================ #
# Tool:         check_flow_record
# Description:  Read the applied rating back from an archived record of
#               stage and flow, period by period, and check it: revisions,
#               runs off the curve, flow above the top of the rating and
#               above bankfull, the flow a stage error makes, stage rising
#               in dry weather, and the match to known ratings. Fits
#               nothing, changes nothing. Release E, design/E3.
# Author:       Jonathan Payne
# Created:      2026-11-27
# Tier:         3
# Inputs:       A record (time, stage_m, discharge_cms, optional quality),
#               optional top and bankfull stages, a stage uncertainty, a
#               dry mask and known ratings.
# Outputs:      A list of class flode_record_check, with a FlodeAssessment.
# Dependencies: data.table, ggplot2, logger, stats
# ============================================================ #

#' @include flode_assessment.R apply_rating.R
NULL

#' Check a rating from the flow record
#'
#' @description
#' Archived flow is stage passed through whichever rating was applied at the
#' time, so the archived pairs of stage and flow carry that rating.
#' `check_flow_record()` reads it back, period by period, and checks it for
#' what gaugings cannot show: when it changed, where the record departs from
#' it, how much flow came from above its top, and how far a stage error moves
#' the flow. It fits nothing, never edits the record, and never sets a number
#' the caller did not give: a check whose input is missing is reported as not
#' assessed, with the reason.
#'
#' The method, its failure behaviour and its limitations are set out in
#' `design/E3_record_checks.md`.
#'
#' @section How the rating is read back:
#' An applied rating is exact: the archived flow at a stage is the rating's
#' flow there, less rounding. A step **departs** when
#' `|Q - C(h)| > max(tolerance * C(h), abs_tolerance)`, with `C` the curve read
#' back for the step's period. The curve is, at each distinct stage (to
#' `stage_resolution_m`), the median flow recorded there, linearly interpolated
#' between stages at most `max_gap_m` apart. A step at a stage the period has
#' not yet seen is untested; nothing is extrapolated.
#'
#' The record is read a day at a time. A day **departs** when more than half
#' its tested steps depart. A departing day followed by departing days, making
#' `min_days` in a row, closes the period: a **revision**, dated at the first
#' departing step of the first such day. Shorter runs are reported as off the
#' curve. Each revision is classed as a **stage shift** of `d` metres when the
#' new curve is the old one moved by `d` (`C_new(h) = C_old(h + d)` at 95% of
#' the stages both cover), or a **change of shape** otherwise.
#'
#' @param record A data frame or data.table, one row per step, with `time`
#'   (POSIXct, UTC, the step's start), `stage_m` (metres above the gauge
#'   datum), `discharge_cms` (archived flow, m3/s) and, optionally, `quality`
#'   (the archive's quality code for the flow). Times must increase, by
#'   whole multiples of the shortest step; a gap is a run of missing steps.
#' @param top_stage_m The highest stage the rating is founded on: the highest
#'   gauging, or the stated limit of its top limb. Enables `record_above_top`.
#' @param bankfull_stage_m The stage above which water may bypass the section.
#'   Enables `record_above_bankfull`.
#' @param stage_uncertainty_m A stage error, as a systematic offset in metres.
#'   Enables `record_stage_error`.
#' @param dry Logical, one per row of `record`: `TRUE` where the caller judges
#'   no rain has fallen on the catchment long enough to matter. Enables
#'   `record_dry_rises`. On a permeable catchment, flow can go on rising for
#'   days after rain as the groundwater answers it: weed grows in summer, so a
#'   rise in a winter month is more likely the catchment than the channel.
#' @param ratings Known ratings: a named list of [FlodeRating] or
#'   [FlodeRatingTable], or the output of [operational_rating_tables()].
#'   Enables `record_known_ratings`.
#' @param tolerance,abs_tolerance A step departs from the curve by more than
#'   `max(tolerance * C, abs_tolerance)`. Defaults 1% and 0.002 m3/s: flow
#'   stored to three decimals is 1% out from rounding alone at 0.05 m3/s.
#' @param stage_resolution_m The resolution stage is archived to.
#' @param max_gap_m The widest gap between curve stages a step may be
#'   interpolated across.
#' @param min_days Departing days in a row that make a revision.
#' @param off_curve_share Share of a period's flow volume off the curve above
#'   which `record_off_curve` warns.
#' @param above_top_share Share of flow volume above `top_stage_m` above which
#'   `record_above_top` warns.
#' @param known_fit_share Share of a period's steps that may depart from a
#'   known rating for it still to fit.
#' @param dry_rise_m_per_day The mean rise of stage over a month's dry steps,
#'   metres a day, above which `record_dry_rises` warns.
#' @param min_period_steps A period with fewer tested steps is listed but not
#'   assessed.
#'
#' @details
#' The thresholds are best-endeavours defaults, not EA policy (limitation L02).
#'
#' @return A list of class `flode_record_check`:
#'   \describe{
#'     \item{assessment}{A [FlodeAssessment], one row per check.}
#'     \item{periods}{One row per period: `period`, `start`, `end`, `steps`,
#'       `tested`, `stage_min_m`, `stage_max_m`, `assessed`, and the known
#'       rating matched, where `ratings` is given.}
#'     \item{curves}{A list of data.tables (`stage_m`, `discharge_cms`), one per
#'       period: the rating read back.}
#'     \item{revisions}{One row per revision: `time`, `from_period`,
#'       `to_period`, `kind` (`"stage shift"` or `"change of shape"`),
#'       `shift_m`, `flow_change` (at the new period's median stage, as a
#'       fraction).}
#'     \item{off_curve}{One row per run of departing steps: `period`, `start`,
#'       `end`, `steps`, `volume_share`, `quality`.}
#'     \item{above}{Peaks above the top and bankfull stages: `limit`, `start`,
#'       `end`, `peak_time`, `peak_stage_m`, `peak_discharge_cms`; with the
#'       shares of volume in attribute `shares`.}
#'     \item{stage_error}{By year and flow band: the volume change from the
#'       offset raised and lowered, m3 and as a share.}
#'     \item{dry_rises}{By month: dry steps, mean stage change and flow change
#'       a day.}
#'     \item{steps}{The record with `period`, `curve_cms`, `tested` and
#'       `departs` added.}
#'     \item{counts}{Steps in, missing stage, missing flow, tested, untested.}
#'     \item{settings}{Every argument, as used.}
#'   }
#'
#' @seealso [compare_gaugings_to_rating()], which tests a rating against
#'   gaugings: the record shows the rating as applied, the gaugings whether it
#'   is right.
#'
#' @examples
#' # A year of a known rating, Q = 5 (h - 0.1)^1.6, with a revision part way:
#' # from 1 July the flow is the same rating read 0.05 m higher.
#' time <- seq(as.POSIXct("2024-01-01", tz = "UTC"), by = 900, length.out = 35136)
#' stage <- round(0.45 + 0.25 * sin(2 * pi * seq_along(time) / 672), 3)
#' shifted <- time >= as.POSIXct("2024-07-01", tz = "UTC")
#' flow <- round(5 * (stage + 0.05 * shifted - 0.1)^1.6, 3)
#' out <- check_flow_record(data.frame(time = time, stage_m = stage, discharge_cms = flow))
#' out$revisions
#' assessment_checks(out$assessment)[, .(check_id, status)]
#'
#' @export
check_flow_record <- function(record, top_stage_m = NULL, bankfull_stage_m = NULL,
                              stage_uncertainty_m = NULL, dry = NULL, ratings = NULL,
                              tolerance = 0.01, abs_tolerance = 0.002,
                              stage_resolution_m = 0.001, max_gap_m = 0.01, min_days = 2L,
                              off_curve_share = 0.01, above_top_share = 0.05,
                              known_fit_share = 0.05, dry_rise_m_per_day = 0.001,
                              min_period_steps = 100L) {
  rec <- .record_input(record)
  .record_number(top_stage_m, "top_stage_m", allow_null = TRUE, any_sign = TRUE)
  .record_number(bankfull_stage_m, "bankfull_stage_m", allow_null = TRUE, any_sign = TRUE)
  .record_number(stage_uncertainty_m, "stage_uncertainty_m", allow_null = TRUE)
  for (nm in c("tolerance", "abs_tolerance", "stage_resolution_m", "max_gap_m",
               "off_curve_share", "above_top_share", "known_fit_share")) {
    .record_number(get(nm), nm)
  }
  .record_number(dry_rise_m_per_day, "dry_rise_m_per_day", any_sign = TRUE)
  if (!is.numeric(min_days) || length(min_days) != 1L || min_days < 1) {
    stop("check_flow_record(): min_days must be one whole number, 1 or more. It is how many ",
         "departing days in a row make a revision.", call. = FALSE)
  }
  min_days <- as.integer(min_days)
  if (!is.null(dry)) {
    if (!is.logical(dry) || length(dry) != nrow(record)) {
      stop(sprintf(paste0("check_flow_record(): dry must be logical, one value per row of record ",
                          "(%d), and has %d values of class %s. Mark each step TRUE where no rain ",
                          "has fallen long enough to matter."),
                   nrow(record), length(dry), class(dry)[1]), call. = FALSE)
    }
    rec[, dry := dry[rec$row]]
  }
  known <- .record_known(ratings)

  settings <- list(top_stage_m = top_stage_m, bankfull_stage_m = bankfull_stage_m,
                   stage_uncertainty_m = stage_uncertainty_m, dry_given = !is.null(dry),
                   ratings = names(known), tolerance = tolerance, abs_tolerance = abs_tolerance,
                   stage_resolution_m = stage_resolution_m, max_gap_m = max_gap_m,
                   min_days = min_days, off_curve_share = off_curve_share,
                   above_top_share = above_top_share, known_fit_share = known_fit_share,
                   dry_rise_m_per_day = dry_rise_m_per_day, min_period_steps = min_period_steps,
                   step_seconds = attr(rec, "step_seconds"))

  read <- .record_read_back(rec, tolerance, abs_tolerance, stage_resolution_m, max_gap_m,
                            min_days)
  step_s <- attr(rec, "step_seconds")
  rec <- read$steps
  curves <- read$curves

  periods <- rec[, .(start = min(time), end = max(time), steps = .N,
                     tested = sum(tested, na.rm = TRUE),
                     stage_min_m = suppressWarnings(min(stage_m, na.rm = TRUE)),
                     stage_max_m = suppressWarnings(max(stage_m, na.rm = TRUE))),
                 by = period]
  periods[, assessed := tested >= min_period_steps]
  good <- periods$period[periods$assessed]

  revisions <- .record_revisions(read$revision_times, rec, curves, tolerance, abs_tolerance,
                                 stage_resolution_m)
  off_curve <- .record_off_curve(rec[period %in% good], step_s)

  rows <- list()
  n_short <- sum(!periods$assessed)
  short_note <- if (n_short) {
    sprintf(" %d period(s) with fewer than %d tested steps are listed but not assessed.",
            n_short, min_period_steps)
  } else {
    ""
  }

  # Coverage: how much of the record could be tested at all.
  n_steps <- nrow(rec)
  n_tested <- sum(rec$tested)
  counts <- list(steps = n_steps, missing_stage = sum(is.na(rec$stage_m)),
                 missing_flow = sum(is.na(rec$discharge_cms)), tested = n_tested,
                 untested = n_steps - n_tested)
  rows$coverage <- .check_row(
    "record_tested", "data",
    if (n_tested < 0.5 * n_steps) "warning" else "pass",
    sprintf(paste0("%d of %d steps (%.0f%%) were tested against a curve read back from the ",
                   "record; %d had no stage and %d no flow.%s"),
            n_tested, n_steps, 100 * n_tested / n_steps, counts$missing_stage,
            counts$missing_flow, short_note),
    if (n_tested < 0.5 * n_steps) {
      "Under half the record was tested: every check rests on the steps that were. A longer record revisits more stages."
    } else {
      NA_character_
    },
    severity = "warning")

  rows$revisions <- .check_row(
    "record_revisions", "hydrometric",
    if (nrow(revisions)) "warning" else "pass",
    if (nrow(revisions)) {
      paste0(sprintf("%d revision(s) of the applied rating: ", nrow(revisions)),
             paste(sprintf("%s (%s%s)", format(revisions$time, "%Y-%m-%d %H:%M", tz = "UTC"),
                           revisions$kind,
                           ifelse(is.na(revisions$shift_m), "",
                                  sprintf(", %+.3f m", revisions$shift_m))),
                   collapse = "; "), ".")
    } else {
      sprintf("One applied rating throughout the %d period(s) read.", nrow(periods))
    },
    if (nrow(revisions)) {
      "Check each date against the rating history. A stage shift points to a datum or control change; a water balance across a revision is two balances."
    } else {
      NA_character_
    },
    stage = rec$stage_m)

  off_share <- if (length(good)) {
    total <- sum(rec[period %in% good]$discharge_cms, na.rm = TRUE)
    if (total > 0) sum(off_curve$volume_m3) / (total * step_s) else 0
  } else {
    NA_real_
  }
  rows$off <- if (!length(good)) {
    .check_row("record_off_curve", "hydrometric", "not_assessed",
               "No period has enough tested steps to be assessed.")
  } else {
    .check_row(
      "record_off_curve", "hydrometric",
      if (off_share > off_curve_share) "warning" else "pass",
      sprintf(paste0("%d run(s) of steps off the applied rating, %d steps, %.2f%% of the flow ",
                     "volume of the periods assessed.%s"),
              nrow(off_curve), sum(off_curve$steps), 100 * off_share, short_note),
      if (off_share > off_curve_share) {
        "Flow off the curve was not made from the stage at the time: infilled, edited or from another record. See off_curve, with the quality codes."
      } else {
        NA_character_
      })
  }

  above <- .record_above(rec, top_stage_m, bankfull_stage_m, step_s)
  shares <- attr(above, "shares")
  rows$top <- if (is.null(top_stage_m)) {
    .check_row("record_above_top", "hydrometric", "not_assessed",
               "Not assessed: top_stage_m was not given.",
               "Give the highest gauged stage, or the stated limit of the rating's top limb.")
  } else {
    peaks <- above[limit == "top"]
    .check_row(
      "record_above_top", "hydrometric",
      if (shares[["top"]] > above_top_share) "warning" else "pass",
      sprintf(paste0("%.1f%% of the flow volume came from stages above the top of the rating ",
                     "(%.3f m), in %d run(s); the highest peak was %.3f m."),
              100 * shares[["top"]], top_stage_m, nrow(peaks),
              if (nrow(peaks)) max(peaks$peak_stage_m) else NA_real_),
      if (shares[["top"]] > above_top_share) {
        "That flow is extrapolated: high-flow gaugings would test it, and a water balance leans on it."
      } else {
        NA_character_
      },
      stage = c(top_stage_m, peaks$peak_stage_m))
  }
  rows$bankfull <- if (is.null(bankfull_stage_m)) {
    .check_row("record_above_bankfull", "hydrometric", "not_assessed",
               "Not assessed: bankfull_stage_m was not given.",
               "Give the stage above which water may bypass the section.")
  } else {
    peaks <- above[limit == "bankfull"]
    .check_row(
      "record_above_bankfull", "hydrometric",
      if (nrow(peaks)) "warning" else "pass",
      sprintf("%d peak(s) above bankfull (%.3f m), holding %.1f%% of the flow volume.",
              nrow(peaks), bankfull_stage_m, 100 * shares[["bankfull"]]),
      if (nrow(peaks)) {
        "Above bankfull, water may go round the section: those floods' flow may be short, and their runoff too low."
      } else {
        NA_character_
      },
      stage = c(bankfull_stage_m, peaks$peak_stage_m))
  }

  stage_error <- NULL
  rows$stage_error <- if (is.null(stage_uncertainty_m)) {
    .check_row("record_stage_error", "hydrometric", "not_assessed",
               "Not assessed: stage_uncertainty_m was not given.",
               "Give a plausible systematic stage error, such as 0.005 or 0.01 m.")
  } else if (!length(good)) {
    .check_row("record_stage_error", "hydrometric", "not_assessed",
               "No period has enough tested steps to be assessed.")
  } else {
    stage_error <- .record_stage_error(rec[period %in% good], curves, stage_uncertainty_m,
                                       step_s)
    whole <- stage_error[year == "all" & band == "all"]
    low <- stage_error[year == "all" & band == "low"]
    if (!nrow(low)) low <- data.table(share_raised = NA_real_, share_lowered = NA_real_)
    .check_row(
      "record_stage_error", "hydrometric", "pass",
      sprintf(paste0("A stage offset of %.3f m moves the flow volume by %+.1f%% (raised) and ",
                     "%+.1f%% (lowered) over the record; low flows: %+.1f%% and %+.1f%%. %d ",
                     "step(s) the offset carried off a curve were left out."),
              stage_uncertainty_m, 100 * whole$share_raised, 100 * whole$share_lowered,
              100 * low$share_raised, 100 * low$share_lowered,
              attr(stage_error, "left_out")),
      "Set this beside the rain's uncertainty: a balance gap well inside it does not need the catchment to explain it.")
  }

  dry_rises <- NULL
  rows$dry <- if (is.null(dry)) {
    .check_row("record_dry_rises", "hydrometric", "not_assessed",
               "Not assessed: dry was not given.",
               "Mark the steps with no rain long enough to matter, from the catchment's rain.")
  } else {
    dry_rises <- .record_dry_rises(rec, step_s)
    rising <- dry_rises[stage_change_m_per_day > dry_rise_m_per_day]
    .check_row(
      "record_dry_rises", "hydrometric",
      if (nrow(rising)) "warning" else "pass",
      if (nrow(rising)) {
        sprintf("Stage rose in dry weather in %d month(s): %s.", nrow(rising),
                paste(sprintf("%s (%+.1f mm a day)", rising$month,
                              1000 * rising$stage_change_m_per_day), collapse = ", "))
      } else {
        sprintf("Stage did not rise on average in dry weather in any of %d month(s).",
                nrow(dry_rises))
      },
      if (nrow(rising)) {
        "A rise with no rain means water held back (weed, a blockage, backwater), and the flow read from it is overstated."
      } else {
        NA_character_
      })
  }

  if (length(known)) {
    matched <- .record_match_known(rec, known, periods, tolerance, abs_tolerance)
    periods <- merge(periods, matched, by = "period", all.x = TRUE, sort = TRUE)
    unfitted <- periods[assessed == TRUE & !(known_departing_share <= known_fit_share)]
    rows$known <- .check_row(
      "record_known_ratings", "hydrometric",
      if (nrow(unfitted)) "warning" else "pass",
      paste0(paste(sprintf("Period %d: %s (%.1f%% of steps depart)", periods$period[periods$assessed],
                           periods$known_rating[periods$assessed],
                           100 * periods$known_departing_share[periods$assessed]),
                   collapse = "; "), "."),
      if (nrow(unfitted)) {
        "A period no known rating fits was made by a rating not in the list given, or edited."
      } else {
        NA_character_
      })
  } else {
    rows$known <- .check_row("record_known_ratings", "hydrometric", "not_assessed",
                             "Not assessed: ratings was not given.",
                             "Give the station's ratings, such as operational_rating_tables() output.")
  }

  assessment <- FlodeAssessment(checks = rbindlist(rows), subject = "flow record",
                                assessed_rows = as.integer(n_tested))
  structure(list(assessment = assessment, periods = periods[], curves = curves,
                 revisions = revisions, off_curve = off_curve, above = above,
                 stage_error = stage_error, dry_rises = dry_rises,
                 steps = rec[, !c("row", "skey"), with = FALSE], counts = counts,
                 settings = settings),
            class = "flode_record_check")
}

# ---- Inputs ----------------------------------------------------------------

.record_number <- function(x, name, allow_null = FALSE, any_sign = FALSE) {
  if (allow_null && is.null(x)) return(invisible())
  ok <- is.numeric(x) && length(x) == 1L && is.finite(x) && (any_sign || x > 0)
  if (!ok) {
    stop(sprintf("check_flow_record(): %s must be one %snumber.", name,
                 if (any_sign) "" else "positive "), call. = FALSE)
  }
  invisible()
}

# The record as a data.table on a regular step, with gaps filled as missing
# steps and the original row kept.
.record_input <- function(record) {
  if (!is.data.frame(record)) {
    stop("check_flow_record(): record must be a data frame of time, stage_m and discharge_cms.",
         call. = FALSE)
  }
  missing_cols <- setdiff(c("time", "stage_m", "discharge_cms"), names(record))
  if (length(missing_cols)) {
    stop(sprintf(paste0("check_flow_record(): record has no %s column. It needs time (POSIXct, ",
                        "UTC), stage_m and discharge_cms; columns found: %s."),
                 paste(missing_cols, collapse = ", "), paste(names(record), collapse = ", ")),
         call. = FALSE)
  }
  if (!inherits(record$time, "POSIXct")) {
    stop("check_flow_record(): record$time must be POSIXct, in UTC.", call. = FALSE)
  }
  if (!is.numeric(record$stage_m) || !is.numeric(record$discharge_cms)) {
    stop("check_flow_record(): stage_m and discharge_cms must be numeric.", call. = FALSE)
  }
  if (anyNA(record$time)) {
    stop(sprintf("check_flow_record(): record$time is missing at row %d.",
                 which(is.na(record$time))[1]), call. = FALSE)
  }
  bad_q <- which(record$discharge_cms < 0)
  if (length(bad_q)) {
    stop(sprintf(paste0("check_flow_record(): discharge_cms is negative at row %d (%g). Flow ",
                        "cannot be negative: remove or correct the row."),
                 bad_q[1], record$discharge_cms[bad_q[1]]), call. = FALSE)
  }
  tt <- as.numeric(record$time)
  d <- diff(tt)
  if (length(d) && any(d <= 0)) {
    i <- which(d <= 0)[1] + 1L
    stop(sprintf(paste0("check_flow_record(): times must increase; row %d (%s) is not after the ",
                        "row before it. Sort the record and remove repeated steps."),
                 i, format(record$time[i], tz = "UTC")), call. = FALSE)
  }
  step <- if (length(d)) min(d) else 900
  if (length(d) && any(abs(d / step - round(d / step)) > 1e-6)) {
    i <- which(abs(d / step - round(d / step)) > 1e-6)[1] + 1L
    stop(sprintf(paste0("check_flow_record(): steps must be whole multiples of the shortest ",
                        "(%g s); row %d is %g s after the one before. Put the record on one ",
                        "regular step."), step, i, d[i - 1L]), call. = FALSE)
  }
  index <- round((tt - tt[1]) / step) + 1
  rec <- data.table(time = seq(record$time[1], by = step, length.out = max(index)))
  attr(rec$time, "tzone") <- "UTC"
  rec[, `:=`(row = NA_integer_, stage_m = NA_real_, discharge_cms = NA_real_)]
  rec[index, `:=`(row = seq_len(nrow(record)), stage_m = record$stage_m,
                  discharge_cms = record$discharge_cms)]
  if ("quality" %in% names(record)) {
    rec[, quality := NA_character_]
    rec[index, quality := as.character(record$quality)]
  }
  rec[, day := as.Date(time, tz = "UTC")]
  both <- !is.na(rec$stage_m) & !is.na(rec$discharge_cms)
  if (length(unique(rec$day[both])) < 7L) {
    stop(paste0("check_flow_record(): the record has fewer than seven days with both stage and ",
                "flow. No curve can be read from so little."), call. = FALSE)
  }
  setattr(rec, "step_seconds", step)
  rec
}

# Known ratings as a named list of FlodeRatingTable or FlodeRating.
.record_known <- function(ratings) {
  if (is.null(ratings)) return(list())
  if (is.list(ratings) && !is.null(ratings$tables) && is.list(ratings$tables)) {
    ratings <- ratings$tables
  }
  ok <- is.list(ratings) && length(ratings) && !is.null(names(ratings)) &&
    all(nzchar(names(ratings))) &&
    all(vapply(ratings, function(r) {
      S7::S7_inherits(r, FlodeRatingTable) || S7::S7_inherits(r, FlodeRating)
    }, logical(1)))
  if (!ok) {
    stop(paste0("check_flow_record(): ratings must be a named list of FlodeRating or ",
                "FlodeRatingTable, or the output of operational_rating_tables()."), call. = FALSE)
  }
  ratings
}

# ---- The curve read back ---------------------------------------------------

# The curve's flow at stage keys k, from known flows q_at (indexed by key -
# offset + 1): exact where the key is known, interpolated linearly between
# known keys at most `gap` keys apart, NA otherwise.
.record_curve_at <- function(k, q_at, offset, gap) {
  out <- rep(NA_real_, length(k))
  ok <- !is.na(k)
  if (!any(ok)) return(out)
  i <- k[ok] - offset + 1L
  known <- which(!is.na(q_at))
  if (!length(known)) return(out)
  lo <- findInterval(i, known)
  hi <- lo + 1L
  exact <- lo >= 1L & known[pmax(lo, 1L)] == i
  v <- rep(NA_real_, length(i))
  v[exact] <- q_at[i[exact]]
  between <- !exact & lo >= 1L & hi <= length(known)
  if (any(between)) {
    a <- known[lo[between]]
    b <- known[hi[between]]
    close <- (b - a) <= gap
    w <- (i[between] - a) / (b - a)
    est <- q_at[a] + w * (q_at[b] - q_at[a])
    est[!close] <- NA_real_
    v[between] <- est
  }
  out[ok] <- v
  out
}

.record_departs <- function(q, c, tol, abs_tol) {
  abs(q - c) > pmax(tol * c, abs_tol) * (1 + 1e-9)
}

# The pass a day at a time. Returns the steps with period, tested, departs and
# curve_cms, each period's curve, and the times of the revisions.
.record_read_back <- function(rec, tol, abs_tol, res, max_gap, min_days) {
  rec[, skey := as.integer(round(stage_m / res))]
  usable <- !is.na(rec$skey) & !is.na(rec$discharge_cms)
  offset <- min(rec$skey, na.rm = TRUE)
  span <- max(rec$skey, na.rm = TRUE) - offset + 1L
  gap <- as.integer(round(max_gap / res))
  days <- split(seq_len(nrow(rec)), rec$day)
  n_days <- length(days)

  period <- integer(nrow(rec))
  accepted <- logical(nrow(rec))
  q_at <- rep(NA_real_, span)
  current <- 1L
  revision_steps <- integer(0)

  test_day <- function(steps) {
    s <- steps[usable[steps]]
    c <- .record_curve_at(rec$skey[s], q_at, offset, gap)
    tested <- !is.na(c)
    dep <- tested & .record_departs(rec$discharge_cms[s], c, tol, abs_tol)
    list(s = s, tested = tested, departs = dep,
         day_departs = sum(tested) > 0 && sum(dep) > 0.5 * sum(tested))
  }
  accept <- function(s) {
    accepted[s] <<- TRUE
    i <- rec$skey[s] - offset + 1L
    fresh <- is.na(q_at[i])
    # The first value seen at a stage stands for it during the pass; the
    # curve kept is the median at each stage, made at the end.
    q_at[i[fresh & !duplicated(i)]] <<- rec$discharge_cms[s][fresh & !duplicated(i)]
  }

  d <- 1L
  while (d <= n_days) {
    steps <- days[[d]]
    t <- test_day(steps)
    if (t$day_departs && d + min_days - 1L <= n_days) {
      run <- all(vapply(seq_len(min_days - 1L), function(j) {
        test_day(days[[d + j]])$day_departs
      }, logical(1)))
      if (run) {
        first <- t$s[which(t$departs)[1]]
        before <- steps[steps < first]
        period[before] <- current
        tb <- t$tested[t$s < first] & !t$departs[t$s < first]
        accept(t$s[t$s < first][tb])
        current <- current + 1L
        revision_steps <- c(revision_steps, first)
        q_at[] <- NA_real_
        after <- steps[steps >= first]
        period[after] <- current
        accept(after[usable[after]])
        d <- d + 1L
        next
      }
    }
    period[steps] <- current
    if (t$day_departs) {
      accept(t$s[t$tested & !t$departs])
    } else {
      accept(t$s[!t$departs])
    }
    d <- d + 1L
  }
  rec[, period := period]

  # Each period's curve: the median of the accepted flows at each stage. The
  # steps are then tested once more against their period's finished curve.
  curves <- list()
  rec[, `:=`(curve_cms = NA_real_, tested = FALSE, departs = FALSE)]
  for (p in seq_len(current)) {
    in_p <- which(rec$period == p)
    acc <- in_p[accepted[in_p]]
    cv <- data.table(skey = rec$skey[acc], q = rec$discharge_cms[acc])[
      , .(q = stats::median(q)), by = skey][order(skey)]
    curves[[p]] <- data.table(stage_m = cv$skey * res, discharge_cms = cv$q)
    qa <- rep(NA_real_, span)
    qa[cv$skey - offset + 1L] <- cv$q
    s <- in_p[usable[in_p]]
    c <- .record_curve_at(rec$skey[s], qa, offset, gap)
    set(rec, s, "curve_cms", c)
    set(rec, s, "tested", !is.na(c))
    set(rec, s, "departs", !is.na(c) & .record_departs(rec$discharge_cms[s], c, tol, abs_tol))
  }
  # A revision's first steps opened the new period's curve, so they pass it by
  # construction; that is the curve they made, not a departure.
  list(steps = rec, curves = curves, revision_times = rec$time[revision_steps])
}

# ---- Revisions -------------------------------------------------------------

# Interpolate a curve (stage_m, discharge_cms) at stage h, NA outside it.
.record_interp <- function(curve, h) {
  if (nrow(curve) < 2L) return(rep(NA_real_, length(h)))
  stats::approx(curve$stage_m, curve$discharge_cms, xout = h, rule = 1)$y
}

.record_revisions <- function(times, rec, curves, tol, abs_tol, res) {
  if (!length(times)) {
    return(data.table(time = as.POSIXct(character(0), tz = "UTC"), from_period = integer(0),
                      to_period = integer(0), kind = character(0), shift_m = numeric(0),
                      flow_change = numeric(0)))
  }
  rbindlist(lapply(seq_along(times), function(r) {
    old <- curves[[r]]
    new <- curves[[r + 1L]]
    new <- new[discharge_cms > abs_tol]
    shifts <- seq(-0.5, 0.5, by = res)
    score <- vapply(shifts, function(d) {
      o <- .record_interp(old, new$stage_m + d)
      ok <- !is.na(o) & o > abs_tol
      if (sum(ok) < 20L) return(NA_real_)
      stats::median(abs(log(new$discharge_cms[ok] / o[ok])))
    }, 0)
    kind <- "change of shape"
    shift <- NA_real_
    if (any(is.finite(score))) {
      best <- shifts[which.min(score)]
      o <- .record_interp(old, new$stage_m + best)
      ok <- !is.na(o)
      within <- !.record_departs(new$discharge_cms[ok], o[ok], tol, abs_tol)
      if (mean(within) >= 0.95 && abs(best) > res / 2) {
        kind <- "stage shift"
        shift <- best
      }
    }
    hm <- stats::median(rec$stage_m[rec$period == r + 1L], na.rm = TRUE)
    qo <- .record_interp(curves[[r]], hm)
    qn <- .record_interp(curves[[r + 1L]], hm)
    data.table(time = times[r], from_period = r, to_period = r + 1L, kind = kind,
               shift_m = shift, flow_change = qn / qo - 1)
  }))
}

# ---- Off the curve ---------------------------------------------------------

.record_off_curve <- function(rec, step_s) {
  empty <- data.table(period = integer(0), start = as.POSIXct(character(0), tz = "UTC"),
                      end = as.POSIXct(character(0), tz = "UTC"), steps = integer(0),
                      volume_m3 = numeric(0), volume_share = numeric(0),
                      quality = character(0))
  if (!nrow(rec) || !any(rec$departs)) return(empty)
  rec <- copy(rec)
  # A run is departing steps in a row, within one period.
  rec[, run := cumsum(c(TRUE, diff(departs) != 0 | diff(period) != 0))]
  volume <- rec[, .(v = sum(discharge_cms, na.rm = TRUE)), by = period]
  runs <- rec[departs == TRUE, .(start = min(time), end = max(time), steps = .N,
                                 volume_m3 = sum(discharge_cms) * step_s,
                                 quality = if ("quality" %in% names(rec)) {
                                   paste(sort(unique(stats::na.omit(quality))), collapse = ", ")
                                 } else {
                                   NA_character_
                                 }),
              by = .(period, run)]
  runs[, volume_share := volume_m3 / (volume$v[match(period, volume$period)] * step_s)]
  runs[, .(period, start, end, steps, volume_m3, volume_share, quality)]
}

# ---- Above the top and bankfull --------------------------------------------

.record_above <- function(rec, top, bankfull, step_s) {
  total <- sum(rec$discharge_cms, na.rm = TRUE)
  shares <- c(top = NA_real_, bankfull = NA_real_)
  peaks <- list()
  for (lim in c("top", "bankfull")) {
    level <- if (lim == "top") top else bankfull
    if (is.null(level)) next
    up <- !is.na(rec$stage_m) & rec$stage_m > level
    shares[[lim]] <- if (total > 0) sum(rec$discharge_cms[up], na.rm = TRUE) / total else 0
    if (!any(up)) next
    run <- cumsum(c(TRUE, diff(up) != 0))
    r <- rec[up, .(start = min(time), end = max(time),
                   peak_time = time[which.max(stage_m)], peak_stage_m = max(stage_m),
                   peak_discharge_cms = discharge_cms[which.max(stage_m)]),
             by = .(run = run[up])]
    peaks[[lim]] <- r[, limit := lim][, .(limit, start, end, peak_time, peak_stage_m,
                                          peak_discharge_cms)]
  }
  out <- if (length(peaks)) {
    rbindlist(peaks)
  } else {
    data.table(limit = character(0), start = as.POSIXct(character(0), tz = "UTC"),
               end = as.POSIXct(character(0), tz = "UTC"),
               peak_time = as.POSIXct(character(0), tz = "UTC"), peak_stage_m = numeric(0),
               peak_discharge_cms = numeric(0))
  }
  attr(out, "shares") <- shares
  out
}

# ---- Stage error to flow ---------------------------------------------------

# Log-flow interpolation of a curve, NA outside it or where flow is zero.
.record_interp_log <- function(curve, h) {
  pos <- curve[discharge_cms > 0]
  if (nrow(pos) < 2L) return(rep(NA_real_, length(h)))
  out <- exp(stats::approx(pos$stage_m, log(pos$discharge_cms), xout = h, rule = 1)$y)
  out
}

.record_stage_error <- function(rec, curves, u, step_s) {
  rec <- rec[!is.na(stage_m) & !is.na(discharge_cms)]
  base <- numeric(nrow(rec))
  raised <- lowered <- base
  for (p in unique(rec$period)) {
    i <- which(rec$period == p)
    base[i] <- .record_interp_log(curves[[p]], rec$stage_m[i])
    raised[i] <- .record_interp_log(curves[[p]], rec$stage_m[i] + u)
    lowered[i] <- .record_interp_log(curves[[p]], rec$stage_m[i] - u)
  }
  keep <- !is.na(base) & !is.na(raised) & !is.na(lowered)
  q <- rec$discharge_cms
  # Flow bands by the record's own flow: high above the flow exceeded 10% of
  # the time, low below that exceeded 70%.
  q10 <- stats::quantile(q, 0.9, names = FALSE)
  q70 <- stats::quantile(q, 0.3, names = FALSE)
  band <- ifelse(q > q10, "high", ifelse(q < q70, "low", "middle"))
  d <- data.table(year = format(rec$time, "%Y", tz = "UTC"), band = band, base = base,
                  raised = raised, lowered = lowered)[keep]
  sums <- function(g) {
    g[, .(volume_m3 = sum(base) * step_s, change_raised_m3 = sum(raised - base) * step_s,
          change_lowered_m3 = sum(lowered - base) * step_s)]
  }
  out <- rbind(
    d[, sums(.SD), by = .(year, band)],
    d[, sums(.SD), by = year][, band := "all"],
    d[, sums(.SD), by = band][, year := "all"],
    sums(d)[, `:=`(year = "all", band = "all")],
    use.names = TRUE)
  out[, `:=`(share_raised = change_raised_m3 / volume_m3,
             share_lowered = change_lowered_m3 / volume_m3)]
  setorder(out, year, band)
  attr(out, "left_out") <- sum(!keep)
  out
}

# ---- Dry-weather rises -----------------------------------------------------

.record_dry_rises <- function(rec, step_s) {
  n <- nrow(rec)
  pair <- which(rec$dry[-n] %in% TRUE & rec$dry[-1L] %in% TRUE &
                  !is.na(rec$stage_m[-n]) & !is.na(rec$stage_m[-1L]))
  per_day <- 86400 / step_s
  d <- data.table(month = format(rec$time[pair], "%Y-%m", tz = "UTC"),
                  dh = rec$stage_m[pair + 1L] - rec$stage_m[pair],
                  dq = rec$discharge_cms[pair + 1L] - rec$discharge_cms[pair])
  d[, .(dry_steps = .N, stage_change_m_per_day = mean(dh) * per_day,
        flow_change_cms_per_day = mean(dq, na.rm = TRUE) * per_day), by = month][order(month)]
}

# ---- Known ratings ---------------------------------------------------------

.record_match_known <- function(rec, known, periods, tol, abs_tol) {
  ok <- !is.na(rec$stage_m) & !is.na(rec$discharge_cms)
  share <- vapply(known, function(r) {
    tbl <- if (S7::S7_inherits(r, FlodeRating)) as_rating_table(r) else r
    q <- logger::with_log_threshold(
      apply_rating(tbl, data.table(.stage = rec$stage_m[ok]), stage_col = ".stage"),
      threshold = logger::WARN
    )$discharge
    dep <- .record_departs(rec$discharge_cms[ok], q, tol, abs_tol)
    tapply(dep, rec$period[ok], mean)[as.character(periods$period)]
  }, numeric(nrow(periods)))
  share <- matrix(share, nrow = nrow(periods))
  best <- apply(share, 1, function(v) if (any(!is.na(v))) which.min(v) else NA_integer_)
  data.table(period = periods$period, known_rating = names(known)[best],
             known_departing_share = share[cbind(seq_len(nrow(periods)), best)])
}

# ---- Printing and plotting -------------------------------------------------

#' @export
print.flode_record_check <- function(x, ...) {
  cat(sprintf("Flow record check: %d steps, %d period(s), %d revision(s)\n",
              x$counts$steps, nrow(x$periods), nrow(x$revisions)))
  chk <- assessment_checks(x$assessment)
  for (i in seq_len(nrow(chk))) {
    cat(sprintf("  %-22s %-12s %s\n", chk$check_id[i], chk$status[i], chk$message[i]))
  }
  invisible(x)
}

#' Plot a flow record check
#'
#' @description
#' The record's stage and flow pairs, coloured by period, with each period's
#' curve read back, the steps off the curve, and the top and bankfull stages
#' where given.
#'
#' @param object,x What [check_flow_record()] returns.
#' @param ... Unused.
#' @return A ggplot object; `plot()` prints it.
#' @examples
#' time <- seq(as.POSIXct("2024-01-01", tz = "UTC"), by = 900, length.out = 2880)
#' stage <- round(0.45 + 0.25 * sin(2 * pi * seq_along(time) / 672), 3)
#' out <- check_flow_record(data.frame(time = time, stage_m = stage,
#'                                     discharge_cms = round(5 * (stage - 0.1)^1.6, 3)))
#' autoplot(out)
#' @export
autoplot.flode_record_check <- function(object, ...) {
  steps <- object$steps[!is.na(stage_m) & !is.na(discharge_cms)]
  steps[, Period := factor(period)]
  curves <- rbindlist(lapply(seq_along(object$curves), function(p) {
    copy(object$curves[[p]])[, Period := factor(p, levels = levels(steps$Period))]
  }))
  p <- ggplot2::ggplot(steps, ggplot2::aes(x = discharge_cms, y = stage_m, colour = Period)) +
    ggplot2::geom_point(size = 0.4, alpha = 0.3) +
    ggplot2::geom_path(data = curves, linewidth = 0.6) +
    ggplot2::geom_point(data = steps[departs == TRUE], colour = "#c0392b", size = 0.8) +
    ggplot2::labs(x = "Archived flow (m3/s)", y = "Stage (m)",
                  title = "The rating read back from the record",
                  subtitle = "Each period's curve; steps off it in red") +
    ggplot2::theme_minimal()
  for (lim in c("top_stage_m", "bankfull_stage_m")) {
    level <- object$settings[[lim]]
    if (!is.null(level)) {
      p <- p + ggplot2::geom_hline(yintercept = level, linetype = "dashed", colour = "#555555") +
        ggplot2::annotate("text", x = -Inf, y = level, hjust = -0.1, vjust = -0.4, size = 3,
                          label = if (lim == "top_stage_m") "top of rating" else "bankfull")
    }
  }
  p
}

#' @rdname autoplot.flode_record_check
#' @export
plot.flode_record_check <- function(x, ...) {
  print(autoplot.flode_record_check(x, ...))
  invisible(x)
}
