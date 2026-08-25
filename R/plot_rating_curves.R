# ============================================================ #
# Tool:         plot_rating_curves
# Description:  Overlay any number of fitted ratings' curves on one
#               plot, for quick visual comparison -- across model
#               architectures (FlodeRating vs FlodeSegmentedRating),
#               gap-closure methods, successive amendments, or
#               anything else compare_ratings()'s two-rating,
#               table-only comparison is too narrow for.
# Author:       Jonathan Payne
# Created:      2026-08-25
# Tier:         3
# Inputs:       Any number of FlodeRating, FlodeSegmentedRating, or
#               FlodeRatingTable instances, in any mix, passed via ...
# Outputs:      A ggplot object, printed as a side effect.
# Dependencies: data.table, ggplot2, S7
# ============================================================ #

#' @include flode_classes.R
NULL

# Build a (stage, discharge) curve for one fitted rating, dispatching on
# class. Reuses the existing apply_rating()/as_rating_table() generics
# rather than re-deriving the discharge equation per class -- FlodeRating
# has no apply_rating method of its own (it goes through the
# as_rating_table() bridge, same as everywhere else in the toolkit that
# needs to evaluate one), FlodeSegmentedRating and FlodeRatingTable
# dispatch directly.
#' @keywords internal
#' @noRd
.rating_curve_points <- function(fit, n_points) {
  if (S7_inherits(fit, FlodeRating)) {
    bounds_dt <- fit@limbs[, .(lower_stage_m, upper_stage_m)]
    stage_seq <- sort(unique(unlist(lapply(seq_len(nrow(bounds_dt)), function(i) {
      seq(bounds_dt$lower_stage_m[i], bounds_dt$upper_stage_m[i], length.out = n_points)
    }))))
    table <- as_rating_table(fit)
    apply_rating(table, data.table(stage = stage_seq), stage_col = "stage", out_col = "discharge")
  } else if (S7_inherits(fit, FlodeSegmentedRating)) {
    stage_lo <- min(fit@coefficients$bp1, min(fit@gaugings$stage_m))
    stage_hi <- max(fit@gaugings$stage_m)
    stage_seq <- seq(stage_lo, stage_hi, length.out = n_points)
    apply_rating(fit, data.table(stage = stage_seq), stage_col = "stage", out_col = "discharge")
  } else if (S7_inherits(fit, FlodeRatingTable)) {
    bounds_dt <- fit@table[, .(lower_level, upper_level)]
    stage_seq <- sort(unique(unlist(lapply(seq_len(nrow(bounds_dt)), function(i) {
      seq(bounds_dt$lower_level[i], bounds_dt$upper_level[i], length.out = n_points)
    }))))
    apply_rating(fit, data.table(stage = stage_seq), stage_col = "stage", out_col = "discharge")
  } else {
    stop(
      "plot_rating_curves(): every argument must be a FlodeRating, ",
      "FlodeSegmentedRating, or FlodeRatingTable -- got an object of class ",
      paste(class(fit), collapse = "/"), "."
    )
  }
}

#' Overlay multiple fitted ratings' curves for quick comparison
#'
#' @description
#' Plots the curves from any number of fitted ratings on one figure --
#' discharge on the x-axis, stage on the y-axis, matching every other
#' plotting function in this toolkit -- so you can eyeball how they
#' differ without reaching for [compare_ratings()]'s more detailed
#' (but two-rating-only, table-representation-only) diff.
#'
#' Accepts [FlodeRating], [FlodeSegmentedRating], and [FlodeRatingTable]
#' instances in any mix: comparing a segmented fit against an
#' independent-limb fit, or a fitted rating against an imported legacy
#' table, works the same way as comparing two of the same class.
#'
#' @param ... Any number of [FlodeRating], [FlodeSegmentedRating], or
#'   [FlodeRatingTable] instances. Name an argument to use that name as
#'   its legend label (`plot_rating_curves(Before = fit1, After =
#'   fit2)`); unnamed arguments are labelled `"Rating 1"`, `"Rating 2"`,
#'   and so on in the order supplied.
#' @param n_points Integer. Points used to draw each limb/segment of
#'   each curve. Default `200L`.
#'
#' @return A `ggplot` object, invisibly. Printed as a side effect.
#'
#' @seealso [compare_ratings()] and [plot_rating_comparison()] for a
#'   two-rating comparison that also reports the discharge difference
#'   and requires a table representation for both sides.
#'
#' @examples
#' set.seed(1)
#' stage_m <- seq(0.5, 3.5, by = 0.05)
#' discharge_cms <- 5 * stage_m^1.6 + rnorm(length(stage_m), sd = 0.05)
#' fit_plain <- rate_optimise(discharge_cms, stage_m, control = c(1.6, 2.5))
#' fit_constrained <- rate_optimise_constrained(discharge_cms, stage_m, control = c(1.6, 2.5))
#' plot_rating_curves(Independent = fit_plain, Constrained = fit_constrained)
#'
#' @export
plot_rating_curves <- function(..., n_points = 200L) {
  fits <- list(...)
  if (length(fits) == 0) stop("plot_rating_curves(): supply at least one fitted rating.")
  if (!is.numeric(n_points) || length(n_points) != 1L || n_points <= 0) {
    stop("n_points must be a single positive integer")
  }

  supplied_names <- names(fits)
  labels <- vapply(seq_along(fits), function(i) {
    nm <- if (!is.null(supplied_names)) supplied_names[i] else ""
    if (!is.na(nm) && nzchar(nm)) nm else sprintf("Rating %d", i)
  }, character(1))
  if (anyDuplicated(labels)) {
    stop("plot_rating_curves(): labels must be unique -- got duplicate(s): ",
      paste(unique(labels[duplicated(labels)]), collapse = ", "))
  }

  curve_list <- lapply(seq_along(fits), function(i) {
    curve_dt <- .rating_curve_points(fits[[i]], n_points)
    curve_dt[, rating := labels[i]]
    curve_dt[, .(stage, discharge, rating)]
  })
  combined_dt <- rbindlist(curve_list)
  combined_dt[, rating := factor(rating, levels = labels)]

  p <- ggplot(combined_dt, aes(x = discharge, y = stage, colour = rating)) +
    geom_path(linewidth = 1.1) +
    labs(
      title = "Rating Curve Comparison",
      x = "Discharge (m\u00b3/s)", y = "Stage (m)", colour = NULL
    ) +
    theme_minimal(base_size = 12) +
    theme(
      plot.title = element_text(face = "bold", size = 13),
      legend.position = "top"
    )

  print(p)
  invisible(p)
}
