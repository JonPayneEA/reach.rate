# ============================================================ #
# Tool:         offset_convention
# Description:  Convert the offset parameter of a rating equation between
#               the package's convention, Q = C (H - a)^n, and the
#               convention of systems that write Q = C (H + a)^n.
# Author:       Jonathan Payne
# Created:      2026-11-18
# Tier:         3
# Inputs:       A table with a column `a`, or a FlodeRating or
#               FlodeRatingTable.
# Outputs:      A data.table.
# Dependencies: data.table
# ============================================================ #

#' @include flode_classes.R accessors.R
NULL

#' Convert a rating's offset between the two sign conventions
#'
#' @description
#' This package writes a rating limb as \eqn{Q = C (H - a)^n}, so `a` is
#' the stage at which flow ceases. Some systems write
#' \eqn{Q = C (H + a)^n}, in which the same offset has the opposite sign.
#' Using one system's `a` in the other's equation shifts the whole curve,
#' by twice the offset, with nothing to say that it has happened.
#'
#' `convert_offset_convention()` changes the sign of `a` and nothing else:
#' \eqn{C}, \eqn{n} and the stage limits are untouched, because
#' \eqn{C (H + a')^n = C (H - a)^n} exactly when \eqn{a' = -a}. Converting
#' there and back returns the original values.
#'
#' It does not change a stage datum. If an external system measures stage
#' from a different zero (a gauge board against metres above ordnance
#' datum, say), the limits and `a` need shifting by that datum as well, and
#' that is not done here.
#'
#' A rating object always uses the package's convention and is not
#' changed. Pass one to read its limbs in the other convention.
#'
#' @param x A `data.frame` or `data.table` with a column `a`, or a
#'   [FlodeRating] or [FlodeRatingTable], whose limbs are read with
#'   [rating_limbs()].
#' @param from,to The convention of `x`, and the one wanted: `"subtract"`
#'   for \eqn{Q = C (H - a)^n} (this package) or `"add"` for
#'   \eqn{Q = C (H + a)^n}. The defaults convert an external `H + a` table
#'   into this package's convention.
#'
#' @return A data.table, a copy of `x` (or of its limbs) with `a` in the
#'   `to` convention. The same table comes back unchanged when `from` and
#'   `to` are the same.
#'
#' @seealso [rating_limbs()], `vignette("mathematical_contract")`
#'
#' @examples
#' # A limb from a system that writes Q = C (H + a)^n, with a = -0.35.
#' external <- data.frame(
#'   lower_level = 0.5, upper_level = 3, C = 4.1, a = -0.35, n = 1.6
#' )
#' internal <- convert_offset_convention(external)
#' internal$a
#'
#' # Both describe one curve: the same stage gives the same discharge.
#' stage <- 1.8
#' external$C * (stage + external$a)^external$n
#' internal$C * (stage - internal$a)^internal$n
#'
#' # Converting back recovers the original.
#' convert_offset_convention(internal, from = "subtract", to = "add")$a
#'
#' @export
convert_offset_convention <- function(x, from = c("add", "subtract"), to = c("subtract", "add")) {
  from <- match.arg(from)
  to <- match.arg(to)
  tbl <- if (S7_inherits(x, FlodeRating) || S7_inherits(x, FlodeRatingTable)) {
    # Objects hold the package's own convention, so reading them says
    # what they are in `subtract` terms regardless of `from`.
    from <- "subtract"
    rating_limbs(x)
  } else if (S7_inherits(x, FlodeSegmentedRating)) {
    stop("convert_offset_convention(): a FlodeSegmentedRating has no per-limb offset to convert. ",
         "Its zero-flow stage is the parameter bp1.", call. = FALSE)
  } else if (is.data.frame(x)) {
    copy(as.data.table(x))
  } else {
    stop("convert_offset_convention(): x must be a data.frame, a FlodeRating or a FlodeRatingTable", call. = FALSE)
  }
  if (!"a" %in% names(tbl)) stop("convert_offset_convention(): x has no column named 'a'", call. = FALSE)
  if (!is.numeric(tbl$a)) stop("convert_offset_convention(): column 'a' must be numeric", call. = FALSE)
  if (from != to) set(tbl, j = "a", value = -tbl$a)
  tbl[]
}
