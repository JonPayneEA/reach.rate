# ============================================================ #
# Tool:         validate_gaugings
# Description:  Check a set of gaugings and return a FlodeAssessment: a
#               table of checks, each with a status, a message, the
#               evidence it concerns and a recommendation. Technical checks
#               fail; hydrometric checks warn. Nothing is removed or
#               changed.
# Author:       Jonathan Payne
# Created:      2026-11-18
# Tier:         3
# Inputs:       A FlodeEvidence, or anything as_flode_evidence() accepts
#               (including the output of read_gaugings()).
# Outputs:      A FlodeAssessment.
# Dependencies: data.table, stats
# ============================================================ #

#' @include flode_evidence.R flode_assessment.R
NULL

# Which gaugings sit in a stage-discharge inversion. A pair is inverted
# when the gauging at the higher stage has a discharge more than `tol`
# below the one at the lower stage. One high gauging would invert with every
# gauging above it, so for each inverted pair the blame goes to the gauging
# that is in more inverted pairs, and to the one at the higher stage when
# they are in as many. Memory is bounded by working in blocks of rows.
.inversion_max_rows <- 10000L

.inversion_flags <- function(stage, q, usable, tol) {
  flagged <- rep(FALSE, length(stage))
  idx <- which(usable)
  n <- length(idx)
  if (n < 2L) return(flagged)
  if (n > .inversion_max_rows) return(NULL)
  o <- idx[order(stage[idx], q[idx])]
  qs <- q[o]
  block <- max(1L, floor(2e6 / n))
  starts <- seq.int(1L, n, by = block)
  later <- integer(n)    # inverted pairs a gauging is the higher-stage member of
  earlier <- integer(n)  # ... and the lower-stage member of
  pairs <- function(rows) {
    qs[rows] < (1 - tol) * matrix(qs, length(rows), n, byrow = TRUE) &
      matrix(qs, length(rows), n, byrow = TRUE) > 0 &
      outer(rows, seq_len(n), function(i, j) j < i)
  }
  for (st in starts) {
    rows <- st:min(n, st + block - 1L)
    v <- pairs(rows)
    later[rows] <- later[rows] + rowSums(v)
    earlier <- earlier + colSums(v)
  }
  for (st in starts) {
    rows <- st:min(n, st + block - 1L)
    v <- pairs(rows)
    hit <- which(v, arr.ind = TRUE)
    if (!nrow(hit)) next
    i <- rows[hit[, 1L]]
    j <- hit[, 2L]
    blame_earlier <- earlier[j] > later[i]
    flagged[o[j[blame_earlier]]] <- TRUE
    flagged[o[i[!blame_earlier]]] <- TRUE
  }
  flagged
}

#' Check a set of gaugings
#'
#' @description
#' Runs a fixed set of checks on gaugings and returns them as a
#' [FlodeAssessment]. It is advice, not a filter: no row is removed,
#' excluded or altered, and a check that finds a problem names the
#' `evidence_id`s concerned so you can look at them.
#'
#' There are two kinds of check. **Technical** checks ask whether the data
#' can be used at all, and fail when it cannot: a stage or discharge that is
#' missing or not finite, a negative discharge, too few usable rows, a
#' repeated `evidence_id`, or a row that [read_gaugings()] could not read.
#' **Hydrometric** checks ask whether the data look right for a river, and
#' only ever warn, because each is a judgement for a person: zero
#' discharge, duplicated gaugings, a discharge that falls as stage rises, a
#' discharge off the curve of its neighbours, a gap in stage coverage, thin
#' support at the top of the range, few gaugings, no recent gaugings, rows
#' already marked excluded, and times of day that were assumed.
#'
#' A check that needs information the table lacks (dates, say, or the
#' notes `read_gaugings()` adds) is `not_assessed`, never `pass`.
#'
#' Hydrometric checks look at rows with a finite stage and discharge. The
#' thresholds are arguments, so a different tolerance is a visible choice.
#' The outlier check is deliberately cautious. In simulation on clean data
#' with randomly placed stages it warned about 3 to 7 sets in 100; a
#' gauging with twice its true discharge was found about 9 times in 10, and
#' one 50% too high about 6 times in 10. It is a prompt to look, not a
#' verdict, and `outlier_mad` sets how easily it speaks.
#'
#' The checks are meant for one station's gaugings, which is what a rating
#' is built from. The inversion check compares every pair of gaugings and is
#' skipped (`not_assessed`) beyond 10,000 usable rows; check an archive one
#' station at a time.
#'
#' @param x A [FlodeEvidence], or a `data.frame` or `data.table` that
#'   [as_flode_evidence()] can convert, including the table
#'   [read_gaugings()] returns.
#' @param min_gaugings Integer. Fewer usable gaugings than this raises the
#'   `few_gaugings` warning. Default 10. (Fewer than 4 is a technical
#'   failure, because a single limb has three parameters.)
#' @param inversion_tolerance Number. Two gaugings are inverted when the one
#'   at the higher stage has a discharge more than this fraction below the
#'   one at the lower stage. Default 0.2. When one gauging is inverted with
#'   several others (a single high value), it alone is reported, not the
#'   gaugings above it; in a simple pair, the higher-stage member is.
#' @param outlier_mad Number. A gauging whose log discharge lies more than
#'   this many robust standard deviations (median absolute deviation) from a
#'   cubic through its two nearest neighbours on each side in stage. The two
#'   end points at each end are not judged. Default 4.
#' @param gap_fraction Number. A gap between neighbouring stages wider than
#'   this fraction of the whole stage range is reported. Default 0.25.
#' @param upper_range_fraction,upper_range_min The top `upper_range_fraction`
#'   of the stage range (default 0.2) should hold at least
#'   `upper_range_min` gaugings (default 3).
#' @param recent_years Number. The latest gauging should fall within this
#'   many years of `reference_time`. Default 10.
#' @param reference_time The time to measure recency from. Default
#'   `Sys.time()`; set it to make a result reproducible.
#'
#' @return A [FlodeAssessment] with one row per check. Read it with
#'   [assessment_checks()] and [assessment_status()].
#'
#' @section Checks:
#' Technical: `stage_finite`, `discharge_finite`, `discharge_not_negative`,
#' `enough_rows`, `evidence_id_unique`, `read_issues`.
#' Hydrometric: `zero_discharge`, `duplicate_gaugings`,
#' `stage_discharge_inversion`, `outliers`, `stage_coverage_gaps`,
#' `upper_range_support`, `few_gaugings`, `temporal_coverage`,
#' `excluded_rows`, `times_assumed`.
#'
#' @seealso [FlodeAssessment], [read_gaugings()], [as_flode_evidence()]
#'
#' @examples
#' set.seed(1)
#' gaugings <- data.frame(
#'   stage_m = round(c(seq(0.4, 3, length.out = 14), 3.05), 3),
#'   discharge_cms = NA_real_
#' )
#' gaugings$discharge_cms <- round(3.2 * gaugings$stage_m^1.7 * exp(rnorm(15, sd = 0.03)), 3)
#' # Put one fault in: a discharge far too high for its stage.
#' gaugings$discharge_cms[6] <- gaugings$discharge_cms[6] * 3
#' assessment <- validate_gaugings(gaugings)
#' assessment
#' assessment_checks(assessment)[status != "pass", .(check_id, domain, status)]
#' plot(assessment)
#'
#' @export
validate_gaugings <- function(x, min_gaugings = 10L, inversion_tolerance = 0.2, outlier_mad = 4,
                              gap_fraction = 0.25, upper_range_fraction = 0.2, upper_range_min = 3L,
                              recent_years = 10, reference_time = Sys.time()) {
  ev <- as_flode_evidence(x)
  if (nrow(ev) == 0L) stop("validate_gaugings(): there are no gaugings to check", call. = FALSE)
  num <- function(v, name, lo = -Inf) {
    if (!is.numeric(v) || length(v) != 1L || is.na(v) || v < lo) {
      stop(sprintf("validate_gaugings(): %s must be a single number%s", name,
                   if (is.finite(lo)) sprintf(" of at least %s", lo) else ""), call. = FALSE)
    }
  }
  num(min_gaugings, "min_gaugings", 0)
  num(inversion_tolerance, "inversion_tolerance", 0)
  num(outlier_mad, "outlier_mad", 0)
  num(gap_fraction, "gap_fraction", 0)
  num(upper_range_fraction, "upper_range_fraction", 0)
  num(upper_range_min, "upper_range_min", 0)
  num(recent_years, "recent_years", 0)

  id <- ev$evidence_id
  stage <- as.numeric(ev$stage_m)
  q <- as.numeric(ev$discharge_cms)
  incl <- ev$included
  obs <- ev$observation_time
  usable <- is.finite(stage) & is.finite(q)
  tech <- "technical"
  hydro <- "hydrometric"
  rows <- list()
  add <- function(...) rows[[length(rows) + 1L]] <<- .check_row(...)
  plural <- function(n, one, many = paste0(one, "s")) if (n == 1L) one else many

  # ---- technical ------------------------------------------------------------
  bad <- !is.finite(stage)
  add("stage_finite", tech, if (any(bad)) "fail" else "pass",
      if (any(bad)) sprintf("%d %s a stage that is missing or not finite.", sum(bad), plural(sum(bad), "row has", "rows have"))
      else "Every stage is a finite number.",
      if (any(bad)) "Find these rows in the source and correct or remove them before fitting." else NA_character_,
      id[bad])

  bad <- !is.finite(q)
  add("discharge_finite", tech, if (any(bad)) "fail" else "pass",
      if (any(bad)) sprintf("%d %s a discharge that is missing or not finite.", sum(bad), plural(sum(bad), "row has", "rows have"))
      else "Every discharge is a finite number.",
      if (any(bad)) "Find these rows in the source and correct or remove them before fitting." else NA_character_,
      id[bad], stage[bad])

  neg <- is.finite(q) & q < 0
  add("discharge_not_negative", tech, if (any(neg)) "fail" else "pass",
      if (any(neg)) sprintf("%d %s a negative discharge.", sum(neg), plural(sum(neg), "gauging has", "gaugings have"))
      else "No discharge is negative.",
      if (any(neg)) "A negative flow is not a gauging on a one-way rating. Check the sign and the source." else NA_character_,
      id[neg], stage[neg])

  n_use <- sum(usable & incl)
  add("enough_rows", tech, if (n_use < 4L) "fail" else "pass",
      if (n_use < 4L) sprintf("Only %d usable %s: a limb has three parameters and needs more than that.", n_use, plural(n_use, "gauging"))
      else sprintf("%d usable gaugings.", n_use),
      if (n_use < 4L) "Add gaugings, or fit a rating by another route." else NA_character_)

  dup_id <- is.na(id) | !nzchar(id) | duplicated(id) | duplicated(id, fromLast = TRUE)
  add("evidence_id_unique", tech, if (any(dup_id)) "fail" else "pass",
      if (any(dup_id)) sprintf("%d %s with a missing or repeated evidence_id.", sum(dup_id), plural(sum(dup_id), "row", "rows"))
      else "Every evidence_id is present and unique.",
      if (any(dup_id)) "Give each row its own evidence_id; a diagnostic cannot name a row it cannot tell apart." else NA_character_,
      id[dup_id], stage[dup_id])

  if ("read_issue" %in% names(ev)) {
    note <- as.character(ev$read_issue)
    only_midnight <- !is.na(note) & note == "time missing, midnight assumed"
    unread <- !is.na(note) & !only_midnight
    add("read_issues", tech, if (any(unread)) "fail" else "pass",
        if (any(unread)) sprintf("%d %s a note from reading the file (for example: %s).",
                                 sum(unread), plural(sum(unread), "row has", "rows have"), note[unread][1])
        else "No row had a problem when it was read.",
        if (any(unread)) "Read the read_issue column for each of these rows and correct the source." else NA_character_,
        id[unread], stage[unread])
  } else {
    add("read_issues", tech, "not_assessed",
        "The table has no read_issue column, so reading problems could not be checked.",
        "Read the file with read_gaugings() to record them.")
  }

  # ---- hydrometric ----------------------------------------------------------
  zero <- usable & q == 0
  add("zero_discharge", hydro, if (any(zero)) "warning" else "pass",
      if (any(zero)) sprintf("%d %s a discharge of zero. A rating on relative error cannot use them.", sum(zero), plural(sum(zero), "gauging has", "gaugings have"))
      else "No gauging has a discharge of zero.",
      if (any(zero)) "A zero flow at a positive stage can be real (a pool above zero flow). Decide whether to keep it." else NA_character_,
      id[zero], stage[zero])

  key <- paste(stage, q, if (all(is.na(obs))) "" else as.character(obs))
  dup <- usable & (duplicated(key) | duplicated(key, fromLast = TRUE))
  add("duplicate_gaugings", hydro, if (any(dup)) "warning" else "pass",
      if (any(dup)) sprintf("%d %s an exact duplicate of another.", sum(dup), plural(sum(dup), "gauging is", "gaugings are"))
      else "No gauging is an exact duplicate of another.",
      if (any(dup)) "Repeated rows give a point more weight than one measurement deserves. Check whether they are one gauging entered twice." else NA_character_,
      id[dup], stage[dup])

  inv <- .inversion_flags(stage, q, usable, inversion_tolerance)
  if (is.null(inv)) {
    inv <- rep(FALSE, length(id))
    add("stage_discharge_inversion", hydro, "not_assessed",
        sprintf("More than %d usable gaugings: the pairwise inversion check is skipped.", .inversion_max_rows),
        "Validate one station at a time; a rating is built from one station's gaugings.")
  } else add("stage_discharge_inversion", hydro, if (any(inv)) "warning" else "pass",
      if (any(inv)) sprintf("%d %s part of a stage-discharge inversion: a discharge more than %g%% below that of a gauging at a lower stage.", sum(inv),
                            plural(sum(inv), "gauging is", "gaugings are"), 100 * inversion_tolerance)
      else "Discharge rises with stage throughout, within tolerance.",
      if (any(inv)) "Check for a shift, backwater, hysteresis on a rising or falling flood, or a wrong stage." else NA_character_,
      id[inv], stage[inv])

  pos <- usable & q > 0
  out_flag <- rep(FALSE, length(id))
  outlier_status <- "not_assessed"
  outlier_msg <- "Fewer than 8 gaugings with a positive discharge: too few to judge."
  if (sum(pos) >= 8L) {
    # Each gauging is compared with the cubic through its two nearest
    # neighbours on each side in stage, in log discharge. A cubic follows
    # the smooth curvature of a rating, which a global trend or a straight
    # line would mistake for error. A spike also disturbs the predictions
    # for the gaugings around it, so only a gauging whose residual is at
    # least as large as those of the two on either side is reported.
    idx <- which(pos)
    o <- idx[order(stage[idx], q[idx])]
    h <- stage[o]
    ly <- log(q[o])
    m <- length(o)
    resid <- rep(NA_real_, m)
    for (k in 3:(m - 2L)) {
      xs <- h[c(k - 2L, k - 1L, k + 1L, k + 2L)]
      if (anyDuplicated(xs) || h[k - 1L] == h[k + 1L]) next
      weights <- vapply(1:4, function(a) prod((h[k] - xs[-a]) / (xs[a] - xs[-a])), numeric(1))
      # The prediction's own noise grows with the sum of squared weights
      # (large when neighbours are bunched), so divide it out; otherwise a
      # badly placed neighbourhood is mistaken for an outlier.
      resid[k] <- (ly[k] - sum(weights * ly[c(k - 2L, k - 1L, k + 1L, k + 2L)])) / sqrt(1 + sum(weights^2))
    }
    spread <- stats::mad(resid, na.rm = TRUE)
    if (is.finite(spread) && spread > 0) {
      r <- abs(resid)
      r[is.na(r)] <- -Inf
      pad <- c(-Inf, -Inf, r, -Inf, -Inf)
      near <- pmax(pad[1:m], pad[2:(m + 1L)], pad[4:(m + 3L)], pad[5:(m + 4L)])
      big <- r > outlier_mad * spread
      out_flag[o[big & r >= near]] <- TRUE
    }
    outlier_status <- if (any(out_flag)) "warning" else "pass"
    outlier_msg <- if (any(out_flag)) {
      sprintf("%d %s off the curve of its neighbours in stage.", sum(out_flag), plural(sum(out_flag), "gauging lies", "gaugings lie"))
    } else {
      "No gauging is off the curve of its neighbours."
    }
  }
  add("outliers", hydro, outlier_status, outlier_msg,
      if (any(out_flag)) "Look at the gauging notes, method and date for each. They may be real (a shift) or an error." else NA_character_,
      id[out_flag], stage[out_flag])

  rng <- if (sum(usable) >= 1L) range(stage[usable]) else c(NA_real_, NA_real_)
  span <- diff(rng)
  if (sum(usable) < 3L || !is.finite(span) || span <= 0) {
    add("stage_coverage_gaps", hydro, "not_assessed", "Fewer than 3 gaugings, or no spread in stage, so coverage cannot be judged.")
  } else {
    s <- sort(unique(stage[usable]))
    gaps <- diff(s)
    wide <- which(gaps > gap_fraction * span)
    if (length(wide)) {
      lo <- s[wide]
      hi <- s[wide + 1L]
      edge <- usable & (stage %in% c(lo, hi))
      add("stage_coverage_gaps", hydro, "warning",
          sprintf("%d %s wider than %g%% of the stage range (largest: %.3g m, from %.3g to %.3g).",
                  length(wide), plural(length(wide), "gap is", "gaps are"), 100 * gap_fraction,
                  max(gaps), s[which.max(gaps)], s[which.max(gaps) + 1L]),
          "A rating across a gap with no gaugings is an interpolation. Gauge in the gap if you can.",
          id[edge], c(lo, hi))
    } else {
      add("stage_coverage_gaps", hydro, "pass", sprintf("No gap in stage is wider than %g%% of the range.", 100 * gap_fraction))
    }
  }

  if (sum(usable) < 4L || !is.finite(span) || span <= 0) {
    add("upper_range_support", hydro, "not_assessed", "Too few gaugings, or no spread in stage, to judge support at the top of the range.")
  } else {
    top <- usable & stage >= rng[2] - upper_range_fraction * span
    thin <- sum(top) < upper_range_min
    add("upper_range_support", hydro, if (thin) "warning" else "pass",
        if (thin) sprintf("Only %d %s in the top %g%% of the stage range (at least %d wanted).", sum(top),
                          plural(sum(top), "gauging"), 100 * upper_range_fraction, as.integer(upper_range_min))
        else sprintf("%d gaugings in the top %g%% of the stage range.", sum(top), 100 * upper_range_fraction),
        if (thin) "High flows matter most to the people who use a rating and are the hardest to gauge. Extrapolation above the top gauging is a modelling choice." else NA_character_,
        id[top], stage[top])
  }

  few <- n_use < min_gaugings
  add("few_gaugings", hydro, if (few) "warning" else "pass",
      if (few) sprintf("%d usable %s, fewer than the %d wanted.", n_use, plural(n_use, "gauging"), as.integer(min_gaugings))
      else sprintf("%d usable gaugings, at least the %d wanted.", n_use, as.integer(min_gaugings)),
      if (few) "Parameter uncertainty will be wide. Treat the fitted limbs with caution." else NA_character_)

  if (all(is.na(obs))) {
    add("temporal_coverage", hydro, "not_assessed", "No gauging has a date, so recency could not be judged.",
        "Supply observation times to check how recent the evidence is.")
  } else {
    latest <- max(obs, na.rm = TRUE)
    earliest <- min(obs, na.rm = TRUE)
    ref <- as.POSIXct(reference_time)
    age <- as.numeric(difftime(ref, as.POSIXct(latest), units = "days")) / 365.25
    old <- age > recent_years
    add("temporal_coverage", hydro, if (old) "warning" else "pass",
        sprintf("Gaugings run from %s to %s; the latest is %.1f years before the reference time.",
                format(as.Date(earliest)), format(as.Date(latest)), age),
        if (old) sprintf("No gauging in the last %g years. The channel may have changed since.", recent_years) else NA_character_)
  }

  excl <- !incl
  add("excluded_rows", hydro, if (any(excl)) "warning" else "pass",
      if (any(excl)) sprintf("%d %s marked as excluded.", sum(excl), plural(sum(excl), "row is", "rows are"))
      else "No row is marked as excluded.",
      if (any(excl)) "Check the exclusion_reason of each. Excluded rows are kept in the evidence but should not drive a fit." else NA_character_,
      id[excl], stage[excl])

  if ("read_issue" %in% names(ev)) {
    assumed <- !is.na(ev$read_issue) & grepl("time missing, midnight assumed", ev$read_issue, fixed = TRUE)
    add("times_assumed", hydro, if (any(assumed)) "warning" else "pass",
        if (any(assumed)) sprintf("%d %s no time of day, so midnight was assumed.", sum(assumed), plural(sum(assumed), "gauging has", "gaugings have"))
        else "No time of day was assumed.",
        if (any(assumed)) "Time matters when a rating changes within a day or gaugings are weighted by age." else NA_character_,
        id[assumed], stage[assumed])
  } else {
    add("times_assumed", hydro, "not_assessed",
        "The table has no read_issue column, so assumed times could not be checked.",
        "Read the file with read_gaugings() to record them.")
  }

  FlodeAssessment(
    checks = rbindlist(rows), subject = "gaugings",
    assessed_rows = as.integer(nrow(ev))
  )
}
