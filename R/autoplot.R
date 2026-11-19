# ============================================================ #
# Tool:         autoplot
# Description:  One plot grammar for every rating (tranche B7). autoplot()
#               and plot() on a FlodeRating, FlodeSegmentedRating or
#               FlodeRatingTable return a ggplot2 object: gaugings shaped by
#               source type with excluded ones muted, the curve, a
#               bootstrap band where there is one, the stage ranges the
#               rating does and does not rest on shaded, units on the axes
#               and the rating's status in the caption. autoplot() is also
#               defined for assessments and sensitivity analyses.
# Author:       Jonathan Payne
# Created:      2026-11-18
# Tier:         3
# Inputs:       A rating.
# Outputs:      A ggplot object.
# Dependencies: ggplot2, data.table
# ============================================================ #

#' @include flode_classes.R support.R invariants.R
NULL

#' @importFrom ggplot2 autoplot
#' @export
ggplot2::autoplot

# Colour-blind safe (Okabe and Ito) and distinguishable without colour: the
# evidence is told apart by shape, the status by line type and label.
.plot_colours <- c(used = "#0072B2", excluded = "#8C8C8C", curve = "#D55E00", modelled = "#009E73")
.source_shapes <- c(gauging = 16, operational_rating = 17, modelled = 15, cross_section = 18,
                    structure_equation = 3, other = 4)

# The curve at `n_points` stages per limb, evaluated directly so that a
# rating that fails its invariants can still be drawn: seeing it is how you
# find out why.
.autoplot_curve <- function(x, n_points) {
  if (S7_inherits(x, FlodeSegmentedRating)) {
    s <- x@gaugings$stage_m
    lo <- min(c(x@coefficients$bp1, s)); hi <- max(s)
    h <- seq(lo, hi, length.out = n_points)
    return(data.table(limb = 1L, stage = h, discharge = .segmented_predict_cms(as.list(x@coefficients), as.integer(x@n_segments), h)))
  }
  tbl <- .invariant_table(x)
  rbindlist(lapply(seq_len(nrow(tbl)), function(i) {
    h <- seq(tbl$lower_level[i], tbl$upper_level[i], length.out = n_points)
    data.table(limb = i, stage = h, discharge = .eval_limb(tbl$C[i], tbl$a[i], tbl$n[i], h))
  }))
}

# The 95% band from the successful bootstrap draws, per limb, or NULL.
.autoplot_band <- function(x, n_points) {
  if (!S7_inherits(x, FlodeRating) || is.null(x@bootstrap) || !nrow(x@bootstrap)) return(NULL)
  draws <- x@bootstrap[success == TRUE]
  if (!nrow(draws)) return(NULL)
  bounds <- x@limbs
  out <- lapply(seq_len(nrow(bounds)), function(i) {
    d <- draws[limb == bounds$limb[i]]
    if (nrow(d) < 2L) return(NULL)
    h <- seq(bounds$lower_stage_m[i], bounds$upper_stage_m[i], length.out = n_points)
    q <- vapply(h, function(s) ifelse(s <= d$a, 0, d$C * (s - d$a)^d$n), numeric(nrow(d)))
    q <- matrix(q, nrow = nrow(d))
    data.table(stage = h, lower = apply(q, 2L, stats::quantile, probs = 0.025, names = FALSE),
               upper = apply(q, 2L, stats::quantile, probs = 0.975, names = FALSE))
  })
  out <- rbindlist(out)
  if (nrow(out)) out else NULL
}

# What the rating is, in a line: how it was made, where it stands, and
# whether it converged and is valid.
.plot_caption <- function(x) {
  state <- .state_lines(x)
  grab <- function(key) sub(paste0("^\\s*", key, ": "), "", state[grepl(paste0("^\\s*", key, ":"), state)][1L])
  sprintf("origin: %s | lifecycle: %s | converged: %s | valid: %s",
          x@fit_origin, x@lifecycle, grab("converged"), grab("valid"))
}

# Draw a rating with ggplot2.
.plot_rating <- function(x, n_points = 200L, band = TRUE, support = TRUE) {
  if (!is.numeric(n_points) || length(n_points) != 1L || n_points < 2) {
    stop("n_points must be a single number of at least 2", call. = FALSE)
  }
  n_points <- as.integer(n_points)
  curve <- .autoplot_curve(x, n_points)
  has_ev <- !S7_inherits(x, FlodeRatingTable)
  ev <- if (has_ev) as.data.table(x@gaugings)[is.finite(stage_m) & is.finite(discharge_cms)] else NULL
  # Rows a guided fit left out are not in @gaugings, but their values are kept
  # with the reason; they are drawn muted, not hidden.
  left_out <- if (has_ev) x@provenance$fit_rating$excluded else NULL
  if (!is.null(left_out) && nrow(left_out) && all(c("stage_m", "discharge_cms") %in% names(left_out))) {
    extra <- left_out[is.finite(stage_m) & is.finite(discharge_cms)]
    if (nrow(extra)) {
      ev <- rbind(ev[, .(stage_m, discharge_cms, source_type, included)],
                  extra[, .(stage_m, discharge_cms, source_type, included = FALSE)], fill = TRUE)
    }
  }
  rng <- .support_ranges(x)
  get <- function(name) c(rng$lower_stage_m[rng$range == name], rng$upper_stage_m[rng$range == name])

  y_all <- c(curve$stage, if (!is.null(ev)) ev$stage_m)
  y_lo <- min(y_all); y_hi <- max(y_all)
  p <- ggplot()

  if (support) {
    shade <- list()
    obs <- get("observed"); mod <- get("modelled"); fit <- get("fitted")
    if (!anyNA(mod)) {
      shade[[length(shade) + 1L]] <- data.table(kind = "Modelled evidence", ymin = mod[1L], ymax = mod[2L])
    }
    lows <- c(obs[1L], mod[1L]); highs <- c(obs[2L], mod[2L])
    has_evidence <- any(is.finite(lows))
    ev_lo <- if (has_evidence) min(lows[is.finite(lows)]) else NA_real_
    ev_hi <- if (has_evidence) max(highs[is.finite(highs)]) else NA_real_
    if (has_evidence && !anyNA(fit)) {
      if (fit[1L] < ev_lo - 1e-9) shade[[length(shade) + 1L]] <- data.table(kind = "Fitted, no evidence", ymin = fit[1L], ymax = ev_lo)
      if (fit[2L] > ev_hi + 1e-9) shade[[length(shade) + 1L]] <- data.table(kind = "Fitted, no evidence", ymin = ev_hi, ymax = fit[2L])
    }
    if (length(shade)) {
      shade <- rbindlist(shade)
      p <- p + geom_rect(data = shade, aes(xmin = -Inf, xmax = Inf, ymin = ymin, ymax = ymax, fill = kind), alpha = 0.18, inherit.aes = FALSE) +
        scale_fill_manual(name = "Support", values = c(`Modelled evidence` = .plot_colours[["modelled"]], `Fitted, no evidence` = "#7F7F7F"))
    }
    op <- get("operational")
    if (!anyNA(op)) {
      p <- p + geom_hline(yintercept = op, linetype = "longdash", colour = "#444444", linewidth = 0.4) +
        annotate("text", x = -Inf, y = op[2L], label = "operational limit", hjust = -0.05, vjust = -0.5, size = 3, colour = "#444444") +
        annotate("text", x = -Inf, y = op[1L], label = "operational limit", hjust = -0.05, vjust = 1.4, size = 3, colour = "#444444")
    }
  }

  bd <- if (band) .autoplot_band(x, n_points) else NULL
  if (!is.null(bd)) {
    p <- p + geom_ribbon(data = bd, aes(y = stage, xmin = lower, xmax = upper), orientation = "y",
                         fill = .plot_colours[["curve"]], alpha = 0.22, inherit.aes = FALSE)
  }

  # Interior breakpoints, drawn faintly, so the limbs can be seen.
  breaks <- if (S7_inherits(x, FlodeRating)) sort(x@limbs$upper_stage_m)[-nrow(x@limbs)] else numeric(0)
  if (length(breaks)) p <- p + geom_hline(yintercept = breaks, linetype = "dotted", colour = "#999999", linewidth = 0.3)

  p <- p + geom_line(data = curve, aes(x = discharge, y = stage, group = limb), colour = .plot_colours[["curve"]], linewidth = 0.9)

  if (!is.null(ev) && nrow(ev)) {
    types <- intersect(names(.source_shapes), unique(ev$source_type))
    ev[, source_type := factor(source_type, levels = names(.source_shapes))]
    ev[, use := factor(ifelse(is.na(included) | included, "used in the fit", "excluded"), levels = c("used in the fit", "excluded"))]
    p <- p + geom_point(data = ev, aes(x = discharge_cms, y = stage_m, shape = source_type, colour = use,
                                      alpha = use, size = use), stroke = 0.9) +
      scale_shape_manual(name = "Evidence", values = .source_shapes, breaks = types, drop = TRUE) +
      scale_colour_manual(name = NULL, values = c(`used in the fit` = .plot_colours[["used"]], excluded = .plot_colours[["excluded"]]), drop = TRUE) +
      scale_alpha_manual(values = c(`used in the fit` = 0.95, excluded = 0.55), guide = "none") +
      scale_size_manual(values = c(`used in the fit` = 2.2, excluded = 1.8), guide = "none")
  }

  n_limbs <- if (S7_inherits(x, FlodeRating)) nrow(x@limbs) else if (S7_inherits(x, FlodeRatingTable)) nrow(x@table) else as.integer(x@n_segments)
  obj <- if (has_ev && !is.null(x@provenance$objective)) sprintf("%s objective", x@provenance$objective) else NULL
  p + labs(
    x = expression("Discharge (m"^3 * "/s)"), y = "Stage (m)",
    title = "Rating curve",
    subtitle = paste(c(sprintf("%d %s", n_limbs, if (n_limbs == 1L) "limb" else if (S7_inherits(x, FlodeSegmentedRating)) "segments" else "limbs"), obj,
                       if (!is.null(bd)) "95% bootstrap band"), collapse = "; "),
    caption = .plot_caption(x)
  ) +
    theme_minimal(base_size = 11) +
    theme(legend.position = "right", plot.caption = element_text(hjust = 0, colour = "#444444"))
}

#' Plot a rating with ggplot2
#'
#' @description
#' `autoplot()` and `plot()` draw a rating with one grammar for every rating
#' class and return a ggplot2 object, so the plot can be added to, themed or
#' saved like any other. They give the same plot; `autoplot()` is the
#' ggplot2 convention and `plot()` is what you reach for first. `autoplot()` is
#' re-exported, so it works without attaching ggplot2.
#'
#' What is on the plot:
#'
#' * the **gaugings**, shaped by `source_type` (a circle for a gauging, other
#'   shapes for modelled, cross-section, structure and operational-rating
#'   evidence) so evidence that is not a measurement cannot be mistaken for
#'   one; rows excluded from the fit are drawn grey, smaller and fainter,
#'   never hidden;
#' * the **curve**, with the interior breakpoints marked faintly;
#' * a **95% band** from the bootstrap draws, if the fit made them (the
#'   caption and subtitle say so; there is no band to draw otherwise);
#' * the **stage ranges the rating rests on**: a green tint over the range of
#'   modelled evidence and a grey one where the curve is fitted but no
#'   evidence lies (see [rating_support()]), and the operational limits as
#'   dashed lines if stated;
#' * **units on the axes**, with discharge on the horizontal axis and stage on
#'   the vertical, the hydrological convention;
#' * the rating's **status in the caption**: how it was made, where it stands
#'   in review, whether it converged and whether it is valid (see
#'   [rating_invariants()]).
#'
#' The curve is evaluated directly, so a rating that fails its invariants can
#' still be drawn, which is how you find out why.
#'
#' An equation table has no evidence, so only the curve and the status are
#' drawn. `autoplot()` also works on a [FlodeAssessment] and a
#' [FlodeSensitivity].
#'
#' @param object,x A [FlodeRating], [FlodeSegmentedRating] or
#'   [FlodeRatingTable] (or, for `autoplot()`, a [FlodeAssessment] or
#'   [FlodeSensitivity]).
#' @param n_points Number of stages per limb at which the curve is drawn.
#'   Default 200.
#' @param band Logical. Draw the bootstrap band if the fit has one. Default
#'   `TRUE`.
#' @param support Logical. Shade the stage ranges the rating does and does not
#'   rest on, and draw operational limits. Default `TRUE`.
#' @param y Unused, present for the `plot()` generic.
#' @param ... Unused.
#'
#' @return A ggplot object.
#'
#' @details
#' `rating_plot()` is superseded by this plot. It still works, but draws with
#' base graphics, offers none of the above, and will warn in a later release.
#'
#' @seealso [rating_support()], [rating_invariants()], [plot_rating_curves()]
#'   to compare several ratings, [plot_rating_residuals()]
#'
#' @name autoplot.FlodeRating
#' @aliases plot.FlodeRating autoplot.FlodeSegmentedRating autoplot.FlodeRatingTable
#'
#' @examples
#' set.seed(1)
#' stage_m <- seq(0.4, 3, length.out = 24)
#' gaugings <- data.frame(stage_m = stage_m,
#'                        discharge_cms = 3.2 * stage_m^1.6 * exp(rnorm(24, sd = 0.04)))
#' fit <- fit_rating(gaugings, n_boot = 40, seed = 1, quiet = TRUE,
#'                   operational_limits = c(0.3, 3.4), operational_basis = "gauged range plus margin")
#' autoplot(fit)
#'
#' # The same plot from plot(), which can be added to like any ggplot.
#' plot(fit) + ggplot2::labs(title = "Station 10250")
NULL

#' @noRd
method(.s7_autoplot, FlodeRating) <- function(object, n_points = 200L, band = TRUE, support = TRUE, ...) .plot_rating(object, n_points, band, support)
#' @noRd
method(.s7_autoplot, FlodeSegmentedRating) <- function(object, n_points = 200L, band = TRUE, support = TRUE, ...) .plot_rating(object, n_points, band, support)
#' @noRd
method(.s7_autoplot, FlodeRatingTable) <- function(object, n_points = 200L, band = TRUE, support = TRUE, ...) .plot_rating(object, n_points, band, support)

#' @noRd
method(.s7_plot, FlodeRating) <- function(x, y, n_points = 200L, band = TRUE, support = TRUE, ...) .plot_rating(x, n_points, band, support)
#' @noRd
method(.s7_plot, FlodeSegmentedRating) <- function(x, y, n_points = 200L, band = TRUE, support = TRUE, ...) .plot_rating(x, n_points, band, support)
#' @noRd
method(.s7_plot, FlodeRatingTable) <- function(x, y, n_points = 200L, band = TRUE, support = TRUE, ...) .plot_rating(x, n_points, band, support)
