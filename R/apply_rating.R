# ============================================================ #
# Tool:         apply_rating
# Description:  Convert a stage time series to discharge using a
#               multi-limb rating equation table, flagging any stage
#               values that fall outside every limb's gauged bounds.
#               apply_rating_interval() propagates bootstrap coefficient
#               uncertainty through to a discharge prediction interval.
#               apply_rating_versioned() selects the correct rating
#               version per timestamp for a rating that has shifted over
#               time.
# Author:       Jonathan Payne
# Created:      2026-08-18
# Modified:     2026-08-18 - JP: initial version
# Modified:     2026-08-18 - JP: added apply_rating_interval() and
#               apply_rating_versioned(), after reviewing Hodson et al.
#               (2024)'s ratingcurve package: their fits carry full
#               posterior uncertainty end to end, and their §1 cites
#               Mansanarez et al. (2019) "Shift Happens!" on ratings
#               changing at known dates -- both were gaps here.
# Modified:     2026-08-19 - JP: converted apply_rating() to an S7
#               method (method(apply_rating, FlodeRatingTable) <- ...)
#               registered against the shared generic from
#               flode_classes.R, alongside rate_optimise.R's method for
#               FlodeRating and rate_optimise_segmented.R's method for
#               FlodeSegmentedRating -- one name, dispatched by class,
#               across all three. BREAKING CHANGE: argument order
#               flipped from apply_rating(stage_dt, rating_dt, ...) to
#               apply_rating(fit, stage_dt, ...), to match the dispatch
#               argument position the other two methods already use.
#               apply_rating_interval() and apply_rating_versioned()
#               stay plain functions -- rating_boot_dt (per-draw
#               coefficients) and rating_history_dt (versioned ratings)
#               are collections of many equations, not a single fitted
#               object with an identity of its own, so wrapping them as
#               FlodeRatingTable would be a poor fit for what that class
#               represents. apply_rating_versioned()'s internal call
#               into apply_rating() now wraps each version's slice in a
#               FlodeRatingTable to satisfy the generic's dispatch.
# Modified:     2026-08-25 - JP: converted from a box module to a package
#               R/ file. data.table/stats/S7 are package-level imports
#               now (R/reach.rate-package.R); FlodeRatingTable and the
#               apply_rating generic (flode_classes.R) need no import at
#               all -- same package namespace.
# Tier:         3
# Inputs:       stage_dt: data.table with a stage column (and, typically,
#               a datetime column carried through unchanged). rating_dt/
#               fit: a FlodeRatingTable, or a plain data.frame/
#               data.table with lower_level/upper_level/C/a/n, one row
#               per limb, contiguous (same shape as
#               expand_rating_table()'s input in the gap_check module).
# Outputs:      stage_dt with a discharge column and an `extrapolated`
#               logical column added (apply_rating()); a discharge
#               prediction interval (apply_rating_interval()); or a
#               discharge column plus which rating version was applied
#               per row (apply_rating_versioned())
# Dependencies: data.table, logger, S7
# ============================================================ #

#' @include flode_classes.R
NULL

log_threshold(INFO)

#' Apply a rating equation table to a stage series to compute discharge (S7 method)
#'
#' @description
#' Registered against the `apply_rating` generic (`flode_classes.R`) for
#' [FlodeRatingTable]. This is the step the rest of the toolkit builds
#' towards but none of it actually performs: turning a stage record into
#' a discharge record. For each stage value, the matching limb is
#' selected by which `[lower_level, upper_level]` band it falls into,
#' and discharge is computed from that limb's `Q = C(h - a)^n`. Stage
#' values below the lowest limb or above the highest are evaluated by
#' extrapolating the nearest limb's equation, and flagged in the
#' `extrapolated` column rather than silently treated the same as an
#' interpolated value.
#'
#' `fit` is a [FlodeRatingTable]. `stage_dt` is a data.frame or
#' data.table with at least a stage column (named by `stage_col`,
#' default `"stage"`); any other columns (e.g. `datetime`) are carried
#' through unchanged. `out_col` (default `"discharge"`) names the output
#' discharge column.
#'
#' @return `stage_dt` as a data.table with two columns added: `out_col`
#'   (computed discharge) and `extrapolated` (logical; `TRUE` where the
#'   stage fell outside every limb's bounds).
#'
#' @examples
#' rating_dt <- data.table::data.table(
#'   lower_level = c(0.0, 1.2), upper_level = c(1.2, 2.5),
#'   C = c(2.5, 4.1), a = c(0, 0), n = c(1.5, 1.7)
#' )
#' rating_table <- FlodeRatingTable(table = rating_dt)
#' stage_dt <- data.table::data.table(stage = c(0.5, 1.8, 3.0))
#' apply_rating(rating_table, stage_dt)
#'
#' @rdname apply_rating
#' @export
method(apply_rating, FlodeRatingTable) <- function(fit, stage_dt, stage_col = "stage", out_col = "discharge") {
  if (!is.data.frame(stage_dt)) stop("stage_dt must be a data.frame or data.table")
  if (!stage_col %in% names(stage_dt)) stop("stage_col must be a column of stage_dt")

  rating_dt <- copy(fit@table)
  setorder(rating_dt, lower_level)

  n_limbs <- nrow(rating_dt)
  if (n_limbs > 1L) {
    contiguous <- all(abs(rating_dt$upper_level[-n_limbs] - rating_dt$lower_level[-1L]) < 1e-8)
    if (!contiguous) {
      stop("apply_rating(): limbs in fit@table must be contiguous (upper_level[i] == lower_level[i+1]).")
    }
  }

  out_dt <- copy(as.data.table(stage_dt))
  stage_vals <- out_dt[[stage_col]]

  breaks <- c(rating_dt$lower_level[1], rating_dt$upper_level)
  limb_idx_raw <- findInterval(stage_vals, breaks, rightmost.closed = TRUE)

  extrapolated <- limb_idx_raw == 0L | limb_idx_raw == (n_limbs + 1L)
  limb_idx <- pmin(pmax(limb_idx_raw, 1L), n_limbs)

  C <- rating_dt$C[limb_idx]
  a <- rating_dt$a[limb_idx]
  n <- rating_dt$n[limb_idx]

  discharge <- C * (stage_vals - a)^n
  discharge[!is.na(stage_vals) & stage_vals <= a] <- 0

  set(out_dt, j = out_col, value = discharge)
  set(out_dt, j = "extrapolated", value = extrapolated)

  n_extrap <- sum(extrapolated, na.rm = TRUE)
  if (n_extrap > 0L) {
    log_info(
      "apply_rating(): {n_extrap} of {nrow(out_dt)} stage value(s) fell outside the rating and were extrapolated."
    )
  }

  out_dt[]
}

#' Apply a rating with bootstrap uncertainty to a stage series
#'
#' @description
#' Like [apply_rating()], but propagates per-limb bootstrap coefficient
#' draws (from `rate_optimise(..., n_boot = )`, bridged through
#' `bootstrap_to_table()`) to a discharge *prediction interval* at each
#' stage, rather than a single point value. For each stage row, discharge
#' is computed once per bootstrap draw using that draw's limb assignment
#' and `C`/`a`/`n`, and the draws are summarised into a mean, median, and
#' geometric standard error -- the same summary Hodson et al. (2024)'s
#' `ratingcurve` package reports -- plus a lower/upper interval at
#' `conf_level`. This is a bootstrap approximation, not a Bayesian
#' posterior; treat the interval as indicative of gauging-driven
#' coefficient uncertainty, not a complete uncertainty budget (it doesn't
#' include stage measurement error, or uncertainty in the equation form
#' itself).
#'
#' Limb bounds are assumed fixed across draws (only `C`/`a`/`n` vary),
#' which matches how `rate_optimise(..., n_boot = )` bootstraps: it
#' resamples gaugings and refits within each limb's fixed stage range,
#' not the breakpoints themselves.
#'
#' @param stage_dt Data.frame or data.table with a stage column.
#' @param rating_boot_dt Data.table of per-draw coefficients, one row per
#'   (limb, draw): columns `limb`, `draw`, `lower_level`, `upper_level`,
#'   `C`, `a`, `n`. See [bootstrap_to_table()] (in `rating_curve_demo`)
#'   for building this from a `rate_optimise(..., n_boot = )` fit.
#' @param stage_col Character. Default `"stage"`.
#' @param conf_level Numeric in (0, 1). Width of the prediction interval.
#'   Default `0.95`.
#'
#' @return `stage_dt` as a data.table with columns added: `discharge_mean`,
#'   `discharge_median`, `discharge_gse` (geometric standard error),
#'   `discharge_lower`, `discharge_upper`, and `extrapolated`.
#'
#' @seealso [apply_rating()]
#'
#' @examples
#' rating_boot_dt <- data.table::data.table(
#'   limb = rep(1L, 20), draw = 1:20,
#'   lower_level = 0.0, upper_level = 3.0,
#'   C = rnorm(20, 3, 0.1), a = 0, n = rnorm(20, 1.6, 0.02)
#' )
#' stage_dt <- data.table::data.table(stage = c(0.5, 1.5, 2.5))
#' apply_rating_interval(stage_dt, rating_boot_dt)
#'
#' @export
apply_rating_interval <- function(stage_dt, rating_boot_dt, stage_col = "stage", conf_level = 0.95) {
  if (!is.data.frame(stage_dt)) stop("stage_dt must be a data.frame or data.table")
  if (!is.data.frame(rating_boot_dt)) stop("rating_boot_dt must be a data.frame or data.table")
  if (!stage_col %in% names(stage_dt)) stop("stage_col must be a column of stage_dt")
  if (nrow(rating_boot_dt) == 0) stop("rating_boot_dt must have at least one row")
  if (!is.numeric(conf_level) || conf_level <= 0 || conf_level >= 1) {
    stop("conf_level must be a number strictly between 0 and 1")
  }

  required <- c("limb", "draw", "lower_level", "upper_level", "C", "a", "n")
  missing <- setdiff(required, names(rating_boot_dt))
  if (length(missing)) {
    stop("apply_rating_interval(): rating_boot_dt is missing column(s): ", paste(missing, collapse = ", "))
  }

  rating_boot_dt <- as.data.table(rating_boot_dt)
  bounds_dt <- unique(rating_boot_dt[, .(limb, lower_level, upper_level)])
  setorder(bounds_dt, lower_level)
  n_limbs <- nrow(bounds_dt)

  out_dt <- copy(as.data.table(stage_dt))
  out_dt[, .row_id := .I]
  stage_vals <- out_dt[[stage_col]]

  breaks <- c(bounds_dt$lower_level[1], bounds_dt$upper_level)
  limb_idx_raw <- findInterval(stage_vals, breaks, rightmost.closed = TRUE)
  extrapolated <- limb_idx_raw == 0L | limb_idx_raw == (n_limbs + 1L)
  limb_idx <- pmin(pmax(limb_idx_raw, 1L), n_limbs)
  out_dt[, .limb := bounds_dt$limb[limb_idx]]
  out_dt[, extrapolated := extrapolated]

  joined_dt <- merge(
    out_dt[, .(.row_id, .limb, .stage_value = get(stage_col))],
    rating_boot_dt[, .(limb, C, a, n)],
    by.x = ".limb", by.y = "limb",
    allow.cartesian = TRUE
  )
  joined_dt[, discharge_draw := fifelse(.stage_value <= a, 0, C * (.stage_value - a)^n)]

  alpha <- 1 - conf_level
  summary_dt <- joined_dt[, .(
    discharge_mean = mean(discharge_draw),
    discharge_median = median(discharge_draw),
    discharge_gse = exp(sd(log(pmax(discharge_draw, .Machine$double.eps)))),
    discharge_lower = quantile(discharge_draw, alpha / 2, names = FALSE),
    discharge_upper = quantile(discharge_draw, 1 - alpha / 2, names = FALSE)
  ), by = .row_id]

  result_dt <- merge(out_dt, summary_dt, by = ".row_id", all.x = TRUE)
  setorder(result_dt, .row_id)
  result_dt[, c(".row_id", ".limb") := NULL]
  result_dt[]
}

#' Apply a versioned rating to a stage time series
#'
#' @description
#' Real ratings shift over time -- bed erosion, deposition, vegetation
#' growth, a channel realignment -- which is exactly why gauging
#' stations get re-rated periodically (Hodson et al. 2024, citing
#' Mansanarez et al. 2019, "Shift Happens!"). [apply_rating()] assumes a
#' single, static rating for an entire stage series; this instead
#' selects, for each stage observation, whichever rating version was in
#' effect at that observation's timestamp, then applies that version's
#' equation -- composing [apply_rating()] once per version rather than
#' reimplementing the discharge calculation.
#'
#' @param stage_dt Data.frame or data.table with a stage column and a
#'   datetime column.
#' @param rating_history_dt Data.table with one row per (version, limb):
#'   `version`, `effective_from`, `effective_to` (both POSIXct or Date;
#'   `effective_to = NA` means "still current", and only the most recent
#'   version may have `NA` here), `lower_level`, `upper_level`, `C`, `a`,
#'   `n`. Version date ranges must not overlap.
#' @param stage_col,datetime_col Character. Column names in `stage_dt`.
#'   Defaults `"stage"`, `"datetime"`.
#' @param out_col Character. Default `"discharge"`.
#'
#' @return `stage_dt` as a data.table with `out_col`, `extrapolated`, and
#'   `version` (which rating version was applied to that row; `NA` if no
#'   version was in effect at that timestamp, in which case `out_col` is
#'   also `NA` for that row and a warning is issued) columns added.
#'
#' @seealso [apply_rating()]
#'
#' @examples
#' rating_history_dt <- data.table::data.table(
#'   version = c("v1", "v2"),
#'   effective_from = as.POSIXct(c("2024-01-01", "2025-06-01"), tz = "UTC"),
#'   effective_to = as.POSIXct(c("2025-06-01", NA), tz = "UTC"),
#'   lower_level = c(0.0, 0.0), upper_level = c(3.0, 3.0),
#'   C = c(3.0, 3.4), a = c(0, 0), n = c(1.6, 1.6)
#' )
#' stage_dt <- data.table::data.table(
#'   datetime = as.POSIXct(c("2024-06-01", "2025-12-01"), tz = "UTC"),
#'   stage = c(1.5, 1.5)
#' )
#' apply_rating_versioned(stage_dt, rating_history_dt)
#'
#' @export
apply_rating_versioned <- function(stage_dt, rating_history_dt,
                                    stage_col = "stage", datetime_col = "datetime",
                                    out_col = "discharge") {
  if (!is.data.frame(stage_dt)) stop("stage_dt must be a data.frame or data.table")
  if (!is.data.frame(rating_history_dt)) stop("rating_history_dt must be a data.frame or data.table")
  if (!stage_col %in% names(stage_dt)) stop("stage_col must be a column of stage_dt")
  if (!datetime_col %in% names(stage_dt)) stop("datetime_col must be a column of stage_dt")

  required <- c("version", "effective_from", "effective_to", "lower_level", "upper_level", "C", "a", "n")
  missing <- setdiff(required, names(rating_history_dt))
  if (length(missing)) {
    stop("apply_rating_versioned(): rating_history_dt is missing column(s): ", paste(missing, collapse = ", "))
  }

  rating_history_dt <- as.data.table(rating_history_dt)
  versions_dt <- unique(rating_history_dt[, .(version, effective_from, effective_to)])
  setorder(versions_dt, effective_from)
  n_versions <- nrow(versions_dt)

  if (n_versions > 1L && any(is.na(versions_dt$effective_to[-n_versions]))) {
    stop("apply_rating_versioned(): only the most recent rating version may have effective_to = NA (open-ended).")
  }
  if (n_versions > 1L) {
    overlap <- any(versions_dt$effective_from[-1] < versions_dt$effective_to[-n_versions])
    if (overlap) {
      stop("apply_rating_versioned(): rating_history_dt has overlapping version date ranges.")
    }
  }

  out_dt <- copy(as.data.table(stage_dt))
  out_dt[, .row_id := .I]
  datetime_vals <- out_dt[[datetime_col]]

  version_for_row <- rep(NA_character_, nrow(out_dt))
  for (v in seq_len(n_versions)) {
    in_effect <- datetime_vals >= versions_dt$effective_from[v] &
      (is.na(versions_dt$effective_to[v]) | datetime_vals < versions_dt$effective_to[v])
    version_for_row[in_effect] <- as.character(versions_dt$version[v])
  }
  out_dt[, version := version_for_row]

  n_no_version <- sum(is.na(out_dt$version))
  if (n_no_version > 0L) {
    warning(sprintf(
      paste(
        "apply_rating_versioned(): %d of %d stage value(s) fall outside every",
        "rating version's effective range; %s set to NA for those rows."
      ),
      n_no_version, nrow(out_dt), out_col
    ))
  }

  result_list <- vector("list", n_versions + 1L)
  for (v in seq_len(n_versions)) {
    ver <- as.character(versions_dt$version[v])
    rows_v_dt <- out_dt[version == ver]
    if (nrow(rows_v_dt) == 0L) next
    rating_v_dt <- rating_history_dt[as.character(version) == ver, .(lower_level, upper_level, C, a, n)]
    rating_v_table <- FlodeRatingTable(table = rating_v_dt)
    result_list[[v]] <- apply_rating(rating_v_table, rows_v_dt, stage_col = stage_col, out_col = out_col)
  }

  no_version_dt <- out_dt[is.na(version)]
  if (nrow(no_version_dt) > 0L) {
    no_version_dt[, (out_col) := NA_real_]
    no_version_dt[, extrapolated := NA]
    result_list[[n_versions + 1L]] <- no_version_dt
  }

  final_dt <- rbindlist(result_list, use.names = TRUE, fill = TRUE)
  setorder(final_dt, .row_id)
  final_dt[, .row_id := NULL]
  final_dt[]
}

#' Invert a rating: convert discharge back to stage
#'
#' @description
#' The other direction from [apply_rating()]: given a discharge series,
#' find the stage that produced it. Within one limb this is safe and
#' closed-form -- `H = a + (Q/C)^(1/n)` -- since [FlodeRatingTable]'s own
#' validator already requires `C > 0` and `n > 0` for every limb, which
#' makes `Q = C(H-a)^n` strictly monotonic increasing over that limb's
#' domain.
#'
#' The real risk is at a junction: if two adjacent limbs' equations don't
#' actually agree at their shared boundary stage (a discharge "gap," the
#' same thing [detect_rc_gaps()] exists to catch), the discharge axis has
#' either an overlap (a query discharge could belong to either limb) or a
#' hole (a query discharge belongs to neither) -- both make the inverse
#' genuinely ambiguous, not just cosmetically imperfect. This function
#' checks every junction directly from the equations (not by discretising
#' first) before doing anything else, using the same `tol_abs`/`tol_rel`
#' combination [detect_rc_gaps()] defaults to, and errors -- rather than
#' guessing -- if any junction is flagged. Close the gap first with
#' [resolve_rc_gaps()], [align_limb_equations()], [align_limb_boundaries()],
#' or [graft_rating()], as appropriate.
#'
#' `discharge <= 0` has no unique inverse (any `H <= a` gives `Q = 0`):
#' `out_col` is `NA` for those rows, with a warning, rather than guessing
#' a boundary convention.
#'
#' This function assumes a genuinely monotonic power-law rating --
#' guaranteed within a single limb, and across limbs once the junction
#' check above passes. It is **not valid for tidal or strongly
#' backwater-affected stations**, where the true stage-discharge
#' relationship is not single-valued at all; no data available from a
#' table alone can detect that condition, so this is a documented
#' limitation, not a runtime check. Uncertainty propagation through the
#' inverse (via the local derivative `dH/dQ = 1/(C n (H-a)^{n-1})`) is
#' not included in this first version.
#'
#' @param fit A [FlodeRating] or [FlodeRatingTable]. A `FlodeRating` is
#'   bridged via [as_rating_table()] first, the same one-line pattern
#'   [align_limb_equations()]/[graft_rating()] already use.
#' @param discharge_dt Data.frame or data.table with a discharge column
#'   (named by `discharge_col`, default `"discharge"`); any other columns
#'   are carried through unchanged.
#' @param discharge_col,out_col Character. Column names for the input
#'   discharge and the output stage. Defaults `"discharge"`/`"stage"`.
#' @param tol_abs,tol_rel Numeric. The same junction-gap tolerance
#'   combination [detect_rc_gaps()] defaults to (`0.5`, `0.02`) -- a
#'   junction is flagged if the discharge mismatch there exceeds *either*
#'   the absolute or the relative tolerance.
#'
#' @return `discharge_dt` as a data.table with two columns added:
#'   `out_col` (the inverted stage; `NA` where `discharge <= 0`) and
#'   `extrapolated` (logical; `TRUE` where the discharge fell outside
#'   every limb's own range and was extrapolated from the nearest one;
#'   `NA` where `discharge <= 0`, since no lookup was attempted there).
#'
#' @seealso [apply_rating()] for the forward direction; [detect_rc_gaps()]
#'   for the same junction check with more diagnostic detail.
#'
#' @examples
#' # C on the upper limb (2.410481) is chosen so the two equations agree
#' # exactly at their shared boundary stage (1.2) -- a genuinely gap-free
#' # table, the precondition this function checks for.
#' rating_dt <- data.table::data.table(
#'   lower_level = c(0.0, 1.2), upper_level = c(1.2, 2.5),
#'   C = c(2.5, 2.410481), a = c(0, 0), n = c(1.5, 1.7)
#' )
#' rating_table <- FlodeRatingTable(table = rating_dt)
#' discharge_dt <- data.table::data.table(discharge = c(1.0, 5.0, 20.0))
#' apply_rating_inverse(rating_table, discharge_dt)
#'
#' @export
apply_rating_inverse <- function(fit, discharge_dt, discharge_col = "discharge", out_col = "stage",
                                  tol_abs = 0.5, tol_rel = 0.02) {
  if (S7_inherits(fit, FlodeRating)) fit <- as_rating_table(fit)
  if (!S7_inherits(fit, FlodeRatingTable)) stop("apply_rating_inverse(): fit must be a FlodeRating or FlodeRatingTable")
  if (!is.data.frame(discharge_dt)) stop("discharge_dt must be a data.frame or data.table")
  if (!discharge_col %in% names(discharge_dt)) stop("discharge_col must be a column of discharge_dt")

  rating_dt <- copy(fit@table)
  setorder(rating_dt, lower_level)
  n_limbs <- nrow(rating_dt)

  if (n_limbs > 1L) {
    contiguous <- all(abs(rating_dt$upper_level[-n_limbs] - rating_dt$lower_level[-1L]) < 1e-8)
    if (!contiguous) {
      stop("apply_rating_inverse(): limbs in fit@table must be contiguous (upper_level[i] == lower_level[i+1]).")
    }
  }

  eval_q <- function(C, a, n, H) C * (H - a)^n

  # Junction gap check, computed directly from the equations at their
  # exact shared boundary stage -- not via expand_rating_table()'s
  # discretisation, so there's no step-size approximation to worry about.
  if (n_limbs > 1L) {
    flagged_junctions <- integer(0)
    for (j in seq_len(n_limbs - 1L)) {
      brk <- rating_dt$upper_level[j]
      q_low <- eval_q(rating_dt$C[j], rating_dt$a[j], rating_dt$n[j], brk)
      q_high <- eval_q(rating_dt$C[j + 1L], rating_dt$a[j + 1L], rating_dt$n[j + 1L], brk)
      gap_abs <- q_high - q_low
      gap_rel <- if (abs(q_low) > 1e-9) gap_abs / q_low else NA_real_
      if (abs(gap_abs) > tol_abs || (!is.na(gap_rel) && abs(gap_rel) > tol_rel)) {
        flagged_junctions <- c(flagged_junctions, j)
      }
    }
    if (length(flagged_junctions) > 0L) {
      stop(sprintf(
        paste(
          "apply_rating_inverse(): junction(s) %s have a discharge gap at their shared",
          "boundary stage -- the inverse is ambiguous there (an overlapping or missing",
          "discharge range between adjacent limbs). Close the gap first with",
          "detect_rc_gaps()/resolve_rc_gaps(), align_limb_equations(),",
          "align_limb_boundaries(), or graft_rating()."
        ),
        paste(flagged_junctions, collapse = ", ")
      ))
    }
  }

  # The discharge-axis equivalent of apply_rating()'s stage-axis breaks --
  # each limb's own equation evaluated at its own bounds, monotonic
  # increasing across limbs since the junction check above just confirmed
  # adjacent limbs' ranges connect rather than overlap or gap.
  q_lo <- eval_q(rating_dt$C, rating_dt$a, rating_dt$n, rating_dt$lower_level)
  q_hi <- eval_q(rating_dt$C, rating_dt$a, rating_dt$n, rating_dt$upper_level)
  q_breaks <- c(q_lo[1], q_hi)

  out_dt <- copy(as.data.table(discharge_dt))
  discharge_vals <- out_dt[[discharge_col]]

  stage <- rep(NA_real_, nrow(out_dt))
  extrapolated <- rep(NA, nrow(out_dt))

  non_positive <- !is.na(discharge_vals) & discharge_vals <= 0
  if (any(non_positive)) {
    warning(sprintf(
      paste(
        "apply_rating_inverse(): %d discharge value(s) <= 0 have no unique inverse stage",
        "(any H <= a gives Q = 0); %s set to NA for those rows."
      ),
      sum(non_positive), out_col
    ))
  }

  valid_idx <- !is.na(discharge_vals) & discharge_vals > 0
  if (any(valid_idx)) {
    q_valid <- discharge_vals[valid_idx]
    limb_idx_raw <- findInterval(q_valid, q_breaks, rightmost.closed = TRUE)
    extrap_valid <- limb_idx_raw == 0L | limb_idx_raw == (n_limbs + 1L)
    limb_idx <- pmin(pmax(limb_idx_raw, 1L), n_limbs)

    C <- rating_dt$C[limb_idx]
    a <- rating_dt$a[limb_idx]
    n <- rating_dt$n[limb_idx]

    stage[valid_idx] <- a + (q_valid / C)^(1 / n)
    extrapolated[valid_idx] <- extrap_valid
  }

  set(out_dt, j = out_col, value = stage)
  set(out_dt, j = "extrapolated", value = extrapolated)

  n_extrap <- sum(extrapolated, na.rm = TRUE)
  if (n_extrap > 0L) {
    log_info(
      "apply_rating_inverse(): {n_extrap} of {nrow(out_dt)} discharge value(s) fell outside the rating and were extrapolated."
    )
  }

  out_dt[]
}
