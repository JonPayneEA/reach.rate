# ============================================================ #
# Tool:         read_helpers
# Description:  Internal helpers shared by read_gaugings() and
#               read_operational_ratings(): read a file or data.frame as
#               text, check the requested columns exist, turn placeholder
#               strings into NA, parse numbers, dates and times, and
#               accumulate a per-row note of anything that did not parse.
#               Nothing here removes a row.
# Author:       Jonathan Payne
# Created:      2026-11-18
# Tier:         3
# Dependencies: data.table
# ============================================================ #

# Text that means "no value" in exports from hydrometric databases.
.placeholder_text <- c("", "NA", "N/A", "n/a", "NULL", "null", "NaN", "-", "--", "---", "----")

# Read a path or a data.frame into a data.table of character columns.
# Reading everything as text keeps every original value, including
# placeholders such as "---", and leaves parsing to explicit, reportable
# steps instead of fread()'s column-type guess.
.read_text_table <- function(x, fn, sep = "auto", encoding = "unknown", sheet = 1L) {
  if (is.data.frame(x)) {
    dt <- copy(as.data.table(x))
    for (col in names(dt)) {
      if (!is.character(dt[[col]])) set(dt, j = col, value = as.character(dt[[col]]))
    }
    return(.unique_names(dt))
  }
  if (!is.character(x) || length(x) != 1L || is.na(x)) {
    stop(fn, ": x must be a single file path or a data.frame")
  }
  if (!file.exists(x)) stop(fn, ": file not found: ", x)
  if (grepl("\\.(xlsx|xlsm|xls)$", x, ignore.case = TRUE)) {
    if (!.has_readxl()) {
      stop(fn, ": reading a spreadsheet needs the 'readxl' package. Install it with install.packages(\"readxl\"), ",
           "or save the sheet as a CSV file.", call. = FALSE)
    }
    # Everything as text, so a number keeps the digits it was stored with
    # and a placeholder such as "---" survives. Date cells arrive as Excel
    # serial numbers; the date and time parsers know about those.
    raw <- readxl::read_excel(x, sheet = sheet, col_types = "text", .name_repair = "minimal")
    return(.unique_names(as.data.table(as.data.frame(raw, stringsAsFactors = FALSE))))
  }
  dt <- fread(x, colClasses = "character", na.strings = NULL, strip.white = TRUE,
              showProgress = FALSE, data.table = TRUE, sep = sep, encoding = encoding,
              blank.lines.skip = TRUE)
  .unique_names(dt)
}

.has_readxl <- function() requireNamespace("readxl", quietly = TRUE)

# A repeated header would make a column impossible to name. Keep every
# column and make the repeats distinct (a, a.1) so none is lost.
.unique_names <- function(dt) {
  nm <- names(dt)
  if (anyDuplicated(nm)) setnames(dt, make.unique(nm))
  dt
}

# Excel stores a date as days since 1899-12-30 and a time as a fraction of
# a day. TRUE where every present value is a plain number in a believable
# range for a date (about 1900 to 2100).
.looks_like_excel_serial <- function(x) {
  x <- x[!is.na(x)]
  if (!length(x)) return(FALSE)
  v <- suppressWarnings(as.numeric(x))
  !anyNA(v) && all(v >= 1 & v < 73415)
}

.excel_serial_to_date <- function(x) {
  as.Date(floor(suppressWarnings(as.numeric(x))), origin = "1899-12-30")
}

# Seconds since midnight from an Excel time cell (a fraction of a day).
.excel_fraction_to_seconds <- function(x) {
  v <- suppressWarnings(as.numeric(x))
  ifelse(!is.na(v) & v >= 0 & v < 1, round(v * 86400), NA_real_)
}

# Seconds since 1970 (read as UTC wall-clock) to a POSIXct whose clock
# reading in `tz` is that same wall-clock time. A file's times carry no
# zone, so the clock reading is kept as it stands; as.POSIXct(n, tz = tz)
# would move it by the zone's offset instead. A wall-clock time that does
# not exist in `tz` (the hour skipped when clocks go forward) becomes NA.
.clock_to_posixct <- function(seconds, tz) {
  utc <- as.POSIXct(seconds, origin = "1970-01-01", tz = "UTC")
  if (identical(tz, "UTC")) return(utc)
  txt <- format(utc, "%Y-%m-%d %H:%M:%S")
  out <- as.POSIXct(txt, format = "%Y-%m-%d %H:%M:%S", tz = tz)
  # Some platforms move a non-existent time forward instead of refusing
  # it; a value that does not read back as it was written is not that time.
  moved <- !is.na(out) & format(out, "%Y-%m-%d %H:%M:%S") != txt
  out[moved] <- NA
  out
}

# Stop with the list of available columns if a requested one is missing.
.require_columns <- function(dt, columns, fn) {
  missing <- setdiff(columns, names(dt))
  if (length(missing)) {
    stop(sprintf(
      "%s: column(s) not found: %s. The columns are: %s. Name the right ones with the matching argument.",
      fn, paste(sprintf("'%s'", missing), collapse = ", "), paste(sprintf("'%s'", names(dt)), collapse = ", ")
    ), call. = FALSE)
  }
  invisible(TRUE)
}

# Trim, and turn placeholder text into NA.
.clean_text <- function(x) {
  x <- trimws(as.character(x))
  x[x %in% .placeholder_text] <- NA_character_
  x
}

# Parse numbers; report text that was present but not a number.
.parse_numeric <- function(x, dec = ".") {
  # A decimal comma is read as a point. Thousands separators are not
  # guessed at: "1,234.5" with dec = "." is reported, not reinterpreted.
  if (identical(dec, ",")) x <- sub(",", ".", x, fixed = TRUE)
  value <- suppressWarnings(as.numeric(x))
  list(value = value, unparsed = !is.na(x) & is.na(value))
}

# Per-row note of what went wrong, built up as semicolon-separated phrases.
.new_notes <- function(n) rep(NA_character_, n)
.add_note <- function(notes, condition, message) {
  condition[is.na(condition)] <- FALSE
  has <- condition & !is.na(notes)
  notes[condition & is.na(notes)] <- message
  notes[has] <- paste(notes[has], message, sep = "; ")
  notes
}

# Date formats tried, in order of preference, for a date column and for a
# column that holds a date and a time together.
.date_formats <- c("%d/%m/%Y", "%Y-%m-%d", "%d-%m-%Y", "%m/%d/%Y", "%d/%m/%y", "%d.%m.%Y")
.datetime_formats <- c(
  "%Y-%m-%d %H:%M:%S", "%Y-%m-%dT%H:%M:%S", "%Y-%m-%d %H:%M", "%d/%m/%Y %H:%M:%S",
  "%d/%m/%Y %H:%M", "%m/%d/%Y %I:%M:%S %p", "%m/%d/%Y %H:%M:%S", "%m/%d/%Y %H:%M",
  "%d/%m/%Y %I:%M:%S %p", "%Y-%m-%d", "%d/%m/%Y", "%m/%d/%Y"
)

# Choose the format that parses the most values (at most 5000 sampled).
# Ties go to the earlier format in the list, which puts day-first before
# month-first. `ambiguous` is TRUE only when the day-month swapped version
# of the chosen format also parses every sampled value AND gives a
# different date for at least one of them. A column of 01/01/2000 reads
# the same either way, so it is not ambiguous; a column holding 03/04/2020
# is, because that is 3 April or 4 March.
.detect_format <- function(x, candidates) {
  x <- x[!is.na(x)]
  if (!length(x)) return(list(format = candidates[1L], rate = NA_real_, ambiguous = FALSE))
  if (length(x) > 5000L) x <- x[round(seq(1, length(x), length.out = 5000L))]
  rate <- vapply(candidates, function(f) mean(!is.na(strptime(x, f, tz = "UTC"))), numeric(1))
  best <- which.max(rate)
  format <- candidates[best]

  ambiguous <- FALSE
  if (rate[best] == 1 && grepl("^%[dm]/%[dm]", format)) {
    swapped <- if (grepl("^%d/%m", format)) sub("^%d/%m", "%m/%d", format) else sub("^%m/%d", "%d/%m", format)
    parsed_swapped <- strptime(x, swapped, tz = "UTC")
    if (all(!is.na(parsed_swapped))) {
      ambiguous <- any(as.numeric(strptime(x, format, tz = "UTC")) != as.numeric(parsed_swapped))
    }
  }
  list(format = format, rate = rate[best], ambiguous = ambiguous)
}

# Seconds since midnight from a time-of-day string.
.parse_clock <- function(x) {
  out <- rep(NA_real_, length(x))
  todo <- !is.na(x)
  for (f in c("%H:%M:%S", "%H:%M", "%I:%M:%S %p", "%I:%M %p")) {
    lt <- strptime(x[todo], f, tz = "UTC")
    ok <- !is.na(lt)
    idx <- which(todo)[ok]
    out[idx] <- lt$hour[ok] * 3600 + lt$min[ok] * 60 + lt$sec[ok]
    todo[idx] <- FALSE
  }
  out
}

# One-line description of the most common issues, for the read summary.
.summarise_notes <- function(notes, top = 5L) {
  if (all(is.na(notes))) return("none")
  parts <- unlist(strsplit(notes[!is.na(notes)], "; ", fixed = TRUE))
  counts <- sort(table(parts), decreasing = TRUE)
  counts <- utils::head(counts, top)
  paste(sprintf("%s (%s)", names(counts), format(as.integer(counts), big.mark = ",", trim = TRUE)), collapse = ", ")
}
