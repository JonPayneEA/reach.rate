# ============================================================ #
# Tool:         match_stations
# Description:  Link the stations of a gauging archive to the stations of
#               an operational ratings export, using a user-supplied table
#               of rating station id and gauging reference where one is
#               given, and the ids as they stand otherwise. Reports what
#               did not match on each side, and any row of the table that
#               could not be used.
# Author:       Jonathan Payne
# Created:      2026-11-18
# Tier:         3
# Inputs:       gaugings (read_gaugings() output) and ratings
#               (read_operational_ratings() output), and optionally a
#               crosswalk data.frame.
# Outputs:      A list of four data.tables. See ?match_stations.
# Dependencies: data.table
# ============================================================ #

#' @include read_helpers.R
NULL

#' Match gauging stations to rating stations
#'
#' @description
#' Links the stations in a gauging archive to the stations in an
#' operational ratings export, so each rating can be checked against its
#' own gaugings. The two files name stations differently, so the link is
#' made in two ways, and you decide how much of each to use:
#'
#' * **A table you supply** (`crosswalk`): one row per link, with the
#'   rating's station id (`FFFSLocID`) and the matching gauging reference
#'   (the gauging file's station number). This is the reliable route, and
#'   it takes priority. A rating station can map to several references,
#'   and several rating stations to one.
#' * **The ids as they stand** (`direct = TRUE`, the default): for a
#'   rating station that the table does not link to a gauging station, the
#'   station id is compared with the gauging file's station ids directly.
#'   Case and surrounding spaces are ignored; nothing else is altered, so
#'   `065006` does not match `065006_TG_802` unless the table says so.
#'
#' Nothing is guessed. What does not match is reported, on both sides, so
#' the table can be extended until the matches you expect are there.
#'
#' @param gaugings A data.table from [read_gaugings()], or any table with a
#'   `station_id` column (and, optionally, `station_name`, `observation_time`).
#' @param ratings A data.table from [read_operational_ratings()], or any
#'   table with a `station_id` column (and, optionally, `station_name` and
#'   `rating_key`).
#' @param crosswalk A data.frame with one column of rating station ids and
#'   one of gauging references, or `NULL` (default) to match on the ids
#'   alone.
#' @param crosswalk_station,crosswalk_reference Character. Names of the
#'   two columns of `crosswalk`. Defaults `"FFFSLocID"` and `"Reference"`.
#'   Names are matched ignoring case.
#' @param direct Logical. Also match ids directly where the table gives no
#'   link. Default `TRUE`.
#' @param quiet Logical. `TRUE` suppresses the summary message.
#'
#' @return A list of four data.tables.
#'   * `links`: one row per link, with `station_id` (the rating side),
#'     `gauging_station_id` and `link` (`"crosswalk"` or `"direct"`).
#'   * `unmatched_ratings`: rating stations with no gauging station, with
#'     `station_id`, `station_name`, `n_ratings` and `n_limbs`.
#'   * `unmatched_gaugings`: gauging stations with no rating station, with
#'     `station_id`, `station_name`, `n_gaugings` and, when the gaugings
#'     have an `observation_time`, `first_gauging` and `last_gauging`.
#'   * `crosswalk_unused`: rows of `crosswalk` that could not be used, with
#'     the `reason`: the station is not in the ratings, the reference is
#'     not in the gaugings, or neither, or a value is missing.
#'
#' @seealso [check_operational_ratings()] to run the comparison for every
#'   matched rating.
#'
#' @examples
#' gaugings <- data.frame(
#'   station_id = c("10250", "10250", "F2405", "684500007", "SD47651250"),
#'   station_name = c("BATHFORD", "BATHFORD", "Skelton", "WHITE MILL", "TAWD")
#' )
#' ratings <- data.frame(
#'   station_id = c("10250", "10250", "065006_TG_802", "684500007", "29004"),
#'   station_name = c("Bathford", "Bathford", "Pelic Seiont", "White Mill", "Ancholme"),
#'   rating_key = c("a/1", "a/1", "b/1", "c/1", "d/1")
#' )
#'
#' # Without a table, only identical ids match
#' match_stations(gaugings, ratings)$unmatched_ratings
#'
#' # A table links what the ids alone cannot, and reports a row that fails
#' crosswalk <- data.frame(
#'   FFFSLocID = c("065006_TG_802", "29004", "99999"),
#'   Reference = c("F2405", "NOT_IN_GAUGINGS", "10250")
#' )
#' result <- match_stations(gaugings, ratings, crosswalk)
#' result$links
#' result$crosswalk_unused
#' result$unmatched_gaugings
#'
#' @export
match_stations <- function(gaugings, ratings, crosswalk = NULL,
                           crosswalk_station = "FFFSLocID", crosswalk_reference = "Reference",
                           direct = TRUE, quiet = FALSE) {
  fn <- "match_stations()"
  if (!is.data.frame(gaugings) || !"station_id" %in% names(gaugings)) {
    stop(fn, ": gaugings must be a table with a station_id column (see read_gaugings())")
  }
  if (!is.data.frame(ratings) || !"station_id" %in% names(ratings)) {
    stop(fn, ": ratings must be a table with a station_id column (see read_operational_ratings())")
  }
  gaugings <- as.data.table(gaugings)
  ratings <- as.data.table(ratings)
  norm <- function(x) toupper(trimws(as.character(x)))

  # Distinct stations on each side, keyed by the normalised id.
  r_ids <- ratings$station_id[!is.na(ratings$station_id)]
  g_ids <- gaugings$station_id[!is.na(gaugings$station_id)]
  r_tab <- data.table(r_key = norm(unique(r_ids)), station_id = unique(r_ids))
  g_tab <- data.table(g_key = norm(unique(g_ids)), gauging_station_id = unique(g_ids))

  links <- list()
  unused <- list()

  if (!is.null(crosswalk)) {
    if (!is.data.frame(crosswalk)) stop(fn, ": crosswalk must be a data.frame or NULL")
    find_col <- function(wanted) {
      hit <- which(tolower(names(crosswalk)) == tolower(wanted))
      if (!length(hit)) {
        stop(sprintf("%s: crosswalk has no column '%s'. Its columns are: %s. Name them with crosswalk_station and crosswalk_reference.",
                     fn, wanted, paste(sprintf("'%s'", names(crosswalk)), collapse = ", ")), call. = FALSE)
      }
      names(crosswalk)[hit[1L]]
    }
    st_col <- find_col(crosswalk_station)
    ref_col <- find_col(crosswalk_reference)
    cw <- data.table(
      station = .clean_text(crosswalk[[st_col]]),
      reference = .clean_text(crosswalk[[ref_col]])
    )
    cw[, "row" := seq_len(nrow(cw))]
    in_r <- norm(cw$station) %in% r_tab$r_key
    in_g <- norm(cw$reference) %in% g_tab$g_key
    missing_value <- is.na(cw$station) | is.na(cw$reference)
    ok <- !missing_value & in_r & in_g
    why <- fifelse(missing_value, "a value is missing",
           fifelse(!in_r & !in_g, "station not in ratings and reference not in gaugings",
           fifelse(!in_r, "station not in ratings", "reference not in gaugings")))
    unused[["crosswalk"]] <- data.table(
      row = cw$row[!ok], station = cw$station[!ok], reference = cw$reference[!ok], reason = why[!ok]
    )
    if (any(ok)) {
      used <- data.table(r_key = norm(cw$station[ok]), g_key = norm(cw$reference[ok]))
      used <- unique(used)
      m <- merge(merge(used, r_tab, by = "r_key"), g_tab, by = "g_key")
      links[["crosswalk"]] <- data.table(station_id = m$station_id, gauging_station_id = m$gauging_station_id,
                                         link = "crosswalk")
    }
  }

  crosswalked <- if (length(links)) unique(links[["crosswalk"]]$station_id) else character(0)
  if (direct) {
    r_left <- r_tab[!r_tab$station_id %in% crosswalked]
    m <- merge(r_left, g_tab, by.x = "r_key", by.y = "g_key")
    if (nrow(m)) {
      links[["direct"]] <- data.table(station_id = m$station_id, gauging_station_id = m$gauging_station_id,
                                      link = "direct")
    }
  }
  links_dt <- if (length(links)) unique(rbindlist(links)) else
    data.table(station_id = character(), gauging_station_id = character(), link = character())

  # What did not match, with enough to recognise it by.
  first_of <- function(dt, id_col, name_col) {
    if (!name_col %in% names(dt)) return(rep(NA_character_, length(unique(dt[[id_col]]))))
    dt[[name_col]][match(unique(dt[[id_col]]), dt[[id_col]])]
  }
  r_station <- data.table(station_id = unique(r_ids))
  r_station[, "station_name" := first_of(ratings[!is.na(ratings$station_id)], "station_id", "station_name")]
  r_valid <- ratings[!is.na(ratings$station_id)]
  rating_count <- if ("rating_key" %in% names(r_valid)) {
    vapply(r_station$station_id, function(s) length(unique(r_valid$rating_key[r_valid$station_id == s])), integer(1))
  } else rep(NA_integer_, nrow(r_station))
  limb_count <- vapply(r_station$station_id, function(s) sum(r_valid$station_id == s), integer(1))
  r_station[, c("n_ratings", "n_limbs") := list(rating_count, limb_count)]
  unmatched_ratings <- r_station[!r_station$station_id %in% links_dt$station_id]

  g_valid <- gaugings[!is.na(gaugings$station_id)]
  g_station <- data.table(station_id = unique(g_ids))
  g_station[, "station_name" := first_of(g_valid, "station_id", "station_name")]
  g_station[, "n_gaugings" := vapply(g_station$station_id, function(s) sum(g_valid$station_id == s), integer(1))]
  if ("observation_time" %in% names(g_valid)) {
    times <- g_valid$observation_time
    first_t <- vapply(g_station$station_id, function(s) as.numeric(suppressWarnings(min(times[g_valid$station_id == s], na.rm = TRUE))), numeric(1))
    last_t <- vapply(g_station$station_id, function(s) as.numeric(suppressWarnings(max(times[g_valid$station_id == s], na.rm = TRUE))), numeric(1))
    first_t[!is.finite(first_t)] <- NA_real_
    last_t[!is.finite(last_t)] <- NA_real_
    g_station[, "first_gauging" := as.POSIXct(first_t, origin = "1970-01-01", tz = "UTC")]
    g_station[, "last_gauging" := as.POSIXct(last_t, origin = "1970-01-01", tz = "UTC")]
  }
  unmatched_gaugings <- g_station[!g_station$station_id %in% links_dt$gauging_station_id]

  crosswalk_unused <- if (length(unused)) unused[["crosswalk"]] else
    data.table(row = integer(), station = character(), reference = character(), reason = character())

  if (!quiet) {
    message(sprintf(
      "match_stations(): %s of %s rating stations matched (%s by table, %s directly); %s of %s gauging stations matched.\n  Unmatched: %s rating stations, %s gauging stations. Table rows not used: %s.",
      format(length(unique(links_dt$station_id)), big.mark = ","), format(nrow(r_station), big.mark = ","),
      format(length(unique(links_dt$station_id[links_dt$link == "crosswalk"])), big.mark = ","),
      format(length(unique(links_dt$station_id[links_dt$link == "direct"])), big.mark = ","),
      format(length(unique(links_dt$gauging_station_id)), big.mark = ","), format(nrow(g_station), big.mark = ","),
      format(nrow(unmatched_ratings), big.mark = ","), format(nrow(unmatched_gaugings), big.mark = ","),
      format(nrow(crosswalk_unused), big.mark = ",")
    ))
  }

  list(links = links_dt[], unmatched_ratings = unmatched_ratings[],
       unmatched_gaugings = unmatched_gaugings[], crosswalk_unused = crosswalk_unused[])
}
