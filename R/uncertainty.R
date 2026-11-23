# ============================================================ #
# Tool:         uncertainty
# Description:  Where a rating's uncertainty comes from (Release E, E2).
#               rating_uncertainty() reports each source on its own and the
#               combination: sampling (which gaugings were taken), gauging
#               error (how well each was measured) and structure (which
#               reasonable fitting choice was made). Sampling and gauging
#               error are intervals. Structure is a range and is never
#               turned into an interval.
# Author:       Jonathan Payne
# Created:      2026-11-23
# Tier:         3
# Inputs:       A FlodeRating or FlodeSegmentedRating fitted from gaugings.
# Outputs:      A FlodeUncertainty.
# Dependencies: data.table, ggplot2
# ============================================================ #

#' @include flode_classes.R sensitivity.R autoplot.R
NULL

.uncertainty_sources <- c("sampling", "gauging", "structure")

# The relative standard uncertainty of each gauging: the evidence's own
# `discharge_uncertainty` column where it has one, filled from the stated
# argument where it does not. NA where neither says.
.unc_gauging_u <- function(g, gauging_uncertainty) {
  col <- if ("discharge_uncertainty" %in% names(g)) as.numeric(g$discharge_uncertainty) else rep(NA_real_, nrow(g))
  if (!is.null(gauging_uncertainty)) col[is.na(col)] <- gauging_uncertainty
  col
}

# One perturbed set of discharges. "shared": one multiplicative error for all
# gaugings from the same source, so an error that every gauging has in common
# moves the whole curve. "independent": one error per gauging.
.unc_perturb <- function(q, u, group, structure) {
  if (structure == "independent") return(q * exp(stats::rnorm(length(q), sd = u)))
  lv <- unique(group)
  shared <- stats::rnorm(length(lv), sd = vapply(lv, function(l) mean(u[group == l]), numeric(1)))
  q * exp(shared[match(group, lv)])
}

#' Where a rating's uncertainty comes from
#'
#' @description
#' Reports each source of a rating's uncertainty on its own, and the
#' combination, so a reviewer can see what a band is made of. It is not a
#' complete uncertainty budget, and every result says so.
#'
#' Three sources can be assessed:
#'
#' * **`sampling`**: the rating would differ with a different set of gaugings.
#'   Case resampling of the gaugings used, refitting each draw with the
#'   settings the rating recorded. An interval.
#' * **`gauging`**: each gauging is itself an estimate. Its discharge is
#'   perturbed by its stated relative standard uncertainty, log-normally, and
#'   the rating refitted. An interval. See *Gauging error* below.
#' * **`structure`**: another reasonable fitting choice would give a different
#'   curve: the other objective, a breakpoint moved, another valid starting
#'   point. A **range**, the lowest and highest curve across those variants
#'   and the fitted rating. It is never an interval, because the variants
#'   have no probability. It depends entirely on which variants were tried.
#'
#' Where both intervals are assessed, a `combined` interval is also given. It
#' comes from joint simulation (each draw resamples the gaugings and then
#' perturbs them), not from adding the two.
#'
#' @section Gauging error:
#' The package does not supply a measurement uncertainty. It takes one from the
#' evidence's own `discharge_uncertainty` column (a fraction per gauging, such
#' as `0.05`), or from `gauging_uncertainty` for any gauging the column leaves
#' blank. With neither, the gauging source is reported as **not assessed**, with
#' the reason. It is never reported as zero.
#'
#' `error_structure` says how the error is shared:
#'
#' * `"shared"` (default): one error per draw, common to all gaugings from the
#'   same `source_name`, as when one meter or one method is biased. This is the
#'   part of gauging error that the scatter of the points about the curve
#'   cannot show, so it is the part that adds to the sampling interval.
#' * `"independent"`: a separate error for each gauging. Independent error is
#'   **already in the sampling interval**, because it is part of the scatter the
#'   resampling sees. Using this option therefore double counts it and
#'   the combined interval will usually be wider than it should. It is here for
#'   comparison and is labelled in the result.
#'
#' @param rating A [FlodeRating] or [FlodeSegmentedRating] fitted from gaugings,
#'   with at least 10 usable gaugings. A [FlodeRatingTable] holds no gaugings and
#'   is refused.
#' @param stage Numeric vector of stages (m) to report at. Default: 25 stages
#'   across the fitted range.
#' @param n_draws Number of refits for each interval. At least 100. Default 500.
#' @param gauging_uncertainty `NULL` (default), or one number between 0 and 0.5:
#'   the relative standard uncertainty of any gauging whose
#'   `discharge_uncertainty` is blank.
#' @param error_structure `"shared"` (default) or `"independent"`. See above.
#' @param sources Which sources to assess: any of `"sampling"`, `"gauging"`,
#'   `"structure"`.
#' @param level Coverage of the intervals. Default 0.95.
#' @param seed Integer or `NULL`. Recorded, so the result can be repeated. Your
#'   own random-number state is put back afterwards.
#'
#' @return A [FlodeUncertainty]. `print()` states first which sources were
#'   assessed and which were not. `autoplot()` draws the sources as separate
#'   bands. [uncertainty_bands()] and [uncertainty_summary()] return the tables.
#'
#' @seealso [rating_sensitivity()], [fit_rating()], [apply_rating_interval()]
#'
#' @examples
#' set.seed(1)
#' stage_m <- seq(0.4, 3, length.out = 24)
#' gaugings <- data.frame(stage_m = stage_m,
#'                        discharge_cms = 3.2 * stage_m^1.6 * exp(rnorm(24, sd = 0.03)))
#' fit <- fit_rating(gaugings, quiet = TRUE)
#' u <- rating_uncertainty(fit, stage = c(0.8, 1.5, 2.5), n_draws = 100,
#'                         gauging_uncertainty = 0.05, seed = 1)
#' u
#' uncertainty_summary(u)
#'
#' @export
rating_uncertainty <- function(rating, stage = NULL, n_draws = 500L, gauging_uncertainty = NULL,
                               error_structure = c("shared", "independent"),
                               sources = .uncertainty_sources, level = 0.95, seed = NULL) {
  fn <- "rating_uncertainty()"
  error_structure <- match.arg(error_structure)
  sources <- match.arg(sources, .uncertainty_sources, several.ok = TRUE)
  if (S7_inherits(rating, FlodeRatingTable)) {
    stop(fn, ": a rating table holds equations only, with no gaugings to resample. ",
         "Use a fit from fit_rating(), rate_optimise() or rate_optimise_segmented().", call. = FALSE)
  }
  if (!(S7_inherits(rating, FlodeRating) || S7_inherits(rating, FlodeSegmentedRating))) {
    stop(fn, ": rating must be a FlodeRating or FlodeSegmentedRating, not ", class(rating)[1L], call. = FALSE)
  }
  if (!identical(rating@fit_origin, "independently_fitted")) {
    stop(sprintf(paste0("%s: this rating has been changed since it was fitted (origin: %s), so it cannot be refitted ",
                        "faithfully. Use the original fit, before it was amended."), fn, rating@fit_origin), call. = FALSE)
  }
  if (!is.numeric(n_draws) || length(n_draws) != 1L || !is.finite(n_draws) || n_draws < 100) {
    stop(fn, ": n_draws must be a single number of at least 100. An interval needs draws.", call. = FALSE)
  }
  n_draws <- as.integer(n_draws)
  if (!is.numeric(level) || length(level) != 1L || !is.finite(level) || level <= 0 || level >= 1) {
    stop(fn, ": level must be a single number between 0 and 1", call. = FALSE)
  }
  if (!is.null(seed) && (!is.numeric(seed) || length(seed) != 1L)) stop(fn, ": seed must be NULL or one number", call. = FALSE)
  if (!is.null(gauging_uncertainty) &&
      (!is.numeric(gauging_uncertainty) || length(gauging_uncertainty) != 1L || !is.finite(gauging_uncertainty) ||
       gauging_uncertainty <= 0 || gauging_uncertainty > 0.5)) {
    stop(fn, ": gauging_uncertainty must be one number above 0 and at most 0.5 (a fraction, such as 0.05 for 5%)", call. = FALSE)
  }

  g <- as.data.table(rating@gaugings)
  n <- nrow(g)
  if (n < 10L) {
    stop(sprintf("%s: only %d gauging%s. Resampling needs at least 10, or the bands say nothing. ",
                 fn, n, if (n == 1L) "" else "s"), call. = FALSE)
  }
  if ("discharge_uncertainty" %in% names(g)) {
    du <- g$discharge_uncertainty
    bad <- which(!is.na(du) & (!is.finite(du) | du <= 0 | du > 0.5))
    if (length(bad)) {
      stop(sprintf("%s: discharge_uncertainty must be above 0 and at most 0.5 (a fraction). Check gauging(s): %s.",
                   fn, paste(utils::head(g$evidence_id[bad], 5L), collapse = ", ")), call. = FALSE)
    }
  }
  st <- .sens_settings(rating)
  fitted <- .fitted_range(rating)
  if (is.null(stage)) stage <- seq(fitted[1L], fitted[2L], length.out = 25L)
  if (!is.numeric(stage) || !length(stage) || any(!is.finite(stage))) stop(fn, ": stage must be finite numbers", call. = FALSE)
  stage <- sort(unique(stage))
  base <- .sens_curve(rating, stage)
  alpha <- (1 - level) / 2
  u_i <- .unc_gauging_u(g, gauging_uncertainty)
  group <- ifelse(is.na(g$source_name), "(none)", as.character(g$source_name))

  assessed <- data.table(source = c("sampling", "gauging", "structure", "combined"), assessed = FALSE,
                         reason = NA_character_, kind = c("interval", "interval", "range", "interval"))
  failed <- c(sampling = 0L, gauging = 0L, combined = 0L)
  curves <- list()

  run_draws <- function(source, resample, perturb) {
    out <- matrix(NA_real_, nrow = n_draws, ncol = length(stage))
    for (b in seq_len(n_draws)) {
      rows <- if (resample) sample.int(n, n, replace = TRUE) else seq_len(n)
      q <- g$discharge_cms[rows]
      if (perturb) q <- .unc_perturb(q, u_i[rows], group[rows], error_structure)
      fit <- .sens_refit(rating, rows, st, st$control, discharge = q)
      if (!is.character(fit) && identical(.sens_status(fit), "ok")) out[b, ] <- .sens_curve(fit, stage)
    }
    ok <- stats::complete.cases(out)
    failed[[source]] <<- sum(!ok)
    if (sum(!ok) > 0.2 * n_draws) {
      msg <- sprintf("%d of %d refits failed or did not converge, so the band would be biased towards easy data",
                     sum(!ok), n_draws)
      warning(fn, ": the ", source, " interval was withheld: ", msg, ".", call. = FALSE)
      return(msg)
    }
    out[ok, , drop = FALSE]
  }

  body <- function() {
    if ("sampling" %in% sources) {
      r <- run_draws("sampling", TRUE, FALSE)
      if (is.character(r)) assessed[source == "sampling", reason := r] else {
        curves$sampling <<- r
        assessed[source == "sampling", assessed := TRUE]
      }
    }
    if ("gauging" %in% sources) {
      if (anyNA(u_i)) {
        assessed[source == "gauging", reason := paste0(
          sum(is.na(u_i)), " of ", n, " gaugings have no stated uncertainty. Give a discharge_uncertainty column in the ",
          "evidence, or gauging_uncertainty, taken from the gauging record or method. The package does not supply one.")]
      } else {
        r <- run_draws("gauging", FALSE, TRUE)
        if (is.character(r)) assessed[source == "gauging", reason := r] else {
          curves$gauging <<- r
          assessed[source == "gauging", assessed := TRUE]
        }
      }
    }
    if (all(c("sampling", "gauging") %in% sources)) {
      if (is.null(curves$sampling) || is.null(curves$gauging)) {
        assessed[source == "combined", reason := "needs the sampling and gauging sources, and one of them was not assessed"]
      } else {
        rc <- run_draws("combined", TRUE, TRUE)
        if (is.character(rc)) assessed[source == "combined", reason := rc] else {
          curves$combined <<- rc
          assessed[source == "combined", assessed := TRUE]
        }
      }
    }
  }
  if (is.null(seed)) body() else .with_seed(as.integer(seed), body())

  variants <- data.table(variant = character(0), kind = character(0), max_abs_change_pct = numeric(0), curve = list())
  if ("structure" %in% sources) {
    vs <- list()
    other <- if (identical(st$objective, "relative")) "absolute" else "relative"
    st2 <- st; st2$objective <- other
    alt <- .sens_refit(rating, seq_len(n), st2, st$control)
    if (!is.character(alt) && identical(.sens_status(alt), "ok")) {
      vs[[length(vs) + 1L]] <- list(variant = sprintf("%s objective", other), kind = "objective", curve = .sens_curve(alt, stage))
    }
    sens <- tryCatch(suppressWarnings(rating_sensitivity(rating, tests = c("starting_values", "boundary_shift"), stages = stage)),
                     error = function(e) NULL)
    if (!is.null(sens)) {
      r <- as.data.table(sens@results)
      r <- r[status == "ok"]
      for (v in unique(r$variant)) {
        d <- r[variant == v][order(stage_m)]
        vs[[length(vs) + 1L]] <- list(variant = v, kind = d$test[1L], curve = d$variant_cms)
      }
    }
    if (length(vs)) {
      variants <- rbindlist(lapply(vs, function(v) data.table(
        variant = v$variant, kind = v$kind,
        max_abs_change_pct = max(abs(100 * (v$curve - base) / ifelse(base > 0, base, NA_real_)), na.rm = TRUE),
        curve = list(v$curve))))
      assessed[source == "structure", assessed := TRUE]
    } else {
      assessed[source == "structure", reason := "no other fitting choice could be refitted from this rating"]
    }
  }
  assessed[!assessed & is.na(reason), reason := "not requested"]

  band_rows <- list()
  for (s in names(curves)) {
    M <- curves[[s]]
    band_rows[[s]] <- data.table(
      stage_m = stage, source = s, lower = apply(M, 2L, stats::quantile, alpha, names = FALSE),
      upper = apply(M, 2L, stats::quantile, 1 - alpha, names = FALSE), median = apply(M, 2L, stats::median),
      min = NA_real_, max = NA_real_)
  }
  if (nrow(variants)) {
    allc <- rbind(base, do.call(rbind, variants$curve))
    band_rows[["structure"]] <- data.table(stage_m = stage, source = "structure", lower = NA_real_, upper = NA_real_,
                                           median = NA_real_, min = apply(allc, 2L, min), max = apply(allc, 2L, max))
  }
  bands <- if (length(band_rows)) rbindlist(band_rows) else data.table(
    stage_m = numeric(0), source = character(0), lower = numeric(0), upper = numeric(0),
    median = numeric(0), min = numeric(0), max = numeric(0))
  bands[, base_cms := base[match(stage_m, stage)]]

  settings <- list(
    n_draws = n_draws, level = level, seed = seed, error_structure = error_structure,
    gauging_uncertainty = gauging_uncertainty,
    uncertainty_source = if (all(is.na(u_i))) "none" else if ("discharge_uncertainty" %in% names(g) && !all(is.na(g$discharge_uncertainty)))
      "evidence column" else "argument",
    n_gaugings = n, stages = stage
  )
  FlodeUncertainty(bands = bands, assessed = assessed, settings = settings,
                   draws_failed = failed, variants = variants[, .(variant, kind, max_abs_change_pct)],
                   stages = stage, level = level)
}

#' The outcome of an uncertainty analysis (S7)
#'
#' @description
#' What [rating_uncertainty()] returns.
#'
#' * `bands`: one row per source and stage: `stage_m`, `source`
#'   (`sampling`, `gauging`, `combined` or `structure`), `lower`, `upper` and
#'   `median` for the intervals, `min` and `max` for the structural range, and
#'   `base_cms`, the fitted rating's discharge.
#' * `assessed`: one row per source, with whether it was assessed and, if not,
#'   why. A source that was not assessed is not zero.
#' * `settings`: draws, level, seed, the error structure, and where the
#'   gauging uncertainty came from.
#' * `draws_failed`: refits that failed or did not converge, per source.
#' * `variants`: the structural variants tried, and how far each moved the
#'   curve.
#'
#' @param bands,assessed,variants Tables, as above.
#' @param settings A list.
#' @param draws_failed A named integer vector.
#' @param stages The stages reported at.
#' @param level The coverage of the intervals.
#'
#' @return A `FlodeUncertainty`.
#'
#' @seealso [rating_uncertainty()], [uncertainty_bands()], [uncertainty_summary()]
#'
#' @export
FlodeUncertainty <- new_class(
  "FlodeUncertainty",
  properties = list(
    bands = new_property(.sens_dt_class, default = quote(data.table())),
    assessed = new_property(.sens_dt_class, default = quote(data.table())),
    settings = new_property(class_list, default = list()),
    draws_failed = new_property(class_integer, default = integer(0)),
    variants = new_property(.sens_dt_class, default = quote(data.table())),
    stages = new_property(class_double, default = numeric(0)),
    level = new_property(class_double, default = 0.95)
  ),
  validator = function(self) {
    if (nrow(self@bands) && !all(c("stage_m", "source", "lower", "upper", "median", "min", "max") %in% names(self@bands))) {
      return("bands is missing columns")
    }
    NULL
  }
)

#' The bands of an uncertainty analysis
#'
#' @param x A [FlodeUncertainty].
#' @return A data.table, one row per source and stage: see [FlodeUncertainty].
#' @seealso [rating_uncertainty()]
#' @examples
#' set.seed(1)
#' stage_m <- seq(0.4, 3, length.out = 24)
#' fit <- fit_rating(data.frame(stage_m = stage_m,
#'                              discharge_cms = 3.2 * stage_m^1.6 * exp(rnorm(24, sd = 0.03))), quiet = TRUE)
#' u <- rating_uncertainty(fit, stage = c(1, 2), n_draws = 100, sources = "sampling", seed = 1)
#' uncertainty_bands(u)
#' @export
uncertainty_bands <- function(x) {
  if (!S7_inherits(x, FlodeUncertainty)) stop("x must be a FlodeUncertainty", call. = FALSE)
  copy(x@bands)
}

#' A summary of an uncertainty analysis
#'
#' @description
#' One row per source: whether it was assessed, why not if not, and the median
#' half-width of its interval across the stages as a percentage of the
#' fitted discharge (for the structural range, half the width of the range).
#'
#' @param x A [FlodeUncertainty].
#' @return A data.table with `source`, `kind`, `assessed`, `reason`,
#'   `median_half_width_pct` and `draws_failed`.
#' @seealso [rating_uncertainty()]
#' @examples
#' set.seed(1)
#' stage_m <- seq(0.4, 3, length.out = 24)
#' fit <- fit_rating(data.frame(stage_m = stage_m,
#'                              discharge_cms = 3.2 * stage_m^1.6 * exp(rnorm(24, sd = 0.03))), quiet = TRUE)
#' u <- rating_uncertainty(fit, stage = c(1, 2), n_draws = 100, sources = "sampling", seed = 1)
#' uncertainty_summary(u)
#' @export
uncertainty_summary <- function(x) {
  if (!S7_inherits(x, FlodeUncertainty)) stop("x must be a FlodeUncertainty", call. = FALSE)
  out <- copy(x@assessed)
  data.table::setindex(out, NULL)
  b <- x@bands
  hw <- function(s) {
    d <- b[source == s]
    if (!nrow(d)) return(NA_real_)
    half <- if (s == "structure") (d$max - d$min) / 2 else (d$upper - d$lower) / 2
    stats::median(100 * half / ifelse(d$base_cms > 0, d$base_cms, NA_real_), na.rm = TRUE)
  }
  out[, median_half_width_pct := vapply(source, hw, numeric(1))]
  out[, draws_failed := ifelse(source %in% names(x@draws_failed), x@draws_failed[source], NA_integer_)]
  out[]
}

#' Print an uncertainty analysis (S7 method)
#' @param x A [FlodeUncertainty].
#' @param ... Unused.
#' @noRd
method(.s7_print, FlodeUncertainty) <- function(x, ...) {
  s <- uncertainty_summary(x)
  yes <- s[assessed == TRUE]
  no <- s[assessed == FALSE & reason != "not requested"]
  cat(sprintf("<FlodeUncertainty> %d stage(s), %s intervals, %d draws\n",
              length(x@stages), sprintf("%g%%", 100 * x@level), x@settings$n_draws))
  cat("Assessed:     ", if (nrow(yes)) paste(yes$source, collapse = ", ") else "none", "\n")
  if (nrow(no)) {
    cat("Not assessed:\n")
    for (i in seq_len(nrow(no))) cat(sprintf("  %-10s %s\n", paste0(no$source[i], ":"), no$reason[i]))
  }
  for (i in seq_len(nrow(yes))) {
    cat(sprintf("  %-10s %s, median half-width %.1f%% of discharge%s\n", paste0(yes$source[i], ":"),
                if (yes$kind[i] == "range") "range" else "interval", yes$median_half_width_pct[i],
                if (yes$source[i] == "structure") " (a range, not an interval)" else ""))
  }
  if (isTRUE(x@settings$error_structure == "independent") && "gauging" %in% yes$source) {
    cat("Note: independent gauging error is already in the sampling interval, so this is wider than it should be.\n")
  }
  cat("This is not a complete uncertainty budget: stage error and the equation form are not modelled.\n")
  invisible(x)
}

.plot_uncertainty <- function(x) {
  b <- as.data.table(x@bands)
  iv <- b[source %in% c("combined", "sampling", "gauging") & is.finite(lower)]
  iv[, source := factor(source, levels = c("combined", "gauging", "sampling"))]
  rg <- b[source == "structure"]
  base <- unique(b[, .(stage_m, base_cms)])
  p <- ggplot2::ggplot() +
    ggplot2::geom_ribbon(data = iv, ggplot2::aes(y = stage_m, xmin = lower, xmax = upper, fill = source),
                         alpha = 0.35, orientation = "y")
  p <- p +
    ggplot2::geom_line(data = base, ggplot2::aes(x = base_cms, y = stage_m), linewidth = 0.8, colour = "#0E2A3B")
  if (nrow(rg)) {
    p <- p + ggplot2::geom_line(data = rg, ggplot2::aes(x = min, y = stage_m), linetype = "dashed", colour = "#B15B00") +
      ggplot2::geom_line(data = rg, ggplot2::aes(x = max, y = stage_m), linetype = "dashed", colour = "#B15B00")
  }
  p + ggplot2::scale_fill_manual(values = c(combined = "#0B6E7F", gauging = "#E3A33B", sampling = "#6FD0DC"), name = "Interval") +
    ggplot2::labs(x = "Discharge (m³/s)", y = "Stage (m)",
                  title = "Sources of uncertainty",
                  caption = paste0("Bands are ", 100 * x@level, "% intervals. Dashed lines are a structural range, not an interval. ",
                                   "Not a complete uncertainty budget.")) +
    ggplot2::theme_minimal()
}

#' @noRd
method(.s7_plot, FlodeUncertainty) <- function(x, y, ...) .plot_uncertainty(x)
#' @noRd
method(.s7_autoplot, FlodeUncertainty) <- function(object, ...) .plot_uncertainty(object)
