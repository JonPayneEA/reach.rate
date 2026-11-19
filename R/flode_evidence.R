# ---------------------------------------------------------------------------
# FlodeEvidence -- the canonical table of observations a rating rests on.
#
# It extends data.table, so `evidence$stage_m`, `evidence[stage_m > 1]`,
# nrow() and saveRDS() behave as they do for any data.table. What it adds is
# a fixed set of columns with fixed meanings, and a validator that holds
# them to it. A rating keeps its evidence in `@gaugings`; a plain table
# given to a fitter is converted on the way in, with a note of what was
# assumed.
# ---------------------------------------------------------------------------

# The schema version of a saved rating object. Bumped when a property is
# added, removed or changes meaning. 1 was the package before FlodeEvidence
# and the status split; those objects carry no version at all.
.rating_schema_version <- 2L

# Controlled vocabulary for `source_type`. A default chosen for this
# package, not taken from an external brief; extending it is a one-line
# change here, and the validator, docs and tests all read it from here.
.evidence_source_types <- c(
  "gauging", "operational_rating", "modelled",
  "cross_section", "structure_equation", "other"
)

# Canonical columns, in order, with the class each must have.
.evidence_columns <- c(
  evidence_id = "character", site_id = "character", stage_m = "numeric",
  discharge_cms = "numeric", observation_time = "time", source_type = "character",
  source_name = "character", source_version = "character", quality_code = "character",
  included = "logical", exclusion_reason = "character", weight = "numeric",
  notes = "character", source_row = "integer", metadata = "list"
)

#' @include s7_external.R
NULL

#' The controlled vocabulary for where evidence came from
#'
#' @description
#' The values `source_type` may take in a [FlodeEvidence] table. Anything
#' else is refused, so that a rating's evidence can be grouped and
#' filtered by origin without guessing at spellings.
#'
#' @return A character vector.
#'
#' @seealso [FlodeEvidence()], [as_flode_evidence()]
#'
#' @examples
#' evidence_source_types()
#'
#' @export
evidence_source_types <- function() .evidence_source_types

.evidence_dt_class <- new_S3_class(
  c("data.table", "data.frame"),
  constructor = function(.data = data.table()) as.data.table(.data)
)

#' Evidence a rating rests on (S7)
#'
#' @description
#' A `data.table` with a fixed set of columns. Each row is one observation
#' (a spot gauging, a point read off an operational rating, a modelled
#' value, a cross-section computation or a structure equation) and keeps a
#' stable identifier, so that a diagnostic, a flag or an exclusion can name
#' the observation it concerns. Because it is a data.table, ordinary
#' subsetting and column access work unchanged.
#'
#' The columns are:
#'
#' | column | class | meaning |
#' |---|---|---|
#' | `evidence_id` | character | unique, never missing; the row's identity |
#' | `site_id` | character | station identifier, `NA` if unknown |
#' | `stage_m` | numeric | stage in metres |
#' | `discharge_cms` | numeric | discharge in cubic metres per second |
#' | `observation_time` | `Date` or `POSIXct` | when it was observed, `NA` if unknown |
#' | `source_type` | character | one of [evidence_source_types()] |
#' | `source_name` | character | the file, system or method it came from |
#' | `source_version` | character | the version or extract date of the source |
#' | `quality_code` | character | the source's own quality marker, carried uninterpreted |
#' | `included` | logical | whether a fit should use it |
#' | `exclusion_reason` | character | why not, when `included` is `FALSE` |
#' | `weight` | numeric | a prior weight, 1 unless set |
#' | `notes` | character | free text |
#' | `source_row` | integer | the row number in the source, for tracing back |
#' | `metadata` | list | anything source-specific, one entry per row |
#'
#' Columns beyond these are allowed and kept, after the canonical ones.
#'
#' @param .data A `data.frame` or `data.table` holding every canonical
#'   column. To build one from a table that does not, use
#'   [as_flode_evidence()], which fills the missing columns and says what it
#'   assumed.
#' @param conversion_note Character. What was assumed when the table was
#'   built from a plainer one; empty when none was.
#'
#' @return A `FlodeEvidence`, which is also a `data.table`.
#'
#' @seealso [as_flode_evidence()], [evidence_source_types()],
#'   [rating_evidence()]
#'
#' @examples
#' evidence <- as_flode_evidence(data.frame(
#'   stage_m = c(0.5, 1.1, 1.8), discharge_cms = c(1.2, 5.1, 12.4)
#' ))
#' evidence
#' evidence$stage_m
#' nrow(evidence[stage_m > 1])
#'
#' @export
FlodeEvidence <- new_class(
  "FlodeEvidence",
  parent = .evidence_dt_class,
  properties = list(
    conversion_note = new_property(class_character, default = character(0))
  ),
  constructor = function(.data = data.table(), conversion_note = character(0)) {
    new_object(as.data.table(.data), conversion_note = conversion_note)
  },
  validator = function(self) {
    # An empty table is the class default, so it passes; a rating's own
    # validator is what insists on at least one row.
    if (ncol(self) == 0L) return(NULL)
    problems <- character(0)
    missing_cols <- setdiff(names(.evidence_columns), names(self))
    if (length(missing_cols)) {
      return(paste0(
        "evidence is missing column(s): ", paste(missing_cols, collapse = ", "),
        ". as_flode_evidence() fills them in."
      ))
    }
    ok <- function(col, cls) {
      v <- .subset2(self, col)
      switch(cls,
        character = is.character(v),
        numeric = is.numeric(v),
        integer = is.integer(v),
        logical = is.logical(v),
        list = is.list(v),
        time = inherits(v, c("Date", "POSIXct"))
      )
    }
    for (col in names(.evidence_columns)) {
      if (!ok(col, .evidence_columns[[col]])) {
        problems <- c(problems, sprintf(
          "%s must be %s", col,
          if (.evidence_columns[[col]] == "time") "a Date or POSIXct vector" else paste("of class", .evidence_columns[[col]])
        ))
      }
    }
    if (length(problems)) return(problems)
    ids <- .subset2(self, "evidence_id")
    if (anyNA(ids) || any(!nzchar(ids))) return("evidence_id must never be missing or empty")
    if (anyDuplicated(ids)) {
      return(sprintf("evidence_id must be unique; repeated: %s", paste(unique(ids[duplicated(ids)])[1:min(3, sum(duplicated(ids)))], collapse = ", ")))
    }
    st <- .subset2(self, "source_type")
    bad <- setdiff(unique(st), .evidence_source_types)
    if (length(bad) || anyNA(st)) {
      return(sprintf(
        "source_type must be one of: %s (found: %s)",
        paste(.evidence_source_types, collapse = ", "),
        paste(if (anyNA(st)) c("NA", bad) else bad, collapse = ", ")
      ))
    }
    if (anyNA(.subset2(self, "included"))) return("included must be TRUE or FALSE, never missing")
    NULL
  }
)

#' Make evidence from a plain table
#'
#' @description
#' Turns a `data.frame` or `data.table` into a [FlodeEvidence], keeping
#' every column it already has and filling the rest. Only `stage_m` and
#' `discharge_cms` are required. The fill is deliberately plain, and the
#' result says what it assumed in its `conversion_note`:
#'
#' * `evidence_id` is generated as `G001`, `G002` and so on, in row order.
#' * `observation_time` is taken from `gauging_datetime` when that column
#'   exists, and is otherwise `NA`.
#' * A table from [read_gaugings()] is recognised: its `station_id` becomes
#'   `site_id`, the file name becomes `source_name`, and a row whose stage
#'   or discharge could not be read becomes `included = FALSE` with its
#'   `read_issue` as the `exclusion_reason`. Nothing is dropped.
#' * `source_type` is `"gauging"`, `weight` is 1 and `source_row` is the row
#'   position. `included` is `TRUE` unless the stage or discharge is
#'   missing, in which case it is `FALSE` and `exclusion_reason` says why.
#' * The remaining text columns are `NA`, and `metadata` is empty for each row.
#'
#' A table that is already a `FlodeEvidence` is returned as it is.
#'
#' @param x A `data.frame`, `data.table` or [FlodeEvidence].
#'
#' @return A [FlodeEvidence].
#'
#' @seealso [FlodeEvidence()], [evidence_source_types()]
#'
#' @examples
#' plain <- data.frame(stage_m = c(0.5, 1.1, 1.8), discharge_cms = c(1.2, 5.1, 12.4))
#' evidence <- as_flode_evidence(plain)
#' evidence$evidence_id
#' evidence@conversion_note
#'
#' @export
as_flode_evidence <- function(x) {
  if (S7_inherits(x, FlodeEvidence)) return(x)
  if (!is.data.frame(x)) stop("x must be a data.frame, data.table or FlodeEvidence", call. = FALSE)
  dt <- copy(as.data.table(x))
  need <- setdiff(c("stage_m", "discharge_cms"), names(dt))
  if (length(need)) {
    stop(sprintf("evidence needs a column named %s", paste(shQuote(need), collapse = " and ")), call. = FALSE)
  }
  n <- nrow(dt)
  filled <- character(0)
  fill <- function(col, value) {
    if (!col %in% names(dt)) {
      set(dt, j = col, value = value)
      filled <<- c(filled, col)
    }
  }
  width <- max(3L, nchar(as.character(n)))
  fill("evidence_id", if (n) sprintf(paste0("G%0", width, "d"), seq_len(n)) else character(0))
  fill("site_id", if ("station_id" %in% names(dt)) as.character(dt$station_id) else rep(NA_character_, n))
  obs <- if ("gauging_datetime" %in% names(dt) && inherits(dt$gauging_datetime, c("Date", "POSIXct"))) {
    dt$gauging_datetime
  } else {
    as.POSIXct(rep(NA_real_, n), origin = "1970-01-01", tz = "UTC")
  }
  fill("observation_time", obs)
  fill("source_type", rep("gauging", n))
  src <- attr(x, "read_info", exact = TRUE)$source
  fill("source_name", rep(if (is.null(src)) NA_character_ else src, n))
  for (col in c("source_version", "quality_code", "notes")) {
    fill(col, rep(NA_character_, n))
  }
  # A row whose stage or discharge could not be read cannot be fitted.
  unusable <- is.na(dt$stage_m) | is.na(dt$discharge_cms)
  reason <- rep(NA_character_, n)
  reason[unusable] <- if ("read_issue" %in% names(dt)) as.character(dt$read_issue)[unusable] else "stage or discharge missing"
  fill("exclusion_reason", reason)
  fill("included", !unusable)
  fill("weight", rep(1, n))
  fill("source_row", seq_len(n))
  fill("metadata", vector("list", n))
  setcolorder(dt, c(names(.evidence_columns), setdiff(names(dt), names(.evidence_columns))))
  note <- if (length(filled)) {
    sprintf(
      "Converted from a plain table; filled %s. source_type assumed 'gauging', weight assumed 1, included TRUE unless stage or discharge is missing.",
      paste(filled, collapse = ", ")
    )
  } else {
    character(0)
  }
  FlodeEvidence(dt, conversion_note = note)
}

#' The schema version of rating objects
#'
#' @description
#' The version of the layout in which [FlodeRating], [FlodeSegmentedRating]
#' and [FlodeRatingTable] objects are stored. It changes when a stored
#' property is added, removed or changes meaning, not on every release, so
#' it is the number to check before trusting an object read back with
#' `readRDS()`. Each rating records the version it was made under in
#' [rating_provenance()], and refuses to validate if that version is
#' missing or newer than this one.
#'
#' @return A single integer.
#'
#' @seealso [rating_provenance()]
#'
#' @examples
#' rating_schema_version()
#'
#' @export
rating_schema_version <- function() .rating_schema_version

# `[` on evidence. data.table's own `[` keeps the S7 class on its result but
# drops the object's other attributes, so selecting columns (`ev[, .(a, b)]`)
# or aggregating (`ev[, .(m = mean(stage_m))]`) used to return something that
# said it was a FlodeEvidence and had no conversion_note, which then failed
# to print or validate. Here, a result that still has every canonical column
# stays evidence and keeps its note; one that does not becomes an ordinary
# data.table. Registered in .onLoad(), because S7 gives the class a name
# (`reach.rate::FlodeEvidence`) that roxygen cannot write into NAMESPACE.
.subset_flode_evidence <- function(x, ...) {
  note <- attr(x, "conversion_note", exact = TRUE)
  out <- NextMethod()
  if (!inherits(out, "data.table")) return(out)
  if (all(names(.evidence_columns) %in% names(out))) {
    if (is.null(attr(out, "conversion_note", exact = TRUE))) {
      data.table::setattr(out, "conversion_note", if (is.null(note)) character(0) else note)
    }
  } else {
    data.table::setattr(out, "class", c("data.table", "data.frame"))
    data.table::setattr(out, "conversion_note", NULL)
  }
  out
}

#' Print evidence (S7 method)
#' @param x A [FlodeEvidence].
#' @param ... Passed to the data.table print method.
#' @noRd
method(.s7_print, FlodeEvidence) <- function(x, ...) {
  inc <- .subset2(x, "included")
  cat(sprintf(
    "<FlodeEvidence> %d row(s), %d included, source type(s): %s\n",
    nrow(x), sum(inc, na.rm = TRUE), paste(unique(.subset2(x, "source_type")), collapse = ", ")
  ))
  if (length(x@conversion_note)) cat("Note:", x@conversion_note, "\n")
  shown <- as.data.table(x)[, intersect(c("evidence_id", "stage_m", "discharge_cms", "observation_time", "source_type", "included"), names(x)), with = FALSE]
  print(shown, ...)
  invisible(x)
}
