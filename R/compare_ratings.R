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
#'   \item{support}{What each stage range rests on, old against new: how
#'     far the observed, fitted and numerical ranges moved, and how many
#'     observations lie in each. This answers "is the new rating better
#'     supported, or only different?"}
#'   \item{evidence}{Only when both inputs are fits. The observations
#'     behind each, matched by `evidence_id` and checked against their
#'     values.}
#' }
#'
#' @param rating_old_dt,rating_new_dt A [FlodeRating], a
#'   [FlodeRatingTable], or a plain data.frame/data.table with columns
#'   `lower_level`, `upper_level`, `C`, `a`, `n` -- one row per limb. Need
#'   not have the same number of limbs. Pass fits, not tables, to compare
#'   their evidence as well. A [FlodeSegmentedRating] is not accepted: its
#'   joint equation has no per-limb coefficients to compare.
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
#'     \item{support}{A `data.table`, one row per stage range
#'       (`observed`, `modelled`, `fitted`, `operational`, `numerical`):
#'       `lower_stage_m_old`, `lower_stage_m_new`, `upper_stage_m_old`,
#'       `upper_stage_m_new`, `lower_moved_m`, `upper_moved_m` (new minus
#'       old; `NA` where either side is missing or has no practical
#'       limit), and `n_evidence_old`, `n_evidence_new`.}
#'     \item{evidence}{`NULL` unless both inputs are fits. Otherwise a list
#'       with `summary`, a one-row `data.table` (`n_old`, `n_new`,
#'       `n_shared`, `n_changed`, `n_added`, `n_removed`, the gauged stage
#'       range of each and the latest observation of each), and `rows`, one
#'       row per observation in either, with `change` one of `"shared"`,
#'       `"changed"` (same id, different stage or discharge), `"added"` or
#'       `"removed"`. Ids made by converting a plain table are positional,
#'       so two different datasets can share ids: such rows show as
#'       `"changed"`, not `"shared"`.}
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
#' cmp$support
#'
#' # With fits, the evidence is compared too.
#' set.seed(1)
#' stage <- seq(0.3, 3, length.out = 25)
#' g <- data.frame(stage_m = stage, discharge_cms = 3 * stage^1.6 * exp(rnorm(25, sd = 0.03)))
#' old_fit <- fit_rating(g[1:20, ], quiet = TRUE)
#' new_fit <- fit_rating(g, quiet = TRUE)
#' cmp2 <- compare_ratings(old_fit, new_fit)
#' cmp2$evidence$summary
#'
#' @export
compare_ratings <- function(rating_old_dt, rating_new_dt, step = 0.01) {
  old <- .cmp_prepare(rating_old_dt, "rating_old_dt")
  new <- .cmp_prepare(rating_new_dt, "rating_new_dt")
  if (!is.numeric(step) || step <= 0) stop("step must be a positive number")

  rating_old_dt <- old$table
  rating_new_dt <- new$table

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

  list(
    coefficients = coefficients_dt, discharge = discharge_dt,
    support = .cmp_support(old$obj, new$obj),
    evidence = .cmp_evidence(old$evidence, new$evidence)
  )
}

# One input of compare_ratings(): the equation table the arithmetic runs on,
# the object that support is read from, and the evidence if it is a fit.
.cmp_prepare <- function(x, arg) {
  if (S7_inherits(x, FlodeSegmentedRating)) {
    stop("compare_ratings(): ", arg, " is a FlodeSegmentedRating. Its joint equation has no per-limb ",
         "coefficients to compare, so it is not accepted here.", call. = FALSE)
  }
  if (S7_inherits(x, FlodeRatingTable)) {
    return(list(table = data.table::as.data.table(x@table), obj = x, evidence = NULL))
  }
  if (S7_inherits(x, FlodeRating)) {
    tbl <- as_rating_table(x)
    return(list(table = data.table::as.data.table(tbl@table), obj = x, evidence = rating_evidence(x)))
  }
  if (is.data.frame(x)) {
    dt <- data.table::as.data.table(x)
    return(list(table = dt, obj = FlodeRatingTable(table = dt), evidence = NULL))
  }
  stop(arg, " must be a FlodeRating, FlodeRatingTable, data.frame, or data.table")
}

# Old against new, range by range. A bound is NA where either side lacks it, or
# where it is the numerical range's "no practical limit".
.cmp_support <- function(old_obj, new_obj) {
  o <- data.table::as.data.table(rating_support(old_obj))[, .(range, lower_stage_m, upper_stage_m, n_evidence)]
  n <- data.table::as.data.table(rating_support(new_obj))[, .(range, lower_stage_m, upper_stage_m, n_evidence)]
  out <- merge(o, n, by = "range", all = TRUE, suffixes = c("_old", "_new"), sort = FALSE)
  ord <- c("observed", "modelled", "fitted", "operational", "numerical")
  out <- out[order(match(range, ord))]
  gap <- function(a, b) {
    d <- b - a
    d[!is.finite(a) | !is.finite(b) | abs(a) > 1e6 | abs(b) > 1e6] <- NA_real_
    d
  }
  out[, `:=`(lower_moved_m = gap(lower_stage_m_old, lower_stage_m_new),
             upper_moved_m = gap(upper_stage_m_old, upper_stage_m_new))]
  data.table::setcolorder(out, c("range", "lower_stage_m_old", "lower_stage_m_new", "upper_stage_m_old",
                                 "upper_stage_m_new", "lower_moved_m", "upper_moved_m",
                                 "n_evidence_old", "n_evidence_new"))
  out[]
}

# Evidence, matched by id and then checked against the values. Only when both
# sides are fits: a table holds no observations to compare.
.cmp_evidence <- function(old_ev, new_ev) {
  if (is.null(old_ev) || is.null(new_ev)) return(NULL)
  keep <- c("evidence_id", "stage_m", "discharge_cms", "source_type", "observation_time")
  o <- data.table::as.data.table(old_ev)[, intersect(keep, names(old_ev)), with = FALSE]
  n <- data.table::as.data.table(new_ev)[, intersect(keep, names(new_ev)), with = FALSE]
  m <- merge(o, n, by = "evidence_id", all = TRUE, suffixes = c("_old", "_new"), sort = FALSE)
  same <- function(a, b) !is.na(a) & !is.na(b) & abs(a - b) <= 1e-9 * pmax(1, abs(a), abs(b))
  m[, change := data.table::fcase(
    is.na(stage_m_old) & is.na(discharge_cms_old), "added",
    is.na(stage_m_new) & is.na(discharge_cms_new), "removed",
    same(stage_m_old, stage_m_new) & same(discharge_cms_old, discharge_cms_new), "shared",
    default = "changed"
  )]
  rows <- m[, .(evidence_id,
                stage_m = data.table::fifelse(change == "removed", stage_m_old, stage_m_new),
                discharge_cms = data.table::fifelse(change == "removed", discharge_cms_old, discharge_cms_new),
                stage_m_old, stage_m_new, discharge_cms_old, discharge_cms_new,
                source_type = data.table::fifelse(is.na(source_type_new), source_type_old, source_type_new),
                change)]
  rng <- function(ev, col) if (nrow(ev)) range(ev[[col]][is.finite(ev[[col]])]) else c(NA_real_, NA_real_)
  latest <- function(ev) if ("observation_time" %in% names(ev) && any(!is.na(ev$observation_time)))
    max(ev$observation_time, na.rm = TRUE) else as.POSIXct(NA)
  ro <- rng(old_ev, "stage_m"); rn <- rng(new_ev, "stage_m")
  summary <- data.table::data.table(
    n_old = nrow(old_ev), n_new = nrow(new_ev),
    n_shared = sum(rows$change == "shared"), n_changed = sum(rows$change == "changed"),
    n_added = sum(rows$change == "added"), n_removed = sum(rows$change == "removed"),
    gauged_min_old_m = ro[1L], gauged_max_old_m = ro[2L], gauged_min_new_m = rn[1L], gauged_max_new_m = rn[2L],
    latest_old = latest(old_ev), latest_new = latest(new_ev)
  )
  list(summary = summary, rows = rows[])
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
      title = sprintf("Discharge Difference (%s - %s)", new_label, old_label),
      x = "Stage", y = "Discharge difference (m\u00b3/s)"
    ) +
    theme_minimal(base_size = 12) +
    theme(plot.title = element_text(face = "bold", size = 12))

  combined <- grid.arrange(p_curves, p_diff, ncol = 1, heights = c(2, 1))
  invisible(combined)
}
