# ============================================================ #
# Tool:         plot_rating_cross_section
# Description:  Overlay a real surveyed channel cross-section on a real
#               fitted rating's own plot -- rescaling the cross-section's
#               distance onto the discharge axis so channel shape and
#               rating shape sit on one figure, with a secondary axis
#               giving the true distance scale back. Complements
#               demo_cross_section_rating() (a fixed, synthetic
#               illustration of the same idea) with a tool that takes a
#               real fit and a real survey.
# Author:       Jonathan Payne
# Created:      2026-08-27
# Tier:         3
# Inputs:       A FlodeRating, FlodeSegmentedRating, or FlodeRatingTable,
#               plus a data.frame/data.table of surveyed
#               distance/elevation points.
# Outputs:      A ggplot object, printed as a side effect.
# Dependencies: data.table, ggplot2, S7
# ============================================================ #

#' @include flode_classes.R plot_rating_curves.R
NULL

#' Overlay a surveyed cross-section on a fitted rating's own plot
#'
#' @description
#' Rescales a surveyed cross-section's distance onto the discharge axis
#' of `fit`'s own rating plot, so the channel's shape and the rating's
#' shape sit on one figure -- the same shape-to-exponent link
#' `vignette("n_bounds_guide")` draws for idealised controls, but for a
#' real survey against a real fit. A secondary axis on top gives the true
#' distance scale back.
#'
#' This is deliberately narrower than `demo_cross_section_rating()`,
#' which builds its own fixed synthetic bed profile and rating purely for
#' illustration and takes no arguments describing a real station. Reach
#' for `demo_cross_section_rating()` to see what such a figure looks
#' like; reach for this function once you have your own fit and your own
#' survey.
#'
#' `elevation_col` must already be expressed on the same vertical datum
#' as the gaugings' stage (`stage_m`) -- this function does not convert a
#' survey's absolute elevation (e.g. metres AOD) onto a gauge's local
#' datum. Do that conversion (typically subtracting the gauge zero)
#' before calling this function.
#'
#' @param fit A [FlodeRating], [FlodeSegmentedRating], or
#'   [FlodeRatingTable] instance -- the same classes [plot_rating_curves()]
#'   accepts.
#' @param cross_section A data.frame/data.table of surveyed
#'   distance/elevation points, at least 2 rows.
#' @param distance_col,elevation_col Character. Column names in
#'   `cross_section` for distance across the channel and bed elevation
#'   (on `stage`'s own datum -- see Description). Default
#'   `"distance_m"`/`"elevation_m"`.
#' @param n_points Integer. Points used to draw the rating curve.
#'   Default `200L`.
#'
#' @return A `ggplot` object, invisibly. Printed as a side effect.
#'
#' @seealso [demo_cross_section_rating()] for a fixed synthetic
#'   illustration of the same cross-section/rating pairing;
#'   [plot_rating_curves()], whose internal curve helper this function
#'   reuses; `vignette("n_bounds_guide")` for what canonical control
#'   shapes look like and the exponent they imply.
#'
#' @examples
#' set.seed(1)
#' stage_m <- seq(0.3, 3, by = 0.05)
#' discharge_cms <- 4 * stage_m^1.6 + rnorm(length(stage_m), sd = 0.05)
#' fit <- rate_optimise(discharge_cms, stage_m)
#'
#' # A simple trapezoidal survey, already on the gauge's own stage datum
#' xs <- data.frame(
#'   distance_m = c(-6, -3, 3, 6),
#'   elevation_m = c(2.4, 0, 0, 2.4)
#' )
#' plot_rating_cross_section(fit, xs)
#'
#' @export
plot_rating_cross_section <- function(fit, cross_section,
                                       distance_col = "distance_m",
                                       elevation_col = "elevation_m",
                                       n_points = 200L) {
  if (!is.data.frame(cross_section)) {
    stop("plot_rating_cross_section(): cross_section must be a data.frame or data.table")
  }
  missing_cols <- setdiff(c(distance_col, elevation_col), names(cross_section))
  if (length(missing_cols)) {
    stop(
      "plot_rating_cross_section(): cross_section is missing column(s): ",
      paste(missing_cols, collapse = ", ")
    )
  }
  if (nrow(cross_section) < 2L) {
    stop("plot_rating_cross_section(): cross_section must have at least 2 rows")
  }

  curve_dt <- .rating_curve_points(fit, n_points)

  gaugings_dt <- if (S7_inherits(fit, FlodeRatingBase)) fit@gaugings else NULL

  xs_dt <- data.table(
    distance_m = cross_section[[distance_col]],
    elevation_m = cross_section[[elevation_col]]
  )
  setorder(xs_dt, distance_m)

  min_dist <- min(xs_dt$distance_m); max_dist <- max(xs_dt$distance_m)
  min_q <- min(curve_dt$discharge); max_q <- max(curve_dt$discharge)
  if (max_dist == min_dist) {
    stop("plot_rating_cross_section(): cross_section distance values are all identical -- cannot rescale")
  }
  to_discharge <- function(distance) (distance - min_dist) / (max_dist - min_dist) * (max_q - min_q) + min_q
  to_distance <- function(discharge) (discharge - min_q) / (max_q - min_q) * (max_dist - min_dist) + min_dist
  xs_dt[, discharge_scaled := to_discharge(distance_m)]

  p <- ggplot() +
    geom_path(
      data = xs_dt, aes(x = discharge_scaled, y = elevation_m, colour = "Cross section"),
      linewidth = 0.9
    ) +
    geom_path(
      data = curve_dt, aes(x = discharge, y = stage, colour = "Rating curve"),
      linewidth = 1.1
    )

  if (!is.null(gaugings_dt) && nrow(gaugings_dt) > 0L) {
    p <- p + geom_point(
      data = gaugings_dt, aes(x = discharge_cms, y = stage_m, colour = "Gaugings"),
      shape = 21, stroke = 1, fill = "white", size = 2.2
    )
  }

  p <- p +
    scale_colour_manual(
      name = NULL,
      values = c("Cross section" = "#8d6e63", "Rating curve" = "#01579b", "Gaugings" = "grey40"),
      breaks = c("Gaugings", "Rating curve", "Cross section")
    ) +
    scale_x_continuous(
      name = "Discharge (m\u00b3/s)",
      sec.axis = sec_axis(trans = to_distance, name = "Distance across channel (m)")
    ) +
    labs(title = "Rating Curve with Cross-Section Overlay", y = "Stage (m)") +
    theme_minimal(base_size = 12) +
    theme(
      plot.title = element_text(face = "bold", size = 13),
      legend.position = "bottom"
    )

  print(p)
  invisible(p)
}
