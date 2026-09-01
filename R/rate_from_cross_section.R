# ============================================================ #
# Tool:         rate_from_cross_section
# Description:  Derive a theoretical stage-discharge rating from a
#               surveyed channel cross-section via Manning's equation --
#               no gaugings required. Generates a dense synthetic
#               (stage, discharge) series from the surveyed geometry and
#               feeds it through rate_optimise()'s own fitting pipeline,
#               so the result is an ordinary FlodeRating carrying the
#               usual C/a/n limbs, diagnostics, and break-detection --
#               distinguished from a gauged fit only by
#               provenance$source.
# Author:       Jonathan Payne
# Created:      2026-09-01
# Tier:         3
# Inputs:       cross_section: data.frame/data.table of surveyed
#               distance/elevation points, on the gauge's own stage
#               datum (same convention plot_rating_cross_section()
#               uses). slope: bed/energy slope (m/m). roughness:
#               Manning's n.
# Outputs:      A FlodeRating instance.
# Dependencies: data.table, minpack.lm, S7, stats
# ============================================================ #

#' @include flode_classes.R rate_optimise.R
NULL

# Wetted area and wetted perimeter of a piecewise-linear cross-section at
# one stage, via trapezoidal integration over each surveyed segment.
# distance_m/elevation_m must already be sorted by distance. A segment
# entirely above `stage` contributes nothing; a segment entirely below
# contributes its full trapezoid; a segment straddling the water surface
# is clipped at the linearly-interpolated crossing point. Perimeter
# excludes the free surface (the top of the water), matching the
# standard hydraulic convention.
.xs_area_perimeter <- function(distance_m, elevation_m, stage) {
  area <- 0
  perimeter <- 0
  for (i in seq_len(length(distance_m) - 1L)) {
    x1 <- distance_m[i]; z1 <- elevation_m[i]
    x2 <- distance_m[i + 1L]; z2 <- elevation_m[i + 1L]
    d1 <- stage - z1
    d2 <- stage - z2
    if (d1 <= 0 && d2 <= 0) next
    if (d1 > 0 && d2 > 0) {
      area <- area + (d1 + d2) / 2 * (x2 - x1)
      perimeter <- perimeter + sqrt((x2 - x1)^2 + (z2 - z1)^2)
    } else {
      frac <- d1 / (d1 - d2)
      xc <- x1 + frac * (x2 - x1)
      if (d1 > 0) {
        area <- area + d1 / 2 * (xc - x1)
        perimeter <- perimeter + sqrt((xc - x1)^2 + d1^2)
      } else {
        area <- area + d2 / 2 * (x2 - xc)
        perimeter <- perimeter + sqrt((x2 - xc)^2 + d2^2)
      }
    }
  }
  c(area = area, perimeter = perimeter)
}

#' Derive a theoretical rating from a surveyed cross-section (Manning's equation)
#'
#' @description
#' Builds a stage-discharge rating from channel geometry alone, with no
#' gaugings: at each of a dense sequence of stages, `cross_section`'s
#' wetted area and wetted perimeter are found by trapezoidal integration
#' of the surveyed points, giving a hydraulic radius, and Manning's
#' equation (`Q = (1/n) * A * R^(2/3) * sqrt(S)`) converts that to a
#' discharge. That synthetic `(stage, discharge)` series is then handed
#' straight to [rate_optimise()], so the returned [FlodeRating] carries
#' the same `C`/`a`/`n` limbs, break detection, and diagnostics as any
#' gauged fit -- the only difference is `fit@provenance$source`, which
#' reads `"cross_section_theoretical"` rather than `"gauged"`, and
#' `fit@gaugings`, which holds the synthetic points the Manning
#' calculation produced rather than real field measurements.
#'
#' This is a standalone diagnostic: a first-cut rating at an ungauged or
#' newly-installed site, or a physically-grounded check on what a
#' surveyed section implies about the shape of the curve -- not (yet) a
#' way to extend an existing gauged rating past its top gauging. Since
#' `cross_section` is exactly the object [plot_rating_cross_section()]
#' also takes, the two compose directly: overlay the returned fit against
#' the very geometry that generated it as a sanity check (see Examples).
#'
#' A single Manning's `n` is applied across the whole wetted section.
#' Real compound channels (a defined low-flow channel plus overbank
#' berms with different roughness) are more accurately handled by the
#' divided-channel method, with a separate `n` per subsection -- not
#' supported here; treat a single-`n` result for a compound section as
#' approximate.
#'
#' `cross_section` must reach at least as high as the highest stage
#' rated: this function does not assume the end points extend as
#' vertical banks above the survey's own top, so a `stage_seq` above
#' `max(elevation_col)` errors rather than silently understating the
#' true wetted perimeter. Supply a wider survey (including bank points)
#' to rate higher stages.
#'
#' @param cross_section A data.frame/data.table of surveyed
#'   distance/elevation points, at least 2 rows, already on `stage`'s own
#'   vertical datum (see Description).
#' @param slope Single positive finite number. Bed/energy slope, m/m.
#' @param roughness Single positive finite number. Manning's `n`.
#' @param distance_col,elevation_col Character. Column names in
#'   `cross_section`, matching [plot_rating_cross_section()]'s own
#'   defaults so the same object works with both functions. Default
#'   `"distance_m"`/`"elevation_m"`.
#' @param stage_seq Numeric vector of stages to evaluate, or `NULL`
#'   (default) for an evenly-spaced sequence of `n_points` stages from
#'   just above the cross-section's lowest surveyed elevation to its
#'   highest.
#' @param n_points Integer. Number of stages in the default `stage_seq`.
#'   Ignored if `stage_seq` is supplied. Default `100L`.
#' @param control,n_bounds As in [rate_optimise()], passed straight
#'   through to fit the synthetic series.
#' @param ... Further arguments passed to [rate_optimise()] (e.g.
#'   `multi_start`, `objective`).
#'
#' @return A [FlodeRating] instance, identical in structure to
#'   [rate_optimise()]'s own return value.
#'
#' @seealso [rate_optimise()], which this function calls internally;
#'   [plot_rating_cross_section()] for overlaying the result on
#'   `cross_section`; [graft_rating()] for joining a rating onto another
#'   above its trusted range (a natural next step for a cross-section
#'   rating used to extend a gauged one, not yet wired up here).
#'
#' @examples
#' # A simple trapezoidal survey (same shape plot_rating_cross_section()'s
#' # own example uses): a 6 m flat bed, 1.25:1 side slopes, 2.4 m banks.
#' xs <- data.frame(
#'   distance_m = c(-6, -3, 3, 6),
#'   elevation_m = c(2.4, 0, 0, 2.4)
#' )
#' fit <- rate_from_cross_section(xs, slope = 0.001, roughness = 0.035, n_points = 30)
#' fit@provenance$source
#'
#' # Overlay the fit on the very geometry that generated it.
#' plot_rating_cross_section(fit, xs)
#'
#' @export
rate_from_cross_section <- function(cross_section, slope, roughness,
                                     distance_col = "distance_m",
                                     elevation_col = "elevation_m",
                                     stage_seq = NULL, n_points = 100L,
                                     control = NULL, n_bounds = NULL, ...) {
  if (!is.data.frame(cross_section)) {
    stop("rate_from_cross_section(): cross_section must be a data.frame or data.table")
  }
  missing_cols <- setdiff(c(distance_col, elevation_col), names(cross_section))
  if (length(missing_cols)) {
    stop(
      "rate_from_cross_section(): cross_section is missing column(s): ",
      paste(missing_cols, collapse = ", ")
    )
  }
  if (nrow(cross_section) < 2L) {
    stop("rate_from_cross_section(): cross_section must have at least 2 rows")
  }
  if (!is.numeric(slope) || length(slope) != 1L || !is.finite(slope) || slope <= 0) {
    stop("rate_from_cross_section(): slope must be a single positive finite number")
  }
  if (!is.numeric(roughness) || length(roughness) != 1L || !is.finite(roughness) || roughness <= 0) {
    stop("rate_from_cross_section(): roughness (Manning's n) must be a single positive finite number")
  }

  xs_dt <- data.table(
    distance_m = cross_section[[distance_col]],
    elevation_m = cross_section[[elevation_col]]
  )
  setorder(xs_dt, distance_m)
  if (anyDuplicated(xs_dt$distance_m)) {
    stop("rate_from_cross_section(): cross_section distance values must be unique")
  }

  min_elev <- min(xs_dt$elevation_m)
  max_elev <- max(xs_dt$elevation_m)
  if (max_elev <= min_elev) {
    stop("rate_from_cross_section(): cross_section elevation values are all identical -- no channel shape to rate")
  }

  if (is.null(stage_seq)) {
    if (!is.numeric(n_points) || length(n_points) != 1L || n_points < 2L) {
      stop("rate_from_cross_section(): n_points must be a single integer >= 2")
    }
    stage_seq <- seq(min_elev, max_elev, length.out = n_points + 1L)[-1]
  } else {
    if (!is.numeric(stage_seq) || any(!is.finite(stage_seq))) {
      stop("rate_from_cross_section(): stage_seq must be numeric with no NA/NaN/infinite values")
    }
    if (any(stage_seq <= min_elev)) {
      stop(
        "rate_from_cross_section(): stage_seq must exceed the cross-section's lowest surveyed ",
        "elevation (", signif(min_elev, 4), ") -- no wetted area otherwise"
      )
    }
    if (any(stage_seq > max_elev)) {
      stop(
        "rate_from_cross_section(): stage_seq exceeds the cross-section's highest surveyed ",
        "elevation (", signif(max_elev, 4), "); the survey does not define channel geometry ",
        "above its own top. Supply a wider survey (e.g. bank points) to rate higher stages."
      )
    }
    stage_seq <- sort(unique(stage_seq))
  }

  geom <- vapply(
    stage_seq,
    function(h) .xs_area_perimeter(xs_dt$distance_m, xs_dt$elevation_m, h),
    numeric(2)
  )
  area_vec <- geom["area", ]
  perimeter_vec <- geom["perimeter", ]
  radius_vec <- ifelse(perimeter_vec > 0, area_vec / perimeter_vec, 0)
  discharge_vec <- (1 / roughness) * area_vec * radius_vec^(2 / 3) * sqrt(slope)

  keep <- discharge_vec > 0
  if (sum(keep) < 2L) {
    stop(
      "rate_from_cross_section(): fewer than 2 stages produced positive discharge -- ",
      "widen stage_seq or check slope/roughness"
    )
  }
  stage_seq <- stage_seq[keep]
  discharge_vec <- discharge_vec[keep]

  fit <- rate_optimise(
    discharge_cms = discharge_vec, stage_m = stage_seq,
    control = control, n_bounds = n_bounds, ...
  )

  FlodeRating(
    limbs = fit@limbs,
    gaugings = fit@gaugings,
    bootstrap = fit@bootstrap,
    fit_starts = fit@fit_starts,
    status = fit@status,
    provenance = c(fit@provenance, list(
      source = "cross_section_theoretical",
      slope = slope,
      roughness = roughness,
      cross_section = list(distance_m = xs_dt$distance_m, elevation_m = xs_dt$elevation_m)
    ))
  )
}
