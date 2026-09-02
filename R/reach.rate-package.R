# ============================================================ #
# File:         reach.rate-package.R
# Purpose:      Package-level documentation and the centralised import
#               directives for the whole package. Every R/ file in this
#               package was originally written as a box module, each with
#               its own box::use() block; box gives every module its own
#               isolated namespace, so each module had to declare its own
#               imports, including of its sibling modules. A package has
#               one shared namespace instead, so:
#                 - imports of external packages (data.table, ggplot2,
#                   minpack.lm, S7, logger, gridExtra, grid, scales,
#                   stats, graphics) are declared once here, centrally,
#                   via roxygen2 @import/@importFrom tags rather than
#                   repeated per file;
#                 - imports of sibling modules (e.g. every file that used
#                   to box::use(./flode_classes[...]) or
#                   box::use(./rate_optimise[...])) are gone entirely --
#                   every function in R/ can already see every other
#                   function in R/, with nothing to import.
#               data.table and ggplot2 are @import'd wholesale (matching
#               the wildcard box::use(data.table[...])/box::use(ggplot2[...])
#               every module used) rather than curated with @importFrom,
#               since dozens of symbols from each are used bare throughout
#               (data.table's `:=`/.N/.SD/data.table()/copy()/setorder()/
#               fifelse() and friends; ggplot2's geom_*()/aes()/theme_*()
#               and friends) -- curating that list would just reproduce
#               the package's exports one at a time.
# ============================================================ #

#' reach.rate: fit, diagnose, and apply hydrometric rating curves
#'
#' @description
#' Tools for fitting multi-limb power-law stage-discharge rating curves
#' by nonlinear least squares ([rate_optimise()]), diagnosing fit
#' quality ([plot_rating_residuals()], [flag_extrapolated_limbs()]),
#' detecting and resolving discontinuities between independently-fitted
#' limbs ([detect_rc_gaps()], [resolve_rc_gaps()],
#' [align_limb_equations()]), converting a fitted rating into a
#' discharge time series ([apply_rating()]), and documenting rating
#' amendments ([compare_ratings()]). [rate_optimise_segmented()] offers
#' a structurally different, joint segmented parameterisation after
#' Hodson et al. (2024), with no junction gap to reconcile in the first
#' place.
#'
#' Fitted ratings are represented as S7 classes ([FlodeRating],
#' [FlodeSegmentedRating], [FlodeRatingTable]) that carry their own
#' gaugings, fitting bookkeeping, and provenance -- see
#' `vignette("rating_curves_guide", package = "reach.rate")` for the
#' full walkthrough and the hydrological reasoning behind the toolkit's
#' design choices.
#'
#' @keywords internal
"_PACKAGE"

## Package-level import directives -- see the file banner above for why
## these are centralised here rather than repeated per file.
#'
#' @import data.table
#' @import ggplot2
#' @importFrom S7 new_class new_property new_generic new_S3_class
#' @importFrom S7 class_any class_list class_character class_logical
#' @importFrom S7 class_integer class_double method method<- S7_object
#' @importFrom S7 S7_inherits
#' @importFrom minpack.lm nlsLM nls.lm.control
#' @importFrom logger log_info log_threshold INFO
#' @importFrom gridExtra grid.arrange arrangeGrob
#' @importFrom grid textGrob gpar
#' @importFrom scales comma_format
#' @importFrom stats coef residuals lm median quantile sd predict rnorm
#' @importFrom stats setNames approx as.formula vcov uniroot
#' @importFrom graphics plot lines abline
NULL

# data.table's namespace-awareness flag. A box module needed this set
# per file (box never sets it the way a real package does); a package
# only needs it once, as a top-level binding anywhere under R/.
.datatable.aware <- TRUE
