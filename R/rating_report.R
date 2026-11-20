# ============================================================ #
# Tool:         rating_report
# Description:  Render a rating and its assessment as a self-contained HTML
#               report a reviewer can read without R (Release C). Built from
#               the stored objects only: it never refits, so it gives the same
#               report from an exported folder as from the live session.
# Author:       Jonathan Payne, Environment Agency Flood Forecasting
# Created:      20/11/2026
# Inputs:       A FlodeRating, FlodeSegmentedRating or FlodeRatingTable, and
#               optionally a FlodeAssessment; or a folder made by
#               export_rating().
# Outputs:      An HTML file.
# Dependencies: rmarkdown, knitr and pandoc (Suggests), data.table, S7
# Tier:         3 (operational forecasting support; see the project governance
#               notes before live use)
# ============================================================ #

#' @include export_rating.R
NULL

#' Write a review report for a rating
#'
#' @description
#' Renders one self-contained HTML page that a reviewer can read without R:
#' the rating's status and lifecycle, its equations and plot, the evidence and
#' what was left out, every assessment check that did not pass with what to
#' look at, what each stage range rests on, how the rating was made and what
#' has been done to it since, and a short list of questions for the reviewer.
#'
#' The report is drawn from the stored objects and never refits anything, so
#' the same rating and assessment give the same report whether they come from
#' the live session or from a folder made by [export_rating()]. It does not
#' approve a rating and never changes its lifecycle. It says so on its first
#' page.
#'
#' Needs the `rmarkdown` and `knitr` packages and pandoc, which are suggested
#' and not required.
#'
#' @param x A [FlodeRating], [FlodeSegmentedRating] or [FlodeRatingTable], or the
#'   path to a folder made by [export_rating()].
#' @param assessment Optional. A [FlodeAssessment] from [assess_rating()]. If `x`
#'   is a folder and this is `NULL`, the folder's own assessment is used.
#' @param path Character. The HTML file to write. Default `"rating_report.html"`.
#' @param title Character. The report's title.
#' @param overwrite Logical. If `FALSE` (default), an existing file is left alone
#'   and an error is raised.
#'
#' @return Invisibly, the full path of the file written.
#'
#' @seealso [export_rating()], [import_rating()], [assess_rating()].
#'
#' @examples
#' \donttest{
#' if (requireNamespace("rmarkdown", quietly = TRUE) && rmarkdown::pandoc_available()) {
#'   set.seed(1)
#'   stage <- seq(0.3, 3, length.out = 25)
#'   gaugings <- data.frame(stage_m = stage,
#'                          discharge_cms = 3 * stage^1.6 * exp(rnorm(25, sd = 0.03)))
#'   fit <- fit_rating(gaugings, quiet = TRUE)
#'   assessment <- assess_rating(fit, reference_time = as.POSIXct("2025-01-01", tz = "UTC"))
#'   out <- rating_report(fit, assessment, path = file.path(tempdir(), "rating_report.html"))
#'   file.exists(out)
#' }
#' }
#' @export
rating_report <- function(x, assessment = NULL, path = "rating_report.html",
                          title = "Rating report", overwrite = FALSE) {
  fn <- "rating_report()"
  if (!requireNamespace("rmarkdown", quietly = TRUE) || !requireNamespace("knitr", quietly = TRUE)) {
    stop(fn, ": needs the rmarkdown and knitr packages. Install them with install.packages(c(\"rmarkdown\", \"knitr\")).",
         call. = FALSE)
  }
  if (!rmarkdown::pandoc_available()) {
    stop(fn, ": needs pandoc to build the page, and none was found. RStudio ships one; otherwise install pandoc.",
         call. = FALSE)
  }
  if (is.character(x)) {
    if (length(x) != 1L || is.na(x)) stop(fn, ": a folder must be a single path", call. = FALSE)
    imported <- import_rating(x)
    x <- imported$rating
    if (is.null(assessment)) assessment <- imported$assessment
  }
  if (!(S7_inherits(x, FlodeRatingBase) || S7_inherits(x, FlodeRatingTable))) {
    stop(fn, ": x must be a FlodeRating, FlodeSegmentedRating, FlodeRatingTable, or the path to a folder from export_rating(), not ",
         class(x)[1L], call. = FALSE)
  }
  if (!is.null(assessment) && !S7_inherits(assessment, FlodeAssessment)) {
    stop(fn, ": assessment must be a FlodeAssessment from assess_rating(), or NULL, not ",
         class(assessment)[1L], call. = FALSE)
  }
  if (!is.character(path) || length(path) != 1L || is.na(path) || !nzchar(path)) {
    stop(fn, ": path must be a single file name", call. = FALSE)
  }
  if (!is.character(title) || length(title) != 1L || is.na(title)) {
    stop(fn, ": title must be a single string", call. = FALSE)
  }
  if (!is.logical(overwrite) || length(overwrite) != 1L || is.na(overwrite)) {
    stop(fn, ": overwrite must be TRUE or FALSE", call. = FALSE)
  }
  if (file.exists(path) && !overwrite) {
    stop(fn, ": '", path, "' already exists. Use overwrite = TRUE to replace it, or choose another file.", call. = FALSE)
  }
  template <- system.file("templates", "rating_report.Rmd", package = "reach.rate")
  if (!nzchar(template)) stop(fn, ": the report template is missing from the installed package", call. = FALSE)

  dir <- dirname(path)
  if (!dir.exists(dir) && !dir.create(dir, recursive = TRUE)) {
    stop(fn, ": could not create the folder '", dir, "'", call. = FALSE)
  }
  work <- tempfile("report_")
  dir.create(work)
  on.exit(unlink(work, recursive = TRUE), add = TRUE)
  file.copy(template, file.path(work, "rating_report.Rmd"))
  out <- tryCatch(
    rmarkdown::render(
      file.path(work, "rating_report.Rmd"),
      output_file = "rating_report.html", output_dir = work, quiet = TRUE,
      params = list(rating = x, assessment = assessment, title = title),
      envir = new.env(parent = globalenv())
    ),
    error = function(e) stop(fn, ": the report could not be built: ", conditionMessage(e), call. = FALSE)
  )
  file.copy(out, path, overwrite = TRUE)
  invisible(normalizePath(path))
}
