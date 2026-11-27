# ============================================================ #
# Tool:         rating_uncertainty
# Description:  A rating's uncertainty, source by source (Release E, E2):
#               sampling (the gaugings could have been others), gauging
#               error shared between gaugings (a meter or method reading
#               high or low for all), the two combined, and structure (other
#               reasonable choices of objective and limbs) as a range, never
#               an interval. Reports each source on its own, and what was not
#               assessed and why.
# Author:       Jonathan Payne
# Created:      2026-11-27
# Tier:         3
# Inputs:       A FlodeRating or FlodeSegmentedRating fitted from evidence;
#               a stated gauging uncertainty, per gauging or one for all.
# Outputs:      A FlodeUncertainty.
# Dependencies: data.table, stats
# ============================================================ #

#' @include sensitivity.R
NULL

.uncertainty_sources <- c("sampling", "gauging", "structure")

# Refit from a table of gaugings (resampled, perturbed or both) with the
# rating's own settings, `st` from .sens_settings(), and the given
# breakpoints. Returns the fit, or a character string saying why not.
.unc_refit <- function(g, st, control, objective = st$objective) {
  obs <- if (!is.null(st$age_halflife)) g$observation_time else NULL
  tryCatch(
    suppressWarnings(
      if (st$segmented) {
        rate_optimise_segmented(g$discharge_cms, g$stage_m, gauging_datetime = obs, control = control,
                                estimate_breakpoints = st$estimate_breakpoints, multi_start = st$multi_start,
                                objective = objective, age_halflife = st$age_halflife,
                                age_min_weight = st$age_min_weight, reference_datetime = st$reference,
                                protect_above = st$protect_above, protect_quantile = st$protect_quantile,
                                protect_width = st$protect_width)
      } else {
        rate_optimise(g$discharge_cms, g$stage_m, gauging_datetime = obs, control = control,
                      multi_start = st$multi_start, n_bounds = st$n_bounds, objective = objective,
                      age_halflife = st$age_halflife, age_min_weight = st$age_min_weight,
                      reference_datetime = st$reference, protect_above = st$protect_above,
                      protect_quantile = st$protect_quantile, protect_width = st$protect_width)
      }
    ),
    error = function(e) conditionMessage(e)
  )
}

#' A rating's uncertainty, source by source
#'
#' @description
#' A rating's uncertainty has several sources, and they behave differently.
#' `rating_uncertainty()` reports each on its own and the combination, so a
#' reviewer can see what a band is made of:
#'
#' * **Sampling.** The rating would differ with a different set of gaugings.
#'   Each draw resamples the gaugings used, with replacement, and refits with
#'   the rating's own settings and breakpoints. Random error in each gauging
#'   is part of this source already: it is the scatter of the gaugings about
#'   the curve, and resampling carries it into the band.
#' * **Gauging.** Error shared between gaugings: a current meter, a method or
#'   a team reading high or low for all of them. It leaves no scatter, so
#'   sampling cannot see it. Each draw moves the discharge of every gauging
#'   in a group by one shared factor, `exp(e)` with `e ~ Normal(0, u^2)`. With
#'   `group_by`, each group (a method, a meter) has its own draw; without,
#'   every gauging shares one.
#' * **Combined.** Each draw resamples, then applies the shared error, then
#'   refits. The two sources are taken as independent, and are never added.
#' * **Structure.** Another reasonable choice would give another curve: the
#'   other objective, a limb fewer (each breakpoint dropped), a breakpoint
#'   moved. Reported as a **range** (the lowest and highest curve, with the
#'   variant giving each), never as an interval: structure has no probability,
#'   only a spread of defensible choices.
#'
#' **The package does not invent `u`.** It comes from the evidence's optional
#' `discharge_uncertainty` column (a fraction per gauging; a group's value is
#' the median of its gaugings') or, failing that, from `gauging_uncertainty`.
#' With neither, the gauging and combined sources are reported as not
#' assessed, with the reason. They are never reported as zero.
#'
#' With one group and no magnitude protection set in discharge, a shared
#' factor `k` on every discharge scales the fitted `C` by exactly `k` and
#' leaves `a` and `n` as they were, under either objective, so the gauging
#' draws need no refit: the curve is multiplied by `k`. With groups, or with
#' `protect_above`, every draw is refitted.
#'
#' The method, its failure behaviour and its limitations are set out in
#' `design/E2_separated_uncertainty.md`.
#'
#' @param rating A [FlodeRating] or [FlodeSegmentedRating] fitted from
#'   evidence. A [FlodeRatingTable] holds no evidence to resample and is
#'   refused.
#' @param stage Stages to report at, metres. Default: 50 stages over the
#'   gauged range.
#' @param n_draws Draws per resampling source, 100 or more. Default 500.
#' @param gauging_uncertainty One fraction for all gaugings, such as `0.05`,
#'   in `(0, 0.5]`, used where the evidence has no `discharge_uncertainty`.
#' @param group_by Optional: the name of an evidence column (such as the
#'   method or the meter). Gaugings sharing a value share an error; groups
#'   are independent.
#' @param sources Which of `"sampling"`, `"gauging"` and `"structure"` to
#'   assess. `"combined"` is reported whenever sampling and gauging both are.
#' @param level Width of the intervals. Default 0.95.
#' @param seed Integer or `NULL`, recorded.
#'
#' @return A [FlodeUncertainty].
#'
#' @seealso [FlodeUncertainty], [uncertainty_bands()], [rating_sensitivity()]
#'
#' @examples
#' set.seed(1)
#' stage_m <- sort(runif(25, 0.3, 3))
#' gaugings <- data.frame(stage_m = stage_m,
#'                        discharge_cms = 3 * (stage_m - 0.1)^1.6 * exp(rnorm(25, sd = 0.05)))
#' fit <- fit_rating(gaugings, quiet = TRUE)
#' u <- rating_uncertainty(fit, n_draws = 100, gauging_uncertainty = 0.03, seed = 1)
#' u
#' head(uncertainty_bands(u))
#'
#' @export
rating_uncertainty <- function(rating, stage = NULL, n_draws = 500, gauging_uncertainty = NULL,
                               group_by = NULL, sources = c("sampling", "gauging", "structure"),
                               level = 0.95, seed = NULL) {
  fn <- "rating_uncertainty()"
  if (S7_inherits(rating, FlodeRatingTable)) {
    stop(fn, ": a rating table holds equations only, with no gaugings to resample. ",
         "Use a fit from fit_rating(), rate_optimise() or rate_optimise_segmented().", call. = FALSE)
  }
  if (!(S7_inherits(rating, FlodeRating) || S7_inherits(rating, FlodeSegmentedRating))) {
    stop(fn, ": rating must be a FlodeRating or FlodeSegmentedRating, not ", class(rating)[1L], call. = FALSE)
  }
  if (!identical(rating@fit_origin, "independently_fitted")) {
    stop(sprintf(paste0("%s: this rating has been changed since it was fitted (origin: %s), so it cannot ",
                        "be refitted faithfully. Assess the original fit, before it was amended."),
                 fn, rating@fit_origin), call. = FALSE)
  }
  sources <- match.arg(sources, .uncertainty_sources, several.ok = TRUE)
  if (!is.numeric(n_draws) || length(n_draws) != 1L || n_draws < 100) {
    stop(fn, ": n_draws must be 100 or more. A band from fewer draws is not worth reading.", call. = FALSE)
  }
  n_draws <- as.integer(n_draws)
  if (!is.numeric(level) || length(level) != 1L || level <= 0 || level >= 1) {
    stop(fn, ": level must be a number between 0 and 1, such as 0.95", call. = FALSE)
  }
  g <- as.data.table(rating@gaugings)
  n <- nrow(g)
  if (n < 10L) {
    stop(sprintf(paste0("%s: the rating rests on %d gaugings. Below 10, resampled bands are not meaningful; ",
                        "gather more gaugings before quoting an uncertainty."), fn, n), call. = FALSE)
  }
  gauged <- range(g$stage_m)
  if (is.null(stage)) stage <- seq(gauged[1L], gauged[2L], length.out = 50L)
  if (!is.numeric(stage) || !length(stage) || any(!is.finite(stage))) {
    stop(fn, ": stage must be finite numbers, in metres", call. = FALSE)
  }
  stage <- sort(unique(stage))
  if (!is.null(seed)) set.seed(seed)
  st <- .sens_settings(rating)
  control <- if (st$segmented) {
    st$control
  } else if (nrow(rating@limbs) > 1L) {
    sort(rating@limbs$upper_stage_m)[-nrow(rating@limbs)]
  } else {
    NULL
  }
  base <- .sens_curve(rating, stage)
  probs <- c((1 - level) / 2, 0.5, 1 - (1 - level) / 2)
  assessed <- list()
  note <- function(src, ok, reason = NA_character_) {
    assessed[[src]] <<- data.table(source = src, assessed = ok, reason = reason)
  }
  failed <- list()
  bands <- list()
  band_rows <- function(src, curves) {
    q <- apply(curves, 1L, stats::quantile, probs = probs, na.rm = TRUE, names = FALSE)
    data.table(stage_m = stage, source = src, lower = q[1L, ], median = q[2L, ], upper = q[3L, ],
               min = NA_real_, max = NA_real_, variant_min = NA_character_, variant_max = NA_character_)
  }

  # The shared gauging error: u per group, from the evidence or the argument.
  u_group <- NULL
  groups <- rep(1L, n)
  if (!is.null(group_by)) {
    if (!is.character(group_by) || length(group_by) != 1L || !group_by %in% names(g)) {
      stop(sprintf("%s: group_by must name a column of the rating's evidence; it has %s.", fn,
                   paste(names(g), collapse = ", ")), call. = FALSE)
    }
    key <- as.character(g[[group_by]])
    key[is.na(key)] <- "(none)"
    groups <- match(key, unique(key))
  }
  u_row <- if ("discharge_uncertainty" %in% names(g)) as.numeric(g$discharge_uncertainty) else rep(NA_real_, n)
  if (!is.null(gauging_uncertainty)) {
    if (!is.numeric(gauging_uncertainty) || length(gauging_uncertainty) != 1L || !is.finite(gauging_uncertainty) ||
          gauging_uncertainty <= 0 || gauging_uncertainty > 0.5) {
      stop(fn, ": gauging_uncertainty must be one fraction in (0, 0.5], such as 0.05", call. = FALSE)
    }
    u_row[is.na(u_row)] <- gauging_uncertainty
  }
  bad_u <- which(!is.na(u_row) & !(is.finite(u_row) & u_row > 0 & u_row <= 0.5))
  if (length(bad_u)) {
    stop(sprintf("%s: discharge_uncertainty must be a fraction in (0, 0.5]; gauging %s has %s.", fn,
                 g$evidence_id[bad_u[1L]], format(u_row[bad_u[1L]])), call. = FALSE)
  }
  want_gauging <- "gauging" %in% sources
  if (want_gauging) {
    if (anyNA(u_row)) {
      note("gauging", FALSE, sprintf(paste("Not assessed: %d of %d gaugings have no stated uncertainty. Give",
                                           "gauging_uncertainty, or a discharge_uncertainty column in the evidence;",
                                           "the package does not assume one."), sum(is.na(u_row)), n))
      want_gauging <- FALSE
    } else {
      u_group <- tapply(u_row, groups, stats::median)
    }
  }
  # One group and no threshold in discharge: the shared factor scales the curve exactly.
  exact_scaling <- length(unique(groups)) == 1L && is.null(st$protect_above)
  shared <- function() {
    e <- stats::rnorm(length(u_group), 0, u_group)
    exp(e)[groups]
  }
  draw_set <- function(src, resample, perturb) {
    curves <- matrix(NA_real_, length(stage), n_draws)
    lost <- 0L
    for (d in seq_len(n_draws)) {
      rows <- if (resample) sample.int(n, n, replace = TRUE) else seq_len(n)
      k <- if (perturb) shared() else rep(1, n)
      if (perturb && !resample && exact_scaling) {
        curves[, d] <- base * k[1L]
        next
      }
      gd <- g[rows]
      if (perturb && !exact_scaling) gd[, discharge_cms := discharge_cms * k[rows]]
      fit <- .unc_refit(gd, st, control)
      if (is.character(fit)) {
        lost <- lost + 1L
        next
      }
      curves[, d] <- .sens_curve(fit, stage) * (if (perturb && exact_scaling) k[1L] else 1)
    }
    failed[[src]] <<- data.table(source = src, draws = n_draws, failed = lost)
    if (lost > 0.2 * n_draws) {
      warning(sprintf(paste("%s: %d of %d %s draws could not be refitted, over the 20%% allowed. The",
                            "source is withheld: a band from the survivors would lean towards easy data."),
                      fn, lost, n_draws, src), call. = FALSE)
      note(src, FALSE, sprintf("Withheld: %d of %d draws could not be refitted.", lost, n_draws))
      return(NULL)
    }
    note(src, TRUE)
    band_rows(src, curves)
  }

  if ("sampling" %in% sources) bands$sampling <- draw_set("sampling", resample = TRUE, perturb = FALSE)
  if (want_gauging) bands$gauging <- draw_set("gauging", resample = FALSE, perturb = TRUE)
  if ("sampling" %in% sources) {
    if (want_gauging) {
      bands$combined <- draw_set("combined", resample = TRUE, perturb = TRUE)
    } else if ("gauging" %in% sources) {
      note("combined", FALSE, "Not assessed: the gauging source was not.")
    }
  }

  # Structure: other reasonable choices, as a range.
  variants <- data.table(variant = character(0), status = character(0))
  if ("structure" %in% sources) {
    if (st$segmented) {
      note("structure", FALSE, "Not assessed: a segmented rating's structure cannot be varied here.")
    } else {
      curves <- list()
      try_variant <- function(label, ctl, objective = st$objective) {
        fit <- .unc_refit(g, st, ctl, objective)
        ok <- !is.character(fit)
        variants <<- rbind(variants, data.table(variant = label, status = if (ok) "fitted" else fit))
        if (ok) curves[[label]] <<- .sens_curve(fit, stage)
      }
      other <- setdiff(c("relative", "absolute"), st$objective)
      try_variant(sprintf("%s objective", other), control, other)
      span <- diff(gauged)
      for (j in seq_along(control)) {
        try_variant(sprintf("without the breakpoint at %.3g m", control[j]),
                    if (length(control) > 1L) control[-j] else NULL)
        for (sgn in c(-1, 1)) {
          moved <- control
          moved[j] <- control[j] + sgn * 0.05 * span
          if (moved[j] > gauged[1L] && moved[j] < gauged[2L] && !is.unsorted(moved, strictly = TRUE)) {
            try_variant(sprintf("breakpoint %.3g m moved to %.3g m", control[j], moved[j]), moved)
          }
        }
      }
      if (!length(curves)) {
        note("structure", FALSE, "Not assessed: no variant could be fitted.")
      } else {
        m <- do.call(cbind, curves)
        lab <- names(curves)
        lo <- apply(m, 1L, which.min)
        hi <- apply(m, 1L, which.max)
        bands$structure <- data.table(stage_m = stage, source = "structure", lower = NA_real_,
                                      median = NA_real_, upper = NA_real_,
                                      min = pmin(apply(m, 1L, min), base), max = pmax(apply(m, 1L, max), base),
                                      variant_min = ifelse(m[cbind(seq_along(stage), lo)] < base, lab[lo], "the rating itself"),
                                      variant_max = ifelse(m[cbind(seq_along(stage), hi)] > base, lab[hi], "the rating itself"))
        note("structure", TRUE)
      }
    }
  }

  out_bands <- rbindlist(bands, use.names = TRUE)
  if (nrow(out_bands)) {
    out_bands[, rating_cms := base[match(stage_m, stage)]]
    out_bands[, support := ifelse(stage_m < gauged[1L] | stage_m > gauged[2L], "extrapolation", "observed")]
  }
  FlodeUncertainty(
    bands = out_bands,
    assessed = rbindlist(assessed[intersect(c("sampling", "gauging", "combined", "structure"), names(assessed))]),
    settings = list(n_draws = n_draws, level = level, seed = seed, group_by = group_by,
                    u = if (is.null(u_group)) NULL else data.table(group = seq_along(u_group), u = as.numeric(u_group)),
                    u_from = if (!"discharge_uncertainty" %in% names(g)) "gauging_uncertainty" else "discharge_uncertainty, then gauging_uncertainty",
                    exact_scaling = exact_scaling, gauged_range_m = gauged),
    draws_failed = rbindlist(failed),
    variants = variants
  )
}

.unc_dt_class <- new_S3_class(c("data.table", "data.frame"),
                              constructor = function(.data = data.table()) as.data.table(.data))

#' A rating's uncertainty, source by source (S7)
#'
#' @description
#' What [rating_uncertainty()] returns.
#'
#' * `bands`: one row per stage and source, with `stage_m`, `source`
#'   (`"sampling"`, `"gauging"`, `"combined"` or `"structure"`), `lower`,
#'   `median` and `upper` for the intervals, `min` and `max` with
#'   `variant_min` and `variant_max` for structure (a range, never an
#'   interval), `rating_cms` (the rating itself) and `support`
#'   (`"observed"` or `"extrapolation"`, beyond the gauged range, not to be
#'   read as reliable).
#' * `assessed`: one row per source, whether it was assessed and, if not, why.
#' * `settings`: the draws, the level, the seed, the group column, the `u`
#'   used for each group and where it came from.
#' * `draws_failed`: per source, the draws that could not be refitted.
#' * `variants`: the structural variants tried, and whether each fitted.
#'
#' None of it is a complete uncertainty budget: stage error is not modelled.
#'
#' @param bands,assessed,draws_failed,variants Tables, as above.
#' @param settings A list, as above.
#'
#' @return A `FlodeUncertainty`.
#'
#' @seealso [rating_uncertainty()], [uncertainty_bands()]
#'
#' @examples
#' set.seed(1)
#' stage_m <- sort(runif(25, 0.3, 3))
#' fit <- fit_rating(data.frame(stage_m = stage_m,
#'                              discharge_cms = 3 * stage_m^1.6 * exp(rnorm(25, sd = 0.05))), quiet = TRUE)
#' u <- rating_uncertainty(fit, n_draws = 100, sources = "sampling", seed = 1)
#' u@assessed
#'
#' @export
FlodeUncertainty <- new_class(
  "FlodeUncertainty",
  properties = list(
    bands = new_property(.unc_dt_class, default = quote(data.table())),
    assessed = new_property(.unc_dt_class, default = quote(data.table())),
    settings = new_property(class_list, default = list()),
    draws_failed = new_property(.unc_dt_class, default = quote(data.table())),
    variants = new_property(.unc_dt_class, default = quote(data.table()))
  ),
  validator = function(self) {
    b <- self@bands
    if (nrow(b) && !all(c("stage_m", "source", "lower", "median", "upper", "min", "max") %in% names(b))) {
      return("bands is missing columns")
    }
    if (nrow(b) && any(b$source == "structure" & is.finite(b$lower))) {
      return("structure is a range: it may not carry an interval")
    }
    NULL
  }
)

#' The bands of a rating's uncertainty
#'
#' @param x A [FlodeUncertainty].
#' @return A data.table, one row per stage and source: see [FlodeUncertainty].
#' @seealso [rating_uncertainty()]
#' @examples
#' set.seed(1)
#' stage_m <- sort(runif(25, 0.3, 3))
#' fit <- fit_rating(data.frame(stage_m = stage_m,
#'                              discharge_cms = 3 * stage_m^1.6 * exp(rnorm(25, sd = 0.05))), quiet = TRUE)
#' head(uncertainty_bands(rating_uncertainty(fit, n_draws = 100, sources = "sampling", seed = 1)))
#' @export
uncertainty_bands <- function(x) {
  if (!S7_inherits(x, FlodeUncertainty)) stop("x must be a FlodeUncertainty", call. = FALSE)
  copy(x@bands)
}

#' Print a rating's uncertainty (S7 method)
#' @param x A [FlodeUncertainty].
#' @param ... Unused.
#' @noRd
method(.s7_print, FlodeUncertainty) <- function(x, ...) {
  cat(sprintf("<FlodeUncertainty> %g%% intervals, %d draws per resampling source\n",
              100 * x@settings$level, x@settings$n_draws))
  a <- x@assessed
  for (i in seq_len(nrow(a))) {
    src <- a$source[i]
    line <- if (a$assessed[i]) {
      b <- x@bands[x@bands$source == src & x@bands$support == "observed"]
      if (src == "structure") {
        sprintf("range %+.1f%% to %+.1f%% of the rating over the gauged range (%d variant(s); a range, not an interval)",
                100 * min(b$min / b$rating_cms - 1), 100 * max(b$max / b$rating_cms - 1), sum(x@variants$status == "fitted"))
      } else {
        sprintf("%+.1f%% to %+.1f%% of the rating, widest, over the gauged range",
                100 * min(b$lower / b$rating_cms - 1), 100 * max(b$upper / b$rating_cms - 1))
      }
    } else {
      a$reason[i]
    }
    cat(sprintf("  %-10s %s\n", paste0(src, ":"), line))
  }
  cat("  Not a complete budget: stage error is not modelled.\n")
  invisible(x)
}

.plot_uncertainty <- function(x) {
  b <- x@bands
  if (!nrow(b)) stop("there are no bands to draw", call. = FALSE)
  iv <- b[b$source != "structure"]
  sr <- b[b$source == "structure"]
  p <- ggplot2::ggplot(mapping = ggplot2::aes(y = stage_m))
  if (nrow(sr)) {
    p <- p + ggplot2::geom_ribbon(data = sr, ggplot2::aes(xmin = min, xmax = max, fill = "structure (range)"),
                                  orientation = "y", alpha = 0.25)
  }
  if (nrow(iv)) {
    p <- p + ggplot2::geom_ribbon(data = iv, ggplot2::aes(xmin = lower, xmax = upper, fill = source),
                                  orientation = "y", alpha = 0.35)
  }
  p + ggplot2::geom_path(data = b[!duplicated(b$stage_m)], ggplot2::aes(x = rating_cms), linewidth = 0.6) +
    ggplot2::labs(x = "Discharge (m3/s)", y = "Stage (m)", fill = "Source",
                  title = "A rating's uncertainty, source by source",
                  subtitle = "Each source on its own; structure is a range, not an interval. Not a complete budget.") +
    ggplot2::theme_minimal()
}

#' @noRd
method(.s7_plot, FlodeUncertainty) <- function(x, y, ...) print(.plot_uncertainty(x))

#' @noRd
method(.s7_autoplot, FlodeUncertainty) <- function(object, ...) .plot_uncertainty(object)
