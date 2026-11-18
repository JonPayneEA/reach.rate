# ============================================================ #
# Tool:         read_gaugings
# Description:  Read a spot-gauging archive from a CSV file or a
#               data.frame into one row per gauging with standard column
#               names, a parsed observation time, and a per-row note of
#               anything that did not parse. Removes nothing.
# Author:       Jonathan Payne
# Created:      2026-11-18
# Tier:         3
# Inputs:       A file path or data.frame with a station id, a date, a
#               stage and a discharge (and optionally a time of day).
# Outputs:      A data.table. See ?read_gaugings.
# Dependencies: data.table
# ============================================================ #

#' @include read_helpers.R
NULL

#' Read a spot-gauging archive
#'
#' @description
#' Reads gaugings from a CSV file (or a data.frame) into a table with
#' standard column names, whatever the original headers were called. It
#' cleans nothing and removes nothing: every row of the file is returned,
#' in order. What it does is read every column as text, turn placeholder
#' text such as `---` into a missing value, parse stage, discharge, date
#' and time explicitly, and record in `read_issue` anything that did not
#' parse, so a bad row is visible and not silently lost or changed.
#'
#' The defaults match the column names of the Environment Agency
#' WISKI-style gauging export (`Station number`, `Date`, `Time`, `Stage`,
#' `Flow`). Use the mapping arguments for any other headers.
#'
#' Dates are detected, not assumed. The format that parses the most values
#' is used, day-first ahead of month-first when both fit (`04/05/1970` is
#' read as 4 May). The format chosen is reported in the message, with a
#' warning when the choice was a default and could be wrong. Pass
#' `date_format` (for example `"%d/%m/%Y"`) to settle it.
#'
#' @param x A file path to a delimited text file, or a data.frame.
#' @param station_id,station_name Character. Columns holding the station
#'   identifier and name. The name is optional: it is skipped if the file
#'   has no column called `Station name`, or if `station_name = NULL`.
#' @param date,time Character. Columns holding the date and the time of
#'   day. `time = NULL` if there is none; a missing time is then
#'   midnight, with no note.
#' @param stage,discharge Character. Columns holding stage (m) and
#'   discharge (cumecs).
#' @param date_format A [strptime()] format for the date column, or `NULL`
#'   (default) to detect it.
#' @param tz Time zone label for `observation_time`. Default `"UTC"`. The
#'   clock time in the file is used as it stands, with no daylight-saving
#'   adjustment, so it is only as good as the file's own convention.
#' @param quiet Logical. `TRUE` suppresses the summary message.
#'
#' @return A data.table, one row per row of the input, with these columns
#'   first: `source_row` (row of the data, header excluded), `station_id`,
#'   `station_name`, `observation_time` (POSIXct), `stage_m`,
#'   `discharge_cms` and `read_issue` (`NA` when the row parsed cleanly,
#'   otherwise the problems separated by semicolons). Every other column
#'   of the input follows unchanged, as text. The columns you mapped are
#'   not repeated; the file still has their original values.
#'
#' @section Notes the function can add:
#' `station id missing`, `stage missing`, `discharge missing`,
#' `stage not a number`, `discharge not a number`, `date missing`,
#' `date not read`, `date outside 1800 to next year`, `time not read` and
#' `time missing, midnight assumed`. A stage of zero, a zero discharge or
#' a discharge with no stage are not noted: they parse, and whether they
#' are acceptable is a hydrometric judgement for a later check.
#'
#' @seealso [read_operational_ratings()] for the matching ratings export;
#'   [compare_gaugings_to_rating()] to check a rating against the result.
#'
#' @examples
#' # A small archive as it might arrive: placeholder text, a blank
#' # station, an unreadable stage, and a stage of zero with a flow.
#' raw <- data.frame(
#'   `Station number` = c("10250", "10250", "", "F2405", "F2405"),
#'   Date  = c("03/02/1970", "05/05/1970", "29/05/1970", "06/01/1960", "12/01/1960"),
#'   Time  = c("12:47:00", "13:02:00", "", "00:00:00", "00:01:00"),
#'   Stage = c("1.6", "---", "0.85", "1.885", "0"),
#'   Flow  = c("53.3371", "9.738", "6.6824", "104.189", "0.425"),
#'   Remark = c("", "dry", "", "FALLING", ""),
#'   check.names = FALSE
#' )
#' gaugings <- read_gaugings(raw)
#' gaugings
#' gaugings[!is.na(gaugings$read_issue), c("source_row", "read_issue")]
#'
#' @export
read_gaugings <- function(x, station_id = "Station number", station_name = "Station name",
                          date = "Date", time = "Time", stage = "Stage", discharge = "Flow",
                          date_format = NULL, tz = "UTC", quiet = FALSE) {
  fn <- "read_gaugings()"
  dt <- .read_text_table(x, fn)
  # The station name is optional: if it is absent under its default name,
  # skip it; a name you gave yourself must exist.
  if (identical(station_name, "Station name") && !"Station name" %in% names(dt)) station_name <- NULL
  mapped <- c(station_id, station_name, date, time, stage, discharge)
  .require_columns(dt, mapped, fn)
  n <- nrow(dt)

  station <- .clean_text(dt[[station_id]])
  name <- if (is.null(station_name)) rep(NA_character_, n) else .clean_text(dt[[station_name]])
  stage_txt <- .clean_text(dt[[stage]])
  flow_txt <- .clean_text(dt[[discharge]])
  date_txt <- .clean_text(dt[[date]])
  time_txt <- if (is.null(time)) rep(NA_character_, n) else .clean_text(dt[[time]])

  stage_p <- .parse_numeric(stage_txt)
  flow_p <- .parse_numeric(flow_txt)

  detected <- NULL
  if (is.null(date_format)) {
    detected <- .detect_format(date_txt, .date_formats)
    date_format <- detected$format
  }
  parsed_date <- as.Date(strptime(date_txt, date_format, tz = "UTC"))
  clock <- .parse_clock(time_txt)
  seconds <- fifelse(is.na(time_txt) & !is.na(parsed_date), 0, clock)
  observation_time <- as.POSIXct(as.numeric(parsed_date) * 86400 + seconds, origin = "1970-01-01", tz = tz)

  this_year <- as.integer(format(Sys.Date(), "%Y"))
  year <- as.integer(format(parsed_date, "%Y"))

  notes <- .new_notes(n)
  notes <- .add_note(notes, is.na(station), "station id missing")
  notes <- .add_note(notes, is.na(stage_txt), "stage missing")
  notes <- .add_note(notes, is.na(flow_txt), "discharge missing")
  notes <- .add_note(notes, stage_p$unparsed, "stage not a number")
  notes <- .add_note(notes, flow_p$unparsed, "discharge not a number")
  notes <- .add_note(notes, is.na(date_txt), "date missing")
  notes <- .add_note(notes, !is.na(date_txt) & is.na(parsed_date), "date not read")
  notes <- .add_note(notes, !is.na(year) & (year < 1800L | year > this_year + 1L), "date outside 1800 to next year")
  if (!is.null(time)) {
    notes <- .add_note(notes, !is.na(time_txt) & is.na(clock), "time not read")
    notes <- .add_note(notes, is.na(time_txt) & !is.na(parsed_date), "time missing, midnight assumed")
  }

  out <- data.table(
    source_row = seq_len(n), station_id = station, station_name = name,
    observation_time = observation_time, stage_m = stage_p$value,
    discharge_cms = flow_p$value, read_issue = notes
  )
  keep <- setdiff(names(dt), mapped)
  for (col in keep) {
    new_name <- if (col %in% names(out)) paste0(col, "_original") else col
    set(out, j = new_name, value = dt[[col]])
  }

  if (!is.null(detected) && isTRUE(detected$ambiguous)) {
    warning(sprintf(
      paste0("read_gaugings(): every date fits both day-first and month-first, so %s was used by default. ",
             "If the file is month-first, pass date_format = \"%%m/%%d/%%Y\"."),
      date_format
    ), call. = FALSE)
  }
  if (!quiet) {
    n_issue <- sum(!is.na(notes))
    message(sprintf(
      "read_gaugings(): %s rows, %s stations, date format %s.\n  Rows with a note: %s. Most common: %s.",
      format(n, big.mark = ","), format(length(unique(station[!is.na(station)])), big.mark = ","),
      date_format, format(n_issue, big.mark = ","), .summarise_notes(notes)
    ))
  }
  out[]
}
