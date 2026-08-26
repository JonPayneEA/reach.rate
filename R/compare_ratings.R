# ============================================================ #
# Tool:         compare_ratings
# Description:  Diff two rating equation tables -- coefficient-by-limb
#               where limb counts match, and discharge-by-stage across
#               their overlapping range regardless of limb count -- and
#               plot the comparison, for documenting rating amendments
# Author:       Jonathan Payne
# Created:      2026-08-18
# Modified:     2026-08-18 - JP: initial version
# Modified:     2026-08-18 - JP: added plot_rating_comparison() -- a
#               diff-only, non-visual result wasn't much use for actually
#               judging a rating amendment.
# Modified:     2026-08-19 - JP: accepts a FlodeRatingTable or a plain
#               table for rating_old_dt/rating_new_dt (unwrapped at the
#               top), and updated the internal apply_rating() calls to
#               its new (fit, stage_dt) argument order, wrapping each
#               table in a FlodeRatingTable to satisfy the generic's
#               dispatch.
# Modified:     2026-08-25 - JP: converted from a box module to a package
#               R/ file. Imports are now package-level
#               (R/reach.rate-package.R); FlodeRatingTable and
#               apply_rating (flode_classes.R/apply_rating.R) need no
#               import at all -- same package namespace.
# Tier:         3
# Inputs:       Two rating equation tables -- FlodeRatingTable or a plain
#               data.frame/data.table with lower_level/upper_level/C/a/n,
#               same shape as expand_rating_table()'s input
# Outputs:      compare_ratings() returns a list(coefficients, discharge)
#               of data.tables. plot_rating_comparison() draws a two-panel
#               figure from that result.
# Dependencies: data.table, ggplot2, gridExtra, logger, S7
# ============================================================ #

log_threshold(INFO)

#' Compare two rating equation tables
#'
#' @description
#' Diffs two rating tables (e.g. before/after a limb-alignment or a
#' gauging review) two ways:
#'
#' \describe{
#'   \item{coefficients}{A limb-by-limb comparison of `C`/`a`/`n`,
#'     produced only when both tables have the same number of limbs in
#'     the same order.}
#'   \item{discharge}{The actual discharge difference across a common
#'     stage sequence, computed by running both tables through
#'     [apply_rating()]. This is the more useful comparison when limb
#'     counts differ, or when the question is "how much does this
#'     amendment actually change the flow", not just "how much did the
#'     coefficients move".}
#' }
#'
#' @param rating_old_dt,rating_new_dt A [FlodeRatingTable], or a plain
#'   data.frame/data.table with columns `lower_level`, `upper_level`,
#'   `C`, `a`, `n` -- one row per limb. Need not have the same number of
#'   limbs.
#' @param step Numeric. Stage increment for the discharge comparison.
#'   Default `0.01`.
#'
#' @return A list with elements:
#'   \describe{
#'     \item{coefficients}{A `data.table` comparing limb-by-limb C/a/n,
#'       or `NULL` if the limb counts differ.}
#'     \item{discharge}{A `data.table` with `stage`, `discharge_old`,
#'       `discharge_new`, `discharge_diff`, `discharge_pct_diff`, and the
#'       `extrapolated` flag from each table, across the overlapping
#'       stage range of both ratings.}
#'   }
#'
#' @seealso [apply_rating()], [plot_rating_comparison()]
#'
#' @examples
#' rating_old_dt <- data.table::data.table(
#'   lower_level = c(0.0, 1.2), upper_level = c(1.2, 3.0),
#'   C = c(2.5, 4.1), a = c(0, 0), n = c(1.5, 1.7)
#' )
#' rating_new_dt <- data.table::data.table(
#'   lower_level = c(0.0, 1.2), upper_level = c(1.2, 3.0),
#'   C = c(2.6, 4.0), a = c(0, 0), n = c(1.5, 1.7)
#' )
#' cmp <- compare_ratings(rating_old_dt, rating_new_dt)
#' cmp$coefficients
#' cmp$discharge
#'
#' @export
compare_ratings <- function(rating_old_dt, rating_new_dt, step = 0.01) {
  if (S7_inherits(rating_old_dt, FlodeRatingTable)) rating_old_dt <- rating_old_dt@table
  if (S7_inherits(rating_new_dt, FlodeRatingTable)) rating_new_dt <- rating_new_dt@table
  if (!is.data.frame(rating_old_dt)) stop("rating_old_dt must be a FlodeRatingTable, data.frame, or data.table")
  if (!is.data.frame(rating_new_dt)) stop("rating_new_dt must be a FlodeRatingTable, data.frame, or data.table")
  if (!is.numeric(step) || step <= 0) stop("step must be a positive number")

  rating_old_dt <- as.data.table(rating_old_dt)
  rating_new_dt <- as.data.table(rating_new_dt)

  coefficients_dt <- NULL
  if (nrow(rating_old_dt) == nrow(rating_new_dt)) {
    coefficients_dt <- data.table(
      limb = seq_len(nrow(rating_old_dt)),
      lower_level = rating_old_dt$lower_level,
      upper_level = rating_old_dt$upper_level,
      C_old = rating_old_dt$C, C_new = rating_new_dt$C,
      a_old = rating_old_dt$a, a_new = rating_new_dt$a,
      n_old = rating_old_dt$n, n_new = rating_new_dt$n
    )
    coefficients_dt[, `:=`(
      C_diff = C_new - C_old,
      a_diff = a_new - a_old,
      n_diff = n_new - n_old
    )]
  } else {
    log_info(
      "compare_ratings(): limb counts differ ({nrow(rating_old_dt)} vs {nrow(rating_new_dt)}) - ",
      "skipping the per-limb coefficient comparison; see $discharge instead."
    )
  }

  common_lo <- max(min(rating_old_dt$lower_level), min(rating_new_dt$lower_level))
  common_hi <- min(max(rating_old_dt$upper_level), max(rating_new_dt$upper_level))
  if (common_hi <= common_lo) {
    stop("compare_ratings(): the two ratings' stage ranges do not overlap.")
  }

  common_stage_dt <- data.table(stage = seq(common_lo, common_hi, by = step))

  old_table <- FlodeRatingTable(table = rating_old_dt)
  new_table <- FlodeRatingTable(table = rating_new_dt)
  old_dt <- apply_rating(old_table, common_stage_dt, stage_col = "stage", out_col = "discharge_old")
  new_dt <- apply_rating(new_table, common_stage_dt, stage_col = "stage", out_col = "discharge_new")

  discharge_dt <- old_dt[, .(stage, discharge_old, extrapolated_old = extrapolated)]
  discharge_dt[, `:=`(
    discharge_new = new_dt$discharge_new,
    extrapolated_new = new_dt$extrapolated
  )]
  discharge_dt[, discharge_diff := discharge_new - discharge_old]
  discharge_dt[, discharge_pct_diff := fifelse(
    abs(discharge_old) > 1e-9, 100 * discharge_diff / discharge_old, NA_real_
  )]

  list(coefficients = coefficients_dt, discharge = discharge_dt)
}

#' Plot a rating comparison: curves and their discharge difference
#'
#' @description
#' Two-panel figure for a [compare_ratings()] result. The top panel
#' overlays the old and new rating curves (dashed vs solid, the same
#' convention `plot_rc_gaps()` uses for before/after), so the shape of
#' the change is visible directly. The bottom panel plots the discharge
#' difference against stage, so it's clear not just *that* an amendment
#' changed the rating but *where in the stage range* it actually matters
#' -- a coefficient change that only bites at high flows looks very
#' different from one that shifts the whole curve evenly.
#'
#' @param cmp The list returned by [compare_ratings()].
#' @param old_label,new_label Character. Legend labels for the two
#'   ratings. Defaults `"Old"` and `"New"`.
#'
#' @return The combined grob from `gridExtra::grid.arrange()`, invisibly.
#'   Printed as a side effect.
#'
#' @seealso [compare_ratings()]
#'
#' @examples
#' rating_old_dt <- data.table::data.table(
#'   lower_level = c(0.0, 1.2), upper_level = c(1.2, 3.0),
#'   C = c(2.5, 4.1), a = c(0, 0), n = c(1.5, 1.7)
#' )
#' rating_new_dt <- data.table::data.table(
#'   lower_level = c(0.0, 1.2), upper_level = c(1.2, 3.0),
#'   C = c(2.6, 4.0), a = c(0, 0), n = c(1.5, 1.7)
#' )
#' cmp <- compare_ratings(rating_old_dt, rating_new_dt)
#' plot_rating_comparison(cmp)
#'
#' @export
plot_rating_comparison <- function(cmp, old_label = "Old", new_label = "New") {
  if (!is.list(cmp) || !("discharge" %in% names(cmp)) || !is.data.frame(cmp$discharge)) {
    stop("cmp must be a list with a 'discharge' data.table (see compare_ratings())")
  }

  discharge_dt <- copy(cmp$discharge)
  colour_map <- setNames(c("grey40", "#0288d1"), c(old_label, new_label))

  p_curves <- ggplot(discharge_dt) +
    geom_path(
      aes(x = discharge_old, y = stage, colour = old_label),
      linetype = "dashed", linewidth = 1
    ) +
    geom_path(
      aes(x = discharge_new, y = stage, colour = new_label),
      linetype = "solid", linewidth = 1.2
    ) +
    scale_colour_manual(name = NULL, values = colour_map) +
    labs(
      title = "Rating Comparison",
      x = "Discharge (m\u00b3/s)", y = "Stage"
    ) +
    theme_minimal(base_size = 12) +
    theme(
      plot.title = element_text(face = "bold", size = 13),
      legend.position = "top"
    )

  p_diff <- ggplot(discharge_dt, aes(x = stage, y = discharge_diff)) +
    geom_hline(yintercept = 0, colour = "grey50", linetype = "dashed") +
    geom_line(colour = "firebrick", linewidth = 1) +
    labs(
      title = sprintf("Discharge Difference (%s \u2212 %s)", new_label, old_label),
      x = "Stage", y = "\u0394 Discharge (m\u00b3/s)"
    ) +
    theme_minimal(base_size = 12) +
    theme(plot.title = element_text(face = "bold", size = 12))

  combined <- grid.arrange(p_curves, p_diff, ncol = 1, heights = c(2, 1))
  invisible(combined)
}
