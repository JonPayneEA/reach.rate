# ============================================================ #
# Tool:         read_operational_ratings
# Description:  Read an operational power-law ratings export (one row per
#               limb) into one row per limb with the package's own
#               coefficient names, and group the limbs into
#               FlodeRatingTable objects, one per rating, reporting any
#               rating whose limbs cannot form a valid table.
# Author:       Jonathan Payne
# Created:      2026-11-18
# Tier:         3
# Inputs:       A file path or data.frame with one row per limb: station
#               id, lower and upper level, and the coefficients A, B, C
#               of Q = C (H - A)^B.
# Outputs:      read_operational_ratings(): a data.table of limbs.
#               operational_rating_tables(): list(tables, problems).
# Dependencies: data.table, S7
# ============================================================ #

#' @include read_helpers.R flode_classes.R
NULL

#' Read an operational ratings export
#'
#' @description
#' Reads an export of operational power-law ratings, one row per limb,
#' into a table with the package's own names. Each row's equation is
#' `Q = C (H - A)^B`: the export's `A` becomes `a` (the stage of zero
#' flow), `B` becomes `n` (the exponent) and `C` stays `C`. Nothing is
#' reinterpreted. As with [read_gaugings()], everything is read as text,
#' parsed explicitly, and anything that did not parse is noted on its
#' row in `read_issue` and not dropped.
#'
#' Ratings flagged as grid-to-grid model output (`G2G` is `TRUE`) are
#' omitted by default, because they are model estimates and not
#' operational ratings; the message says how many rows went. Set
#' `omit_g2g = FALSE` to keep them and filter on the `g2g` column. The
#' export's `Flag` is carried through as `flag` with no meaning assumed.
#'
#' The export marks an open-ended top limb with an upper level of `999`;
#' `open_ended` is `TRUE` for those rows and the level itself is left as
#' it is.
#'
#' @param x A file path to a delimited text file, or a data.frame.
#' @param rating_id,station_id,station_name,qualifier,season,curve_id,source_id,flag,ea,g2g
#'   Character. Names of the export's columns. The defaults match the
#'   export (`ID`, `FFFSLocID`, `FFFSLocName`, `Qualifier`, `Season`,
#'   `RatingCurveID`, `SourceID`, `Flag`, `EA`, `G2G`). A column that is
#'   absent under its default name is simply skipped; one you name
#'   yourself must exist. `NULL` skips a column.
#' @param start_date,end_date Character. Columns holding the dates the
#'   rating applies from and to.
#' @param lower_level,upper_level Character. Columns holding each limb's
#'   stage range (m).
#' @param offset,exponent,scale Character. Columns holding `A`, `B` and
#'   `C`. Defaults `"A"`, `"B"`, `"C"`.
#' @param omit_g2g Logical. Drop rows where `g2g` is `TRUE`. Default
#'   `TRUE`.
#' @param open_ended_level Numeric. An upper level at or above this marks
#'   an open-ended limb. Default `999`.
#' @param date_format A [strptime()] format for both date columns, or
#'   `NULL` (default) to detect each column's format.
#' @param quiet Logical. `TRUE` suppresses the summary message.
#'
#' @return A data.table, one row per limb, with `source_row`, `rating_key`
#'   (the rating id and the curve id together, which identifies one
#'   rating), `rating_id`, `station_id`, `station_name`, `qualifier`,
#'   `season`, `start_date`, `end_date`, `end_before_start` (`TRUE` where
#'   the end date is earlier than the start date, which in this export is
#'   how an open end appears; left for you to interpret), `curve_id`,
#'   `source_id`, `lower_level`, `upper_level`, `open_ended`, `C`, `a`,
#'   `n`, `flag`, `ea`, `g2g` and `read_issue`.
#'
#' @section Notes the function can add:
#' `station id missing`, `lower level missing`, `upper level missing`,
#' `A missing`, `B missing`, `C missing`, `a value not a number`
#' (for any of those columns), `upper level not above lower level`,
#' `C not positive`, `B not positive`, `G2G not read`, and
#' `date not read`.
#'
#' @seealso [operational_rating_tables()] to turn the limbs into rating
#'   tables; [read_gaugings()].
#'
#' @examples
#' raw <- data.frame(
#'   ID = rep(c("r1", "r2"), c(3, 2)), FFFSLocID = rep(c("4761", "29004"), c(3, 2)),
#'   FFFSLocName = rep(c("Spinney Hill Park", "Ancholme Bishopbridge"), c(3, 2)),
#'   Qualifier = "Power", Season = "All",
#'   StartDate = "01/01/2000 00:00", EndDate = "12/31/1999 12:00:00 AM",
#'   RatingCurveID = rep(c("c1", "c2"), c(3, 2)), SourceID = "s1",
#'   LowerLevel = c(0, 0.241, 0.897, 0, 0.314), UpperLevel = c(0.241, 0.897, 999, 0.314, 999),
#'   A = c(0, 0.1, 0.4, 0, 0.01), B = c(1.254, 1.541, 0.8265, 1.5042, 2.2279),
#'   C = c(3.114, 10.717, 13.462, 4.711, 11.7052),
#'   Flag = c(0, 0, 3, 0, 0), EA = TRUE, G2G = c(FALSE, FALSE, FALSE, TRUE, TRUE)
#' )
#' limbs <- read_operational_ratings(raw)
#' limbs[, c("rating_key", "station_id", "lower_level", "upper_level", "C", "a", "n", "open_ended")]
#'
#' @export
read_operational_ratings <- function(x, rating_id = "ID", station_id = "FFFSLocID",
                                     station_name = "FFFSLocName", qualifier = "Qualifier",
                                     season = "Season", start_date = "StartDate",
                                     end_date = "EndDate", curve_id = "RatingCurveID",
                                     source_id = "SourceID", lower_level = "LowerLevel",
                                     upper_level = "UpperLevel", offset = "A", exponent = "B",
                                     scale = "C", flag = "Flag", ea = "EA", g2g = "G2G",
                                     omit_g2g = TRUE, open_ended_level = 999,
                                     date_format = NULL, quiet = FALSE) {
  fn <- "read_operational_ratings()"
  dt <- .read_text_table(x, fn)

  required <- c(station_id, lower_level, upper_level, offset, exponent, scale)
  .require_columns(dt, required, fn)
  n <- nrow(dt)

  # An optional column named by its default and absent is skipped; one the
  # caller named explicitly must exist.
  defaults <- list(rating_id = "ID", station_name = "FFFSLocName", qualifier = "Qualifier",
                   season = "Season", start_date = "StartDate", end_date = "EndDate",
                   curve_id = "RatingCurveID", source_id = "SourceID", flag = "Flag",
                   ea = "EA", g2g = "G2G")
  given <- list(rating_id = rating_id, station_name = station_name, qualifier = qualifier,
                season = season, start_date = start_date, end_date = end_date,
                curve_id = curve_id, source_id = source_id, flag = flag, ea = ea, g2g = g2g)
  optional <- lapply(names(given), function(k) {
    col <- given[[k]]
    if (is.null(col)) return(NULL)
    if (col %in% names(dt)) return(col)
    if (identical(col, defaults[[k]])) return(NULL)
    .require_columns(dt, col, fn)
  })
  names(optional) <- names(given)
  text_col <- function(k) if (is.null(optional[[k]])) rep(NA_character_, n) else .clean_text(dt[[optional[[k]]]])

  station <- .clean_text(dt[[station_id]])
  lower_txt <- .clean_text(dt[[lower_level]])
  upper_txt <- .clean_text(dt[[upper_level]])
  a_txt <- .clean_text(dt[[offset]])
  n_txt <- .clean_text(dt[[exponent]])
  c_txt <- .clean_text(dt[[scale]])
  lower_p <- .parse_numeric(lower_txt)
  upper_p <- .parse_numeric(upper_txt)
  a_p <- .parse_numeric(a_txt)
  n_p <- .parse_numeric(n_txt)
  c_p <- .parse_numeric(c_txt)

  parse_dates <- function(txt, fmt) {
    if (all(is.na(txt))) return(list(value = as.POSIXct(rep(NA_real_, length(txt)), origin = "1970-01-01", tz = "UTC"), format = NA_character_, failed = rep(FALSE, length(txt)), ambiguous = FALSE))
    detected <- if (is.null(fmt)) .detect_format(txt, .datetime_formats) else list(format = fmt, ambiguous = FALSE)
    value <- as.POSIXct(strptime(txt, detected$format, tz = "UTC"))
    list(value = value, format = detected$format, failed = !is.na(txt) & is.na(value), ambiguous = isTRUE(detected$ambiguous))
  }
  start_p <- parse_dates(text_col("start_date"), date_format)
  end_p <- parse_dates(text_col("end_date"), date_format)

  g2g_txt <- toupper(text_col("g2g"))
  g2g_val <- fifelse(g2g_txt %in% c("TRUE", "T", "1", "YES", "Y"), TRUE,
                     fifelse(g2g_txt %in% c("FALSE", "F", "0", "NO", "N"), FALSE, NA))
  ea_txt <- toupper(text_col("ea"))
  ea_val <- fifelse(ea_txt %in% c("TRUE", "T", "1", "YES", "Y"), TRUE,
                    fifelse(ea_txt %in% c("FALSE", "F", "0", "NO", "N"), FALSE, NA))
  flag_p <- .parse_numeric(text_col("flag"))

  notes <- .new_notes(n)
  notes <- .add_note(notes, is.na(station), "station id missing")
  notes <- .add_note(notes, is.na(lower_txt), "lower level missing")
  notes <- .add_note(notes, is.na(upper_txt), "upper level missing")
  notes <- .add_note(notes, is.na(a_txt), "A missing")
  notes <- .add_note(notes, is.na(n_txt), "B missing")
  notes <- .add_note(notes, is.na(c_txt), "C missing")
  notes <- .add_note(notes, lower_p$unparsed | upper_p$unparsed | a_p$unparsed | n_p$unparsed | c_p$unparsed,
                     "a value not a number")
  notes <- .add_note(notes, !is.na(lower_p$value) & !is.na(upper_p$value) & upper_p$value <= lower_p$value,
                     "upper level not above lower level")
  notes <- .add_note(notes, !is.na(c_p$value) & c_p$value <= 0, "C not positive")
  notes <- .add_note(notes, !is.na(n_p$value) & n_p$value <= 0, "B not positive")
  notes <- .add_note(notes, !is.na(g2g_txt) & is.na(g2g_val), "G2G not read")
  notes <- .add_note(notes, start_p$failed | end_p$failed, "date not read")

  id_txt <- text_col("rating_id")
  curve_txt <- text_col("curve_id")
  out <- data.table(
    source_row = seq_len(n),
    rating_key = paste(fifelse(is.na(id_txt), "", id_txt), fifelse(is.na(curve_txt), "", curve_txt), sep = "/"),
    rating_id = id_txt, station_id = station, station_name = text_col("station_name"),
    qualifier = text_col("qualifier"), season = text_col("season"),
    start_date = start_p$value, end_date = end_p$value,
    end_before_start = !is.na(start_p$value) & !is.na(end_p$value) & end_p$value < start_p$value,
    curve_id = curve_txt, source_id = text_col("source_id"),
    lower_level = lower_p$value, upper_level = upper_p$value,
    open_ended = !is.na(upper_p$value) & upper_p$value >= open_ended_level,
    C = c_p$value, a = a_p$value, n = n_p$value,
    flag = flag_p$value, ea = ea_val, g2g = g2g_val, read_issue = notes
  )

  n_g2g <- sum(out$g2g %in% TRUE)
  if (omit_g2g && n_g2g > 0L) out <- out[!(out$g2g %in% TRUE)]

  for (p in list(start_p, end_p)) {
    if (isTRUE(p$ambiguous)) {
      warning(sprintf(
        "read_operational_ratings(): every date fits both day-first and month-first, so %s was used by default. If that is wrong, pass date_format.",
        p$format
      ), call. = FALSE)
      break
    }
  }
  if (!quiet) {
    message(sprintf(
      "read_operational_ratings(): %s limbs in %s ratings at %s stations.\n  G2G rows %s: %s. Rows with a note: %s. Most common: %s.",
      format(nrow(out), big.mark = ","), format(length(unique(out$rating_key)), big.mark = ","),
      format(length(unique(out$station_id[!is.na(out$station_id)])), big.mark = ","),
      if (omit_g2g) "omitted" else "kept", format(n_g2g, big.mark = ","),
      format(sum(!is.na(out$read_issue)), big.mark = ","), .summarise_notes(out$read_issue)
    ))
  }
  out[]
}

#' Turn operational rating limbs into rating tables
#'
#' @description
#' Groups the limbs from [read_operational_ratings()] into one
#' [FlodeRatingTable] per rating. A rating whose limbs cannot form a valid
#' table is not forced into one and not dropped silently: it is listed in
#' `problems` with the reason, so a messy export gives you the good
#' ratings and a precise list of the rest.
#'
#' A rating is rejected, with its reason, when a limb has a missing level
#' or coefficient, when a limb's upper level is not above its lower level,
#' when two limbs share a lower level, or when the limbs are not
#' contiguous (a gap or an overlap between one limb's upper level and the
#' next limb's lower level).
#'
#' @param limbs A data.table from [read_operational_ratings()], or any
#'   table with `lower_level`, `upper_level`, `C`, `a`, `n` and the
#'   `group_by` column.
#' @param group_by Character. The column that identifies one rating.
#'   Default `"rating_key"`.
#'
#' @return A list of two elements. `tables` is a named list of
#'   [FlodeRatingTable]s, named by the `group_by` value, with limbs in
#'   stage order. `problems` is a data.table with one row per rejected
#'   rating: the `group_by` value, `station_id` (when present), `n_limbs`
#'   and `reason`.
#'
#' @seealso [read_operational_ratings()], [apply_rating()].
#'
#' @examples
#' limbs <- data.frame(
#'   rating_key = c("a", "a", "b", "b"),
#'   lower_level = c(0, 1, 0, 1.5), upper_level = c(1, 3, 1, 3),
#'   C = 2, a = 0, n = 1.5
#' )
#' result <- operational_rating_tables(limbs)
#' names(result$tables)
#' result$problems
#'
#' @export
operational_rating_tables <- function(limbs, group_by = "rating_key") {
  fn <- "operational_rating_tables()"
  if (!is.data.frame(limbs)) stop(fn, ": limbs must be a data.frame or data.table")
  needed <- c(group_by, "lower_level", "upper_level", "C", "a", "n")
  missing <- setdiff(needed, names(limbs))
  if (length(missing)) stop(fn, ": limbs is missing column(s): ", paste(missing, collapse = ", "))

  limbs <- as.data.table(limbs)
  has_station <- "station_id" %in% names(limbs)
  groups <- split(seq_len(nrow(limbs)), limbs[[group_by]], drop = TRUE)

  tables <- list()
  problems <- list()
  reject <- function(key, rows, reason) {
    problems[[length(problems) + 1L]] <<- data.table(
      .group = key,
      station_id = if (has_station) limbs$station_id[rows[1L]] else NA_character_,
      n_limbs = length(rows), reason = reason
    )
  }

  for (key in names(groups)) {
    rows <- groups[[key]]
    g <- limbs[rows]
    cols <- c("lower_level", "upper_level", "C", "a", "n")
    if (anyNA(g[, cols, with = FALSE])) {
      reject(key, rows, "a limb has a missing level or coefficient")
      next
    }
    g <- g[order(g$lower_level)]
    if (any(g$upper_level <= g$lower_level)) {
      reject(key, rows, "a limb's upper level is not above its lower level")
      next
    }
    if (anyDuplicated(g$lower_level)) {
      reject(key, rows, "two limbs share a lower level")
      next
    }
    if (nrow(g) > 1L) {
      step <- g$lower_level[-1L] - g$upper_level[-nrow(g)]
      bad <- which(abs(step) >= 1e-8)
      if (length(bad)) {
        first <- bad[1L]
        reject(key, rows, sprintf(
          "limbs are not contiguous: %s of %.6g m between limb %d and limb %d",
          if (step[first] > 0) "gap" else "overlap", abs(step[first]), first, first + 1L
        ))
        next
      }
    }
    tables[[key]] <- FlodeRatingTable(table = g[, cols, with = FALSE])
  }

  problems_dt <- if (length(problems)) rbindlist(problems) else
    data.table(.group = character(), station_id = character(), n_limbs = integer(), reason = character())
  setnames(problems_dt, ".group", group_by)
  list(tables = tables, problems = problems_dt[])
}
