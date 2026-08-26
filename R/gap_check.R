# ============================================================ #
# Tool:         gap_check
# Description:  Detect and resolve discharge discontinuities ("gaps")
#               between independently-fitted rating-curve limbs, and plot
#               the before/after comparison
# Author:       Jonathan Payne
# Created:      2025-01-01
# Modified:     2026-08-18 - JP: restyled to R Tool Governance v1.3.
#               Converted data.frame internals to data.table (DT[i,j,by],
#               update by reference with set()/:=). Replaced message()
#               with logger::log_info(). Added if()/stop() input
#               validation. Function/argument names already snake_case;
#               unchanged.
# Modified:     2026-08-18 - JP: added align_limb_equations(). resolve_rc_
#               gaps() only patches the discretised table, so the fix does
#               not survive re-expansion or direct equation evaluation.
#               align_limb_equations() corrects the C coefficient itself,
#               propagating outward from an anchor limb so every junction
#               matches exactly; A and B are untouched and the original C
#               is kept alongside the corrected value for audit purposes.
# Modified:     2026-08-19 - JP: expand_rating_table() used tail(h, 1L)
#               to get the last element of a numeric vector -- tail() is
#               a utils function, not base, and was unresolvable inside
#               this module's namespace. Replaced with h[length(h)]
#               rather than adding a utils import for one call site.
# Modified:     2026-08-19 - JP: added .datatable.aware <- TRUE (see
#               rate_optimise.R's changelog for the full explanation).
# Modified:     2026-08-19 - JP: cross-referenced align_limb_equations()
#               to rate_optimise_constrained() (rate_optimise.R), which
#               genuinely refits against raw gaugings under a junction
#               constraint rather than this function's C-only rescale of
#               already-fitted equations.
# Modified:     2026-08-19 - JP: fixed a confirmed bug found by an
#               external review: resolve_rc_gaps()'s "interpolate"
#               method was never actually interpolating. Its bridge
#               helper (.interp_y, now removed) was always evaluated at
#               one of its own defining endpoints, which trivially
#               returns that endpoint's value unchanged -- the method
#               was computing a plain average of the two original
#               endpoint discharges the whole time, using no interior
#               point from either limb despite the name. Renamed to
#               "midpoint" to describe what it actually does (breaking
#               change: "interpolate" is no longer a valid method value).
#               Also fixed detect_rc_gaps() relying on unique() for limb
#               order, which reflects first-occurrence-in-the-data order
#               rather than stage order -- now sorts by each limb's own
#               minimum stage explicitly. align_limb_equations() gained
#               scale_factor/pct_change/alignment_stage/target_discharge
#               provenance columns and an explicit guard against a
#               non-finite or non-positive depth or result at the
#               junction (previously this could silently produce NaN/Inf
#               rather than erroring).
# Modified:     2026-08-19 - JP: detect_rc_gaps() previously assumed the
#               lower limb's last stage always equals the upper limb's
#               first stage -- true for a table from
#               expand_rating_table()'s contiguous limbs, not guaranteed
#               for an arbitrary rc_dt. Added stage_tol and a
#               junction_type column (shared_stage/stage_gap/
#               stage_overlap); a discharge "gap" computed across two
#               different stages is not comparable to one computed at a
#               genuinely shared stage, so gap_abs/gap_rel are now NA
#               for the latter two cases rather than a misleading
#               number. resolve_rc_gaps() now skips (with a warning)
#               any junction that isn't a genuine shared-stage
#               discontinuity, since averaging or snapping endpoints
#               only makes sense when both limbs are evaluated at the
#               same stage. plot_rc_gaps()'s junction labels now show
#               "stage gap"/"stage overlap" for those cases instead of a
#               bare "\u0394Q = NA".
# Modified:     2026-08-19 - JP: converted align_limb_equations() to
#               return a FlodeRatingTable (flode_classes.R) with a
#               genuine audit chain (@status/@previous referencing the
#               exact pre-alignment object) instead of a mutated table
#               with an attribute someone had to remember to check.
#               Accepts a FlodeRatingTable or a plain table. Neither the
#               input nor the output is ever mutated in place.
#               expand_rating_table() now also accepts a
#               FlodeRatingTable directly (unwrapped at the top),
#               alongside the existing plain data.frame/data.table path.
#               detect_rc_gaps()/resolve_rc_gaps()/plot_rc_gaps() are
#               unchanged -- they operate on the discretised stage-
#               discharge table expand_rating_table() produces, which
#               stays a plain data.table by design (a materialised view
#               for plotting/gap-checking, not a fitted-parameter object
#               with its own audit-trail concerns).
# Tier:         3
# Inputs:       rating equation tables and stage-discharge data.tables
#               (see individual function docs)
# Outputs:      data.tables of gap reports, corrected rating curves, and
#               aligned rating equations; plot_rc_gaps() also produces a
#               ggplot2 figure
# Dependencies: data.table, ggplot2, logger
# Modified:     2026-08-25 - JP: converted from a box module to a package
#               R/ file. Imports are now package-level
#               (R/reach.rate-package.R); FlodeRatingTable
#               (flode_classes.R) needs no import at all -- same package
#               namespace.
# ============================================================ #

log_threshold(INFO)

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

#' Auto-detect rating-curve limbs from discharge monotonicity breaks
#'
#' Assigns an integer limb ID to each row. A new limb is started whenever
#' discharge drops by more than \code{tol_frac} of the previous value,
#' indicating an independently-fitted segment beginning below the prior end.
#'
#' @param q Numeric vector of discharge values (stage-ascending order).
#' @param tol_frac Fractional drop threshold that triggers a new limb
#' (default \code{0.05}, i.e. a 5% fall in Q).
#' @return Integer vector of limb IDs, same length as \code{q}.
#' @keywords internal
#' @noRd
.auto_limb <- function(q, tol_frac = 0.05) {
  n <- length(q)
  limb <- integer(n)
  limb[1L] <- 1L
  k <- 1L
  for (i in seq(2L, n)) {
    ref <- max(abs(q[i - 1L]), 1e-9)
    if ((q[i - 1L] - q[i]) / ref > tol_frac) {
      k <- k + 1L
    }
    limb[i] <- k
  }
  limb
}

# ---------------------------------------------------------------------------
# expand_rating_table()
# ---------------------------------------------------------------------------

#' Expand a rating equation table into a stage-discharge data.table
#'
#' @description
#' Evaluates the rating equation \eqn{Q = C \cdot (h - a)^b} for every limb
#' defined in a rating table and returns a single stage-discharge
#' \code{data.table} ready for use with \code{\link{detect_rc_gaps}},
#' \code{\link{resolve_rc_gaps}}, and \code{\link{plot_rc_gaps}}.
#'
#' Each limb is defined by a row in \code{rating_dt} containing a lower and
#' upper stage bound, the three equation parameters (C, A, B), and an
#' optional \emph{doubtful} flag (commonly set for upper limbs derived from
#' flood-frequency estimates rather than direct gauging).
#'
#' @param rating_dt A data.frame or data.table with one row per limb. Must
#'   contain the columns named by \code{lower_col}, \code{upper_col},
#'   \code{c_col}, \code{a_col}, and \code{b_col}. An optional doubtful flag
#'   column named by \code{doubtful_col} is carried through to the output
#'   if present.
#' @param step Numeric. Stage increment for generating evaluation points
#'   within each limb (default \code{0.01}). The upper bound of each limb
#'   is always included regardless of rounding.
#' @param max_stage Numeric or \code{NULL}. Upper bound applied to every
#'   limb before generating stage sequences. Useful when the last limb uses
#'   a sentinel value such as \code{999} to indicate an open-ended upper
#'   limit. When \code{NULL} (default) the raw \code{upper_col} values are
#'   used unchanged. A warning is issued for any limb whose upper level
#'   exceeds \code{max_stage}.
#' @param lower_col,upper_col Character. Column names for the lower and
#'   upper stage limits of each limb (defaults \code{"lower_level"} and
#'   \code{"upper_level"}).
#' @param c_col,a_col,b_col Character. Column names for the equation
#'   parameters C (multiplier), A (offset / zero-flow level), and B
#'   (exponent). Defaults \code{"C"}, \code{"A"}, \code{"B"}.
#' @param doubtful_col Character. Column name for the doubtful flag
#'   (default \code{"doubtful"}). Ignored if the column is absent from
#'   \code{rating_dt}.
#'
#' @return A \code{data.table} with columns:
#'   \describe{
#'     \item{stage}{Stage values at which Q was evaluated.}
#'     \item{discharge}{Computed discharge (m\eqn{^3}/s). Stages at or
#'       below the zero-flow offset \code{A} are returned as \code{0}.}
#'     \item{limb}{Integer limb ID (row index of \code{rating_dt}).}
#'     \item{doubtful}{Logical flag carried from \code{rating_dt} (only
#'       present when \code{doubtful_col} exists in \code{rating_dt}).}
#'   }
#'
#' @details
#' The breakpoint stage shared between two adjacent limbs (the upper limit
#' of limb \eqn{n} equals the lower limit of limb \eqn{n+1}) is included in
#' \emph{both} limbs. This lets \code{detect_rc_gaps()} compare the end
#' discharge of the lower limb against the start discharge of the upper
#' limb at the exact same stage, which is where gaps are most visible.
#'
#' Because each limb is fitted independently, the discharge values at a
#' shared breakpoint stage will generally differ -- that difference is the
#' gap that \code{detect_rc_gaps()} measures and \code{resolve_rc_gaps()}
#' corrects.
#'
#' @seealso \code{\link{detect_rc_gaps}}, \code{\link{resolve_rc_gaps}},
#'   \code{\link{plot_rc_gaps}}
#'
#' @examples
#' # Three-limb rating with independent C/A/B parameters.
#' rating_dt <- data.table::data.table(
#'   lower_level = c(0.0, 1.2, 2.5),
#'   upper_level = c(1.2, 2.5, 4.0),
#'   C = c(2.5, 4.1, 7.8),
#'   A = c(0.0, 0.0, 0.0),
#'   B = c(1.50, 1.70, 2.00),
#'   doubtful = c(FALSE, FALSE, TRUE)
#' )
#' rc_dt <- expand_rating_table(rating_dt)
#' gaps_dt <- detect_rc_gaps(rc_dt)
#' rc_fixed_dt <- resolve_rc_gaps(rc_dt)
#'
#' @export
expand_rating_table <- function(rating_dt,
                                 step = 0.01,
                                 max_stage = NULL,
                                 lower_col = "lower_level",
                                 upper_col = "upper_level",
                                 c_col = "C",
                                 a_col = "A",
                                 b_col = "B",
                                 doubtful_col = "doubtful") {
  # Accepts either a FlodeRatingTable (unwrapped here) or a plain
  # data.frame/data.table directly, so this still works for a legacy
  # rating imported from elsewhere with no FlodeRatingTable identity.
  if (S7_inherits(rating_dt, FlodeRatingTable)) rating_dt <- rating_dt@table
  if (!is.data.frame(rating_dt)) stop("rating_dt must be a FlodeRatingTable, data.frame, or data.table")
  if (!is.numeric(step) || step <= 0) stop("step must be a positive number")

  rating_dt <- as.data.table(rating_dt)
  required <- c(lower_col, upper_col, c_col, a_col, b_col)
  missing <- setdiff(required, names(rating_dt))
  if (length(missing)) {
    stop("expand_rating_table(): missing column(s): ", paste(missing, collapse = ", "))
  }

  has_doubtful <- doubtful_col %in% names(rating_dt)
  rows <- vector("list", nrow(rating_dt))

  for (i in seq_len(nrow(rating_dt))) {
    lo <- rating_dt[[lower_col]][i]
    hi <- rating_dt[[upper_col]][i]
    C <- rating_dt[[c_col]][i]
    A <- rating_dt[[a_col]][i]
    B <- rating_dt[[b_col]][i]

    if (!is.null(max_stage) && hi > max_stage) {
      warning(sprintf(
        "expand_rating_table(): limb %d upper level (%.4g) exceeds max_stage (%.4g); capped.",
        i, hi, max_stage
      ))
      hi <- max_stage
    }

    h <- seq(lo, hi, by = step)
    if (abs(h[length(h)] - hi) > .Machine$double.eps * 100) h <- c(h, hi)

    depth <- h - A
    Q <- fifelse(depth <= 0, 0, C * depth^B)

    limb_dt <- data.table(stage = h, discharge = Q, limb = i)
    if (has_doubtful) limb_dt[, doubtful := rating_dt[[doubtful_col]][i]]
    rows[[i]] <- limb_dt
  }

  rbindlist(rows)
}

# ---------------------------------------------------------------------------
# align_limb_equations()
# ---------------------------------------------------------------------------

#' Align rating-curve limb equations so junctions match exactly
#'
#' @description
#' `resolve_rc_gaps()` only patches the discretised stage-discharge table
#' produced by [expand_rating_table()]. That fix does not survive
#' re-expanding the same rating equations, or evaluating them directly --
#' the underlying `C`/`A`/`B` triples are untouched, so the gap reappears.
#'
#' `align_limb_equations()` corrects the equations themselves instead. It
#' rescales the `C` coefficient of every limb except one fixed anchor,
#' propagating outward limb by limb: each limb's `C` is set so that its
#' discharge at the junction with its \emph{already-corrected} neighbour
#' matches exactly. `A` and `B` are left untouched, so each limb keeps its
#' fitted shape and zero-flow datum; only the scale changes.
#'
#' Because each limb is anchored on one junction and its other junction is
#' resolved by correcting the \emph{next} limb along the chain, an interior
#' limb with gaps on both sides is handled without needing a stage-
#' dependent taper -- every junction in the chain ends up exact.
#'
#' The original `C` is always kept (as `C_original`) alongside the
#' corrected value, and an `aligned` flag marks which limbs were changed,
#' so the amendment is auditable rather than a silent overwrite.
#'
#' @param rating_dt A [FlodeRatingTable], or a plain data.frame/
#'   data.table with columns `lower_level`, `upper_level`, `C`, `A`, `B`
#'   (the same shape expected by [expand_rating_table()]; for a legacy
#'   rating with no prior `FlodeRatingTable` identity of its own). Limbs
#'   must be contiguous: `upper_level[i]` must equal `lower_level[i + 1]`.
#' @param anchor_limb Integer. Row index of the limb held fixed; every
#'   other limb is corrected relative to it, propagating outward in both
#'   directions along the chain. Default `1L` (the lowest limb, typically
#'   the best-gauged one).
#' @param on_align_failure Character. What to do when a limb's own fixed
#'   `A` (zero-flow datum) sits at or beyond the junction stage it would
#'   need to align to -- `depth = junction_stage - A` non-positive, so
#'   no real-valued `C` solves `C * depth^B = target` -- or the solved
#'   `C` comes out non-finite or non-positive. This is a real
#'   possibility whenever gaugings (and so `A`) can be negative, not a
#'   sign of malformed input: independently-fitted limbs can end up with
#'   a datum that just doesn't reach a neighbour's junction. `"error"`
#'   (default) stops immediately, as before. `"skip"` warns, leaves that
#'   limb's `C` at its original (unaligned) value, flags it in the new
#'   `align_failed` column, and continues aligning the rest of the chain
#'   from there -- the same "keep what worked, don't discard everything
#'   over one bad limb" fallback `rate_optimise_constrained()` already
#'   uses for its own refit failures.
#'
#' @return A [FlodeRatingTable] with `@status` `"post_fit_aligned"` and
#'   `@previous` referencing the exact pre-alignment object this was
#'   built from (`NULL` if `rating_dt` was a plain table with no prior
#'   `FlodeRatingTable` identity) -- a genuine audit chain, not an
#'   attribute someone has to remember to check. `@table` gains columns:
#'   `C_original` (the input `C`, unchanged), `aligned` (logical; `TRUE`
#'   only for a limb that was actually rescaled -- `FALSE` for
#'   `anchor_limb` and, under `on_align_failure = "skip"`, for any limb
#'   that failed to align), `align_failed` (logical; `TRUE` for a
#'   skipped limb, always `FALSE` under the default `on_align_failure =
#'   "error"` since that stops instead), `scale_factor`
#'   (`C / C_original`), `pct_change` (percentage change in `C`),
#'   `alignment_stage` (the junction stage this limb was aligned at),
#'   and `target_discharge` (the discharge it was aligned to match). The
#'   last four are `NA` wherever `aligned` is `FALSE`. `C` itself is
#'   replaced by the aligned value for every successfully-aligned limb;
#'   `A` and `B` are always unchanged. Neither the input nor the output
#'   is ever mutated in place.
#'
#' @seealso [expand_rating_table()], [resolve_rc_gaps()],
#'   `rate_optimise_constrained()` (in the `rate_optimise` module) for a
#'   genuine constrained refit against the raw gaugings, rather than this
#'   function's closed-form C-only rescale of the already-fitted
#'   equations -- use that instead when the raw gaugings are available;
#'   this remains useful when only the fitted equations are (an imported
#'   legacy rating, for instance)
#'
#' @examples
#' rating_dt <- data.table::data.table(
#'   lower_level = c(0.0, 1.2, 2.5),
#'   upper_level = c(1.2, 2.5, 4.0),
#'   C = c(2.5, 4.1, 7.8),
#'   A = c(0.0, 0.0, 0.0),
#'   B = c(1.50, 1.70, 2.00)
#' )
#' aligned_result <- align_limb_equations(rating_dt)
#' aligned_result
#' aligned_result@status
#'
#' # The aligned equations, re-expanded, have no junction gaps left --
#' # expand_rating_table() accepts the FlodeRatingTable directly
#' rc_dt <- expand_rating_table(aligned_result)
#' gaps_dt <- detect_rc_gaps(rc_dt)
#' any(gaps_dt$gap_flagged)
#'
#' @export
align_limb_equations <- function(rating_dt, anchor_limb = 1L,
                                  on_align_failure = c("error", "skip")) {
  on_align_failure <- match.arg(on_align_failure)
  input_was_flode_table <- S7_inherits(rating_dt, FlodeRatingTable)
  previous_table <- if (input_was_flode_table) rating_dt else NULL
  if (input_was_flode_table) rating_dt <- rating_dt@table

  if (!is.data.frame(rating_dt)) stop("rating_dt must be a FlodeRatingTable, data.frame, or data.table")
  if (nrow(rating_dt) == 0) stop("rating_dt must have at least one row")
  if (anchor_limb < 1L || anchor_limb > nrow(rating_dt)) {
    stop("anchor_limb must be a valid row index of rating_dt")
  }

  required <- c("lower_level", "upper_level", "C", "A", "B")
  missing <- setdiff(required, names(rating_dt))
  if (length(missing)) {
    stop("align_limb_equations(): missing column(s): ", paste(missing, collapse = ", "))
  }

  out_dt <- copy(as.data.table(rating_dt))
  n <- nrow(out_dt)

  if (n > 1L) {
    contiguous <- all(abs(out_dt$upper_level[-n] - out_dt$lower_level[-1L]) < 1e-8)
    if (!contiguous) {
      stop("align_limb_equations(): limbs must be contiguous (upper_level[i] == lower_level[i+1]).")
    }
  }

  out_dt[, `:=`(
    C_original = C,
    aligned = FALSE,
    align_failed = FALSE,
    scale_factor = NA_real_,
    pct_change = NA_real_,
    alignment_stage = NA_real_,
    target_discharge = NA_real_
  )]

  eval_q <- function(stage, C, A, B) C * (stage - A)^B

  # On failure, either stop() (on_align_failure = "error", the default --
  # unchanged behaviour) or warn() and leave this limb's C at its
  # original, unaligned value (on_align_failure = "skip"). Either way the
  # *next* limb in the chain is unaffected: it reads out_dt$C[i] fresh
  # when its own turn comes, so a skipped limb just means the chain
  # continues from that limb's original equation instead of a rescaled
  # one -- the same "keep what worked" fallback
  # rate_optimise_constrained() uses for a refit that fails to converge.
  fail_or_skip <- function(i, msg) {
    if (on_align_failure == "error") stop(msg)
    warning(msg, ' Leaving this limb\'s original C unaligned (on_align_failure = "skip").')
    set(out_dt, i = i, j = "align_failed", value = TRUE)
  }

  align_one <- function(i, s_brk, q_target) {
    depth <- s_brk - out_dt$A[i]
    if (!is.finite(depth) || depth <= 0) {
      fail_or_skip(i, sprintf(
        "align_limb_equations(): limb at row %d has an invalid depth (stage - A = %.6g) at the junction stage %.6g; cannot align.",
        i, depth, s_brk
      ))
      return(invisible(NULL))
    }
    c_original <- out_dt$C[i]
    c_new <- q_target / depth^out_dt$B[i]
    if (!is.finite(c_new) || c_new <= 0) {
      fail_or_skip(i, sprintf(
        "align_limb_equations(): limb at row %d produced a non-finite or non-positive aligned C; cannot align.",
        i
      ))
      return(invisible(NULL))
    }
    set(out_dt, i = i, j = "C", value = c_new)
    set(out_dt, i = i, j = "aligned", value = TRUE)
    set(out_dt, i = i, j = "scale_factor", value = c_new / c_original)
    set(out_dt, i = i, j = "pct_change", value = 100 * (c_new - c_original) / c_original)
    set(out_dt, i = i, j = "alignment_stage", value = s_brk)
    set(out_dt, i = i, j = "target_discharge", value = q_target)
  }

  # Propagate upward: anchor_limb + 1 .. n, each limb matched to the
  # already-finalised limb below it
  if (anchor_limb < n) {
    for (i in seq(anchor_limb + 1L, n)) {
      s_brk <- out_dt$lower_level[i]
      q_target <- eval_q(s_brk, out_dt$C[i - 1L], out_dt$A[i - 1L], out_dt$B[i - 1L])
      align_one(i, s_brk, q_target)
    }
  }

  # Propagate downward: anchor_limb - 1 .. 1, each limb matched to the
  # already-finalised limb above it
  if (anchor_limb > 1L) {
    for (i in seq(anchor_limb - 1L, 1L)) {
      s_brk <- out_dt$upper_level[i]
      q_target <- eval_q(s_brk, out_dt$C[i + 1L], out_dt$A[i + 1L], out_dt$B[i + 1L])
      align_one(i, s_brk, q_target)
    }
  }

  # An actual audit chain rather than an attribute someone has to
  # remember to check: `previous` references the exact pre-alignment
  # FlodeRatingTable this was built from (NULL if the input was a plain
  # data.table with no prior identity of its own), and `status` says
  # what happened without needing to inspect the `aligned` column to
  # find out. Neither out_dt nor previous_table is ever mutated in
  # place -- align_limb_equations() always returns a new object.
  FlodeRatingTable(
    table = out_dt[],
    status = "post_fit_aligned",
    previous = previous_table
  )
}

# ---------------------------------------------------------------------------
# align_limb_boundaries()
# ---------------------------------------------------------------------------

# Solve C1*(H-A1)^B1 = C2*(H-A2)^B2 for H within [search_lo, search_hi],
# or NA_real_ if no crossing is found there (curves don't cross in range,
# or the interval doesn't bracket a sign change of the difference).
#' @keywords internal
#' @noRd
.find_intersection_stage <- function(C1, A1, B1, C2, A2, B2, search_lo, search_hi) {
  f <- function(H) C1 * (H - A1)^B1 - C2 * (H - A2)^B2
  f_lo <- tryCatch(f(search_lo), error = function(e) NA_real_)
  f_hi <- tryCatch(f(search_hi), error = function(e) NA_real_)
  if (!is.finite(f_lo) || !is.finite(f_hi) || sign(f_lo) == sign(f_hi)) {
    return(NA_real_)
  }
  # uniroot()'s default tol (~1.2e-4) is loose enough that, on a steep
  # curve, the discharge values at the "found" root can visibly disagree
  # -- tighten it so the two curves genuinely agree at the stage returned.
  tryCatch(
    uniroot(f, lower = search_lo, upper = search_hi, tol = .Machine$double.eps^0.5)$root,
    error = function(e) NA_real_
  )
}

#' Relocate a junction to where two limb equations actually cross
#'
#' @description
#' `align_limb_equations()` and `resolve_rc_gaps()` both close a junction
#' gap by changing a \emph{value} (a rescaled `C`, or a patched discharge)
#' at a \emph{fixed} junction stage. `align_limb_boundaries()` does the
#' opposite: it leaves every limb's `C`/`A`/`B` completely untouched, and
#' instead moves the junction stage itself to wherever the two limbs'
#' curves genuinely cross -- the stage `H` solving `C_lower*(H-A_lower)^
#' B_lower = C_upper*(H-A_upper)^B_upper`. At that stage the two unchanged
#' curves already agree, so nothing about either equation needs to change.
#'
#' Unlike `align_limb_equations()`'s rescale (which needs a fixed anchor
#' limb and propagates outward, since rescaling one limb changes the
#' reference point for the next), boundary relocation has no such
#' dependency: because no equation is ever changed, junction `i`'s
#' crossing depends only on limbs `i` and `i + 1`, regardless of what
#' happens at any other junction. Every junction is resolved
#' independently -- there is no `anchor_limb` argument.
#'
#' The search for a crossing is bounded to the union of the two limbs'
#' own existing stage ranges (never extrapolated further than either limb
#' was actually fitted over), and above both limbs' zero-flow stage so
#' `(H - A)^B` stays real-valued. When no crossing exists in that range --
#' the curves may not cross at all, or only outside where either was
#' fitted -- that junction is left unchanged and a warning is issued
#' rather than the whole call failing.
#'
#' @param rating_dt A [FlodeRatingTable], or a plain data.frame/
#'   data.table with columns `lower_level`, `upper_level`, `C`, `A`, `B`
#'   (the same shape expected by [expand_rating_table()] and
#'   [align_limb_equations()]). Limbs must be contiguous: `upper_level[i]`
#'   must equal `lower_level[i + 1]`.
#'
#' @return A [FlodeRatingTable] with `@status` `"post_fit_aligned"` and
#'   `@previous` referencing the exact pre-alignment object this was
#'   built from (`NULL` if `rating_dt` was a plain table with no prior
#'   `FlodeRatingTable` identity). `@table` gains columns:
#'   `lower_level_original`/`upper_level_original` (the input boundaries,
#'   unchanged) and `boundary_adjusted` (logical; `TRUE` for a limb whose
#'   `lower_level` and/or `upper_level` actually moved). `C`, `A`, and `B`
#'   are always unchanged -- only `lower_level`/`upper_level` are ever
#'   modified. Neither the input nor the output is ever mutated in place.
#'
#' @seealso [align_limb_equations()] for closing a junction by rescaling
#'   `C` at a fixed stage instead of moving the stage; [resolve_rc_gaps()]
#'   for the discretised-table-only equivalent; [expand_rating_table()]
#'
#' @examples
#' # A small, realistic gap at the breakpoint (limb 2 reads ~5% high there)
#' rating_dt <- data.table::data.table(
#'   lower_level = c(0.0, 1.2),
#'   upper_level = c(1.2, 4.0),
#'   C = c(2.5, 2.554),
#'   A = c(0.0, 0.0),
#'   B = c(1.50, 1.65)
#' )
#' relocated_result <- align_limb_boundaries(rating_dt)
#' relocated_result@table[, .(lower_level, upper_level, boundary_adjusted)]
#'
#' @export
align_limb_boundaries <- function(rating_dt) {
  input_was_flode_table <- S7_inherits(rating_dt, FlodeRatingTable)
  previous_table <- if (input_was_flode_table) rating_dt else NULL
  if (input_was_flode_table) rating_dt <- rating_dt@table

  if (!is.data.frame(rating_dt)) stop("rating_dt must be a FlodeRatingTable, data.frame, or data.table")
  if (nrow(rating_dt) == 0) stop("rating_dt must have at least one row")

  required <- c("lower_level", "upper_level", "C", "A", "B")
  missing <- setdiff(required, names(rating_dt))
  if (length(missing)) {
    stop("align_limb_boundaries(): missing column(s): ", paste(missing, collapse = ", "))
  }

  out_dt <- copy(as.data.table(rating_dt))
  n <- nrow(out_dt)

  if (n > 1L) {
    contiguous <- all(abs(out_dt$upper_level[-n] - out_dt$lower_level[-1L]) < 1e-8)
    if (!contiguous) {
      stop("align_limb_boundaries(): limbs must be contiguous (upper_level[i] == lower_level[i+1]).")
    }
  }

  out_dt[, `:=`(
    lower_level_original = lower_level,
    upper_level_original = upper_level,
    boundary_adjusted = FALSE
  )]

  if (n > 1L) {
    for (i in seq_len(n - 1L)) {
      j <- i + 1L
      # Union of the two limbs' own ranges is [lower_level[i], upper_level[j]]:
      # contiguity guarantees lower_level[i] < lower_level[j] == the current
      # junction and upper_level[i] == lower_level[j] < upper_level[j], so
      # the lower/upper limb's own bound is already the extreme in each
      # direction -- no min()/max() needed across the pair for the range
      # itself, only for the zero-flow floor.
      search_lo <- max(out_dt$A[i], out_dt$A[j], out_dt$lower_level[i]) + 1e-6
      search_hi <- out_dt$upper_level[j]

      if (!is.finite(search_lo) || !is.finite(search_hi) || search_lo >= search_hi) {
        warning(sprintf(
          paste(
            "align_limb_boundaries(): junction between limb %d and %d has no",
            "valid search range for an intersection (both curves must be",
            "above their zero-flow stage); leaving this junction's boundary",
            "unchanged."
          ),
          i, j
        ), call. = FALSE)
        next
      }

      h_star <- .find_intersection_stage(
        out_dt$C[i], out_dt$A[i], out_dt$B[i],
        out_dt$C[j], out_dt$A[j], out_dt$B[j],
        search_lo, search_hi
      )

      if (is.na(h_star)) {
        warning(sprintf(
          paste(
            "align_limb_boundaries(): limb %d and %d's curves do not cross",
            "within [%.4g, %.4g]; leaving this junction's boundary unchanged."
          ),
          i, j, search_lo, search_hi
        ), call. = FALSE)
        next
      }

      set(out_dt, i = i, j = "upper_level", value = h_star)
      set(out_dt, i = j, j = "lower_level", value = h_star)
      set(out_dt, i = i, j = "boundary_adjusted", value = TRUE)
      set(out_dt, i = j, j = "boundary_adjusted", value = TRUE)
    }
  }

  # Defensive: two adjacent relocations landing in the wrong order would
  # otherwise silently produce a table that violates FlodeRatingTable's
  # own contiguity validator, or worse, one with a collapsed/inverted
  # limb range that happens to still pass it.
  if (any(out_dt$upper_level <= out_dt$lower_level)) {
    stop(paste(
      "align_limb_boundaries(): resulting limb boundaries are invalid",
      "(a limb's upper_level <= lower_level) -- this can happen when",
      "adjacent intersections cross each other; inspect the table before",
      "retrying."
    ))
  }

  FlodeRatingTable(
    table = out_dt[],
    status = "post_fit_aligned",
    previous = previous_table
  )
}

# ---------------------------------------------------------------------------
# detect_rc_gaps()
# ---------------------------------------------------------------------------

#' Detect discharge gaps between rating-curve limbs
#'
#' @description
#' Scans every junction between consecutive limbs and measures the
#' absolute and relative discharge gap. A gap arises when the last
#' discharge value of one limb does not match the first discharge value of
#' the next limb at the shared breakpoint stage.
#'
#' A shared breakpoint stage isn't guaranteed for an arbitrary `rc_dt` --
#' only for one built by `expand_rating_table()` from contiguous limbs.
#' This distinguishes three kinds of junction: a genuine \strong{shared-
#' stage discontinuity} (the case above, where a discharge gap is
#' calculated), a \strong{stage gap} (the upper limb's first stage is
#' beyond the lower limb's last stage -- no stage-discharge coverage in
#' between), and a \strong{stage overlap} (the reverse). A discharge
#' difference between two limbs that don't actually share a stage isn't
#' comparable to one that does, so `gap_abs`/`gap_rel` are `NA` for the
#' latter two cases rather than a number computed across mismatched
#' stages.
#'
#' @param rc_dt A data.frame or data.table containing the rating curve.
#'   Rows should be ordered by stage (ascending) within each limb.
#' @param stage_col Character. Name of the stage (water level) column.
#'   Default \code{"stage"}.
#' @param discharge_col Character. Name of the discharge column.
#'   Default \code{"discharge"}.
#' @param limb_col Character or \code{NULL}. Name of the column that
#'   identifies each limb (integer or character values). If \code{NULL} or
#'   not present in \code{rc_dt}, limbs are auto-detected from
#'   monotonicity breaks in discharge. Default \code{"limb"}.
#' @param tol_abs Numeric. Absolute discharge tolerance (same units as
#'   \code{discharge_col}) below which a shared-stage gap is not flagged.
#'   Default \code{0.5}.
#' @param tol_rel Numeric. Relative discharge tolerance (fraction of the
#'   lower limb's end discharge) below which a shared-stage gap is not
#'   flagged. Default \code{0.02} (2%).
#' @param stage_tol Numeric. Two stages within this tolerance of each
#'   other are treated as "the same stage" for classifying a junction as
#'   shared-stage vs a stage gap/overlap. Default \code{1e-6}.
#'
#' @return A \code{data.table} with one row per limb junction containing:
#'   \describe{
#'     \item{junction}{Junction index (1 = between limbs 1 and 2, etc.)}
#'     \item{limb_lower}{Limb ID of the lower limb.}
#'     \item{limb_upper}{Limb ID of the upper limb.}
#'     \item{stage_break}{The lower limb's last stage, kept for backward
#'       compatibility; see \code{stage_lower_end}/\code{stage_upper_start}
#'       for both endpoints explicitly, which differ for a stage gap or
#'       overlap.}
#'     \item{stage_lower_end}{The lower limb's last stage.}
#'     \item{stage_upper_start}{The upper limb's first stage.}
#'     \item{junction_type}{One of \code{"shared_stage"},
#'       \code{"stage_gap"}, or \code{"stage_overlap"}.}
#'     \item{q_lower_end}{Discharge at the end of the lower limb.}
#'     \item{q_upper_start}{Discharge at the start of the upper limb.}
#'     \item{gap_abs}{Absolute gap: \code{q_upper_start - q_lower_end}.
#'       \code{NA} unless \code{junction_type == "shared_stage"}.}
#'     \item{gap_rel}{Relative gap: \code{gap_abs / q_lower_end}. \code{NA}
#'       unless \code{junction_type == "shared_stage"}, or if
#'       \code{q_lower_end} is too close to zero to divide by.}
#'     \item{gap_flagged}{Logical; \code{TRUE} if a shared-stage gap
#'       exceeds \code{tol_abs} or \code{tol_rel}, or if the junction is a
#'       stage gap or overlap at all (both are worth flagging regardless
#'       of tolerance).}
#'   }
#'   Returns \code{NULL} invisibly when fewer than two limbs are detected.
#'
#' @examples
#' stage_seq1 <- seq(8.0, 10.0, by = 0.2)
#' limb1_dt <- data.table::data.table(
#'   stage = stage_seq1,
#'   discharge = 12 * (stage_seq1 - 8.0)^1.65,
#'   limb = 1L
#' )
#' stage_seq2 <- seq(10.0, 11.5, by = 0.2)
#' limb2_dt <- data.table::data.table(
#'   stage = stage_seq2,
#'   discharge = (tail(limb1_dt$discharge, 1) - 5) + 30 * (stage_seq2 - 10.0)^1.4,
#'   limb = 2L
#' )
#' rc_raw_dt <- data.table::rbindlist(list(limb1_dt, limb2_dt))
#' detect_rc_gaps(rc_raw_dt)
#'
#' @export
detect_rc_gaps <- function(rc_dt,
                            stage_col = "stage",
                            discharge_col = "discharge",
                            limb_col = "limb",
                            tol_abs = 0.5,
                            tol_rel = 0.02,
                            stage_tol = 1e-6) {
  if (!is.data.frame(rc_dt)) stop("rc_dt must be a data.frame or data.table")
  if (!is.numeric(tol_abs)) stop("tol_abs must be numeric")
  if (!is.numeric(tol_rel)) stop("tol_rel must be numeric")
  if (!is.numeric(stage_tol) || length(stage_tol) != 1L || stage_tol < 0) {
    stop("stage_tol must be a single non-negative number")
  }

  rc_dt <- copy(as.data.table(rc_dt))

  if (is.null(limb_col) || !limb_col %in% names(rc_dt)) {
    log_info("'{limb_col}' not found in rc_dt - auto-detecting limbs from discharge monotonicity.")
    rc_dt[, limb_ := .auto_limb(get(discharge_col))]
    limb_col <- "limb_"
  }

  # unique() returns values in order of first occurrence in the data, not
  # stage order -- if rc_dt happened to arrive with limb 2's rows before
  # limb 1's (not guaranteed by anything in this function's contract),
  # this would pair the wrong limbs as "adjacent" junctions. Ordering by
  # each limb's own minimum stage is robust to input row order.
  limb_order_dt <- rc_dt[, .(min_stage = min(get(stage_col))), by = c(limb_col)]
  setorderv(limb_order_dt, "min_stage")
  limbs <- limb_order_dt[[limb_col]]
  if (length(limbs) < 2L) {
    log_info("Only one limb detected - no junctions to check.")
    return(invisible(NULL))
  }

  results <- vector("list", length(limbs) - 1L)

  for (j in seq_len(length(limbs) - 1L)) {
    lower_id <- limbs[j]
    upper_id <- limbs[j + 1L]

    lower_dt <- rc_dt[get(limb_col) == lower_id][order(get(stage_col))]
    upper_dt <- rc_dt[get(limb_col) == upper_id][order(get(stage_col))]

    q_low <- lower_dt[[discharge_col]][nrow(lower_dt)]
    q_high <- upper_dt[[discharge_col]][1L]
    s_lower_end <- lower_dt[[stage_col]][nrow(lower_dt)]
    s_upper_start <- upper_dt[[stage_col]][1L]
    stage_diff <- s_upper_start - s_lower_end

    # Everything downstream (resolve_rc_gaps(), plot_rc_gaps()) assumes
    # the lower limb's last row and the upper limb's first row sit at the
    # same stage -- true for a table built by expand_rating_table() from
    # contiguous limbs, but not guaranteed for an arbitrary rc_dt. A
    # discharge "gap" computed between two DIFFERENT stages isn't
    # comparable to one computed at a genuinely shared stage, so this is
    # distinguished explicitly rather than silently treated the same way.
    if (abs(stage_diff) <= stage_tol) {
      junction_type <- "shared_stage"
      gap_abs <- q_high - q_low
      gap_rel <- if (abs(q_low) > 1e-9) gap_abs / q_low else NA_real_
      gap_flagged <- abs(gap_abs) > tol_abs | (!is.na(gap_rel) & abs(gap_rel) > tol_rel)
    } else {
      # A discharge difference between two different stages isn't a
      # meaningful "gap" in the same sense -- report NA rather than a
      # number that looks comparable to a genuine shared-stage gap.
      junction_type <- if (stage_diff > 0) "stage_gap" else "stage_overlap"
      gap_abs <- NA_real_
      gap_rel <- NA_real_
      gap_flagged <- TRUE
    }

    results[[j]] <- data.table(
      junction = j,
      limb_lower = as.character(lower_id),
      limb_upper = as.character(upper_id),
      stage_break = s_lower_end,
      stage_lower_end = s_lower_end,
      stage_upper_start = s_upper_start,
      junction_type = junction_type,
      q_lower_end = q_low,
      q_upper_start = q_high,
      gap_abs = gap_abs,
      gap_rel = gap_rel,
      gap_flagged = gap_flagged
    )
  }

  junctions_dt <- rbindlist(results)
  n_stage_issues <- sum(junctions_dt$junction_type != "shared_stage")
  if (n_stage_issues > 0L) {
    log_info(
      "Checked {nrow(junctions_dt)} junction(s): {sum(junctions_dt$gap_flagged)} flagged, ",
      "of which {n_stage_issues} are a stage gap or overlap rather than a shared-stage discharge gap."
    )
  } else {
    log_info(
      "Checked {nrow(junctions_dt)} junction(s): {sum(junctions_dt$gap_flagged)} gap(s) flagged."
    )
  }
  junctions_dt
}

# ---------------------------------------------------------------------------
# resolve_rc_gaps()
# ---------------------------------------------------------------------------

#' Resolve discharge gaps between rating-curve limbs
#'
#' @description
#' Closes discharge discontinuities at limb junctions identified by
#' \code{\link{detect_rc_gaps}} using one of five strategies (plus two
#' deprecated aliases for backward compatibility):
#'
#' \describe{
#'   \item{\code{"midpoint"} (default)}{
#'     Both limbs' endpoint discharges are moved to the simple average of
#'     the two original endpoint values at the breakpoint stage. An
#'     earlier version of this function called this method
#'     \code{"interpolate"} and computed it via a linear-interpolation
#'     helper -- but that helper was always evaluated at one of its own
#'     defining endpoints, which trivially returns that endpoint's value
#'     unchanged regardless of the other point supplied. The result was
#'     never anything other than the average of the two original
#'     endpoints; it was not using any interior point from either limb,
#'     despite the name. Renamed to describe what it actually computes.}
#'   \item{\code{"match_upper_to_lower"}}{
#'     Only the upper limb's *first row* is changed: its discharge is set
#'     equal to the lower limb's last discharge. Use when the lower
#'     (typically gauged) limb is authoritative and you only need the
#'     single junction point to agree, not the whole upper curve reshaped.}
#'   \item{\code{"match_lower_to_upper"}}{
#'     Only the lower limb's *last row* is changed: its discharge is set
#'     equal to the upper limb's first discharge. Use when the upper limb
#'     (e.g. a flood-frequency estimate) is authoritative and only the
#'     junction point needs to agree.}
#'   \item{\code{"extend_lower_to_upper"}}{
#'     The lower limb's discharge is rescaled by a single constant factor
#'     across *every* one of its rows, chosen so its last value exactly
#'     matches the upper limb's first discharge -- since
#'     \eqn{Q = C(H+a)^n} is linear in \eqn{C}, this is equivalent to
#'     rescaling the lower limb's \eqn{C} and preserves its curve shape.
#'     The upper limb is untouched, and (being unchanged) is what the
#'     lower limb's rescaled curve now "starts from" at the junction. Use
#'     when the upper limb is authoritative and the whole lower curve,
#'     not just its endpoint, should reflect that.}
#'   \item{\code{"extend_upper_to_lower"}}{
#'     The mirror image of \code{"extend_lower_to_upper"}: the upper
#'     limb's discharge is rescaled across every row so its first value
#'     matches the lower limb's last discharge; the lower limb is
#'     untouched.}
#'   \item{\code{"snap_to_lower"}, \code{"snap_to_upper"} (deprecated)}{
#'     Old names for \code{"match_upper_to_lower"} and
#'     \code{"match_lower_to_upper"} respectively -- kept working via a
#'     deprecation warning, but the names read backwards from what they
#'     do (\code{"snap_to_lower"} moves the \emph{upper} limb, not the
#'     lower one) and new code should use the replacements.}
#' }
#'
#' Only junctions flagged by \code{detect_rc_gaps} (i.e. those exceeding
#' \code{tol_abs} or \code{tol_rel}) are modified. Whichever method is
#' used, this amends the discretised \strong{table} at the junction rows
#' only -- it does not touch the equations that produced them (see
#' \code{\link{align_limb_equations}} for that).
#'
#' On a rating with 3 or more limbs (2 or more junctions), each junction
#' reads the \emph{current} discharge at its own endpoints rather than a
#' value captured before any junction was resolved, and -- for the
#' \code{"extend_*"} methods specifically -- junctions are resolved in
#' whichever order keeps each limb settling exactly once: top-down for
#' \code{"extend_lower_to_upper"} (a limb is only rescaled as a "lower"
#' limb after it has already settled as an "upper" one), bottom-up for
#' \code{"extend_upper_to_lower"}. This mirrors
#' \code{\link{align_limb_equations}}'s outward propagation from an
#' anchor limb; without it, a middle limb rescaled to close the junction
#' above it could silently reopen the junction below.
#'
#' @param rc_dt A data.frame or data.table containing the rating curve.
#' @param stage_col Character. Name of the stage column. Default
#'   \code{"stage"}.
#' @param discharge_col Character. Name of the discharge column.
#'   Default \code{"discharge"}.
#' @param limb_col Character or \code{NULL}. Name of the limb-ID column.
#'   Auto-detected if absent. Default \code{"limb"}.
#' @param method Character. Resolution strategy: \code{"midpoint"},
#'   \code{"match_lower_to_upper"}, \code{"match_upper_to_lower"},
#'   \code{"extend_lower_to_upper"}, \code{"extend_upper_to_lower"}, or
#'   the deprecated \code{"snap_to_lower"}/\code{"snap_to_upper"} aliases.
#'   Default \code{"midpoint"}.
#' @param tol_abs Numeric. Absolute discharge tolerance passed to
#'   \code{\link{detect_rc_gaps}}. Default \code{0.5}.
#' @param tol_rel Numeric. Relative discharge tolerance passed to
#'   \code{\link{detect_rc_gaps}}. Default \code{0.02}.
#'
#' @return The corrected \code{data.table} with the same columns as
#'   \code{rc_dt}, sorted by \code{stage_col} ascending. If no gaps are
#'   flagged the input is returned unchanged (as a data.table).
#'
#' @seealso \code{\link{detect_rc_gaps}}, \code{\link{plot_rc_gaps}},
#'   \code{\link{align_limb_equations}} for correcting the equations
#'   themselves rather than just the discretised table
#'
#' @examples
#' stage_seq1 <- seq(8.0, 10.0, by = 0.2)
#' limb1_dt <- data.table::data.table(
#'   stage = stage_seq1,
#'   discharge = 12 * (stage_seq1 - 8.0)^1.65,
#'   limb = 1L
#' )
#' stage_seq2 <- seq(10.0, 11.5, by = 0.2)
#' limb2_dt <- data.table::data.table(
#'   stage = stage_seq2,
#'   discharge = (tail(limb1_dt$discharge, 1) - 5) + 30 * (stage_seq2 - 10.0)^1.4,
#'   limb = 2L
#' )
#' rc_raw_dt <- data.table::rbindlist(list(limb1_dt, limb2_dt))
#' rc_fixed_dt <- resolve_rc_gaps(rc_raw_dt, method = "midpoint")
#' rc_matched_dt <- resolve_rc_gaps(rc_raw_dt, method = "match_upper_to_lower")
#' rc_extended_dt <- resolve_rc_gaps(rc_raw_dt, method = "extend_lower_to_upper")
#'
#' @export
resolve_rc_gaps <- function(rc_dt,
                             stage_col = "stage",
                             discharge_col = "discharge",
                             limb_col = "limb",
                             method = c(
                               "midpoint", "match_lower_to_upper", "match_upper_to_lower",
                               "extend_lower_to_upper", "extend_upper_to_lower",
                               "snap_to_lower", "snap_to_upper"
                             ),
                             tol_abs = 0.5,
                             tol_rel = 0.02) {
  method <- match.arg(method)
  if (method %in% c("snap_to_lower", "snap_to_upper")) {
    new_method <- if (method == "snap_to_lower") "match_upper_to_lower" else "match_lower_to_upper"
    warning(sprintf(
      paste0(
        "resolve_rc_gaps(): method = \"%s\" is deprecated -- its name reads backwards ",
        "from what it does (it moves the %s limb, not the %s one). Use \"%s\" instead, ",
        "which does exactly the same thing."
      ),
      method, if (method == "snap_to_lower") "upper" else "lower",
      if (method == "snap_to_lower") "lower" else "upper", new_method
    ), call. = FALSE)
    method <- new_method
  }
  if (!is.data.frame(rc_dt)) stop("rc_dt must be a data.frame or data.table")

  rc_out_dt <- copy(as.data.table(rc_dt))

  if (is.null(limb_col) || !limb_col %in% names(rc_out_dt)) {
    log_info("'{limb_col}' not found in rc_dt - auto-detecting limbs.")
    rc_out_dt[, limb_ := .auto_limb(get(discharge_col))]
    limb_col <- "limb_"
  }

  gaps_dt <- detect_rc_gaps(
    rc_out_dt,
    stage_col = stage_col,
    discharge_col = discharge_col,
    limb_col = limb_col,
    tol_abs = tol_abs,
    tol_rel = tol_rel
  )

  if (is.null(gaps_dt) || !any(gaps_dt$gap_flagged)) {
    log_info("No gaps to resolve - returning input unchanged.")
    return(rc_out_dt)
  }

  flagged_dt <- gaps_dt[gap_flagged == TRUE]
  setorder(flagged_dt, junction)

  # Processing order matters for the "extend_*" methods on a 3+ limb
  # chain, even with the fresh-read fix below: "extend_lower_to_upper"
  # only ever rescales the *lower* limb of the junction it's resolving, so
  # a middle limb must be fully settled as an "upper" neighbour (junction
  # below it) before it is itself rescaled as a "lower" limb (junction
  # above it) -- otherwise that later rescale silently reopens the
  # junction below. Resolving top-down (highest junction first) makes
  # each limb settle exactly once, propagating from the topmost limb
  # downward -- the same anchor-and-propagate shape as
  # align_limb_equations(anchor_limb = n). "extend_upper_to_lower" is the
  # mirror image and needs the opposite (bottom-up, the default) order,
  # propagating from the lowest limb upward. Order doesn't matter for
  # "midpoint"/"match_*", which only ever touch one row per limb.
  junction_order <- seq_len(nrow(flagged_dt))
  if (method == "extend_lower_to_upper") junction_order <- rev(junction_order)

  for (i in junction_order) {
    jct <- flagged_dt[i]

    if (!is.null(jct$junction_type) && jct$junction_type != "shared_stage") {
      warning(sprintf(
        paste(
          "resolve_rc_gaps(): junction %d (limbs %s/%s) is a %s, not a",
          "shared-stage discontinuity -- skipping. Averaging or snapping",
          "endpoint discharges only makes sense when both limbs are",
          "evaluated at the same stage; a stage gap or overlap needs",
          "re-gauging that stage range, or an equation-level fix",
          "(align_limb_equations()/rate_optimise_constrained()), not a",
          "table endpoint adjustment."
        ),
        jct$junction, jct$limb_lower, jct$limb_upper, jct$junction_type
      ))
      next
    }

    lower_id <- jct$limb_lower
    upper_id <- jct$limb_upper
    s_brk <- jct$stage_break

    lower_idx <- which(rc_out_dt[[limb_col]] == lower_id)
    upper_idx <- which(rc_out_dt[[limb_col]] == upper_id)

    last_lower_pos <- lower_idx[which.max(rc_out_dt[[stage_col]][lower_idx])]
    first_upper_pos <- upper_idx[which.min(rc_out_dt[[stage_col]][upper_idx])]

    # Read current values, not the upfront detect_rc_gaps() snapshot: an
    # earlier junction's "extend_*" resolution can have already rescaled a
    # middle limb shared with this junction, and that update must be seen
    # here for a 3+ limb chain to resolve correctly in sequence.
    q_low_end <- rc_out_dt[[discharge_col]][last_lower_pos]
    q_up_start <- rc_out_dt[[discharge_col]][first_upper_pos]

    if (method == "midpoint") {
      q_agreed <- (q_low_end + q_up_start) / 2.0

      log_info(
        "Junction {jct$junction} (limbs {lower_id}/{upper_id}, stage {round(s_brk, 3)}): ",
        "gap {round(q_low_end, 2)} -> {round(q_up_start, 2)} | agreed Q = {round(q_agreed, 4)}"
      )

      set(rc_out_dt, i = last_lower_pos, j = discharge_col, value = q_agreed)
      set(rc_out_dt, i = first_upper_pos, j = discharge_col, value = q_agreed)
    } else if (method == "match_upper_to_lower") {
      log_info(
        "Junction {jct$junction} (limbs {lower_id}/{upper_id}, stage {round(s_brk, 3)}): ",
        "matching upper start {round(q_up_start, 4)} -> {round(q_low_end, 4)}"
      )
      set(rc_out_dt, i = first_upper_pos, j = discharge_col, value = q_low_end)
    } else if (method == "match_lower_to_upper") {
      log_info(
        "Junction {jct$junction} (limbs {lower_id}/{upper_id}, stage {round(s_brk, 3)}): ",
        "matching lower end {round(q_low_end, 4)} -> {round(q_up_start, 4)}"
      )
      set(rc_out_dt, i = last_lower_pos, j = discharge_col, value = q_up_start)
    } else if (method == "extend_lower_to_upper") {
      if (!is.finite(q_low_end) || abs(q_low_end) < 1e-9) {
        warning(sprintf(
          paste(
            "resolve_rc_gaps(): junction %d (limbs %s/%s) -- the lower limb's",
            "discharge at the junction (%.6g) is too close to zero to rescale",
            "by; skipping this junction."
          ),
          jct$junction, lower_id, upper_id, q_low_end
        ), call. = FALSE)
        next
      }
      scale_factor <- q_up_start / q_low_end
      log_info(
        "Junction {jct$junction} (limbs {lower_id}/{upper_id}, stage {round(s_brk, 3)}): ",
        "extending lower limb by a factor of {round(scale_factor, 6)} to reach {round(q_up_start, 4)}"
      )
      rc_out_dt[lower_idx, (discharge_col) := get(discharge_col) * scale_factor]
    } else if (method == "extend_upper_to_lower") {
      if (!is.finite(q_up_start) || abs(q_up_start) < 1e-9) {
        warning(sprintf(
          paste(
            "resolve_rc_gaps(): junction %d (limbs %s/%s) -- the upper limb's",
            "discharge at the junction (%.6g) is too close to zero to rescale",
            "by; skipping this junction."
          ),
          jct$junction, lower_id, upper_id, q_up_start
        ), call. = FALSE)
        next
      }
      scale_factor <- q_low_end / q_up_start
      log_info(
        "Junction {jct$junction} (limbs {lower_id}/{upper_id}, stage {round(s_brk, 3)}): ",
        "extending upper limb by a factor of {round(scale_factor, 6)} to reach {round(q_low_end, 4)}"
      )
      rc_out_dt[upper_idx, (discharge_col) := get(discharge_col) * scale_factor]
    }
  }

  setorderv(rc_out_dt, stage_col)
  rc_out_dt[]
}

# ---------------------------------------------------------------------------
# plot_rc_gaps()
# ---------------------------------------------------------------------------

#' Diagnostic plot for rating-curve gap detection and resolution
#'
#' @description
#' Produces a ggplot2 figure overlaying the original (dashed) and corrected
#' (solid) rating curves. Works for any number of limbs.
#'
#' The original (Before) curve is drawn as one dashed line per limb,
#' coloured by limb ID, so gaps between independently-fitted segments are
#' visible. The corrected (After) curve is drawn the same way; junction
#' dots bridge the colour seam where adjacent limbs meet post-resolution.
#'
#' Flagged gap junctions are marked with a dotted horizontal line; labels
#' are pinned to the right margin and staggered vertically so they never
#' overlap the curves or each other. A short segment connects each label
#' back to its junction stage line.
#'
#' @param rc_before_dt Data.frame or data.table. The original, uncorrected
#'   rating curve passed to \code{\link{resolve_rc_gaps}}.
#' @param rc_after_dt Data.frame or data.table. The corrected rating curve
#'   returned by \code{\link{resolve_rc_gaps}}.
#' @param stage_col Character. Name of the stage column. Default
#'   \code{"stage"}.
#' @param discharge_col Character. Name of the discharge column.
#'   Default \code{"discharge"}.
#' @param limb_col Character or \code{NULL}. Name of the limb-ID column.
#'   Defaults to \code{"limb"}; a single limb is assumed if the column is
#'   absent.
#' @param doubtful_col Character. Name of the doubtful flag column
#'   (default \code{"doubtful"}). Rows where this column is \code{TRUE}
#'   are excluded from both the Before and After curves. Ignored if the
#'   column is absent from \code{rc_before_dt} / \code{rc_after_dt}.
#'
#' @return A \code{ggplot} object (printed as a side-effect). Returned
#'   invisibly so it can be further modified or saved with
#'   \code{\link[ggplot2]{ggsave}}.
#'
#' @seealso \code{\link{detect_rc_gaps}}, \code{\link{resolve_rc_gaps}}
#'
#' @examples
#' stage_seq1 <- seq(8.0, 10.0, by = 0.2)
#' limb1_dt <- data.table::data.table(
#'   stage = stage_seq1,
#'   discharge = 12 * (stage_seq1 - 8.0)^1.65,
#'   limb = 1L
#' )
#' stage_seq2 <- seq(10.0, 11.5, by = 0.2)
#' limb2_dt <- data.table::data.table(
#'   stage = stage_seq2,
#'   discharge = (tail(limb1_dt$discharge, 1) - 5) + 30 * (stage_seq2 - 10.0)^1.4,
#'   limb = 2L
#' )
#' rc_raw_dt <- data.table::rbindlist(list(limb1_dt, limb2_dt))
#' rc_fixed_dt <- resolve_rc_gaps(rc_raw_dt)
#' p <- plot_rc_gaps(rc_raw_dt, rc_fixed_dt)
#' # ggplot2::ggsave("rc_gap_check.png", p, width = 8, height = 6)
#'
#' @export
plot_rc_gaps <- function(rc_before_dt,
                          rc_after_dt,
                          stage_col = "stage",
                          discharge_col = "discharge",
                          limb_col = "limb",
                          doubtful_col = "doubtful") {
  if (!is.data.frame(rc_before_dt)) stop("rc_before_dt must be a data.frame or data.table")
  if (!is.data.frame(rc_after_dt)) stop("rc_after_dt must be a data.frame or data.table")

  make_plot_dt <- function(rc_dt, version_label) {
    rc_dt <- copy(as.data.table(rc_dt))
    if (!limb_col %in% names(rc_dt)) rc_dt[, (limb_col) := 1L]
    if (doubtful_col %in% names(rc_dt)) rc_dt <- rc_dt[get(doubtful_col) != TRUE]
    data.table(
      stage_ = rc_dt[[stage_col]],
      discharge_ = rc_dt[[discharge_col]],
      limb_f = factor(rc_dt[[limb_col]]),
      version = version_label
    )
  }

  before_dt <- make_plot_dt(rc_before_dt, "Before")
  after_dt <- make_plot_dt(rc_after_dt, "After")

  gaps_dt <- detect_rc_gaps(
    rc_before_dt,
    stage_col = stage_col,
    discharge_col = discharge_col,
    limb_col = limb_col
  )

  p <- ggplot() +
    # geom_path (not geom_line) is used throughout: geom_line sorts by X
    # (discharge) before connecting, which breaks corrected limbs whose
    # first point has been raised above the second by the gap-resolution
    # step. geom_path connects in data order (stage-ascending), always safe.
    geom_path(
      data = before_dt,
      aes(x = discharge_, y = stage_, colour = limb_f, group = limb_f),
      linetype = "dashed", linewidth = 0.65
    ) +
    geom_path(
      data = after_dt,
      aes(x = discharge_, y = stage_, colour = limb_f, group = limb_f),
      linetype = "solid", linewidth = 1.2
    ) +
    scale_colour_discrete(name = "Limb") +
    labs(
      title = "Rating Curve \u2014 Gap Detection & Resolution",
      x = "Discharge (m\u00b3/s)",
      y = paste0("Stage (", stage_col, ")"),
      caption = "Dashed = original | Solid = corrected | Dots = resolved junctions | Doubtful limbs hidden"
    ) +
    theme_minimal(base_size = 12) +
    theme(
      plot.title = element_text(face = "bold", size = 13),
      panel.grid.minor = element_blank(),
      panel.border = element_rect(colour = "grey80", fill = NA)
    )

  if (!is.null(gaps_dt) && any(gaps_dt$gap_flagged)) {
    flagged_dt <- gaps_dt[gap_flagged == TRUE]

    q_max <- max(after_dt$discharge_, before_dt$discharge_)
    stage_range <- diff(range(after_dt$stage_, before_dt$stage_))
    min_sep <- stage_range * 0.07

    setorder(flagged_dt, stage_break)
    label_y <- flagged_dt$stage_break
    for (i in seq_along(label_y)[-1L]) {
      if (label_y[i] - label_y[i - 1L] < min_sep) {
        label_y[i] <- label_y[i - 1L] + min_sep
      }
    }

    label_dt <- data.table(
      x = q_max,
      y = label_y,
      y_junction = flagged_dt$stage_break,
      label = ifelse(
        flagged_dt$junction_type == "shared_stage",
        sprintf("Gap %d \u0394Q = %.1f m\u00b3/s", flagged_dt$junction, flagged_dt$gap_abs),
        sprintf(
          "Gap %d: %s",
          flagged_dt$junction,
          ifelse(flagged_dt$junction_type == "stage_gap", "stage gap", "stage overlap")
        )
      )
    )

    jct_pts_dt <- after_dt[stage_ %in% flagged_dt$stage_break]
    jct_pts_dt <- jct_pts_dt[!duplicated(jct_pts_dt$stage_)]

    p <- p +
      geom_hline(
        data = flagged_dt,
        aes(yintercept = stage_break),
        colour = "firebrick", linetype = "dotted", linewidth = 0.5
      ) +
      geom_point(
        data = jct_pts_dt,
        aes(x = discharge_, y = stage_),
        colour = "grey20", size = 2.5, shape = 16
      ) +
      geom_segment(
        data = label_dt,
        aes(x = x, xend = x, y = y, yend = y_junction),
        colour = "firebrick", linewidth = 0.4, linetype = "solid"
      ) +
      geom_label(
        data = label_dt,
        aes(x = x, y = y, label = label),
        hjust = 1, vjust = 0.5,
        colour = "firebrick", size = 3,
        label.size = 0.2, fill = "white", alpha = 0.9
      )
  }

  print(p)
  invisible(p)
}

# ---------------------------------------------------------------------------
# rating_plot() method for FlodeRatingTable
# ---------------------------------------------------------------------------

#' Plot a rating table's curve, one colour per limb (S7 method)
#'
#' @description
#' Registered against the `rating_plot` generic (`flode_classes.R`) for
#' [FlodeRatingTable] -- the equation-table representation produced by
#' `align_limb_equations()`, `as_rating_table()`, or built directly from a
#' legacy import. Unlike `FlodeRating`/`FlodeSegmentedRating`, a
#' `FlodeRatingTable` carries no raw gaugings, so there's no scatter to
#' overlay -- just each limb's curve, coloured separately (rather than
#' one continuous line as `plot_rating_curves()` draws) so a remaining
#' kink or overlap at a junction -- exactly what `resolve_rc_gaps()` and
#' `align_limb_equations()` exist to close -- is visible at a glance,
#' matching `rating_plot(FlodeRating)`'s per-limb colouring.
#'
#' `fit` is a [FlodeRatingTable] instance. `n_points` (default `200L`) is
#' the number of points used to draw each limb's curve.
#'
#' @return A `ggplot` object, invisibly.
#' @seealso [plot_rc_gaps()] for a before/after view of a
#'   `resolve_rc_gaps()` correction specifically; [plot_rating_curves()]
#'   for overlaying several fitted ratings (in any mix of classes,
#'   including this one) for comparison.
#' @export
method(rating_plot, FlodeRatingTable) <- function(fit, n_points = 200L) {
  if (!is.numeric(n_points) || length(n_points) != 1L || n_points <= 0) {
    stop("n_points must be a single positive integer")
  }

  table_dt <- copy(fit@table)
  setorder(table_dt, lower_level)
  n_limbs <- nrow(table_dt)

  curve_list <- lapply(seq_len(n_limbs), function(i) {
    stage_seq <- seq(table_dt$lower_level[i], table_dt$upper_level[i], length.out = n_points)
    # Same formula and zero-flow clamp as method(apply_rating, FlodeRatingTable).
    discharge_seq <- table_dt$C[i] * (stage_seq - table_dt$A[i])^table_dt$B[i]
    discharge_seq[stage_seq <= table_dt$A[i]] <- 0
    data.table(stage = stage_seq, discharge = discharge_seq, limb = factor(i))
  })
  curve_dt <- rbindlist(curve_list)

  p <- ggplot(curve_dt, aes(x = discharge, y = stage, colour = limb)) +
    geom_path(linewidth = 1.2) +
    labs(
      title = sprintf(
        "Rating Table (%d limb%s, status: %s)",
        n_limbs, if (n_limbs > 1L) "s" else "", fit@status
      ),
      x = "Discharge (m\u00b3/s)", y = "Stage (m)", colour = "Limb"
    ) +
    theme_minimal(base_size = 12) +
    theme(
      plot.title = element_text(face = "bold", size = 13),
      panel.grid.minor = element_blank(),
      panel.border = element_rect(colour = "grey80", fill = NA)
    )

  if (n_limbs > 1L) {
    p <- p + geom_hline(
      yintercept = table_dt$upper_level[-n_limbs],
      colour = "grey60", linetype = "dashed", linewidth = 0.5
    )
  }

  print(p)
  invisible(p)
}
