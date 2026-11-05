# ============================================================ #
# Tool:         extend_rating_low
# Description:  Add an explicit linear limb below the lowest limb of a
#               rating, joined to it with matching discharge and matching
#               gradient, so low and negative stage values are handled by
#               a deliberate limb rather than by extrapolating the lowest
#               power-law limb downwards.
# Author:       Jonathan Payne
# Created:      2026-11-05
# Tier:         3
# Inputs:       A FlodeRating, FlodeRatingTable, or data.frame/data.table
#               with lower_level/upper_level/C/a/n (contiguous).
# Outputs:      A FlodeRatingTable with one extra limb at the bottom.
# Dependencies: data.table, S7
# ============================================================ #

#' @include flode_classes.R
NULL

#' Add a linear limb below the lowest limb of a rating
#'
#' @description
#' Below its lowest limb a rating normally extrapolates that limb's power
#' law downwards, flagged but unchecked. That is poor behaviour where the
#' stage record can fall below the lowest gauged stage, and especially
#' where stage values are negative, because the power law's slope is then
#' set by a datum `a` that no gauging constrains. `extend_rating_low()`
#' replaces that extrapolation with an explicit, user-requested linear
#' limb that joins the lowest limb smoothly: same discharge and same
#' gradient at the junction stage.
#'
#' Write the lowest limb as `Q = C(H - a)^n` and let `h` be its
#' `lower_level`. The new limb is the tangent line to that curve at `h`:
#' \deqn{Q = Q_h + m (H - h), \quad Q_h = C(h - a)^n, \quad m = nC(h - a)^{n-1}.}
#' This line reaches zero discharge at
#' \deqn{H_0 = h - (h - a)/n,}
#' so it is stored as an ordinary row of the equation table with
#' `C = m`, `a = H_0` and `n = 1`: `Q = m(H - H_0)` is the same line. No
#' new column or class is needed, and [apply_rating()],
#' [apply_rating_inverse()], [apply_rating_interval()], [detect_rc_gaps()]
#' and the plotting functions all evaluate it correctly. Discharge is
#' floored at zero below `H_0`, as it is for any limb.
#'
#' The lowest limb is not altered. Because the line is tangent to a power
#' law with `n > 1` (which lies above its tangent) the new limb gives
#' slightly less discharge than extrapolating the power law would; for
#' `n < 1` it gives slightly more. For `n = 1` the two are identical.
#'
#' @param rating A [FlodeRating], a [FlodeRatingTable], or a
#'   data.frame/data.table with `lower_level`, `upper_level`, `C`, `a`
#'   and `n`, one row per limb, contiguous. A `FlodeRating` is bridged
#'   through [as_rating_table()] first.
#' @param lower_stage Numeric or `NULL`. Stage at the bottom of the new
#'   limb, which must lie in `[H_0, h)`. The default `NULL` uses `H_0`,
#'   the stage at which the line reaches zero discharge. A larger value
#'   (e.g. the lowest stage you expect to see) is allowed; stage below it
#'   is then treated as extrapolation and flagged by [apply_rating()],
#'   though the same line is still evaluated.
#'
#' @return A [FlodeRatingTable] with `@status` `"extended_low"`,
#'   `@previous` holding the rating exactly as passed in (when that was a
#'   `FlodeRating` or `FlodeRatingTable`), and `@table` gaining a logical
#'   `linear_extension` column that is `TRUE` for the new limb only.
#'
#' @seealso [graft_rating()] for joining a rating onto one above its top
#'   limb; [apply_rating()] to use the result.
#'
#' @examples
#' rating_dt <- data.table::data.table(
#'   lower_level = c(0.20, 1.2), upper_level = c(1.2, 2.5),
#'   C = c(2.5, 2.410481), a = c(0, 0), n = c(1.5, 1.7)
#' )
#' extended <- extend_rating_low(rating_dt)
#' extended@table
#'
#' # Negative stage is now handled by the linear limb
#' apply_rating(extended, data.table::data.table(stage = c(-0.1, 0.1, 0.5, 1.8)))
#'
#' @export
extend_rating_low <- function(rating, lower_stage = NULL) {
  original <- if (S7_inherits(rating, FlodeRating) || S7_inherits(rating, FlodeRatingTable)) rating else NULL
  if (S7_inherits(rating, FlodeRating)) rating <- as_rating_table(rating)
  if (S7_inherits(rating, FlodeRatingTable)) rating <- rating@table

  if (!is.data.frame(rating)) {
    stop("extend_rating_low(): rating must be a FlodeRating, FlodeRatingTable, or data.frame/data.table")
  }
  required <- c("lower_level", "upper_level", "C", "a", "n")
  missing <- setdiff(required, names(rating))
  if (length(missing)) {
    stop("extend_rating_low(): rating is missing column(s): ", paste(missing, collapse = ", "))
  }
  if (nrow(rating) == 0L) stop("extend_rating_low(): rating must have at least one row")

  rating_dt <- copy(as.data.table(rating))
  setorder(rating_dt, lower_level)
  n_limbs <- nrow(rating_dt)
  if (n_limbs > 1L) {
    contiguous <- all(abs(rating_dt$upper_level[-n_limbs] - rating_dt$lower_level[-1L]) < 1e-8)
    if (!contiguous) {
      stop("extend_rating_low(): limbs must be contiguous (upper_level[i] == lower_level[i+1]).")
    }
  }

  lowest <- rating_dt[1L]
  h <- lowest$lower_level
  if (!is.finite(h)) stop("extend_rating_low(): the lowest limb's lower_level must be finite")
  depth <- h - lowest$a
  if (depth <= 0) {
    stop(sprintf(
      paste(
        "extend_rating_low(): the lowest limb has lower_level (%.6g) at or below its a (%.6g),",
        "so its discharge and gradient at the junction are not both defined and positive."
      ),
      h, lowest$a
    ))
  }

  slope <- lowest$n * lowest$C * depth^(lowest$n - 1)
  zero_stage <- h - depth / lowest$n

  if (is.null(lower_stage)) lower_stage <- zero_stage
  if (!is.numeric(lower_stage) || length(lower_stage) != 1L || !is.finite(lower_stage)) {
    stop("extend_rating_low(): lower_stage must be NULL or a single finite number")
  }
  if (lower_stage >= h) {
    stop(sprintf("extend_rating_low(): lower_stage (%.6g) must be below the lowest limb's lower_level (%.6g)", lower_stage, h))
  }
  if (lower_stage < zero_stage - 1e-9) {
    stop(sprintf(
      paste(
        "extend_rating_low(): lower_stage (%.6g) is below the stage where the linear limb",
        "reaches zero discharge (%.6g); discharge is zero below that stage, so the limb",
        "need not reach further."
      ),
      lower_stage, zero_stage
    ))
  }

  new_row <- data.table(
    lower_level = lower_stage, upper_level = h,
    C = slope, a = zero_stage, n = 1
  )
  # Any extra columns on the input (e.g. `source`) are filled with NA on the
  # new row by rbind(fill = TRUE) below.
  set(rating_dt, j = "linear_extension", value = FALSE)
  set(new_row, j = "linear_extension", value = TRUE)

  combined_dt <- rbind(new_row, rating_dt, use.names = TRUE, fill = TRUE)

  FlodeRatingTable(
    table = combined_dt[],
    status = "extended_low",
    previous = original
  )
}
