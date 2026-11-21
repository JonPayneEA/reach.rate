# ============================================================ #
# Tool:         export_rating / import_rating
# Description:  Write a rating, and optionally its assessment, to a folder
#               that a reviewer can read without R and that R can read back
#               exactly (Release C). The folder holds the objects themselves
#               (.rds, the record), plain CSV tables of the same content (for
#               people, spreadsheets and other software), a short README and
#               a manifest of checksums, so that a damaged or altered file is
#               found on import and not trusted silently.
# Author:       Jonathan Payne, Environment Agency Flood Forecasting
# Created:      19/11/2026
# Inputs:       A FlodeRating, FlodeSegmentedRating or FlodeRatingTable, and
#               optionally a FlodeAssessment.
# Outputs:      A folder (export_rating) and a list of what it holds
#               (import_rating).
# Dependencies: S7, data.table, tools (md5sum)
# Tier:         3 (operational forecasting support; see the project governance
#               notes before live use)
# ============================================================ #

#' @include flode_classes.R flode_assessment.R
NULL

.export_record_files <- c(rating = "rating.rds", assessment = "assessment.rds")

# Plain tables written beside the objects, for people. Each is a function of
# the rating so that one that cannot be made for this class (a table holds no
# gaugings) is recorded as unavailable and not as an error.
.export_tables <- function(rating, assessment) {
  list(
    limbs = list(file = "limbs.csv", what = "One row per limb: stage range, coefficients and fit statistics.",
                 make = function() rating_limbs(rating)),
    coefficients = list(file = "coefficients.csv", what = "Every fitted coefficient, with its bounds and status.",
                        make = function() rating_coefficients(rating)),
    evidence = list(file = "evidence.csv", what = "Every observation the rating rests on, used or not, with its id and source.",
                    make = function() rating_evidence(rating)),
    history = list(file = "history.csv", what = "What was done to this rating, in order.",
                   make = function() rating_history(rating)),
    lifecycle = list(file = "lifecycle.csv", what = "Who changed the lifecycle, from what to what, when and why. Written only if there are records.",
                     make = function() { lg <- rating_lifecycle(rating); if (nrow(lg)) lg else NULL }),
    support = list(file = "support.csv", what = "What each stage range rests on: gaugings, modelled evidence, or the equation alone.",
                   make = function() rating_support(rating)),
    assessment_checks = list(file = "assessment_checks.csv", what = "Every assessment check, with its domain, status and what to look at.",
                             make = function() if (is.null(assessment)) NULL else assessment_checks(assessment))
  )
}

# A CSV cannot hold a list column. Drop them and say which went.
.csv_table <- function(x) {
  dt <- data.table::as.data.table(data.table::copy(x))
  dropped <- names(dt)[vapply(dt, is.list, logical(1))]
  if (length(dropped)) dt[, (dropped) := NULL]
  list(table = dt, dropped = dropped)
}

.write_text <- function(lines, file) {
  con <- file(file, open = "wb")
  on.exit(close(con), add = TRUE)
  writeLines(enc2utf8(lines), con, useBytes = TRUE)
  invisible(file)
}

#' Write a rating and its assessment to a folder for review
#'
#' @description
#' Saves everything a reviewer needs to check a rating without asking its
#' author: the rating itself, its assessment if you give one, plain tables of
#' the same content, and a manifest that lets [import_rating()] confirm that
#' nothing has changed since.
#'
#' The folder holds:
#'
#' * `rating.rds` and, if given, `assessment.rds`. These are the record.
#'   [import_rating()] reads them back exactly.
#' * `limbs.csv`, `coefficients.csv`, `evidence.csv`, `history.csv`,
#'   `support.csv`, `lifecycle.csv` (only if someone has recorded a lifecycle
#'   change with [set_lifecycle()]) and, with an assessment,
#'   `assessment_checks.csv`. The same
#'   content as plain tables, for people, spreadsheets and other software. A
#'   column that holds a list (evidence `metadata`) is left out of the CSV and
#'   stays in the `.rds`. A table that does not apply to this class (a
#'   [FlodeRatingTable] holds no gaugings) is not written, and the README says so.
#' * `README.txt`, which says what the folder is, when and with what version it
#'   was made, and the rating's lifecycle.
#' * `manifest.csv`, which lists every other file with its size and MD5
#'   checksum. The checksum detects accidental damage and untracked edits. It is
#'   not a defence against someone who edits the manifest as well.
#'
#' Exporting does not change the rating. In particular it never moves the
#' lifecycle on: a draft is exported as a draft. Approval is a decision for a
#' person.
#'
#' @param rating A [FlodeRating], [FlodeSegmentedRating] or [FlodeRatingTable].
#' @param assessment Optional. A [FlodeAssessment] from [assess_rating()].
#' @param path Character. The folder to write. Created if absent.
#' @param overwrite Logical. If `FALSE` (default), a folder that already holds
#'   files from an earlier export is left alone and an error is raised. If
#'   `TRUE`, only the files this function writes are replaced; anything else in
#'   the folder is left where it is.
#'
#' @return Invisibly, a list with `path` and `files`, a `data.table` with one
#'   row per file written (`file`, `description`, `bytes`, `md5`).
#'
#' @seealso [import_rating()], [assess_rating()], [fit_rating()].
#'
#' @examples
#' set.seed(1)
#' stage <- seq(0.3, 3, length.out = 25)
#' gaugings <- data.frame(stage_m = stage,
#'                        discharge_cms = 3 * stage^1.6 * exp(rnorm(25, sd = 0.03)))
#' fit <- fit_rating(gaugings, quiet = TRUE)
#' assessment <- assess_rating(fit, reference_time = as.POSIXct("2025-01-01", tz = "UTC"))
#'
#' folder <- file.path(tempdir(), "example_rating")
#' out <- export_rating(fit, assessment, path = folder)
#' out$files[, c("file", "bytes")]
#'
#' # Read it back: the rating is the same object.
#' back <- import_rating(folder)
#' identical(apply_rating(back$rating, c(1, 2))$discharge,
#'           apply_rating(fit, c(1, 2))$discharge)
#' @export
export_rating <- function(rating, assessment = NULL, path, overwrite = FALSE) {
  fn <- "export_rating()"
  if (!(S7_inherits(rating, FlodeRatingBase) || S7_inherits(rating, FlodeRatingTable))) {
    stop(fn, ": rating must be a FlodeRating, FlodeSegmentedRating or FlodeRatingTable, not ",
         class(rating)[1L], call. = FALSE)
  }
  if (!is.null(assessment) && !S7_inherits(assessment, FlodeAssessment)) {
    stop(fn, ": assessment must be a FlodeAssessment from assess_rating(), or NULL, not ",
         class(assessment)[1L], call. = FALSE)
  }
  if (missing(path) || !is.character(path) || length(path) != 1L || is.na(path) || !nzchar(path)) {
    stop(fn, ": path must be a single folder name", call. = FALSE)
  }
  if (!is.logical(overwrite) || length(overwrite) != 1L || is.na(overwrite)) {
    stop(fn, ": overwrite must be TRUE or FALSE", call. = FALSE)
  }
  if (file.exists(path) && !dir.exists(path)) {
    stop(fn, ": '", path, "' is a file, not a folder", call. = FALSE)
  }

  tables <- .export_tables(rating, assessment)
  ours <- c(unname(.export_record_files[c("rating", if (!is.null(assessment)) "assessment")]),
            vapply(tables, `[[`, "", "file"), "README.txt", "manifest.csv")
  if (dir.exists(path)) {
    present <- intersect(ours, list.files(path, all.files = TRUE, no.. = TRUE))
    if (length(present) && !overwrite) {
      stop(fn, ": '", path, "' already holds files from an export (", paste(present, collapse = ", "),
           "). Use overwrite = TRUE to replace them, or choose another folder.", call. = FALSE)
    }
    unlink(file.path(path, present))
  } else if (!dir.create(path, recursive = TRUE)) {
    stop(fn, ": could not create the folder '", path, "'", call. = FALSE)
  }

  written <- list()
  add <- function(file, description) {
    full <- file.path(path, file)
    written[[length(written) + 1L]] <<- data.table::data.table(
      file = file, description = description,
      bytes = as.numeric(file.size(full)), md5 = unname(tools::md5sum(full))
    )
  }

  saveRDS(rating, file.path(path, .export_record_files[["rating"]]))
  add(.export_record_files[["rating"]], "The rating, as an R object. The record: import_rating() reads this.")
  if (!is.null(assessment)) {
    saveRDS(assessment, file.path(path, .export_record_files[["assessment"]]))
    add(.export_record_files[["assessment"]], "The assessment, as an R object.")
  }

  notes <- character(0)
  for (nm in names(tables)) {
    t <- tables[[nm]]
    res <- tryCatch(t$make(), error = function(e) e)
    if (inherits(res, "error")) {
      notes <- c(notes, sprintf("%s not written: %s", t$file, conditionMessage(res)))
      next
    }
    if (is.null(res)) next
    ct <- .csv_table(res)
    data.table::fwrite(ct$table, file.path(path, t$file))
    add(t$file, t$what)
    if (length(ct$dropped)) {
      notes <- c(notes, sprintf("%s leaves out the list column(s) %s; they are in rating.rds.",
                                t$file, paste(ct$dropped, collapse = ", ")))
    }
  }

  lifecycle <- tryCatch(rating@lifecycle, error = function(e) NA_character_)
  origin <- tryCatch(rating@fit_origin, error = function(e) NA_character_)
  status <- if (is.null(assessment)) "no assessment was exported" else
    paste0("overall ", assessment_status(assessment))
  readme <- c(
    "This folder was made by reach.rate::export_rating().",
    "",
    sprintf("Made:               %s", format(Sys.time(), tz = "UTC", format = "%Y-%m-%d %H:%M:%S UTC")),
    sprintf("reach.rate version: %s", as.character(utils::packageVersion("reach.rate"))),
    sprintf("Schema version:     %d", .rating_schema_version),
    sprintf("Rating class:       %s", class(rating)[1L]),
    sprintf("Lifecycle:          %s", lifecycle),
    sprintf("Fit origin:         %s", origin),
    sprintf("Assessment:         %s", status),
    "",
    "The lifecycle is recorded as it was. Exporting does not approve a rating:",
    "approval is a decision for a person.",
    "",
    "To read this folder back into R:",
    "",
    "    imported <- reach.rate::import_rating(\"this-folder\")",
    "    imported$rating",
    "",
    "import_rating() checks every file against manifest.csv first. The .rds files are",
    "the record; the .csv files are the same content for reading without R.",
    "",
    "Files:",
    vapply(written, function(w) sprintf("  %-22s %s", w$file, w$description), ""),
    if (length(notes)) c("", "Notes:", paste0("  ", notes))
  )
  .write_text(readme, file.path(path, "README.txt"))
  add("README.txt", "This file.")

  files <- data.table::rbindlist(written)
  data.table::fwrite(files, file.path(path, "manifest.csv"))
  invisible(list(path = normalizePath(path), files = files))
}

# Migrations from one schema version to the next, keyed by the version they
# start from: .rating_migrations[["2"]] takes a version 2 object to version 3.
# There are none yet, because version 2 is the first schema that carries a
# version. The mechanism is here and tested so that the first change to the
# layout has somewhere to go, and so that an object from an older layout is
# refused with a reason and not loaded half-understood.
.rating_migrations <- list()

.migrate_rating <- function(x, fn = "import_rating()") {
  v <- x@schema_version
  while (!is.na(v) && v < .rating_schema_version) {
    step <- .rating_migrations[[as.character(v)]]
    if (is.null(step)) {
      stop(sprintf(
        paste0("%s: this rating was saved under schema version %d and this reach.rate understands %d. ",
               "No migration from %d exists, so it cannot be read as it stands. ",
               "Refit it from its evidence, or use the reach.rate version that saved it."),
        fn, v, .rating_schema_version, v), call. = FALSE)
    }
    x <- step(x)
    nv <- x@schema_version
    if (is.na(nv) || nv <= v) {
      stop(fn, ": the migration from schema version ", v, " did not advance the version", call. = FALSE)
    }
    v <- nv
  }
  x
}

#' Read back a rating written by export_rating()
#'
#' @description
#' Reads a folder made by [export_rating()] and returns the rating and, if one
#' was exported, its assessment. Before it reads anything, it checks every file
#' against the folder's `manifest.csv`, so a file that was damaged, truncated or
#' edited afterwards is reported by name and not trusted.
#'
#' The rating that comes back is the one that went in: the same coefficients,
#' evidence, history, provenance and lifecycle, equal in every value. (It is not
#' `identical()` in the byte-for-byte sense, which no R object is after being
#' written and read: `data.table` keeps internal pointers that differ.) A rating saved under an older
#' schema version is migrated if a migration exists, and refused with the reason
#' if not. A rating saved under a newer one is refused: update the package.
#'
#' @param path Character. A folder made by [export_rating()].
#' @param verify Logical. If `TRUE` (default), check every file against the
#'   manifest first. Switching it off is for the case where you have already
#'   decided the folder is trusted and the manifest is lost.
#'
#' @return A list with `rating`, `assessment` (`NULL` if none was exported) and
#'   `manifest`, the checksum table.
#'
#' @seealso [export_rating()].
#'
#' @examples
#' set.seed(1)
#' stage <- seq(0.3, 3, length.out = 25)
#' gaugings <- data.frame(stage_m = stage,
#'                        discharge_cms = 3 * stage^1.6 * exp(rnorm(25, sd = 0.03)))
#' fit <- fit_rating(gaugings, quiet = TRUE)
#' folder <- file.path(tempdir(), "example_import")
#' export_rating(fit, path = folder)
#'
#' back <- import_rating(folder)
#' rating_limbs(back$rating)
#' @export
import_rating <- function(path, verify = TRUE) {
  fn <- "import_rating()"
  if (missing(path) || !is.character(path) || length(path) != 1L || is.na(path) || !nzchar(path)) {
    stop(fn, ": path must be a single folder name", call. = FALSE)
  }
  if (!is.logical(verify) || length(verify) != 1L || is.na(verify)) {
    stop(fn, ": verify must be TRUE or FALSE", call. = FALSE)
  }
  if (!dir.exists(path)) stop(fn, ": '", path, "' is not a folder", call. = FALSE)
  mf <- file.path(path, "manifest.csv")
  if (!file.exists(mf)) {
    stop(fn, ": '", path, "' has no manifest.csv, so it does not look like a folder made by export_rating()",
         call. = FALSE)
  }
  manifest <- data.table::fread(mf, colClasses = list(character = c("file", "description", "md5")))
  if (!all(c("file", "md5") %in% names(manifest)) || !.export_record_files[["rating"]] %in% manifest$file) {
    stop(fn, ": manifest.csv does not list ", .export_record_files[["rating"]], ", so the folder is incomplete",
         call. = FALSE)
  }
  if (verify) {
    for (i in seq_len(nrow(manifest))) {
      f <- file.path(path, manifest$file[i])
      if (!file.exists(f)) {
        stop(fn, ": ", manifest$file[i], " is listed in the manifest but missing from the folder", call. = FALSE)
      }
      if (!identical(unname(tools::md5sum(f)), manifest$md5[i])) {
        stop(fn, ": ", manifest$file[i], " does not match its checksum in the manifest. It was changed or damaged ",
             "after it was exported, so it is not read.", call. = FALSE)
      }
    }
  }
  read_obj <- function(file, ok, what) {
    obj <- tryCatch(readRDS(file.path(path, file)),
                    error = function(e) stop(fn, ": could not read ", file, ": ", conditionMessage(e), call. = FALSE))
    if (!ok(obj)) stop(fn, ": ", file, " does not hold ", what, call. = FALSE)
    obj
  }
  rating <- read_obj(.export_record_files[["rating"]],
                     function(o) S7_inherits(o, FlodeRatingBase) || S7_inherits(o, FlodeRatingTable),
                     "a FlodeRating, FlodeSegmentedRating or FlodeRatingTable")
  rating <- tryCatch(
    .migrate_rating(rating, fn),
    error = function(e) stop(conditionMessage(e), call. = FALSE)
  )
  problems <- tryCatch({ S7::validate(rating); NULL }, error = function(e) conditionMessage(e))
  if (!is.null(problems)) {
    stop(fn, ": the saved rating is not valid: ", problems, call. = FALSE)
  }
  assessment <- NULL
  if (.export_record_files[["assessment"]] %in% manifest$file) {
    assessment <- read_obj(.export_record_files[["assessment"]], function(o) S7_inherits(o, FlodeAssessment),
                           "a FlodeAssessment")
  }
  list(rating = rating, assessment = assessment, manifest = manifest)
}
