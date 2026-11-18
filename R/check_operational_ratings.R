# ============================================================ #
# Tool:         check_operational_ratings
# Description:  Check every operational rating against the gaugings of its
#               matched station: build each rating as a table, find its
#               gaugings through match_stations(), compare them with
#               compare_gaugings_to_rating(), and collect the results,
#               together with everything that could not be compared and why.
# Author:       Jonathan Payne
# Created:      2026-11-18
# Tier:         3
# Inputs:       gaugings (read_gaugings() output) and ratings
#               (read_operational_ratings() output), optionally a
#               crosswalk of rating station ids and gauging references.
# Outputs:      A list. See ?check_operational_ratings.
# Dependencies: data.table
# ============================================================ #

#' @include match_stations.R compare_gaugings.R read_operational_ratings.R
NULL

#' Check every operational rating against its gaugings
#'
#' @description
#' Runs [compare_gaugings_to_rating()] for every rating in an operational
#' ratings export, against the gaugings of the station it is matched to,
#' and collects the results in one place. It is the whole of the check in
#' one call: build each rating as a table, link ratings to gauging
#' stations, compare, and report both the findings and everything that
#' could not be compared.
#'
#' Nothing is excluded for being odd. A rating that cannot form a valid
#' table, a rating whose station has no gaugings, a gauging station with no
#' rating, and a row of the matching table that matched nothing are each
#' listed with the reason, so the picture is complete and the unmatched
#' part can be worked down.
#'
#' By default every gauging of a matched station is compared with every
#' rating of that station, whatever its dates. A station that has had
#' several ratings over time will therefore show each rating against all
#' of its gaugings. Set `use_dates = TRUE` to compare each rating only
#' with gaugings taken while it was in force: from its `start_date` to its
#' `end_date`, where an end date is missing, or is earlier than the start
#' date (which the ratings export uses for "no end"), the rating is
#' treated as still in force.
#'
#' @param gaugings A table from [read_gaugings()].
#' @param ratings A table from [read_operational_ratings()].
#' @param crosswalk,crosswalk_station,crosswalk_reference,direct As in
#'   [match_stations()].
#' @param use_dates Logical. Compare each rating only with the gaugings
#'   taken while it was in force. Default `FALSE`. Needs
#'   `observation_time` in `gaugings` and `start_date` and `end_date` in
#'   `ratings`.
#' @param tol_rel Numeric. Tolerance for `share_within_tol`, as in
#'   [compare_gaugings_to_rating()]. Default `0.10`.
#' @param keep_gaugings Logical. Also return every gauging with its
#'   residual against each rating it was compared with. Default `FALSE`:
#'   for a large archive this is a large table.
#' @param quiet Logical. `TRUE` suppresses the summary message.
#'
#' @return A list with these elements.
#'   * `ratings`: one row per rating, with `rating_key`, `station_id`,
#'     `station_name`, `n_limbs`, `status` (`"compared"`, `"no gaugings"` or
#'     `"not a valid table"`), `reason` (for a rating that is not a valid
#'     table), `n_gaugings` (compared), `n_inside` and `n_extrapolated`,
#'     `n_limbs_with_gaugings`, `top_limb_has_gaugings`, `gauged_max_stage`,
#'     `median_residual_pct` and `share_within_tol` over the gaugings inside
#'     the rating.
#'   * `limbs`: one row per limb of every compared rating, with
#'     `rating_key`, `station_id`, the columns of
#'     [compare_gaugings_to_rating()]'s `limbs`, and the export's `flag`
#'     and `open_ended` for that limb. `flag` is carried through so you can
#'     see whether it lines up with limbs that have no gaugings.
#'   * `gaugings`: the per-gauging results, or `NULL` unless
#'     `keep_gaugings = TRUE`.
#'   * `matches`: the list returned by [match_stations()].
#'   * `problems`: the ratings that are not valid tables, with the reason.
#'
#' @seealso [match_stations()], [compare_gaugings_to_rating()],
#'   [read_gaugings()], [read_operational_ratings()].
#'
#' @examples
#' # Two ratings and one archive of gaugings. Station "S1" has gaugings up to
#' # 2.3 m, so the top limb of its rating (to 4 m) has none. Station "S2" has
#' # a rating but no gaugings, and station "S3" has gaugings but no rating.
#' ratings <- data.frame(
#'   rating_key = rep(c("r1", "r2"), c(4, 2)), station_id = rep(c("S1", "S2"), c(4, 2)),
#'   station_name = rep(c("Bathford", "Skelton"), c(4, 2)),
#'   lower_level = c(0.30, 0.90, 1.70, 2.60, 0, 1), upper_level = c(0.90, 1.70, 2.60, 4.00, 1, 3),
#'   C = c(1.80000, 2.85549, 4.72355, 2.36038, 2, 2), a = c(0.10, 0.25, 0.55, 0.40, 0, 0),
#'   n = c(1.60, 1.90, 1.45, 2.20, 1.5, 1.5),
#'   flag = c(0, 0, 0, 3, 0, 0), open_ended = c(FALSE, FALSE, FALSE, TRUE, FALSE, TRUE)
#' )
#' set.seed(3)
#' stage_m <- sort(runif(40, 0.3, 2.3))
#' gaugings <- data.frame(
#'   station_id = c(rep("S1", 40), rep("S3", 3)),
#'   stage_m = c(stage_m, 1, 1.5, 2),
#'   discharge_cms = c(apply_rating(FlodeRatingTable(table = data.table::as.data.table(ratings[1:4, 4:8])),
#'                                  stage_m)$discharge * exp(rnorm(40, sd = 0.04)), 3, 5, 8)
#' )
#' check <- check_operational_ratings(gaugings, ratings)
#' check$ratings[, c("rating_key", "status", "n_gaugings", "median_residual_pct")]
#' check$limbs[, c("rating_key", "limb", "n_gaugings", "has_gaugings", "flag")]
#' check$matches$unmatched_gaugings
#'
#' @export
check_operational_ratings <- function(gaugings, ratings, crosswalk = NULL,
                                      crosswalk_station = "FFFSLocID", crosswalk_reference = "Reference",
                                      direct = TRUE, use_dates = FALSE, tol_rel = 0.10,
                                      keep_gaugings = FALSE, quiet = FALSE) {
  fn <- "check_operational_ratings()"
  if (!is.data.frame(gaugings)) stop(fn, ": gaugings must be a table from read_gaugings()")
  if (!is.data.frame(ratings)) stop(fn, ": ratings must be a table from read_operational_ratings()")
  need_g <- c("station_id", "stage_m", "discharge_cms", if (use_dates) "observation_time")
  need_r <- c("rating_key", "station_id", "lower_level", "upper_level", "C", "a", "n",
              if (use_dates) c("start_date", "end_date"))
  miss_g <- setdiff(need_g, names(gaugings))
  miss_r <- setdiff(need_r, names(ratings))
  if (length(miss_g)) stop(fn, ": gaugings is missing column(s): ", paste(miss_g, collapse = ", "))
  if (length(miss_r)) stop(fn, ": ratings is missing column(s): ", paste(miss_r, collapse = ", "))

  gaugings <- as.data.table(gaugings)
  ratings <- as.data.table(ratings)

  matches <- match_stations(gaugings, ratings, crosswalk, crosswalk_station, crosswalk_reference,
                            direct = direct, quiet = TRUE)
  built <- operational_rating_tables(ratings)
  g_rows <- split(seq_len(nrow(gaugings)), gaugings$station_id)

  keys <- unique(ratings$rating_key)
  summary_rows <- vector("list", length(keys))
  limb_rows <- list()
  gauging_rows <- list()

  for (i in seq_along(keys)) {
    key <- keys[i]
    meta <- ratings[ratings$rating_key == key]
    meta <- meta[order(meta$lower_level)]
    station <- meta$station_id[1L]
    base <- data.table(
      rating_key = key, station_id = station,
      station_name = if ("station_name" %in% names(meta)) meta$station_name[1L] else NA_character_,
      n_limbs = nrow(meta)
    )
    empty_stats <- list(
      n_gaugings = 0L, n_inside = 0L, n_extrapolated = 0L, n_limbs_with_gaugings = NA_integer_,
      top_limb_has_gaugings = NA, gauged_max_stage = NA_real_, median_residual_pct = NA_real_,
      share_within_tol = NA_real_
    )

    if (!key %in% names(built$tables)) {
      reason <- built$problems$reason[built$problems[[1L]] == key]
      summary_rows[[i]] <- cbind(base, status = "not a valid table", reason = reason[1L], as.data.table(empty_stats))
      next
    }

    gids <- matches$links$gauging_station_id[matches$links$station_id == station]
    rows <- if (length(gids)) sort(unique(unlist(g_rows[gids], use.names = FALSE))) else integer(0)
    if (use_dates && length(rows)) {
      when <- gaugings$observation_time[rows]
      start <- meta$start_date[1L]
      end <- meta$end_date[1L]
      open_end <- is.na(end) || (!is.na(start) && end < start)
      keep <- (is.na(start) | is.na(when) | when >= start) & (open_end | is.na(when) | when <= end)
      rows <- rows[keep]
    }
    if (!length(rows)) {
      summary_rows[[i]] <- cbind(base, status = "no gaugings", reason = NA_character_, as.data.table(empty_stats))
      next
    }

    keep_cols <- intersect(c("source_row", "station_id", "observation_time", "stage_m", "discharge_cms"), names(gaugings))
    g_sub <- gaugings[rows, keep_cols, with = FALSE]
    result <- compare_gaugings_to_rating(built$tables[[key]], g_sub, tol_rel = tol_rel)

    limbs <- result$limbs
    limbs[, "flag" := if ("flag" %in% names(meta)) meta$flag else NA_real_]
    limbs[, "open_ended" := if ("open_ended" %in% names(meta)) meta$open_ended else NA]
    limb_rows[[length(limb_rows) + 1L]] <- cbind(data.table(rating_key = key, station_id = station), limbs)

    detail <- result$gaugings
    inside <- detail[detail$extrapolated %in% FALSE]
    stats <- list(
      n_gaugings = nrow(detail), n_inside = nrow(inside), n_extrapolated = sum(detail$extrapolated %in% TRUE),
      n_limbs_with_gaugings = sum(limbs$has_gaugings),
      top_limb_has_gaugings = limbs$has_gaugings[nrow(limbs)],
      gauged_max_stage = if (any(!is.na(detail$stage_m))) max(detail$stage_m, na.rm = TRUE) else NA_real_,
      median_residual_pct = if (any(!is.na(inside$residual_pct))) stats::median(inside$residual_pct, na.rm = TRUE) else NA_real_,
      share_within_tol = if (any(!is.na(inside$within_tol))) mean(inside$within_tol, na.rm = TRUE) else NA_real_
    )
    summary_rows[[i]] <- cbind(base, status = "compared", reason = NA_character_, as.data.table(stats))
    if (keep_gaugings) {
      gauging_rows[[length(gauging_rows) + 1L]] <- cbind(data.table(rating_key = key), detail)
    }
  }

  ratings_out <- if (length(summary_rows)) rbindlist(summary_rows) else data.table()
  limbs_out <- if (length(limb_rows)) rbindlist(limb_rows) else data.table()
  gaugings_out <- if (keep_gaugings) (if (length(gauging_rows)) rbindlist(gauging_rows) else data.table()) else NULL

  if (!quiet) {
    st <- table(factor(ratings_out$status, levels = c("compared", "no gaugings", "not a valid table")))
    message(sprintf(
      "check_operational_ratings(): %s ratings: %s compared, %s with no gaugings, %s not valid tables.\n  Limbs with no gaugings: %s of %s in compared ratings. Unmatched: %s rating stations, %s gauging stations.",
      format(nrow(ratings_out), big.mark = ","), format(st[["compared"]], big.mark = ","),
      format(st[["no gaugings"]], big.mark = ","), format(st[["not a valid table"]], big.mark = ","),
      format(sum(!limbs_out$has_gaugings), big.mark = ","), format(nrow(limbs_out), big.mark = ","),
      format(nrow(matches$unmatched_ratings), big.mark = ","), format(nrow(matches$unmatched_gaugings), big.mark = ",")
    ))
  }

  list(ratings = ratings_out[], limbs = limbs_out[], gaugings = gaugings_out,
       matches = matches, problems = built$problems)
}
