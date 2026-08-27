# ============================================================ #
# Tool:         demo_cross_section_rating
# Description:  Demonstration plot pairing a river cross-section (with
#               stage levels) against its Manning-style power-law rating
#               curve, for a synthetic example channel
# Author:       Jonathan Payne
# Created:      2025-06-01
# Modified:     2026-08-18 - JP: restyled to R Tool Governance v1.3.
#               Replaced dplyr/tibble/native pipe with data.table.
#               Replaced patchwork (no fastverse equivalent) with
#               gridExtra::grid.arrange for the combined figure.
# Modified:     2026-08-18 - JP: water polygons were built from the raw,
#               sparsely-sampled bed profile, so a band's edge landed on
#               whichever sample happened to sit under the level rather
#               than where the bed actually crossed it -- visibly
#               undershooting the wet extent. Fixed by densifying the bed
#               profile with linear interpolation before building bands.
#               Also replaced the three overlapping, alpha-blended water
#               polygons with non-overlapping solid-colour bands (no more
#               alpha stacking to interpret), and moved the level labels
#               off the crowded left edge to the right side of the panel.
# Modified:     2026-08-19 - JP: approx() (used to densify the bed
#               profile, see above) is a stats function, not base --
#               unresolvable inside this module's namespace. Added.
# Modified:     2026-08-19 - JP: added .datatable.aware <- TRUE. This is
#               the file that actually surfaced "name '.datatable.aware'
#               not found in 'env'" when box::use()'d from walkthrough.R
#               (see rate_optimise.R's changelog for the full
#               explanation) -- fixed here and, defensively, in every
#               other module that uses data.table's := as heavily.
# Modified:     2026-08-25 - JP: converted from a box module -- a plain
#               script whose top-level objects (cross_section_dt,
#               rating_curve_dt, p_xs, p_rc, combined) became importable
#               bindings when box::use()'d -- into a package function,
#               demo_cross_section_rating(). A package's R/ files are
#               parsed and byte-compiled once at build/load time, not
#               re-run per call, so top-level executable code that builds
#               a specific figure has to live inside a function to be
#               (re)runnable on demand; wrapping it also lets a caller
#               (or a test) get the intermediate objects back directly
#               instead of sourcing the file into an environment.
# Modified:     2026-08-27 - JP: this function stays a fixed synthetic
#               illustration on purpose. For the same cross-section/
#               rating pairing built from a real fit and a real survey,
#               see plot_rating_cross_section() (R/plot_rating_cross_section.R).
# Tier:         3
# Inputs:       None -- self-contained synthetic example.
# Outputs:      A combined two-panel plot (cross-section over rating
#               curve), printed as a side effect when plot = TRUE, and
#               returned (with its components) invisibly.
# Dependencies: data.table, ggplot2, gridExtra, grid, scales, stats
# ============================================================ #

# Build a single non-overlapping band polygon between two water levels:
# bottom = the bed itself where it's above low_level (nothing to fill
# there yet in this band), or low_level where the bed is already below
# it (fully wet up to the band top); top = high_level throughout. The
# band simply has zero width wherever the bed is at or above high_level.
# Because bands never overlap, they can be drawn as flat, fully opaque
# colours -- no alpha stacking, no ambiguity about which layer is on top.
#' @keywords internal
#' @noRd
.make_band_poly <- function(low_level, high_level, cross_section_dense_dt) {
  band_dt <- cross_section_dense_dt[elevation_maod < high_level]
  if (nrow(band_dt) == 0L) {
    return(data.table(distance_m = numeric(0), elevation_maod = numeric(0)))
  }
  bottom_dt <- data.table(
    distance_m = band_dt$distance_m,
    elevation_maod = pmax(band_dt$elevation_maod, low_level)
  )
  top_dt <- data.table(
    distance_m = rev(band_dt$distance_m),
    elevation_maod = high_level
  )
  rbindlist(list(bottom_dt, top_dt))
}

#' Demonstrate a river cross-section against its rating curve
#'
#' @description
#' A self-contained, synthetic worked example pairing a river
#' cross-section (with annotated stage levels: low flow, bankfull,
#' flood) against its Manning-style power-law rating curve
#' \eqn{Q = a(H - H_0)^b}, drawn side by side so the shape of the
#' channel and the shape of the rating are directly comparable. Not a
#' fitting tool -- it builds a synthetic bed profile and rating curve
#' from fixed constants, for illustration.
#'
#' @param plot Logical. Print the combined two-panel figure as a side
#'   effect. Default `TRUE`.
#'
#' @return Invisibly, a list with elements `cross_section` (the bed
#'   profile data.table), `rating_curve` (the stage-discharge
#'   data.table), `gauged` (the synthetic gauged points),
#'   `p_xs`/`p_rc` (the two individual `ggplot` objects), and `combined`
#'   (the combined grob from `gridExtra::grid.arrange()`).
#'
#' @seealso [plot_rating_cross_section()] for the same pairing built from
#'   a real fit and a real surveyed cross-section, on one shared axis,
#'   rather than this function's fixed synthetic illustration.
#'
#' @examples
#' result <- demo_cross_section_rating(plot = FALSE)
#' result$cross_section
#' result$rating_curve
#'
#' @export
demo_cross_section_rating <- function(plot = TRUE) {
  # ---------------------------------------------------------------- #
  # 1. Cross-section geometry
  # ---------------------------------------------------------------- #

  # Simulate a natural channel bed (distance, elevation)
  cross_section_dt <- data.table(
    distance_m = c(0, 2, 5, 8, 10, 12, 15, 18, 22, 26, 30, 34, 38, 40, 42, 45),
    elevation_maod = c(
      12.0, 11.8, 10.5, 9.2, 8.6, 8.3, 8.0, 8.1, 8.4, 9.0,
      9.8, 10.6, 11.5, 11.9, 12.1, 12.3
    )
  )

  # Bank-full / water surface levels to annotate. Colours are distinct and
  # solid (no shared hue family relying on alpha to separate them), since
  # the bands below no longer overlap and so no longer need transparency
  # to stay legible.
  water_levels_dt <- data.table(
    label = c("Low flow", "Bankfull", "Flood"),
    elevation_maod = c(8.8, 10.2, 11.4),
    colour = c("#0288d1", "#01579b", "#7b1fa2")
  )

  channel_bottom_maod <- min(cross_section_dt$elevation_maod)

  # The raw bed is only sampled every 2-4 m. Using those raw points directly
  # to decide "is this x wet at this level" means a band's edge lands on
  # whichever sample happens to sit under the line, not on where the bed
  # actually crosses it -- undershooting the true wet extent by up to one
  # sample spacing (visibly, several metres, on the Flood/Bankfull bands).
  # Densifying first with linear interpolation fixes this: the interpolated
  # curve is geometrically identical to what geom_line() already draws
  # between the raw points, just with enough vertices that a level crossing
  # falls almost exactly where the bed profile actually crosses it.
  dense_x <- seq(min(cross_section_dt$distance_m), max(cross_section_dt$distance_m), by = 0.02)
  dense_y <- approx(cross_section_dt$distance_m, cross_section_dt$elevation_maod, xout = dense_x)$y
  cross_section_dense_dt <- data.table(distance_m = dense_x, elevation_maod = dense_y)

  water_bands_dt <- rbindlist(list(
    { # Low flow: bed up to the low-flow level
      poly_dt <- .make_band_poly(channel_bottom_maod, water_levels_dt$elevation_maod[1], cross_section_dense_dt)
      poly_dt[, band := water_levels_dt$label[1]]
    },
    { # Bankfull increment: low-flow level up to bankfull level
      poly_dt <- .make_band_poly(water_levels_dt$elevation_maod[1], water_levels_dt$elevation_maod[2], cross_section_dense_dt)
      poly_dt[, band := water_levels_dt$label[2]]
    },
    { # Flood increment: bankfull level up to flood level
      poly_dt <- .make_band_poly(water_levels_dt$elevation_maod[2], water_levels_dt$elevation_maod[3], cross_section_dense_dt)
      poly_dt[, band := water_levels_dt$label[3]]
    }
  ))

  # ---------------------------------------------------------------- #
  # 2. Rating curve (Stage-Discharge)
  # ---------------------------------------------------------------- #

  # Manning-style power law: Q = a * (H - H0)^b
  H0_maod <- channel_bottom_maod # zero-flow datum
  a_coef <- 12 # scale coefficient
  b_exp <- 1.65 # exponent

  rating_curve_dt <- data.table(stage_maod = seq(H0_maod + 0.05, 11.8, by = 0.05))
  rating_curve_dt[, discharge_cms := a_coef * (stage_maod - H0_maod)^b_exp]
  rating_curve_dt[, above_bankfull := stage_maod >= water_levels_dt$elevation_maod[2]]

  gauged_dt <- data.table(
    discharge_cms = c(1.5, 5, 14, 35, 80, 150, 260)
  )
  gauged_dt[, stage_maod := H0_maod + (discharge_cms / a_coef)^(1 / b_exp)]

  # ---------------------------------------------------------------- #
  # 3. Plot A - Cross section
  # ---------------------------------------------------------------- #

  p_xs <- ggplot() +
    geom_ribbon(
      data = cross_section_dt,
      aes(x = distance_m, ymin = 6.5, ymax = elevation_maod),
      fill = "#8d6e63", colour = NA
    ) +
    # Non-overlapping water bands, drawn as flat opaque colours -- each
    # metre of the panel belongs to exactly one band, so there's no alpha
    # stacking and no ambiguity about which colour is "underneath".
    geom_polygon(
      data = water_bands_dt,
      aes(distance_m, elevation_maod, fill = band),
      colour = NA
    ) +
    scale_fill_manual(
      values = setNames(water_levels_dt$colour, water_levels_dt$label),
      breaks = water_levels_dt$label,
      guide = "none"
    ) +
    geom_line(
      data = cross_section_dt,
      aes(distance_m, elevation_maod),
      colour = "#4e342e", linewidth = 1.2
    ) +
    geom_hline(
      data = water_levels_dt,
      aes(yintercept = elevation_maod, colour = label),
      linetype = "dashed", linewidth = 0.5, alpha = 0.9
    ) +
    # Labels sit at the right edge, away from the bed's left-bank rise and
    # away from the water fill, so the white label background always reads
    # clearly against open sky or the right bank rather than competing with
    # a colour block.
    geom_label(
      data = water_levels_dt,
      aes(x = max(cross_section_dt$distance_m) - 1, y = elevation_maod, label = label, colour = label),
      hjust = 1, vjust = -0.4, size = 3.5, fontface = "bold",
      label.size = 0.4, fill = "white", alpha = 0.95
    ) +
    scale_colour_manual(
      values = setNames(water_levels_dt$colour, water_levels_dt$label),
      guide = "none"
    ) +
    scale_y_continuous(limits = c(6.5, 12.8), expand = c(0, 0)) +
    scale_x_continuous(expand = c(0, 0)) +
    labs(
      title = "River Cross-Section with Stage Levels",
      x = "Distance across channel (m)",
      y = "Elevation (m AOD)"
    ) +
    theme_minimal(base_size = 12) +
    theme(
      plot.title = element_text(face = "bold", size = 13),
      panel.grid.minor = element_blank(),
      panel.border = element_rect(colour = "grey80", fill = NA)
    )

  # ---------------------------------------------------------------- #
  # 4. Plot B - Rating curve
  # ---------------------------------------------------------------- #

  p_rc <- ggplot(rating_curve_dt, aes(x = discharge_cms, y = stage_maod)) +
    annotate("rect",
      xmin = -Inf, xmax = Inf,
      ymin = water_levels_dt$elevation_maod[2],
      ymax = Inf,
      fill = "#01579b", alpha = 0.08
    ) +
    geom_hline(
      yintercept = water_levels_dt$elevation_maod[2],
      colour = "#0288d1", linetype = "dashed", linewidth = 0.7
    ) +
    annotate("text",
      x = max(rating_curve_dt$discharge_cms) * 0.95,
      y = water_levels_dt$elevation_maod[2] + 0.12,
      label = "Bankfull", colour = "#0288d1",
      hjust = 1, size = 3
    ) +
    geom_line(
      data = rating_curve_dt[above_bankfull == FALSE],
      colour = "#0288d1", linewidth = 1.4
    ) +
    geom_line(
      data = rating_curve_dt[above_bankfull == TRUE],
      colour = "#01579b", linewidth = 1.4, linetype = "solid"
    ) +
    geom_point(
      data = gauged_dt,
      aes(discharge_cms, stage_maod),
      colour = "#e65100", size = 2.5, shape = 21,
      fill = "#ff8a65", stroke = 1
    ) +
    annotate("text",
      x = 30, y = 8.45, label = "Gauged observations",
      colour = "#e65100", size = 3, hjust = 0
    ) +
    scale_x_continuous(
      labels = comma_format(suffix = " m\u00b3/s"),
      expand = expansion(mult = c(0, 0.05))
    ) +
    scale_y_continuous(
      limits = c(channel_bottom_maod, 11.8),
      expand = expansion(mult = c(0, 0.05))
    ) +
    labs(
      title = "Rating Curve (Stage-Discharge)",
      x = "Discharge (m\u00b3/s)",
      y = "Stage / Water surface elevation (m AOD)"
    ) +
    theme_minimal(base_size = 12) +
    theme(
      plot.title = element_text(face = "bold", size = 13),
      panel.grid.minor = element_blank(),
      panel.border = element_rect(colour = "grey80", fill = NA)
    )

  # ---------------------------------------------------------------- #
  # 5. Combine
  # ---------------------------------------------------------------- #

  # arrangeGrob() builds the combined gtable without drawing it -- unlike
  # grid.arrange(), which always draws as a side effect of being called.
  # That side effect is exactly what plot = FALSE needs to suppress.
  combined <- arrangeGrob(
    p_xs, p_rc,
    ncol = 1,
    top = textGrob(
      "Hydrometric Station \u2014 Cross-Section & Rating Curve",
      gp = gpar(fontface = "bold", fontsize = 15)
    ),
    bottom = textGrob(
      "Synthetic example | Manning-derived power-law rating | Q = 12\u00b7(H \u2212 H\u2080)^1.65",
      gp = gpar(fontsize = 9, col = "grey50")
    )
  )

  if (isTRUE(plot)) {
    grid::grid.newpage()
    grid::grid.draw(combined)
  }

  invisible(list(
    cross_section = cross_section_dt,
    rating_curve = rating_curve_dt,
    gauged = gauged_dt,
    p_xs = p_xs,
    p_rc = p_rc,
    combined = combined
  ))
}
