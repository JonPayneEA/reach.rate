# The reference examples of design/E3_record_checks.md. Each record is made
# from a known rating, so the expected value of every check follows from the
# construction, stated beside it. Stage is rounded to the millimetre and flow
# to three decimals, as the archive rounds them.

# Two years of 15-minute stage: a weekly swing, a seasonal one, and a storm
# every nine days rising 0.6 m and falling away over about two days. It stays
# between about 0.17 and 1.23 m, so it crosses the rating's break at 0.8 m.
record_stage <- function(start = "2024-01-01", n = 70176) {
  time <- seq(as.POSIXct(start, tz = "UTC"), by = 900, length.out = n)
  i <- seq_len(n)
  storm <- 0.6 * exp(-((i - 1) %% 864) / 192)
  stage <- 0.4 + 0.15 * sin(2 * pi * i / 672) + 0.08 * sin(2 * pi * i / 35040) + storm
  list(time = time, stage = round(stage, 3))
}

# The rating: Q = 5 (h - 0.1)^1.6 to 0.8 m, then C2 (h - 0.3)^1.3, with C2 set
# so the limbs meet at 0.8 m.
c2 <- 5 * 0.7^1.6 / 0.5^1.3
rating_q <- function(h) ifelse(h <= 0.8, 5 * (h - 0.1)^1.6, c2 * (h - 0.3)^1.3)
rating_table <- function(shift = 0) {
  # The same rating read `shift` metres higher: Q(h) = R(h + shift).
  FlodeRatingTable(table = data.table(
    lower_level = c(0.1, 0.8) - shift, upper_level = c(0.8, 3) - shift,
    C = c(5, c2), a = c(0.1, 0.3) - shift, n = c(1.6, 1.3)
  ))
}

make_record <- function(q_fun = function(h, time) rating_q(h)) {
  s <- record_stage()
  data.frame(time = s$time, stage_m = s$stage, discharge_cms = round(q_fun(s$stage, s$time), 3))
}

change_day <- as.POSIXct("2024-09-10", tz = "UTC")

test_that("one rating throughout gives one period, no revisions and nothing off the curve", {
  out <- check_flow_record(make_record())
  expect_identical(nrow(out$periods), 1L)
  expect_identical(nrow(out$revisions), 0L)
  expect_identical(nrow(out$off_curve), 0L)
  chk <- assessment_checks(out$assessment)
  expect_identical(chk[check_id == "record_revisions"]$status, "pass")
  expect_identical(chk[check_id == "record_off_curve"]$status, "pass")
  # The inputs not given are not assessed, never assumed.
  expect_identical(chk[check_id == "record_above_top"]$status, "not_assessed")
  expect_identical(chk[check_id == "record_stage_error"]$status, "not_assessed")
  expect_identical(chk[check_id == "record_dry_rises"]$status, "not_assessed")
  expect_identical(chk[check_id == "record_known_ratings"]$status, "not_assessed")
})

test_that("a stage shift is found on its day, as a shift of its size", {
  # From change_day the flow is the rating read 0.05 m higher: Q = R(h + 0.05),
  # so C_new(h) = C_old(h + 0.05) and the shift is +0.05 m.
  rec <- make_record(function(h, time) rating_q(h + 0.05 * (time >= change_day)))
  out <- check_flow_record(rec)
  expect_identical(nrow(out$revisions), 1L)
  # The day's first step is at a stage the old curve knows, and departs.
  expect_equal(out$revisions$time, change_day)
  expect_identical(out$revisions$kind, "stage shift")
  expect_lte(abs(out$revisions$shift_m - 0.05), 0.002)
  expect_identical(nrow(out$off_curve), 0L)
})

test_that("a change of shape is not taken for a shift", {
  # From change_day, Q = 5 (h - 0.1)^1.9: the ratio to the old rating,
  # (h - 0.1)^0.3 below the break, changes with stage, so no single shift fits.
  rec <- make_record(function(h, time) {
    ifelse(time >= change_day, 5 * (h - 0.1)^1.9, rating_q(h))
  })
  out <- check_flow_record(rec)
  expect_identical(nrow(out$revisions), 1L)
  expect_equal(out$revisions$time, change_day)
  expect_identical(out$revisions$kind, "change of shape")
  expect_true(is.na(out$revisions$shift_m))
})

test_that("a day of flow not made from the stage is one run off the curve", {
  # One day's flow set 20% high and marked Estimated: every step of it departs
  # (20% against a 1% tolerance), one day is short of the two a revision needs,
  # and nothing else departs.
  rec <- make_record()
  bad <- rec$time >= as.POSIXct("2024-05-02", tz = "UTC") &
    rec$time < as.POSIXct("2024-05-03", tz = "UTC")
  rec$discharge_cms[bad] <- round(1.2 * rec$discharge_cms[bad], 3)
  rec$quality <- ifelse(bad, "Estimated", "Good")
  out <- check_flow_record(rec)
  expect_identical(nrow(out$revisions), 0L)
  expect_identical(nrow(out$off_curve), 1L)
  expect_equal(out$off_curve$start, as.POSIXct("2024-05-02", tz = "UTC"))
  expect_equal(out$off_curve$end, as.POSIXct("2024-05-02 23:45", tz = "UTC"))
  expect_identical(out$off_curve$steps, 96L)
  expect_identical(out$off_curve$quality, "Estimated")
  expect_equal(out$off_curve$volume_share,
               sum(rec$discharge_cms[bad]) / sum(rec$discharge_cms))
})

test_that("the share of flow above the top of the rating is the hand sum", {
  rec <- make_record()
  out <- check_flow_record(rec, top_stage_m = 0.9)
  above <- rec$stage_m > 0.9
  expect_equal(attr(out$above, "shares")[["top"]],
               sum(rec$discharge_cms[above]) / sum(rec$discharge_cms))
  expect_equal(max(out$above$peak_stage_m), max(rec$stage_m))
  # One run above 0.9 m for each storm that reaches it.
  expect_identical(nrow(out$above), sum(diff(c(FALSE, above)) == 1L))
})

test_that("bankfull is reported, and warns when any peak is above it", {
  out <- check_flow_record(make_record(), bankfull_stage_m = 1.1)
  chk <- assessment_checks(out$assessment)
  expect_identical(chk[check_id == "record_above_bankfull"]$status, "warning")
  out <- check_flow_record(make_record(), bankfull_stage_m = 2)
  chk <- assessment_checks(out$assessment)
  expect_identical(chk[check_id == "record_above_bankfull"]$status, "pass")
})

test_that("a stage offset changes the flow volume by the hand sum, on one power-law limb", {
  # Q = 5 (h - 0.1)^1.6 throughout. An offset u = 0.01 m changes the volume by
  # sum(5 (h - 0.1 + u)^1.6 - 5 (h - 0.1)^1.6) over sum(5 (h - 0.1)^1.6), over the
  # steps whose h + u and h - u stay within the stages the record covers.
  one_limb <- function(h) 5 * (h - 0.1)^1.6
  rec <- make_record(function(h, time) one_limb(h))
  u <- 0.01
  out <- check_flow_record(rec, stage_uncertainty_m = u)
  h <- rec$stage_m
  keep <- h + u <= max(h) & h - u >= min(h)
  base <- sum(one_limb(h[keep]))
  whole <- out$stage_error[year == "all" & band == "all"]
  expect_equal(whole$share_raised, sum(one_limb(h[keep] + u)) / base - 1, tolerance = 1e-3)
  expect_equal(whole$share_lowered, sum(one_limb(h[keep] - u)) / base - 1, tolerance = 1e-3)
  expect_identical(attr(out$stage_error, "left_out"), sum(!keep))
  # The same offset is a larger share of a low flow than of a high one.
  all_years <- out$stage_error[year == "all"]
  expect_gt(all_years[band == "low"]$share_raised, all_years[band == "high"]$share_raised)
})

test_that("stage rising in dry weather is found in its month and no other", {
  # March 2024 dry, with stage rising 2 mm a day from 0.4 m; April dry too, and
  # falling 1 mm a day; the rest wet. A pair of steps belongs to the month of its
  # first step, so March's pairs run from its first step to April's first. The
  # changes telescope: March's mean change a day is (h at April's first step -
  # h at March's first) / (March's steps) x 96, which rounded to the millimetre
  # is 2 mm a day to within 1e-5 m.
  s <- record_stage()
  march <- s$time >= as.POSIXct("2024-03-01", tz = "UTC") &
    s$time < as.POSIXct("2024-04-01", tz = "UTC")
  april <- s$time >= as.POSIXct("2024-04-01", tz = "UTC") &
    s$time < as.POSIXct("2024-05-01", tz = "UTC")
  stage <- s$stage
  k_m <- seq_len(sum(march)) - 1
  stage[march] <- round(0.4 + 0.002 * k_m / 96, 3)
  top <- 0.4 + 0.002 * sum(march) / 96
  stage[april] <- round(top - 0.001 * (seq_len(sum(april)) - 1) / 96, 3)
  rec <- data.frame(time = s$time, stage_m = stage, discharge_cms = round(rating_q(stage), 3))
  out <- check_flow_record(rec, dry = march | april)
  expected <- (stage[april][1] - stage[march][1]) / sum(march) * 96
  expect_equal(out$dry_rises[month == "2024-03"]$stage_change_m_per_day, expected)
  expect_lte(abs(expected - 0.002), 1e-5)
  expect_lt(out$dry_rises[month == "2024-04"]$stage_change_m_per_day, 0)
  chk <- assessment_checks(out$assessment)
  expect_identical(chk[check_id == "record_dry_rises"]$status, "warning")
  expect_match(chk[check_id == "record_dry_rises"]$message, "2024-03")
  expect_false(grepl("2024-04", chk[check_id == "record_dry_rises"]$message))
})

test_that("each period is matched to the known rating that made it", {
  rec <- make_record(function(h, time) rating_q(h + 0.05 * (time >= change_day)))
  out <- check_flow_record(rec, ratings = list(original = rating_table(),
                                               shifted = rating_table(0.05)))
  expect_identical(out$periods$known_rating, c("original", "shifted"))
  # Rounding to three decimals is inside the 0.002 m3/s allowance: no step departs.
  expect_equal(out$periods$known_departing_share, c(0, 0))
  chk <- assessment_checks(out$assessment)
  expect_identical(chk[check_id == "record_known_ratings"]$status, "pass")
  # Given only the original, the second period fits no known rating.
  out <- check_flow_record(rec, ratings = list(original = rating_table()))
  chk <- assessment_checks(out$assessment)
  expect_identical(chk[check_id == "record_known_ratings"]$status, "warning")
})

test_that("missing steps are kept and counted, and gaps in time are filled as missing", {
  rec <- make_record()
  rec$stage_m[100:199] <- NA
  rec <- rec[-(500:595), ]
  out <- check_flow_record(rec)
  expect_identical(out$counts$steps, 70176L)
  expect_identical(out$counts$missing_stage, 100L + 96L)
  expect_identical(out$counts$missing_flow, 96L)
  expect_identical(nrow(out$revisions), 0L)
})

test_that("bad records are refused with the reason", {
  rec <- make_record()[1:2000, ]
  expect_error(check_flow_record(rec[, c("time", "stage_m")]), "no discharge_cms column")
  expect_error(check_flow_record(rec[c(2, 1, 3:2000), ]), "times must increase")
  odd <- rec
  odd$time[10] <- odd$time[10] + 60
  expect_error(check_flow_record(odd), "whole multiples")
  neg <- rec
  neg$discharge_cms[5] <- -1
  expect_error(check_flow_record(neg), "negative at row 5")
  # 500 steps of 15 minutes touch six calendar days.
  expect_error(check_flow_record(rec[1:500, ]), "fewer than seven days")
  expect_error(check_flow_record(rec, dry = TRUE), "one value per row")
  expect_error(check_flow_record(rec, stage_uncertainty_m = -0.01), "positive number")
  expect_error(check_flow_record(rec, ratings = list(1)), "named list")
})

test_that("the plot draws the pairs, the curves and the limits", {
  out <- check_flow_record(make_record()[1:5000, ], top_stage_m = 0.9)
  p <- autoplot(out)
  expect_s3_class(p, "ggplot")
  expect_silent(ggplot2::ggplot_build(p))
})
