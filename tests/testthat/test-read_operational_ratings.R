ratings_frame <- function() {
  data.frame(
    ID = c(rep("r1", 5), rep("r2", 3), rep("r3", 2)),
    FFFSLocID = c(rep("4761", 5), rep("065006_TG_802", 3), rep("29004", 2)),
    FFFSLocName = c(rep("Spinney Hill Park", 5), rep("Pelic Seiont", 3), rep("Ancholme", 2)),
    Qualifier = "Power", Season = "All",
    StartDate = "01/01/2000 00:00", EndDate = "12/31/1999 12:00:00 AM",
    RatingCurveID = c(rep("c1", 5), rep("c2", 3), rep("c3", 2)),
    SourceID = "s1",
    LowerLevel = c(0, 0.241, 0.897, 1.235, 1.687,   0, 0.1, 0.569,   0, 0.314),
    UpperLevel = c(0.241, 0.897, 1.235, 1.687, 999, 0.1, 0.569, 999, 0.314, 999),
    A = c(0, 0.1, 0.4, 0.8, 0.8,   -0.12979, -0.12979, 0.314,   0, 0.01),
    B = c(1.254, 1.541, 0.8265, 0.4962, 0.4962,   3.17347, 3.17347, 0.991336,   1.5042, 2.2279),
    C = c(3.114, 10.717, 13.462, 17.5309, 17.5309,   16.2542, 16.2542, 20.2019,   4.711, 11.7052),
    # r2 is the grid-to-grid model's alone: G2G and not EA.
    Flag = c(0, 0, 0, 0, 3,   3, 0, 0,   0, 0),
    EA = c(rep(TRUE, 5), rep(FALSE, 3), rep(TRUE, 2)),
    G2G = c(rep(FALSE, 5), rep(TRUE, 3), rep(FALSE, 2)),
    stringsAsFactors = FALSE
  )
}

test_that("coefficients are renamed to the package's own and nothing is reinterpreted", {
  out <- read_operational_ratings(ratings_frame(), omit_g2g = FALSE, quiet = TRUE)

  expect_equal(nrow(out), 10L)
  expect_equal(out$C[2], 10.717)
  expect_equal(out$a[2], 0.1)    # export A is the stage of zero flow
  expect_equal(out$n[2], 1.541)  # export B is the exponent
  expect_equal(out$a[6], -0.12979)
  expect_equal(out$lower_level[2:3], c(0.241, 0.897))
  expect_equal(out$flag[5], 3)
  expect_equal(out$rating_key[c(1, 6, 9)], c("r1/c1", "r2/c2", "r3/c3"))
})

test_that("ratings for the G2G model alone are omitted by default and reported", {
  expect_message(out <- read_operational_ratings(ratings_frame()), "G2G-only rows omitted: 3")
  expect_equal(nrow(out), 7L)
  expect_false(any(out$g2g))
  expect_false("r2/c2" %in% out$rating_key)

  kept <- read_operational_ratings(ratings_frame(), omit_g2g = FALSE, quiet = TRUE)
  expect_equal(sum(kept$g2g), 3L)
})

# Regression: a rating flagged for both EA and G2G is operational and was dropped with the
# G2G-only ones. With r2 flagged for both, none of its three rows may go; without an EA
# column, a G2G row counts as the model's alone and goes, as before.
test_that("a rating flagged for both EA and G2G is kept", {
  both <- ratings_frame()
  both$EA <- TRUE
  expect_message(out <- read_operational_ratings(both),
                 "G2G-only rows omitted: 0. Rows for both EA and G2G kept: 3")
  expect_equal(nrow(out), 10L)
  expect_true("r2/c2" %in% out$rating_key)
  no_ea <- ratings_frame()
  no_ea$EA <- NULL
  out <- read_operational_ratings(no_ea, quiet = TRUE)
  expect_equal(nrow(out), 7L)
  expect_false("r2/c2" %in% out$rating_key)
})

test_that("open-ended top limbs are marked and the level is left alone", {
  out <- read_operational_ratings(ratings_frame(), quiet = TRUE)
  expect_equal(out$open_ended, out$upper_level == 999)
  expect_equal(max(out$upper_level), 999)
})

test_that("an end date before the start date is flagged, not reinterpreted", {
  out <- read_operational_ratings(ratings_frame(), quiet = TRUE)
  expect_true(all(out$end_before_start))
  expect_equal(format(out$start_date[1], "%Y-%m-%d"), "2000-01-01")
  expect_equal(format(out$end_date[1], "%Y-%m-%d"), "1999-12-31")
})

test_that("problems are noted per row and rows are never dropped", {
  d <- ratings_frame()
  d$C[2] <- "---"
  d$B[3] <- "abc"
  d$UpperLevel[4] <- 1.0   # not above its lower level (1.235)
  d$C[1] <- -1
  d$G2G[10] <- "maybe"
  out <- read_operational_ratings(d, quiet = TRUE)

  expect_equal(nrow(out), 7L)  # three G2G rows omitted, nothing else
  expect_match(out$read_issue[2], "C missing")
  expect_match(out$read_issue[3], "a value not a number")
  expect_match(out$read_issue[4], "upper level not above lower level")
  expect_match(out$read_issue[1], "C not positive")
  expect_match(out$read_issue[7], "G2G not read")
  expect_true(is.na(out$read_issue[5]))
})

test_that("dates in the export's two styles are detected per column", {
  d <- ratings_frame()
  d$StartDate <- "2013-04-05 09:30:00"
  out <- read_operational_ratings(d, quiet = TRUE)
  expect_equal(format(out$start_date[1], "%Y-%m-%d %H:%M"), "2013-04-05 09:30")
  expect_equal(format(out$end_date[1], "%Y-%m-%d"), "1999-12-31")
})

test_that("missing optional columns are skipped, required ones are named", {
  d <- ratings_frame()[, c("FFFSLocID", "LowerLevel", "UpperLevel", "A", "B", "C")]
  out <- read_operational_ratings(d, quiet = TRUE)
  expect_equal(nrow(out), 10L)
  expect_true(all(is.na(out$g2g)))
  expect_error(read_operational_ratings(d[, -4]), "'A'")
  expect_error(read_operational_ratings(ratings_frame(), season = "Seasn"), "'Seasn'")
})

test_that("a file with a byte-order mark and mixed text reads correctly", {
  path <- tempfile(fileext = ".csv")
  d <- ratings_frame()
  utils::write.csv(d, path, row.names = FALSE)
  out <- read_operational_ratings(path, quiet = TRUE)
  expect_equal(nrow(out), 7L)
  expect_equal(out$station_id[1], "4761")
})

test_that("limbs group into rating tables that compare with gaugings", {
  limbs <- read_operational_ratings(ratings_frame(), quiet = TRUE)
  result <- operational_rating_tables(limbs)

  expect_named(result$tables, c("r1/c1", "r3/c3"))
  expect_equal(nrow(result$problems), 0L)
  tbl <- result$tables[["r1/c1"]]
  expect_s3_class(tbl@table, "data.table")
  expect_equal(tbl@table$C, c(3.114, 10.717, 13.462, 17.5309, 17.5309))
  expect_equal(names(tbl@table), c("lower_level", "upper_level", "C", "a", "n"))

  # The limbs in the export meet in discharge, which is the check that
  # Q = C (H - A)^B with the offset subtracted is the right reading
  junction <- tbl@table$upper_level[1]
  q_low <- tbl@table$C[1] * (junction - tbl@table$a[1])^tbl@table$n[1]
  q_high <- tbl@table$C[2] * (junction - tbl@table$a[2])^tbl@table$n[2]
  expect_equal(q_low, q_high, tolerance = 0.01)

  # Stage 0.5 is on limb 2 (0.241 to 0.897) and stage 1.0 on limb 3
  tb <- tbl@table
  expect_equal(apply_rating(tbl, c(0.5, 1.0))$discharge,
               c(tb$C[2] * (0.5 - tb$a[2])^tb$n[2], tb$C[3] * (1.0 - tb$a[3])^tb$n[3]))
})

test_that("a rating that cannot form a table is listed with its reason", {
  limbs <- data.frame(
    rating_key = c("ok", "ok", "gap", "gap", "overlap", "overlap", "missing", "missing", "dup", "dup", "bad", "bad"),
    station_id = c("1", "1", "2", "2", "3", "3", "4", "4", "5", "5", "6", "6"),
    lower_level = c(0, 1,   0, 1.5,   0, 0.8,   0, 1,   0, 0,   0, 1),
    upper_level = c(1, 2,   1, 2,     1, 2,     1, 2,   1, 1,   1, 0.5),
    C = c(2, 2, 2, 2, 2, 2, 2, NA, 2, 2, 2, 2), a = 0, n = 1.5
  )
  result <- operational_rating_tables(limbs)

  expect_named(result$tables, "ok")
  expect_equal(sort(result$problems$rating_key), c("bad", "dup", "gap", "missing", "overlap"))
  reason <- function(k) result$problems$reason[result$problems$rating_key == k]
  expect_match(reason("gap"), "gap of 0.5 m between limb 1 and limb 2")
  expect_match(reason("overlap"), "overlap of 0.2 m")
  expect_match(reason("missing"), "missing level or coefficient")
  expect_match(reason("dup"), "share a lower level")
  expect_match(reason("bad"), "not above its lower level")
  expect_equal(result$problems$station_id[result$problems$rating_key == "gap"], "2")
  expect_equal(result$problems$n_limbs[result$problems$rating_key == "gap"], 2L)
})

test_that("limbs out of order are sorted, and the empty case is fine", {
  limbs <- data.frame(rating_key = "a", lower_level = c(1, 0), upper_level = c(2, 1), C = 2, a = 0, n = 1.5)
  result <- operational_rating_tables(limbs)
  expect_equal(result$tables$a@table$lower_level, c(0, 1))

  empty <- operational_rating_tables(limbs[0, ])
  expect_length(empty$tables, 0L)
  expect_equal(nrow(empty$problems), 0L)
  expect_error(operational_rating_tables(limbs[, -1]), "missing column")
  expect_error(operational_rating_tables(1:3), "data.frame")
})
