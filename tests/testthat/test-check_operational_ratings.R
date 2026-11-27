# Two-limb rating: Q = 2 H^1.5 on 0.5 to 1, and on 1 to 3 the same equation
two_limb <- function(key, station, name = "X") {
  data.table::data.table(
    rating_key = key, station_id = station, station_name = name,
    lower_level = c(0.5, 1), upper_level = c(1, 3), C = 2, a = 0, n = 1.5,
    flag = c(0, 3), open_ended = c(FALSE, TRUE)
  )
}
gauging_set <- function(station, stage, factor = 1) {
  data.table::data.table(
    source_row = seq_along(stage), station_id = station, stage_m = stage,
    discharge_cms = 2 * stage^1.5 * factor,
    observation_time = as.POSIXct("2000-01-01", tz = "UTC") + seq_along(stage) * 86400
  )
}

test_that("each rating is compared with the gaugings of its matched station", {
  ratings <- rbind(two_limb("r1", "S1"), two_limb("r2", "S2"))
  gaugings <- rbind(gauging_set("S1", c(0.6, 0.8, 1.2), factor = 1.1), gauging_set("S2", c(0.7, 0.9), factor = 0.9))
  res <- check_operational_ratings(gaugings, ratings, quiet = TRUE)

  expect_equal(res$ratings$rating_key, c("r1", "r2"))
  expect_equal(res$ratings$status, c("compared", "compared"))
  expect_equal(res$ratings$n_gaugings, c(3L, 2L))
  expect_equal(res$ratings$median_residual_pct, c(10, -10), tolerance = 1e-9)
  expect_equal(res$ratings$share_within_tol, c(1, 1))
})

test_that("limb summaries carry the export's flag and open-ended marker", {
  ratings <- two_limb("r1", "S1")
  gaugings <- gauging_set("S1", c(0.6, 0.8))   # nothing on the top limb
  limbs <- check_operational_ratings(gaugings, ratings, quiet = TRUE)$limbs

  expect_equal(limbs$rating_key, c("r1", "r1"))
  expect_equal(limbs$has_gaugings, c(TRUE, FALSE))
  expect_equal(limbs$flag, c(0, 3))
  expect_equal(limbs$open_ended, c(FALSE, TRUE))
})

test_that("the rating summary records top-limb support and the gauged maximum", {
  ratings <- two_limb("r1", "S1")
  none_top <- check_operational_ratings(gauging_set("S1", c(0.6, 0.8)), ratings, quiet = TRUE)$ratings
  expect_false(none_top$top_limb_has_gaugings)
  expect_equal(none_top$n_limbs_with_gaugings, 1L)
  expect_equal(none_top$gauged_max_stage, 0.8)

  with_top <- check_operational_ratings(gauging_set("S1", c(0.6, 2)), ratings, quiet = TRUE)$ratings
  expect_true(with_top$top_limb_has_gaugings)
  expect_equal(with_top$n_limbs_with_gaugings, 2L)
})

test_that("a rating with no gaugings and a rating that is not a valid table are listed with the reason", {
  good <- two_limb("r1", "S1")
  nogauge <- two_limb("r2", "S2")
  gap <- two_limb("r3", "S3"); gap$lower_level <- c(0.5, 1.5)
  gaugings <- gauging_set("S1", c(0.6, 1.2))
  res <- check_operational_ratings(gaugings, rbind(good, nogauge, gap), quiet = TRUE)

  status <- setNames(res$ratings$status, res$ratings$rating_key)
  expect_equal(status[["r1"]], "compared")
  expect_equal(status[["r2"]], "no gaugings")
  expect_equal(status[["r3"]], "not a valid table")
  expect_match(res$ratings$reason[res$ratings$rating_key == "r3"], "gap of 0.5 m")
  expect_equal(res$problems$rating_key, "r3")
  expect_equal(res$ratings$n_gaugings[res$ratings$rating_key == "r2"], 0L)
  # Only compared ratings have limb rows
  expect_equal(unique(res$limbs$rating_key), "r1")
})

test_that("unmatched stations on both sides are reported through matches", {
  ratings <- rbind(two_limb("r1", "S1"), two_limb("r2", "S2"))
  gaugings <- rbind(gauging_set("S1", 0.6), gauging_set("S9", 0.7))
  res <- check_operational_ratings(gaugings, ratings, quiet = TRUE)
  expect_equal(res$matches$unmatched_ratings$station_id, "S2")
  expect_equal(res$matches$unmatched_gaugings$station_id, "S9")
})

test_that("a crosswalk lets a rating find gaugings recorded under another id", {
  ratings <- two_limb("r1", "065006_TG_802")
  gaugings <- gauging_set("F2405", c(0.6, 0.8, 1.2))
  without <- check_operational_ratings(gaugings, ratings, quiet = TRUE)
  expect_equal(without$ratings$status, "no gaugings")

  cw <- data.frame(FFFSLocID = "065006_TG_802", Reference = "F2405")
  with_cw <- check_operational_ratings(gaugings, ratings, crosswalk = cw, quiet = TRUE)
  expect_equal(with_cw$ratings$status, "compared")
  expect_equal(with_cw$ratings$n_gaugings, 3L)
})

test_that("by default every gauging is compared with every rating of a station", {
  ratings <- rbind(two_limb("old", "S1"), two_limb("new", "S1"))
  gaugings <- gauging_set("S1", c(0.6, 0.8, 1.2))
  res <- check_operational_ratings(gaugings, ratings, quiet = TRUE)
  expect_equal(res$ratings$n_gaugings, c(3L, 3L))
})

test_that("use_dates restricts each rating to gaugings taken while it was in force", {
  ratings <- rbind(two_limb("old", "S1"), two_limb("new", "S1"))
  ratings$start_date <- as.POSIXct(rep(c("1990-01-01", "2000-01-03"), each = 2), tz = "UTC")
  # old ends before new starts; new's end is before its start, which means open
  ratings$end_date <- as.POSIXct(rep(c("2000-01-03", "1999-12-31"), each = 2), tz = "UTC")
  gaugings <- gauging_set("S1", c(0.6, 0.7, 0.8, 0.9, 1.2))   # one per day from 2000-01-02
  res <- check_operational_ratings(gaugings, ratings, use_dates = TRUE, quiet = TRUE)

  # Gaugings fall on 2 to 6 January: old covers up to 3 January (two of them), new covers from 3 January on
  expect_equal(res$ratings$n_gaugings[res$ratings$rating_key == "old"], 2L)
  expect_equal(res$ratings$n_gaugings[res$ratings$rating_key == "new"], 4L)

  expect_error(check_operational_ratings(gaugings, two_limb("r", "S1"), use_dates = TRUE),
               "ratings is missing column\\(s\\): start_date, end_date")
})

test_that("keep_gaugings returns every comparison with its rating", {
  ratings <- two_limb("r1", "S1")
  gaugings <- gauging_set("S1", c(0.6, 0.8, 1.2))
  res <- check_operational_ratings(gaugings, ratings, keep_gaugings = TRUE, quiet = TRUE)
  expect_equal(nrow(res$gaugings), 3L)
  expect_true(all(c("rating_key", "stage_m", "residual_pct", "limb", "extrapolated") %in% names(res$gaugings)))
  expect_null(check_operational_ratings(gaugings, ratings, quiet = TRUE)$gaugings)
})

test_that("gaugings with missing values are compared without error", {
  ratings <- two_limb("r1", "S1")
  gaugings <- gauging_set("S1", c(0.6, NA, 1.2))
  gaugings$discharge_cms[3] <- NA
  res <- check_operational_ratings(gaugings, ratings, quiet = TRUE)
  expect_equal(res$ratings$status, "compared")
  expect_equal(res$ratings$n_gaugings, 3L)
})

test_that("an empty gauging table gives ratings with no gaugings", {
  ratings <- two_limb("r1", "S1")
  gaugings <- gauging_set("S1", 0.6)[0]
  res <- check_operational_ratings(gaugings, ratings, quiet = TRUE)
  expect_equal(res$ratings$status, "no gaugings")
  expect_equal(nrow(res$limbs), 0L)
})

test_that("input errors name what is missing", {
  r <- two_limb("r1", "S1"); g <- gauging_set("S1", 0.6)
  expect_error(check_operational_ratings(g[, "station_id"], r), "gaugings is missing column\\(s\\): stage_m, discharge_cms")
  expect_error(check_operational_ratings(g, r[, c("rating_key", "station_id")]), "ratings is missing column")
  expect_error(check_operational_ratings(1:3, r), "gaugings must be a table")
})

test_that("the summary message counts ratings by outcome", {
  ratings <- rbind(two_limb("r1", "S1"), two_limb("r2", "S2"))
  gaugings <- gauging_set("S1", c(0.6, 0.8))
  expect_message(check_operational_ratings(gaugings, ratings), "2 ratings: 1 compared, 1 with no gaugings, 0 not valid tables")
  expect_message(check_operational_ratings(gaugings, ratings), "Limbs with no gaugings: 1 of 2")
})

test_that("raw files go through every step: read, match, compare", {
  g_path <- tempfile(fileext = ".csv")
  writeLines(c(
    "Site name,Station number,Station name,Date,Time,Stage,Flow,Remark",
    "Wessex,10250,BATHFORD,13/02/1970,12:47:00,0.6,1.1,",
    "Wessex,10250,BATHFORD,14/05/1970,13:02:00,0.9,1.9,---",
    "Wessex,10250,BATHFORD,15/05/1970,13:02:00,---,1.9,",
    "Yorkshire,F2405,Skelton,16/01/1960,00:00:00,1.2,3.0,",
    "Yorkshire,SD999,Orphan,17/01/1960,00:00:00,1.2,3.0,"
  ), g_path)
  r_path <- tempfile(fileext = ".csv")
  writeLines(c(
    "ID,FFFSLocID,FFFSLocName,Qualifier,Season,StartDate,EndDate,RatingCurveID,SourceID,LowerLevel,UpperLevel,A,B,C,Flag,EA,G2G",
    "i1,10250,Bathford,Power,All,01/01/2000 00:00,12/31/1999 12:00:00 AM,c1,s1,0.5,1,0,1.5,2,0,TRUE,FALSE",
    "i1,10250,Bathford,Power,All,01/01/2000 00:00,12/31/1999 12:00:00 AM,c1,s1,1,999,0,1.5,2,3,TRUE,FALSE",
    "i2,065006_TG_802,Pelic,Power,All,01/01/2000 00:00,12/31/1999 12:00:00 AM,c2,s1,0.5,999,0,1.5,2,0,TRUE,FALSE",
    "i3,77777,Model only,Power,All,01/01/2000 00:00,12/31/1999 12:00:00 AM,c3,s1,0,999,0,1.5,2,0,FALSE,TRUE"
  ), r_path)

  gaugings <- read_gaugings(g_path, quiet = TRUE)
  ratings <- read_operational_ratings(r_path, quiet = TRUE)
  cw <- data.frame(FFFSLocID = "065006_TG_802", Reference = "F2405")
  res <- check_operational_ratings(gaugings, ratings, crosswalk = cw, quiet = TRUE)

  expect_equal(res$ratings$rating_key, c("i1/c1", "i2/c2"))      # the G2G-only rating was omitted
  expect_equal(res$ratings$status, c("compared", "compared"))
  expect_equal(res$ratings$n_gaugings, c(3L, 1L))                # the "---" stage row is kept, not dropped
  expect_equal(res$matches$unmatched_gaugings$station_id, "SD999")
  expect_equal(res$limbs$flag[res$limbs$rating_key == "i1/c1"], c(0, 3))
  # Q = 2 H^1.5: 0.6 m gives 0.9295, so a gauged 1.1 is +18%
  expect_equal(res$limbs$median_residual_pct[1], median(c(100 * (1.1 - 2 * 0.6^1.5) / (2 * 0.6^1.5), 100 * (1.9 - 2 * 0.9^1.5) / (2 * 0.9^1.5))), tolerance = 1e-9)
})
