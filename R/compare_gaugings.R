# ============================================================ #
# Tool:         compare_gaugings
# Description:  Compare a rating with a set of spot gaugings that were not
#               necessarily used to fit it: the residual of each gauging
#               against the rating, and per limb how many gaugings sit on
#               it, over what stage range, and how closely it fits them.
#               Built for checking an operational rating against an
#               archive of gaugings, and for seeing which limbs rest on
#               gauged evidence and which do not.
# Author:       Jonathan Payne
# Created:      2026-11-18
# Tier:         3
# Inputs:       rating: FlodeRating, FlodeRatingTable, or a plain table
#               with lower_level/upper_level/C/a/n. gaugings: data.frame
#               with a stage column and a discharge column.
# Outputs:      list(gaugings, limbs) of data.tables.
# Dependencies: data.table, logger, S7
# ============================================================ #

#' @include flode_classes.R apply_rating.R
NULL

#' Compare a rating with a set of gaugings
#'
#' @description
#' Checks a rating against spot gaugings: for each gauging, what the
#' rating predicts at that stage and how far the gauged discharge is from
#' it; for each limb, how many gaugings sit on it, over what stage range,
#' and how closely the limb fits them. The gaugings need not be the ones
#' the rating was fitted to, so this suits an operational rating checked
#' against a full gauging archive.
#'
#' It reports and does not judge. A limb with no gaugings (`has_gaugings`
#' is `FALSE`) is not wrong, but nothing in the supplied gaugings supports
#' it, which is what you would expect of a limb modelled for high flows.
#' A gauging below the lowest limb or above the highest is evaluated by
#' extrapolating the nearest limb, as [apply_rating()] does, and flagged
#' `extrapolated`; extrapolated gaugings are counted separately and left
#' out of each limb's fit statistics, so a limb's bias is measured only
#' on stage it actually covers.
#'
#' @param rating A [FlodeRating], a [FlodeRatingTable], or a
#'   data.frame/data.table with `lower_level`, `upper_level`, `C`, `a` and
#'   `n`, one row per limb, contiguous. A `FlodeRating` is bridged through
#'   [as_rating_table()] first.
#' @param gaugings A data.frame or data.table with a stage column and a
#'   discharge column. Other columns, such as a station or date, are
#'   carried through unchanged. Rows with a missing stage or discharge are
#'   kept, with missing results, and never dropped.
#' @param stage_col,discharge_col Character. Names of the stage (m) and
#'   discharge (cumecs) columns of `gaugings`. Defaults `"stage_m"` and
#'   `"discharge_cms"`. Both must be numeric.
#' @param tol_rel Numeric. A gauging counts as within tolerance when its
#'   discharge is within this fraction of the rating's prediction. Default
#'   `0.10`, that is 10 per cent. A gauging exactly on the tolerance
#'   counts as within it.
#'
#' @return A list of two data.tables.
#'   * `gaugings`: `gaugings` with columns added: `limb` (the row of the
#'     rating whose equation was used, the nearest limb for an
#'     extrapolated gauging), `extrapolated`, `discharge_predicted_cms`,
#'     `residual_cms` (gauged minus predicted), `residual_pct` (residual
#'     as a percentage of the prediction, `NA` where the prediction is
#'     zero) and `within_tol`.
#'   * `limbs`: one row per limb of the rating, with `limb`, `lower_level`,
#'     `upper_level`, `n_gaugings` (inside the limb's range),
#'     `n_extrapolated` (gaugings that fell outside the rating and were
#'     assigned to this limb), `gauged_min_stage` and `gauged_max_stage`
#'     (`NA` with no gaugings), `median_residual_pct` (positive means the
#'     gaugings sit above the rating), `spread_pct` (interquartile range
#'     of `residual_pct`), `share_within_tol` and `has_gaugings`.
#'
#' @section Why medians:
#' A percentage residual is unstable where the rating predicts a very
#' small discharge: a gauging of 0.3 cumecs at a stage where the rating
#' gives 0.00000001 is 3 billion per cent out. Archives often hold such
#' rows (a stage of zero with a measured flow, for example). A mean or a
#' root mean square would be set by that one row, so each limb is
#' summarised by the median and the interquartile range of `residual_pct`,
#' and by the share of gaugings within tolerance, none of which a single
#' extreme row can move. The row itself stays visible in `gaugings`.
#'
#' @seealso [read_gaugings()] and [read_operational_ratings()] to bring in
#'   a gauging archive and a ratings export;
#'   [compare_ratings()] to compare two ratings with each other;
#'   [flag_extrapolated_limbs()] and [plot_rating_residuals()] for a fit
#'   against the gaugings it was fitted to.
#'
#' @examples
#' # A four-limb operational rating, with limbs that meet in discharge
#' rating_dt <- data.table::data.table(
#'   lower_level = c(0.30, 0.90, 1.70, 2.60),
#'   upper_level = c(0.90, 1.70, 2.60, 4.00),
#'   C           = c(1.80000, 2.85549, 4.72355, 2.36038),
#'   a           = c(0.10, 0.25, 0.55, 0.40),
#'   n           = c(1.60, 1.90, 1.45, 2.20)
#' )
#' rating <- FlodeRatingTable(table = rating_dt)
#'
#' # An archive of spot gaugings. Gaugings reach only stage 2.3, so the
#' # top limb has none. The truth in the bankfull limb (1.7 to 2.6 m) is
#' # 15 per cent below what the rating says, and two gaugings were taken
#' # below the lowest limb.
#' set.seed(11)
#' stage_m <- c(0.25, 0.28, sort(runif(60, 0.3, 2.3)))
#' predicted <- apply_rating(rating, stage_m)$discharge
#' truth_factor <- ifelse(stage_m >= 1.7, 0.85, 1)
#' gaugings <- data.frame(
#'   stage_m = stage_m,
#'   discharge_cms = predicted * truth_factor * exp(rnorm(length(stage_m), sd = 0.04))
#' )
#'
#' check <- compare_gaugings_to_rating(rating, gaugings)
#' check$limbs
#' head(check$gaugings)
#'
#' library(ggplot2)
#' plot_dt <- check$gaugings
#' plot_dt$limb <- factor(plot_dt$limb)
#' ggplot(plot_dt, aes(stage_m, residual_pct, colour = limb, shape = extrapolated)) +
#'   annotate("rect", xmin = -Inf, xmax = Inf, ymin = -10, ymax = 10,
#'            fill = "grey85", alpha = 0.6) +
#'   geom_hline(yintercept = 0, colour = "grey40") +
#'   geom_vline(xintercept = rating_dt$upper_level[-4], linetype = "22", colour = "grey60") +
#'   geom_point(size = 2) +
#'   scale_shape_manual(values = c(`FALSE` = 16, `TRUE` = 4),
#'                      labels = c(`FALSE` = "Inside rating", `TRUE` = "Extrapolated")) +
#'   labs(x = "Stage (m)", y = "Gauged minus rating (% of rating)",
#'        colour = "Limb", shape = NULL,
#'        title = "Gaugings against an operational rating",
#'        subtitle = "Grey band: within 10 per cent. Limb 4 has no gaugings. On limb 3 the rating reads high.") +
#'   theme_minimal() +
#'   theme(legend.position = "bottom")
#'
#' @export
compare_gaugings_to_rating <- function(rating, gaugings, stage_col = "stage_m",
                                        discharge_col = "discharge_cms", tol_rel = 0.10) {
  if (S7_inherits(rating, FlodeRating)) rating <- as_rating_table(rating)
  if (is.data.frame(rating)) {
    rating <- copy(as.data.table(rating))
    if ("lower_level" %in% names(rating)) setorder(rating, lower_level)
    rating <- FlodeRatingTable(table = rating)
  }
  if (!S7_inherits(rating, FlodeRatingTable)) {
    stop("compare_gaugings_to_rating(): rating must be a FlodeRating, FlodeRatingTable, or data.frame/data.table")
  }
  if (!is.data.frame(gaugings)) {
    stop("compare_gaugings_to_rating(): gaugings must be a data.frame or data.table")
  }
  for (col in c(stage_col, discharge_col)) {
    if (!col %in% names(gaugings)) {
      stop(sprintf("compare_gaugings_to_rating(): '%s' is not a column of gaugings (columns are: %s)",
                   col, paste(names(gaugings), collapse = ", ")))
    }
    if (!is.numeric(gaugings[[col]])) {
      stop(sprintf(
        "compare_gaugings_to_rating(): column '%s' must be numeric but is %s; convert it first, for example with as.numeric() after turning placeholder text into NA",
        col, class(gaugings[[col]])[1]
      ))
    }
  }
  if (!is.numeric(tol_rel) || length(tol_rel) != 1L || is.na(tol_rel) || tol_rel <= 0) {
    stop("compare_gaugings_to_rating(): tol_rel must be a single positive number")
  }

  added <- c("limb", "extrapolated", "discharge_predicted_cms", "residual_cms", "residual_pct", "within_tol")
  clash <- intersect(added, names(gaugings))
  if (length(clash)) {
    stop("compare_gaugings_to_rating(): gaugings already has column(s) this function adds: ",
         paste(clash, collapse = ", "), ". Rename them first.")
  }

  rating_dt <- copy(rating@table)
  setorder(rating_dt, lower_level)
  rating_sorted <- FlodeRatingTable(table = rating_dt)
  n_limbs <- nrow(rating_dt)

  out_dt <- copy(as.data.table(gaugings))
  stage_vals <- out_dt[[stage_col]]
  observed <- out_dt[[discharge_col]]

  applied <- logger::with_log_threshold(
    apply_rating(rating_sorted, data.table(.stage = stage_vals), stage_col = ".stage"),
    threshold = logger::WARN
  )
  predicted <- applied$discharge
  extrapolated <- applied$extrapolated

  breaks <- c(rating_dt$lower_level[1], rating_dt$upper_level)
  limb <- pmin(pmax(findInterval(stage_vals, breaks, rightmost.closed = TRUE), 1L), n_limbs)

  residual_cms <- observed - predicted
  residual_pct <- fifelse(!is.na(predicted) & predicted > 0, 100 * residual_cms / predicted, NA_real_)
  # The small relative allowance stops floating-point noise from putting a
  # gauging exactly on the tolerance (10.000000000000009 per cent) outside it.
  within_tol <- abs(residual_pct) <= 100 * tol_rel * (1 + 1e-9)

  set(out_dt, j = "limb", value = limb)
  set(out_dt, j = "extrapolated", value = extrapolated)
  set(out_dt, j = "discharge_predicted_cms", value = predicted)
  set(out_dt, j = "residual_cms", value = residual_cms)
  set(out_dt, j = "residual_pct", value = residual_pct)
  set(out_dt, j = "within_tol", value = within_tol)

  mean_or_na <- function(x) if (all(is.na(x))) NA_real_ else mean(x, na.rm = TRUE)
  median_or_na <- function(x) if (all(is.na(x))) NA_real_ else stats::median(x, na.rm = TRUE)
  iqr_or_na <- function(x) if (all(is.na(x))) NA_real_ else stats::IQR(x, na.rm = TRUE)

  rows <- data.table(
    limb = limb, extrapolated = extrapolated, stage = stage_vals,
    residual_pct = residual_pct, within_tol = within_tol
  )
  inside <- rows[!is.na(limb) & extrapolated %in% FALSE]
  outside <- rows[!is.na(limb) & extrapolated %in% TRUE]

  limbs_dt <- data.table(
    limb = seq_len(n_limbs), lower_level = rating_dt$lower_level, upper_level = rating_dt$upper_level,
    n_gaugings = 0L, n_extrapolated = 0L,
    gauged_min_stage = NA_real_, gauged_max_stage = NA_real_,
    median_residual_pct = NA_real_, spread_pct = NA_real_, share_within_tol = NA_real_
  )
  for (i in seq_len(n_limbs)) {
    on_limb <- inside[inside$limb == i]
    set(limbs_dt, i, "n_gaugings", nrow(on_limb))
    set(limbs_dt, i, "n_extrapolated", sum(outside$limb == i))
    if (nrow(on_limb) > 0L) {
      set(limbs_dt, i, "gauged_min_stage", min(on_limb$stage))
      set(limbs_dt, i, "gauged_max_stage", max(on_limb$stage))
      set(limbs_dt, i, "median_residual_pct", median_or_na(on_limb$residual_pct))
      set(limbs_dt, i, "spread_pct", iqr_or_na(on_limb$residual_pct))
      set(limbs_dt, i, "share_within_tol", mean_or_na(as.numeric(on_limb$within_tol)))
    }
  }
  set(limbs_dt, j = "has_gaugings", value = limbs_dt$n_gaugings > 0L)

  list(gaugings = out_dt[], limbs = limbs_dt[])
}
