build_gaugings <- function() {
  data.table::data.table(
    station_id = c("10250", "10250", "f2405", "684500007", "SD47651250", "181806006_staID_909805476", NA),
    station_name = c("BATHFORD", "BATHFORD", "Skelton", "WHITE MILL", "TAWD", "FULLERTON", "NOBODY"),
    observation_time = as.POSIXct(c("1970-02-03", "1971-05-05", "1960-01-06", "1960-01-12",
                                    "1960-01-11", "1960-01-19", "1960-01-01"), tz = "UTC")
  )
}
build_ratings <- function() {
  data.table::data.table(
    station_id = c("10250", "10250", "F2405", "684500007", "065006_TG_802", "29004", NA),
    station_name = c("Bathford", "Bathford", "Skelton", "White Mill", "Pelic Seiont", "Ancholme", "No id"),
    rating_key = c("a/1", "a/1", "b/1", "c/1", "d/1", "e/1", "f/1")
  )
}

test_that("identical ids match directly, ignoring case and spaces", {
  g <- build_gaugings()
  g$station_id[1:2] <- c(" 10250 ", "10250")
  res <- match_stations(g, build_ratings(), quiet = TRUE)

  expect_setequal(res$links$station_id, c("10250", "F2405", "684500007"))
  expect_true(all(res$links$link == "direct"))
  # F2405 (ratings) matches f2405 (gaugings) and keeps each side's own spelling
  row <- res$links[res$links$station_id == "F2405"]
  expect_equal(row$gauging_station_id, "f2405")
})

test_that("what does not match is reported on both sides with context", {
  res <- match_stations(build_gaugings(), build_ratings(), quiet = TRUE)

  expect_setequal(res$unmatched_ratings$station_id, c("065006_TG_802", "29004"))
  expect_equal(res$unmatched_ratings$n_limbs, c(1L, 1L))
  expect_equal(res$unmatched_ratings$n_ratings, c(1L, 1L))
  expect_setequal(res$unmatched_gaugings$station_id, c("SD47651250", "181806006_staID_909805476"))
  expect_equal(res$unmatched_gaugings$n_gaugings, c(1L, 1L))
  expect_true(all(c("first_gauging", "last_gauging") %in% names(res$unmatched_gaugings)))
  # A missing station id on either side is not a station
  expect_false(any(is.na(res$unmatched_ratings$station_id)))
  expect_false(any(is.na(res$unmatched_gaugings$station_id)))
})

test_that("a crosswalk links ids that differ, and takes priority", {
  cw <- data.frame(
    FFFSLocID = c("065006_TG_802", "29004"),
    Reference = c("SD47651250", "181806006_staID_909805476")
  )
  res <- match_stations(build_gaugings(), build_ratings(), cw, quiet = TRUE)

  expect_equal(res$links[res$links$link == "crosswalk"]$gauging_station_id[order(res$links[res$links$link == "crosswalk"]$station_id)],
               c("SD47651250", "181806006_staID_909805476"))
  expect_equal(nrow(res$unmatched_ratings), 0L)
  expect_equal(nrow(res$unmatched_gaugings), 0L)
  expect_equal(nrow(res$crosswalk_unused), 0L)
})

test_that("a crosswalk row that cannot be used is reported with its reason", {
  cw <- data.frame(
    FFFSLocID = c("065006_TG_802", "NOT_A_RATING", "29004", "", "ZZZ"),
    Reference = c("SD47651250", "10250", "NOT_A_GAUGING", "F2405", "ALSO_NOT")
  )
  res <- match_stations(build_gaugings(), build_ratings(), cw, quiet = TRUE)

  reason <- function(r) res$crosswalk_unused$reason[res$crosswalk_unused$row == r]
  expect_equal(reason(2L), "station not in ratings")
  expect_equal(reason(3L), "reference not in gaugings")
  expect_equal(reason(4L), "a value is missing")
  expect_equal(reason(5L), "station not in ratings and reference not in gaugings")
  expect_false(1L %in% res$crosswalk_unused$row)
  # The unusable row for 29004 does not stop it being tried directly, and it still does not match
  expect_true("29004" %in% res$unmatched_ratings$station_id)
})

test_that("one rating station can map to several gauging references", {
  cw <- data.frame(FFFSLocID = c("29004", "29004"), Reference = c("SD47651250", "684500007"))
  res <- match_stations(build_gaugings(), build_ratings(), cw, quiet = TRUE)
  expect_setequal(res$links$gauging_station_id[res$links$station_id == "29004"], c("SD47651250", "684500007"))
})

test_that("direct = FALSE uses the table alone", {
  cw <- data.frame(FFFSLocID = "29004", Reference = "SD47651250")
  res <- match_stations(build_gaugings(), build_ratings(), cw, direct = FALSE, quiet = TRUE)
  expect_equal(res$links$station_id, "29004")
  expect_true("10250" %in% res$unmatched_ratings$station_id)
})

test_that("crosswalk column names can be mapped and are matched ignoring case", {
  cw <- data.frame(fffslocid = "29004", reference = "SD47651250")
  res <- match_stations(build_gaugings(), build_ratings(), cw, quiet = TRUE)
  expect_true("29004" %in% res$links$station_id)

  cw2 <- data.frame(loc = "29004", ref = "SD47651250")
  res2 <- match_stations(build_gaugings(), build_ratings(), cw2, crosswalk_station = "loc",
                         crosswalk_reference = "ref", quiet = TRUE)
  expect_true("29004" %in% res2$links$station_id)
})

test_that("bad input is refused with a message that names the problem", {
  g <- build_gaugings(); r <- build_ratings()
  expect_error(match_stations(g[, "station_name"], r), "gaugings must be a table with a station_id")
  expect_error(match_stations(g, r[, "station_name"]), "ratings must be a table with a station_id")
  expect_error(match_stations(g, r, data.frame(a = 1, b = 2)), "crosswalk has no column 'FFFSLocID'.*'a', 'b'")
  expect_error(match_stations(g, r, "table.csv"), "crosswalk must be a data.frame")
})

test_that("the summary message counts matches by route", {
  cw <- data.frame(FFFSLocID = "29004", Reference = "SD47651250")
  expect_message(match_stations(build_gaugings(), build_ratings(), cw),
                 "4 of 5 rating stations matched \\(1 by table, 3 directly\\)")
})

test_that("empty inputs give empty, well-formed results", {
  g <- build_gaugings()[0]
  res <- match_stations(g, build_ratings(), quiet = TRUE)
  expect_equal(nrow(res$links), 0L)
  expect_equal(nrow(res$unmatched_gaugings), 0L)
  expect_equal(nrow(res$unmatched_ratings), 5L)
})
