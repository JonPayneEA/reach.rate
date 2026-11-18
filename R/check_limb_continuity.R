# ============================================================ #
# Tool:         check_limb_continuity
# Description:  Exact continuity check at every junction between limbs
#               (tranche B6): the discharge gap in absolute and relative
#               terms, the stage gap, and the change of slope, optionally
#               before and after an alignment. Works from the equations,
#               not from a discretised table.
# Author:       Jonathan Payne
# Created:      2026-11-18
# Tier:         3
# Inputs:       A FlodeRating or FlodeRatingTable, and optionally the same
#               rating after align_limb_equations() or
#               align_limb_boundaries().
# Outputs:      A data.table, one row per junction.
# Dependencies: data.table
# ============================================================ #

#' @include flode_classes.R invariants.R gap_check.R
NULL

# Continuity measures at each junction of an equation table, at the exact
# stage the two limbs share.
.junction_metrics <- function(tbl, tol_abs, tol_rel, tol_stage, tol_slope) {
  n <- nrow(tbl)
  empty <- data.table(
    junction = integer(0), stage_m = numeric(0), limb_below = integer(0), limb_above = integer(0),
    q_below_cms = numeric(0), q_above_cms = numeric(0), gap_cms = numeric(0), gap_rel = numeric(0),
    stage_gap_m = numeric(0), slope_below = numeric(0), slope_above = numeric(0), slope_change_pct = numeric(0),
    discharge_ok = logical(0), stage_ok = logical(0), slope_ok = logical(0), continuous = logical(0)
  )
  if (n < 2L) return(empty)
  j <- seq_len(n - 1L)
  h <- tbl$upper_level[j]
  qb <- .eval_limb(tbl$C[j], tbl$a[j], tbl$n[j], h)
  qa <- .eval_limb(tbl$C[j + 1L], tbl$a[j + 1L], tbl$n[j + 1L], h)
  gap <- qa - qb
  rel <- ifelse(qb > 0, gap / qb, NA_real_)
  # The horizontal gap: the stage at which the upper limb gives the discharge
  # the lower limb gives at the junction, less the junction stage. Negative
  # when the upper limb is the higher curve. It is what a gauge reader sees as
  # "the rating jumps by this many millimetres of stage".
  up_stage <- ifelse(qb > 0, tbl$a[j + 1L] + (qb / tbl$C[j + 1L])^(1 / tbl$n[j + 1L]), NA_real_)
  stage_gap <- up_stage - h
  slope <- function(C, a, n, h) ifelse(h > a, C * n * (h - a)^(n - 1), 0)
  sb <- slope(tbl$C[j], tbl$a[j], tbl$n[j], h)
  sa <- slope(tbl$C[j + 1L], tbl$a[j + 1L], tbl$n[j + 1L], h)
  slope_change <- ifelse(sb > 0, 100 * (sa - sb) / sb, NA_real_)
  # Small flows are judged on the absolute gap and large ones on the
  # relative gap, so a tiny flow does not fail a percentage test and a big
  # one does not need a fraction of a cumec.
  # A gap exactly on a tolerance passes. Floating point can put 2.1 - 2 a
  # hair above 0.1, so the comparison carries a relative allowance of 1e-9.
  fuzz <- 1 + 1e-9
  discharge_ok <- abs(gap) <= tol_abs * fuzz | (!is.na(rel) & abs(rel) <= tol_rel * fuzz)
  stage_ok <- ifelse(is.na(stage_gap), abs(gap) <= tol_abs * fuzz, abs(stage_gap) <= tol_stage * fuzz)
  slope_ok <- if (is.null(tol_slope)) rep(NA, length(j)) else (is.na(slope_change) | abs(slope_change) <= 100 * tol_slope * fuzz)
  data.table(
    junction = j, stage_m = h, limb_below = j, limb_above = j + 1L,
    q_below_cms = qb, q_above_cms = qa, gap_cms = gap, gap_rel = rel, stage_gap_m = stage_gap,
    slope_below = sb, slope_above = sa, slope_change_pct = slope_change,
    discharge_ok = discharge_ok, stage_ok = stage_ok, slope_ok = slope_ok,
    continuous = discharge_ok & stage_ok
  )
}

#' Check that the limbs of a rating meet
#'
#' @description
#' At each junction between two limbs, measures how far apart the two
#' equations are at the stage they share, three ways:
#'
#' * the **discharge gap**, in m\eqn{^3}/s (`gap_cms`) and as a fraction of the
#'   discharge below the junction (`gap_rel`);
#' * the **stage gap** (`stage_gap_m`): how far the upper limb would have to
#'   move sideways to meet the lower one, which is the number a gauge reader
#'   sees as the rating jumping at that stage. It is negative when the upper
#'   limb is the higher curve;
#' * the **change of slope** (`slope_change_pct`): the difference in
#'   \eqn{dQ/dH} across the junction. A change of slope at a breakpoint is
#'   normal, because that is what a breakpoint is for, so it is reported but
#'   judged only if you give `tol_slope`.
#'
#' A junction is `continuous` when the discharge gap and the stage gap are both
#' within tolerance. The discharge gap passes if it is within `tol_abs`
#' **or** within `tol_rel`, so a tiny flow is not failed on a percentage and a
#' large flow does not need a fraction of a cumec; the stage gap passes if it is
#' within `tol_stage`.
#'
#' It works from the equations, exactly at the shared stage, where
#' [detect_rc_gaps()] scans a discretised rating table. With `after` it reports
#' the same measures before and after an alignment ([align_limb_equations()] or
#' [align_limb_boundaries()]), so the effect of the amendment is on the table
#' and not only claimed.
#'
#' A single limb has no junction, and a [FlodeSegmentedRating] is continuous
#' by construction (every later factor of its joint equation is exactly 1 at
#' its breakpoint), so each gives a table with no rows.
#'
#' @param x A [FlodeRating] or [FlodeRatingTable].
#' @param after `NULL` (default), or the same rating after an alignment, with
#'   the same number of limbs, to compare with `x`.
#' @param tol_abs Number, m\eqn{^3}/s. Default 0.05.
#' @param tol_rel Number. Default 0.01 (1%).
#' @param tol_stage Number, metres. Default 0.005, about the resolution of a
#'   gauge.
#' @param tol_slope Number or `NULL`. A change of slope larger than this
#'   fraction (0.1 is 10%) is reported as `slope_ok = FALSE`. `NULL`
#'   (default): the slope is reported, not judged, and `slope_ok` is `NA`.
#'
#' @return A data.table, one row per junction, with `junction`, `stage_m`,
#'   `limb_below`, `limb_above`, `q_below_cms`, `q_above_cms`, `gap_cms`,
#'   `gap_rel`, `stage_gap_m`, `slope_below`, `slope_above`,
#'   `slope_change_pct`, `discharge_ok`, `stage_ok`, `slope_ok` and
#'   `continuous`.
#'
#'   With `after`, one row per junction with `junction` and, for `stage_m`,
#'   `gap_cms`, `gap_rel`, `stage_gap_m`, `slope_change_pct` and `continuous`,
#'   a `_before` and an `_after` column, and `improved`, `TRUE` where the
#'   discharge gap shrank. Boundaries can move in [align_limb_boundaries()], so
#'   the junction stage is given for both.
#'
#' @seealso [detect_rc_gaps()], [align_limb_equations()],
#'   [align_limb_boundaries()], [rating_invariants()] for the same question as
#'   a warning
#'
#' @examples
#' # Two limbs that do not quite meet at 1 m.
#' rating <- FlodeRatingTable(table = data.table::data.table(
#'   lower_level = c(0.2, 1), upper_level = c(1, 3),
#'   C = c(2, 2.1), a = c(0, 0), n = c(1.5, 1.6)
#' ))
#' check_limb_continuity(rating)[, .(stage_m, gap_cms, gap_rel, stage_gap_m, continuous)]
#'
#' # Before and after closing the gap.
#' aligned <- align_limb_equations(rating)
#' check_limb_continuity(rating, after = aligned)[, .(gap_cms_before, gap_cms_after, improved)]
#'
#' @export
check_limb_continuity <- function(x, after = NULL, tol_abs = 0.05, tol_rel = 0.01, tol_stage = 0.005, tol_slope = NULL) {
  fn <- "check_limb_continuity()"
  num <- function(v, name) {
    if (!is.numeric(v) || length(v) != 1L || is.na(v) || v < 0) stop(sprintf("%s: %s must be a single non-negative number", fn, name), call. = FALSE)
  }
  num(tol_abs, "tol_abs"); num(tol_rel, "tol_rel"); num(tol_stage, "tol_stage")
  if (!is.null(tol_slope)) num(tol_slope, "tol_slope")
  as_table <- function(r, what) {
    if (S7_inherits(r, FlodeSegmentedRating)) return(NULL)
    tbl <- if (S7_inherits(r, FlodeRating) || S7_inherits(r, FlodeRatingTable)) .invariant_table(r) else NULL
    if (is.null(tbl)) stop(sprintf("%s: %s must be a FlodeRating or FlodeRatingTable", fn, what), call. = FALSE)
    tbl
  }
  tbl <- as_table(x, "x")
  before <- if (is.null(tbl)) .junction_metrics(data.table(upper_level = numeric(0)), tol_abs, tol_rel, tol_stage, tol_slope) else
    .junction_metrics(tbl, tol_abs, tol_rel, tol_stage, tol_slope)
  if (is.null(after)) return(before[])

  tbl2 <- as_table(after, "after")
  aft <- if (is.null(tbl2)) before[0] else .junction_metrics(tbl2, tol_abs, tol_rel, tol_stage, tol_slope)
  if (nrow(before) != nrow(aft)) {
    stop(sprintf("%s: x has %d junction(s) and after has %d. Compare a rating with its own alignment.", fn, nrow(before), nrow(aft)),
         call. = FALSE)
  }
  out <- data.table(junction = before$junction)
  for (col in c("stage_m", "gap_cms", "gap_rel", "stage_gap_m", "slope_change_pct", "continuous")) {
    set(out, j = paste0(col, "_before"), value = before[[col]])
    set(out, j = paste0(col, "_after"), value = aft[[col]])
  }
  set(out, j = "improved", value = abs(aft$gap_cms) < abs(before$gap_cms) - 1e-12)
  out[]
}
