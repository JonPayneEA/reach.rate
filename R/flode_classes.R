# ============================================================ #
# Tool:         flode_classes
# Description:  S7 class definitions for the rating_curves toolkit --
#               FlodeRating (rate_optimise()'s independent-limb fit),
#               FlodeSegmentedRating (rate_optimise_segmented()'s joint
#               model), and FlodeRatingTable (gap_check's equation-table
#               representation), sharing a common abstract base
#               (FlodeRatingBase) for gaugings/fit-bookkeeping/provenance.
#               Replaces the previous design of a plain data.table with
#               a class string tacked on and dependent data stashed in
#               attributes, which is vulnerable to going stale under
#               ordinary data.table subsetting (an attribute survives a
#               `[` subset by luck, not by guarantee) and gives no
#               structural way to tell an independently-fitted result
#               from a post-fit-amended one apart from remembering to
#               check a column.
# Author:       Jonathan Payne
# Created:      2026-08-19
# Modified:     2026-08-19 - JP: initial version. Follows the r-oop
#               skill's S7-by-default convention: typed properties,
#               mandatory validators (this toolkit is Tier 3),
#               FlodeX-prefixed exported class names. FlodeRatingBase is
#               abstract -- gaugings/fit_starts/status/provenance are
#               common to both fit types; FlodeRating adds the per-limb
#               table and bootstrap; FlodeSegmentedRating adds the
#               single-row coefficient table and segment count.
#               FlodeRatingTable is separate (not part of the fit
#               hierarchy): it's the gap_check module's equation-table
#               representation, and carries its own audit chain
#               (status/previous) since align_limb_equations() amends it
#               without a raw-gaugings-based refit the way the fit
#               classes have.
# Modified:     2026-08-25 - JP: converted from a box module to a package
#               R/ file (see R/reach.rate-package.R for why). The
#               box::use() import block is gone -- S7/data.table are
#               package-level imports now (declared once, centrally),
#               and there are no sibling-module imports left to declare:
#               every function under R/ shares this package's one
#               namespace.
# Tier:         3
# Inputs:       None directly -- this module only defines classes and
#               generics; other modules construct and use instances.
# Outputs:      The S7 class objects and generics themselves, plus print
#               methods for console display.
# Dependencies: S7, data.table
# ============================================================ #

# ---------------------------------------------------------------------------
# FlodeRatingBase (abstract) -- shared by FlodeRating and FlodeSegmentedRating
# ---------------------------------------------------------------------------

#' Abstract base class for a fitted rating (S7)
#'
#' @description
#' Properties and validation shared by [FlodeRating] and
#' [FlodeSegmentedRating]: the gaugings a fit was built from, multi-start
#' fitting bookkeeping (if any), a status flag distinguishing an
#' independently-fitted result from a post-fit amendment, a provenance
#' list for auditability (fitting method, controls, bounds, tool
#' version), and a `previous` chain for amendments produced from an
#' earlier fit of the same class. Never constructed directly -- see
#' [FlodeRating] and [FlodeSegmentedRating].
#'
#' @param gaugings Data.table with `discharge_cms` and `stage_m`
#'   columns -- the gaugings the fit was built from. May optionally
#'   include a `gauging_datetime` column (`Date` or `POSIXct`) recording
#'   when each spot gauging was taken. Nothing in the package currently
#'   reads this column -- it's groundwork for a future age-aware fitting
#'   option (see issue #9).
#' @param fit_starts Data.table of multi-start fitting attempts, or
#'   `NULL` if the fit wasn't produced with `multi_start = TRUE`.
#' @param status Character. One of `"independently_fitted"`,
#'   `"post_fit_aligned"`, or `"constrained_refit"`.
#' @param provenance List recording how the fit was made (fitting
#'   method, controls, bounds, tool version).
#' @param previous The exact pre-amendment fit this was built from (same
#'   class as this instance), or `NULL` (default) for a fit with no such
#'   history -- an independently-fitted result, for instance. Mirrors
#'   [FlodeRatingTable]'s own `@previous` audit chain.
#' @export
FlodeRatingBase <- new_class(
  "FlodeRatingBase",
  properties = list(
    gaugings = new_property(new_S3_class(c("data.table", "data.frame"))),
    fit_starts = new_property(class_any, default = NULL),
    status = new_property(class_character, default = "independently_fitted"),
    # default = quote(list()), not default = list(): S7 evaluates a
    # scalar/quoted-call default once per instance, but a literal list()
    # would be one shared, mutable object handed to every instance --
    # exactly the classic mutable-default-argument trap. (S7 currently
    # warns on this and will make it an error in a future release.)
    provenance = new_property(class_list, default = quote(list())),
    previous = new_property(class_any, default = NULL)
  ),
  abstract = TRUE,
  validator = function(self) {
    if (!all(c("discharge_cms", "stage_m") %in% names(self@gaugings))) {
      return("gaugings must have discharge_cms and stage_m columns")
    }
    if (nrow(self@gaugings) == 0) return("gaugings must have at least one row")
    if ("gauging_datetime" %in% names(self@gaugings) &&
        !inherits(self@gaugings$gauging_datetime, c("Date", "POSIXct"))) {
      return("gaugings$gauging_datetime, if present, must be a Date or POSIXct vector")
    }
    if (!self@status %in% c("independently_fitted", "post_fit_aligned", "constrained_refit")) {
      return("status must be one of: independently_fitted, post_fit_aligned, constrained_refit")
    }
    NULL
  }
)

# ---------------------------------------------------------------------------
# FlodeRating -- rate_optimise()'s independent-limb fit
# ---------------------------------------------------------------------------

#' A fitted multi-limb rating curve (S7)
#'
#' @description
#' The result of [rate_optimise()] (or [rate_optimise_constrained()]):
#' one row per limb in `@limbs` (bounds, coefficients `C`/`a`/`n`, fit
#' diagnostics, and -- when produced by `rate_optimise_constrained()` --
#' alignment provenance), the raw gaugings in `@gaugings`, and
#' bootstrap draws in `@bootstrap` when `rate_optimise(..., n_boot = )`
#' was used.
#'
#' @param gaugings Data.table with `discharge_cms` and `stage_m`
#'   columns -- the gaugings the fit was built from. May optionally
#'   include a `gauging_datetime` column (`Date` or `POSIXct`) recording
#'   when each spot gauging was taken. Nothing in the package currently
#'   reads this column -- it's groundwork for a future age-aware fitting
#'   option (see issue #9).
#' @param fit_starts Data.table of multi-start fitting attempts, or
#'   `NULL` if the fit wasn't produced with `multi_start = TRUE`.
#' @param status Character. One of `"independently_fitted"`,
#'   `"post_fit_aligned"`, or `"constrained_refit"`.
#' @param provenance List recording how the fit was made (fitting
#'   method, controls, bounds, tool version).
#' @param limbs Data.table, one row per limb: bounds, coefficients
#'   `C`/`a`/`n`, and fit diagnostics.
#' @param bootstrap Data.table of per-draw bootstrap coefficients, or
#'   `NULL` if the fit wasn't produced with `n_boot > 0`.
#' @param previous The exact pre-amendment `FlodeRating` this was built
#'   from (e.g. by `align_limb_equations()`/`align_limb_boundaries()`),
#'   or `NULL` (default) for an independently-fitted result.
#' @export
FlodeRating <- new_class(
  "FlodeRating",
  parent = FlodeRatingBase,
  properties = list(
    limbs = new_property(new_S3_class(c("data.table", "data.frame"))),
    bootstrap = new_property(class_any, default = NULL)
  ),
  validator = function(self) {
    required <- c("limb", "lower_stage_m", "upper_stage_m", "C", "a", "n")
    missing_cols <- setdiff(required, names(self@limbs))
    if (length(missing_cols)) {
      return(paste("limbs is missing required column(s):", paste(missing_cols, collapse = ", ")))
    }
    if (nrow(self@limbs) == 0) return("limbs must have at least one row")
    if (any(self@limbs$C <= 0)) return("C must be positive for every limb")
    if (any(self@limbs$n <= 0)) return("n must be positive for every limb")
    if (any(self@limbs$upper_stage_m <= self@limbs$lower_stage_m)) {
      return("upper_stage_m must exceed lower_stage_m for every limb")
    }
    NULL
  }
)

#' Print a fitted rating curve (S7 method)
#'
#' @description
#' Registered against base R's `print` generic for [FlodeRating] --
#' `method(print, ...) <- `, not a plain S3 `print.FlodeRating`
#' function, since an S7 class defined inside a package is
#' namespace-qualified (`class(fit)` is `"reach.rate::FlodeRating"`, not
#' bare `"FlodeRating"`), which a plain S3-named function can never
#' dispatch against. `.onLoad()` (`zzz.R`) calls `S7::methods_register()`
#' so this (and every other S7 method registered with `method<-` in this
#' package) dispatches correctly regardless of how the package was
#' loaded.
#'
#' @param x A [FlodeRating] instance.
#' @param ... Unused; present for consistency with the `print` generic.
#' @return `x`, invisibly.
#' @export
method(print, FlodeRating) <- function(x, ...) {
  cat(sprintf("<FlodeRating> %d limb(s), status: %s\n", nrow(x@limbs), x@status))
  print(x@limbs[, .(limb, lower_stage_m, upper_stage_m, C, a, n, rmse_cms, r_squared)])
  invisible(x)
}

# ---------------------------------------------------------------------------
# FlodeSegmentedRating -- rate_optimise_segmented()'s joint model
# ---------------------------------------------------------------------------

#' A fitted segmented rating curve, Hodson et al. (2024) parameterisation (S7)
#'
#' @description
#' The result of [rate_optimise_segmented()]: a single joint model
#' rather than independent limbs, so `@coefficients` is one row (`C`,
#' `bp1..bpk`, `n1..nk`, diagnostics), not one row per segment.
#'
#' @param gaugings Data.table with `discharge_cms` and `stage_m`
#'   columns -- the gaugings the fit was built from. May optionally
#'   include a `gauging_datetime` column (`Date` or `POSIXct`) recording
#'   when each spot gauging was taken. Nothing in the package currently
#'   reads this column -- it's groundwork for a future age-aware fitting
#'   option (see issue #9).
#' @param fit_starts Data.table of multi-start fitting attempts, or
#'   `NULL` if the fit wasn't produced with `multi_start = TRUE`.
#' @param status Character. One of `"independently_fitted"`,
#'   `"post_fit_aligned"`, or `"constrained_refit"`.
#' @param provenance List recording how the fit was made (fitting
#'   method, controls, bounds, tool version).
#' @param coefficients Single-row data.table: `C`, `bp1..bpk`,
#'   `n1..nk`, and fit diagnostics.
#' @param n_segments Integer. Number of segments `k`.
#' @param estimate_breakpoints Logical. Whether the interior
#'   breakpoints were refit as free parameters (`TRUE`) or held fixed
#'   at `control` (`FALSE`).
#' @param previous The exact pre-amendment `FlodeSegmentedRating` this
#'   was built from, or `NULL` (default) for an independently-fitted
#'   result. Nothing in the package currently produces an amended
#'   `FlodeSegmentedRating` -- this exists for parity with [FlodeRating].
#' @export
FlodeSegmentedRating <- new_class(
  "FlodeSegmentedRating",
  parent = FlodeRatingBase,
  properties = list(
    coefficients = new_property(new_S3_class(c("data.table", "data.frame"))),
    n_segments = class_integer,
    estimate_breakpoints = class_logical
  ),
  validator = function(self) {
    if (nrow(self@coefficients) != 1L) return("coefficients must have exactly one row")
    if (self@coefficients$C[1] <= 0) return("C must be positive")
    if (self@n_segments < 1L) return("n_segments must be at least 1")
    NULL
  }
)

#' Print a fitted segmented rating curve (S7 method)
#'
#' @description
#' Registered against base R's `print` generic for
#' [FlodeSegmentedRating]. Same reasoning as [FlodeRating]'s `print`
#' method: a plain S3 `print.FlodeSegmentedRating` function can never
#' dispatch against a namespace-qualified S7 class name.
#'
#' @param x A [FlodeSegmentedRating] instance.
#' @param ... Unused; present for consistency with the `print` generic.
#' @return `x`, invisibly.
#' @export
method(print, FlodeSegmentedRating) <- function(x, ...) {
  cat(sprintf(
    "<FlodeSegmentedRating> %d segment(s), status: %s, R\u00b2 = %.4f\n",
    x@n_segments, x@status, x@coefficients$r_squared[1]
  ))
  print(x@coefficients)
  invisible(x)
}

# ---------------------------------------------------------------------------
# FlodeRatingTable -- gap_check's equation-table representation
# ---------------------------------------------------------------------------

#' A rating equation table (S7), gap_check's native representation
#'
#' @description
#' Wraps the `lower_level`/`upper_level`/`C`/`a`/`n` equation table used
#' throughout the `gap_check` module. Unlike [FlodeRating], this carries
#' its own audit chain directly: `@status` and `@previous` let
#' `align_limb_equations()` return a new object referencing the exact
#' pre-alignment table it was built from, rather than mutating a table
#' in place and relying on a column someone has to remember to check.
#'
#' @param table Data.table with `lower_level`, `upper_level`, `C`, `a`,
#'   `n` columns, one row per limb, contiguous. Same names and sign
#'   convention as [FlodeRating]'s `@limbs` (`Q = C(H - a)^n`).
#' @param status Character. One of `"independently_fitted"`,
#'   `"post_fit_aligned"`.
#' @param previous The exact pre-amendment [FlodeRatingTable] this one
#'   was built from, or `NULL` if it has no such prior identity.
#' @export
FlodeRatingTable <- new_class(
  "FlodeRatingTable",
  properties = list(
    table = new_property(new_S3_class(c("data.table", "data.frame"))),
    status = new_property(class_character, default = "independently_fitted"),
    previous = new_property(class_any, default = NULL)
  ),
  validator = function(self) {
    required <- c("lower_level", "upper_level", "C", "a", "n")
    missing_cols <- setdiff(required, names(self@table))
    if (length(missing_cols)) {
      return(paste("table is missing required column(s):", paste(missing_cols, collapse = ", ")))
    }
    if (nrow(self@table) == 0) return("table must have at least one row")
    n <- nrow(self@table)
    if (n > 1L) {
      contiguous <- all(abs(self@table$upper_level[-n] - self@table$lower_level[-1L]) < 1e-8)
      if (!contiguous) return("limbs must be contiguous (upper_level[i] == lower_level[i+1])")
    }
    NULL
  }
)

#' Print a rating equation table (S7 method)
#'
#' @description
#' Registered against base R's `print` generic for [FlodeRatingTable].
#' Same reasoning as [FlodeRating]'s `print` method: a plain S3
#' `print.FlodeRatingTable` function can never dispatch against a
#' namespace-qualified S7 class name.
#'
#' @param x A [FlodeRatingTable] instance.
#' @param ... Unused; present for consistency with the `print` generic.
#' @return `x`, invisibly.
#' @export
method(print, FlodeRatingTable) <- function(x, ...) {
  cat(sprintf("<FlodeRatingTable> %d limb(s), status: %s\n", nrow(x@table), x@status))
  print(x@table)
  invisible(x)
}

# ---------------------------------------------------------------------------
# Shared generics -- methods registered by rate_optimise.R and
# rate_optimise_segmented.R for their own classes. Every method defined
# anywhere under R/ is available wherever this package is loaded, so both
# are always available alongside this classes file -- there is no
# box::use()-style "only if you imported the fitting module too" caveat
# any more.
# ---------------------------------------------------------------------------

#' Plot a fitted rating curve (S7 generic)
#'
#' @description
#' Dispatches on the fit's class: [FlodeRating] and
#' [FlodeSegmentedRating] each provide their own method, so the same
#' call works regardless of which model architecture produced the fit.
#'
#' @param fit A `FlodeRating` or `FlodeSegmentedRating` object.
#' @param ... Passed to the class-specific method.
#'
#' @export
rating_plot <- new_generic("rating_plot", "fit")

#' Apply a fitted rating to a stage series (S7 generic)
#'
#' @description
#' Dispatches on the fit's class: [FlodeRating] and
#' [FlodeSegmentedRating] each provide their own method. Replaces the
#' previous separate `apply_rating()`/`apply_segmented_rating()` pair --
#' one name, dispatched by what you're holding.
#'
#' @param fit A `FlodeRating` or `FlodeSegmentedRating` object.
#' @param ... Passed to the class-specific method -- typically
#'   `stage_dt` (a data.frame or data.table with a stage column) plus
#'   `stage_col`/`out_col`; see the individual methods' examples.
#'
#' @export
apply_rating <- new_generic("apply_rating", "fit")

#' Convert a fit to gap_check's equation-table representation (S7 generic)
#'
#' @description
#' Replaces `fitted_rating_to_table()`. Dispatches on the fit's class.
#'
#' @param fit A `FlodeRating` or `FlodeSegmentedRating` object.
#' @param ... Passed to the class-specific method.
#'
#' @return A [FlodeRatingTable].
#'
#' @export
as_rating_table <- new_generic("as_rating_table", "fit")
