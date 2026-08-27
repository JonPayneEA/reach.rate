# ============================================================ #
# Tool:         graft_rating
# Description:  Join a freshly-fitted rating (trusted only up to its own
#               gauged range) onto a pre-existing rating used above that
#               range -- finding the stage where the two curves actually
#               cross and combining them into one contiguous table.
#               Distinct from align_limb_equations()/align_limb_boundaries(),
#               which reconcile junctions *within* one already-built
#               table; this joins two independently-sourced ratings.
# Author:       Jonathan Payne
# Created:      2026-08-27
# Tier:         3
# Inputs:       new_rating: a FlodeRating or FlodeRatingTable, freshly
#               fitted, trusted up to its own top boundary.
#               existing_rating: a FlodeRatingTable or a plain
#               data.frame/data.table (lower_level, upper_level, C, a, n)
#               already valid above the new rating's gauged range.
# Outputs:      A FlodeRatingTable, one contiguous table spanning both
#               sources.
# Dependencies: data.table, S7
# ============================================================ #

#' @include flode_classes.R gap_check.R
NULL

#' Graft a freshly-fitted rating onto a pre-existing one above its gauged range
#'
#' @description
#' Real stations are sometimes only re-gauged, and re-fitted, up to some
#' stage -- extreme floods above that stay described by whatever rating
#' was already in force there. `graft_rating()` joins the two: it finds
#' the stage where `new_rating`'s top limb and `existing_rating`'s lowest
#' still-relevant limb actually cross (the same crossing search
#' [align_limb_boundaries()] uses for a junction inside one table, here
#' used to join two different ones), trims/extends both limbs to that
#' stage, and returns one contiguous table.
#'
#' This is deliberately different from [align_limb_equations()]/
#' [align_limb_boundaries()], which reconcile a junction *within* one
#' already-built table. `graft_rating()` combines two independently
#' sourced ratings -- one just fitted, one pre-existing -- into a new one.
#'
#' The result is always a [FlodeRatingTable], even when `new_rating` was a
#' [FlodeRating]: the grafted-on limbs come from `existing_rating`, which
#' carries no gaugings of its own, so a `FlodeRating` result would be
#' honest about some limbs and silently false about others. `new_rating`
#' itself, ungrafted, remains the right object for diagnostics on the
#' newly-fitted part.
#'
#' @param new_rating A [FlodeRating] or [FlodeRatingTable] -- the freshly
#'   fitted rating, trusted only up to its own top boundary.
#' @param existing_rating A [FlodeRatingTable], or a plain
#'   data.frame/data.table with columns `lower_level`, `upper_level`,
#'   `C`, `a`, `n` (same shape as [expand_rating_table()]'s input). Only
#'   limbs whose `upper_level` exceeds `new_rating`'s top boundary are
#'   used; it is an error if none qualify.
#' @param search_range `NULL` (default), or a numeric `c(lower, upper)`
#'   bracket to search for the crossing stage, overriding the default
#'   `c(new_rating's top boundary, first retained existing limb's
#'   upper_level)`.
#' @param on_no_crossing Character. What to do when no crossing exists
#'   within `search_range`. `"error"` (default) stops. `"join_at_top"`
#'   joins exactly at `new_rating`'s top boundary instead, accepting
#'   whatever discontinuity results there, with a warning naming the
#'   resulting jump in discharge.
#'
#' @return A [FlodeRatingTable] with `@status` `"grafted"`, `@previous`
#'   referencing `new_rating` exactly as passed in, and `@table` gaining
#'   a `source` column (`"new"`/`"existing"`) marking which side each
#'   limb came from.
#'
#' @seealso [align_limb_boundaries()], whose crossing search this
#'   function reuses, for reconciling a junction within one table rather
#'   than joining two different ones.
#'
#' @examples
#' new_table <- data.table::data.table(
#'   lower_level = c(0.0, 1.5), upper_level = c(1.5, 3.41),
#'   C = c(2.5, 2.831), a = c(0.0, -0.886), n = c(1.50, 1.935)
#' )
#' existing_table <- data.table::data.table(
#'   lower_level = 3.41, upper_level = 6.0,
#'   C = 0.3128, a = 0, n = 4.095
#' )
#' grafted <- graft_rating(new_table, existing_table)
#' grafted@table[, .(lower_level, upper_level, C, a, n, source)]
#'
#' @export
graft_rating <- function(new_rating, existing_rating, search_range = NULL,
                          on_no_crossing = c("error", "join_at_top")) {
  on_no_crossing <- match.arg(on_no_crossing)

  new_rating_original <- if (S7_inherits(new_rating, FlodeRating) || S7_inherits(new_rating, FlodeRatingTable)) {
    new_rating
  } else {
    NULL
  }
  if (S7_inherits(new_rating, FlodeRating)) new_rating <- as_rating_table(new_rating)
  if (S7_inherits(new_rating, FlodeRatingTable)) new_rating <- new_rating@table
  if (S7_inherits(existing_rating, FlodeRatingTable)) existing_rating <- existing_rating@table

  required <- c("lower_level", "upper_level", "C", "a", "n")
  .check_shape <- function(tbl, label) {
    if (!is.data.frame(tbl)) stop(sprintf("graft_rating(): %s must be a FlodeRating, FlodeRatingTable, or data.frame/data.table", label))
    if (nrow(tbl) == 0) stop(sprintf("graft_rating(): %s must have at least one row", label))
    missing <- setdiff(required, names(tbl))
    if (length(missing)) {
      stop(sprintf("graft_rating(): %s is missing column(s): %s", label, paste(missing, collapse = ", ")))
    }
  }
  .check_shape(new_rating, "new_rating")
  .check_shape(existing_rating, "existing_rating")

  .check_contiguous <- function(tbl, label) {
    n <- nrow(tbl)
    if (n > 1L) {
      contiguous <- all(abs(tbl$upper_level[-n] - tbl$lower_level[-1L]) < 1e-8)
      if (!contiguous) {
        stop(sprintf("graft_rating(): %s limbs must be contiguous (upper_level[i] == lower_level[i+1]).", label))
      }
    }
  }
  new_dt <- copy(as.data.table(new_rating))
  existing_dt <- copy(as.data.table(existing_rating))
  .check_contiguous(new_dt, "new_rating")
  .check_contiguous(existing_dt, "existing_rating")

  new_top <- new_dt$upper_level[nrow(new_dt)]
  existing_above <- existing_dt[upper_level > new_top]
  if (nrow(existing_above) == 0L) {
    stop("graft_rating(): no existing_rating limb extends above new_rating's top boundary (", new_top, ") -- nothing to graft onto.")
  }
  setorder(existing_above, lower_level)

  top_new <- new_dt[nrow(new_dt)]
  first_existing <- existing_above[1L]

  eval_q <- function(stage, C, a, n) C * (stage - a)^n

  if (is.null(search_range)) search_range <- c(new_top, first_existing$upper_level)
  if (!is.numeric(search_range) || length(search_range) != 2L || search_range[1] >= search_range[2]) {
    stop("graft_rating(): search_range must be NULL or a numeric c(lower, upper) with lower < upper")
  }

  join_stage <- .find_intersection_stage(
    top_new$C, top_new$a, top_new$n,
    first_existing$C, first_existing$a, first_existing$n,
    search_range[1], search_range[2]
  )

  if (is.na(join_stage)) {
    msg <- sprintf(
      "graft_rating(): no crossing found between new_rating's top limb and existing_rating's first qualifying limb within [%.6g, %.6g].",
      search_range[1], search_range[2]
    )
    if (on_no_crossing == "error") stop(msg)
    join_stage <- new_top
    q1 <- eval_q(join_stage, top_new$C, top_new$a, top_new$n)
    q2 <- eval_q(join_stage, first_existing$C, first_existing$a, first_existing$n)
    warning(sprintf(
      '%s Joining at new_rating\'s top boundary (H = %.6g) instead (on_no_crossing = "join_at_top") -- discharge jumps from %.6g to %.6g there.',
      msg, join_stage, q1, q2
    ))
  }

  new_dt[nrow(new_dt), upper_level := join_stage]
  existing_above[1L, lower_level := join_stage]

  new_dt[, source := "new"]
  existing_above[, source := "existing"]
  combined_dt <- rbind(new_dt, existing_above, fill = TRUE)

  FlodeRatingTable(
    table = combined_dt[],
    status = "grafted",
    previous = new_rating_original
  )
}
