# ============================================================ #
# Tool:         rating_curve_demo
# Description:  Worked example wiring rate_optimise() (fitting) and
#               gap_check (junction gap detection/resolution) together,
#               demonstrating the two modules composing end to end
# Author:       Jonathan Payne
# Created:      2026-08-18
# Modified:     see prior changelog entries in version control for the
#               full history of this file's evolution -- summarised
#               here rather than repeated in full.
# Modified:     2026-08-19 - JP: converted to S7. fitted_rating_to_table()
#               is gone entirely, replaced by method(as_rating_table,
#               FlodeRating) <- ..., registered against the shared
#               generic in flode_classes.R -- it now returns a
#               FlodeRatingTable (with a genuine identity of its own)
#               rather than a plain data.table. bootstrap_to_table() and
#               plot_rating_interval() read fit@limbs/fit@gaugings/
#               fit@bootstrap instead of $-columns and attributes.
#               run_demo() updated to match: as_rating_table(fit)
#               instead of fitted_rating_to_table(fit), and rating_plot
#               imported directly from flode_classes rather than
#               relying on it being re-exported through rate_optimise.R.
# Tier:         1
# Inputs:       None -- self-contained synthetic example
# Outputs:      run_demo() returns a list (fit, gaps, rc_raw, rc_fixed) and
#               draws rating_plot() + plot_rc_gaps() as a side effect.
#               plot_rating_interval() draws a ggplot figure.
# Dependencies: data.table, ggplot2, S7, stats
# Modified:     2026-08-25 - JP: converted from a box module to a package
#               R/ file. Imports are now package-level
#               (R/reach.rate-package.R); everything this file used to
#               box::use() from flode_classes/rate_optimise/gap_check/
#               apply_rating needs no import at all -- same package
#               namespace.
# ============================================================ #

#' @include flode_classes.R
#' @include rate_optimise.R
#' @include gap_check.R
#' @include apply_rating.R
NULL

#' Convert a fitted rating curve to gap_check's equation-table representation (S7 method)
#'
#' @description
#' Registered against the `as_rating_table` generic (`flode_classes.R`)
#' for [FlodeRating]. `rate_optimise()` and `gap_check` parameterise the
#' same rating equation with opposite-signed offsets: `rate_optimise()`
#' fits `Q = C(H + a)^n`; `expand_rating_table()` evaluates
#' `Q = C(h - A)^B`. So `A = -a` and `B = n`. That sign flip is easy to
#' get backwards, which is exactly why it lives in a named, tested
#' method here rather than as an inline flip at the call site.
#'
#' If `fit@limbs` carries a `doubtful` column (see
#' `flag_extrapolated_limbs()`), it is carried through unchanged so it
#' reaches `expand_rating_table()` and `plot_rc_gaps()` automatically.
#'
#' @param fit A [FlodeRating] instance.
#'
#' @return A [FlodeRatingTable] with `@status` `"independently_fitted"`
#'   and `@previous` `NULL`, ready for `expand_rating_table()`.
#'
#' @examples
#' set.seed(1)
#' stage_seq <- seq(0.5, 2.5, by = 0.05)
#' discharge_seq <- 5 * stage_seq^1.6 + rnorm(length(stage_seq), sd = 0.02)
#' fit <- rate_optimise(discharge_seq, stage_seq)
#' as_rating_table(fit)
#'
#' @export
method(as_rating_table, FlodeRating) <- function(fit) {
  limbs_dt <- fit@limbs
  out_dt <- data.table(
    lower_level = limbs_dt$lower_stage_m,
    upper_level = limbs_dt$upper_stage_m,
    C = limbs_dt$C,
    A = -limbs_dt$a,
    B = limbs_dt$n
  )

  if ("doubtful" %in% names(limbs_dt)) {
    out_dt[, doubtful := limbs_dt$doubtful]
  }

  FlodeRatingTable(table = out_dt[])
}

#' Convert a fit's bootstrap draws into apply_rating_interval()'s input
#'
#' @description
#' Bridges `rate_optimise(..., n_boot = )`'s per-draw coefficient samples
#' (`fit@bootstrap`, which records every requested draw including failed
#' or rejected ones) to the shape `apply_rating_interval()` expects: one
#' row per successful (limb, draw), with the same `A = -a`, `B = n` sign
#' flip the `as_rating_table` method applies to the point-estimate
#' coefficients, applied here to every draw. Failed or rejected draws
#' (`success == FALSE`) are dropped -- they have no coefficients to
#' bridge.
#'
#' @param fit A [FlodeRating] instance from `rate_optimise(..., n_boot > 0)`.
#'
#' @return A `data.table` with columns `limb`, `draw`, `lower_level`,
#'   `upper_level`, `C`, `A`, `B` -- one row per successful bootstrap
#'   draw. Errors if no draws succeeded.
#'
#' @seealso `as_rating_table()` (in `flode_classes`)
#'
#' @examples
#' set.seed(1)
#' stage_seq <- seq(0.5, 2.5, by = 0.05)
#' discharge_seq <- 5 * stage_seq^1.6 + rnorm(length(stage_seq), sd = 0.02)
#' fit <- rate_optimise(discharge_seq, stage_seq, n_boot = 50L, boot_seed = 1L)
#' bootstrap_to_table(fit)
#'
#' @export
bootstrap_to_table <- function(fit) {
  if (!S7_inherits(fit, FlodeRating)) {
    stop("fit must be a FlodeRating object from rate_optimise()")
  }

  boot_dt <- fit@bootstrap
  if (is.null(boot_dt)) {
    stop("bootstrap_to_table(): fit has no bootstrap draws attached -- call rate_optimise(..., n_boot = <n>) first")
  }

  boot_ok_dt <- boot_dt[boot_dt$success == TRUE]
  if (nrow(boot_ok_dt) == 0) {
    stop("bootstrap_to_table(): fit has no successful bootstrap draws to bridge -- every draw failed or was rejected.")
  }

  bounds_dt <- fit@limbs[, .(limb, lower_level = lower_stage_m, upper_level = upper_stage_m)]

  out_dt <- merge(boot_ok_dt, bounds_dt, by = "limb")
  out_dt[, `:=`(A = -a, B = n)]
  out_dt[, c("a", "n", "success", "reason") := NULL]
  setorder(out_dt, limb, draw)
  out_dt[]
}

#' Plot a fitted rating curve with a bootstrap prediction interval
#'
#' @description
#' Like `rating_plot()`, but for a fit produced with
#' `rate_optimise(..., n_boot = )`: draws the mean discharge curve with a
#' shaded prediction-interval band (from `apply_rating_interval()`)
#' instead of a single point-estimate line, and overlays the gauged
#' points. This is the plot Hodson et al. (2024)'s Figure 1 shows for
#' their Bayesian fits; the band here is the bootstrap approximation to
#' the same idea, not a Bayesian posterior.
#'
#' @param fit A [FlodeRating] instance from `rate_optimise(..., n_boot > 0)`.
#' @param conf_level Numeric in (0, 1). Width of the shaded interval.
#'   Default `0.95`.
#' @param n_points Integer. Stage points per limb used to draw the band.
#'   Default `150L`.
#'
#' @return A `ggplot` object, invisibly. Printed as a side effect.
#'
#' @seealso [rate_optimise()], [bootstrap_to_table()],
#'   `apply_rating_interval()` (in the `apply_rating` module)
#'
#' @examples
#' set.seed(1)
#' stage_m <- seq(0.5, 3.5, by = 0.1)
#' discharge_cms <- 5 * stage_m^1.6 + rnorm(length(stage_m), sd = 0.05)
#' fit <- rate_optimise(discharge_cms, stage_m, n_boot = 200L, boot_seed = 1L)
#' plot_rating_interval(fit)
#'
#' @export
plot_rating_interval <- function(fit, conf_level = 0.95, n_points = 150L) {
  if (!S7_inherits(fit, FlodeRating)) {
    stop("fit must be a FlodeRating object from rate_optimise()")
  }
  if (is.null(fit@bootstrap)) {
    stop("plot_rating_interval(): fit has no bootstrap draws attached -- call rate_optimise(..., n_boot = <n>) first")
  }

  gaugings_dt <- fit@gaugings
  limbs_dt <- fit@limbs
  rating_boot_dt <- bootstrap_to_table(fit)

  # A dense stage sequence spanning every limb, so the ribbon and mean
  # line are drawn continuously across the whole fitted range.
  stage_seq <- unlist(lapply(seq_len(nrow(limbs_dt)), function(i) {
    seq(limbs_dt$lower_stage_m[i], limbs_dt$upper_stage_m[i], length.out = n_points)
  }))
  stage_dt <- data.table(stage = sort(unique(stage_seq)))

  interval_dt <- apply_rating_interval(stage_dt, rating_boot_dt, stage_col = "stage", conf_level = conf_level)

  p <- ggplot(interval_dt, aes(y = stage)) +
    geom_ribbon(
      aes(xmin = discharge_lower, xmax = discharge_upper),
      orientation = "y", fill = "#0288d1", alpha = 0.2
    ) +
    geom_path(aes(x = discharge_mean), colour = "#0288d1", linewidth = 1.2) +
    geom_point(
      data = gaugings_dt,
      aes(x = discharge_cms, y = stage_m),
      colour = "#e65100", size = 2.2, shape = 21, fill = "#ff8a65", stroke = 1
    ) +
    labs(
      title = sprintf("Rating Curve with %.0f%% Bootstrap Prediction Interval", conf_level * 100),
      x = "Discharge (m\u00b3/s)", y = "Stage (m)",
      caption = "Shaded band = bootstrap prediction interval  |  Points = gauged observations"
    ) +
    theme_minimal(base_size = 12) +
    theme(
      plot.title = element_text(face = "bold", size = 13),
      panel.grid.minor = element_blank(),
      panel.border = element_rect(colour = "grey80", fill = NA)
    )

  if (nrow(limbs_dt) > 1L) {
    p <- p + geom_hline(
      yintercept = limbs_dt$upper_stage_m[-nrow(limbs_dt)],
      colour = "grey50", linetype = "dashed", linewidth = 0.5
    )
  }

  print(p)
  invisible(p)
}

#' Run the fit -> flag -> expand -> detect -> resolve -> plot pipeline
#'
#' @description
#' A worked example showing `rate_optimise` and `gap_check` operating as a
#' single pipeline: gaugings go in, a fitted multi-limb rating comes out,
#' limbs that extrapolate beyond their own gaugings are flagged doubtful,
#' the fit is bridged to a rating table and expanded to stage-discharge
#' rows, junction gaps between independently-fitted limbs are detected
#' and resolved, and both stages are plotted.
#'
#' @param plot Logical. Draw `rating_plot()` and `plot_rc_gaps()` as a
#'   side effect. Default `TRUE`.
#'
#' @return A list with elements `fit` (the [FlodeRating] instance, with
#'   `doubtful` flagged in `@limbs`), `gaps` (the junction gap report),
#'   `rc_raw` (the expanded table before resolution), and `rc_fixed`
#'   (after resolution).
#'
#' @examples
#' result <- run_demo(plot = FALSE)
#' result$gaps
#'
#' @export
run_demo <- function(plot = TRUE) {
  # 1. Simulate gaugings across three limbs with independent C/a/n --
  #    deliberately independent so that fitting each limb separately
  #    reproduces the junction-gap problem gap_check exists to handle.
  set.seed(42)
  stage_seq <- seq(0.5, 3.5, by = 0.05)
  true_limb <- cut(
    stage_seq,
    breaks = c(0.5, 1.6, 2.2, 3.5),
    labels = FALSE,
    include.lowest = TRUE
  )
  coefs_by_limb <- data.frame(C = c(3, 6, 10), a = c(0, 0.1, 0.2), n = c(1.4, 1.6, 1.8))
  discharge_seq <- coefs_by_limb$C[true_limb] *
    (stage_seq + coefs_by_limb$a[true_limb])^coefs_by_limb$n[true_limb] +
    rnorm(length(stage_seq), sd = 0.05)

  # 2. Fit the rating curve (rate_optimise module)
  fit <- rate_optimise(discharge_seq, stage_seq, control = c(1.6, 2.2))

  # 3. Flag any limb extrapolating beyond its own gaugings
  fit <- flag_extrapolated_limbs(fit)

  # 4. Bridge to a rating table (doubtful carries through) and expand to
  #    stage-discharge rows (gap_check module)
  rating_table <- as_rating_table(fit)
  rc_raw_dt <- expand_rating_table(rating_table, step = 0.01)

  # 5. Detect and resolve junction gaps
  gaps_dt <- detect_rc_gaps(rc_raw_dt)
  rc_fixed_dt <- resolve_rc_gaps(rc_raw_dt)

  # 6. Plot both views
  if (plot) {
    rating_plot(fit, colours = c(3, 4, 2))
    plot_rc_gaps(rc_raw_dt, rc_fixed_dt)
  }

  list(fit = fit, gaps = gaps_dt, rc_raw = rc_raw_dt, rc_fixed = rc_fixed_dt)
}
