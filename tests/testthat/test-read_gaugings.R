write_csv_text <- function(lines) {
  path <- tempfile(fileext = ".csv")
  writeLines(lines, path)
  path
}

archive_lines <- c(
  "Site name,Station number,Station name,Date,Time,Stage,Flow,Remark,Team",
  "Wessex,10250,BATHFORD,03/02/1970,12:47:00,1.6,53.3371,\"Migrated, comment\",PR",
  "Wessex,10250,BATHFORD,05/05/1970,13:02:00,---,9.738,---,---",
  "Wessex,,BATHFORD,29/05/1970,,0.85,6.6824,,",
  "Yorkshire,F2405,Skelton,06/01/1960,00:00:00,1.885,104.189,FALLING,---",
  "Yorkshire,F2405,Skelton,12/01/1960,00:01:00,0,0.425,,",
  "Yorkshire,F2405,Skelton,13/01/1960,00:01:00,abc,1.5,,"
)

test_that("every row is kept, in order, with standard columns first", {
  out <- read_gaugings(write_csv_text(archive_lines), quiet = TRUE)

  expect_equal(nrow(out), 6L)
  expect_equal(out$source_row, 1:6)
  expect_equal(names(out)[1:7], c("source_row", "station_id", "station_name", "observation_time",
                                  "stage_m", "discharge_cms", "read_issue"))
  # Unmapped original columns follow, unchanged and as text
  expect_equal(out$Remark[1], "Migrated, comment")
  expect_true(all(c("Site name", "Remark", "Team") %in% names(out)))
  expect_false(any(c("Date", "Stage", "Flow") %in% names(out)))
})

test_that("values are parsed and placeholders become missing", {
  out <- read_gaugings(write_csv_text(archive_lines), quiet = TRUE)

  expect_equal(out$stage_m, c(1.6, NA, 0.85, 1.885, 0, NA))
  expect_equal(out$discharge_cms, c(53.3371, 9.738, 6.6824, 104.189, 0.425, 1.5))
  expect_equal(out$station_id, c("10250", "10250", NA, "F2405", "F2405", "F2405"))
  expect_equal(out$observation_time[1], as.POSIXct("1970-02-03 12:47:00", tz = "UTC"))
  expect_equal(out$observation_time[4], as.POSIXct("1960-01-06 00:00:00", tz = "UTC"))
})

test_that("each problem is noted on its own row, and clean rows have no note", {
  out <- read_gaugings(write_csv_text(archive_lines), quiet = TRUE)

  expect_true(is.na(out$read_issue[1]))
  expect_equal(out$read_issue[2], "stage missing")
  expect_equal(out$read_issue[3], "station id missing; time missing, midnight assumed")
  expect_true(is.na(out$read_issue[4]))
  # A stage of zero with a flow parses and is not noted: judging it is for a later check
  expect_true(is.na(out$read_issue[5]))
  expect_equal(out$read_issue[6], "stage not a number")
  # A missing time becomes midnight on the right date
  expect_equal(out$observation_time[3], as.POSIXct("1970-05-29 00:00:00", tz = "UTC"))
})

test_that("day-first dates are read as day-first, and the format is reported", {
  expect_message(read_gaugings(write_csv_text(archive_lines)), "date format %d/%m/%Y")
  out <- read_gaugings(write_csv_text(archive_lines), quiet = TRUE)
  # 29/05/1970 and 13/01/1960 can only be day-first
  expect_equal(format(out$observation_time[3], "%Y-%m-%d"), "1970-05-29")
  expect_equal(format(out$observation_time[6], "%Y-%m-%d"), "1960-01-13")
})

test_that("ISO and month-first dates are detected", {
  iso <- data.frame(`Station number` = "1", Date = c("2020-03-04", "2020-12-25"), Time = "10:00",
                    Stage = "1", Flow = "2", check.names = FALSE)
  out <- read_gaugings(iso, quiet = TRUE)
  expect_equal(format(out$observation_time, "%Y-%m-%d"), c("2020-03-04", "2020-12-25"))

  us <- data.frame(`Station number` = "1", Date = c("12/25/2020", "03/04/2020"), Time = "10:00",
                   Stage = "1", Flow = "2", check.names = FALSE)
  # 12/25 forces month-first; 03/04 then reads as 4 March
  out_us <- read_gaugings(us, quiet = TRUE)
  expect_equal(format(out_us$observation_time, "%Y-%m-%d"), c("2020-12-25", "2020-03-04"))
})

test_that("a date format that is only a default is warned about, and can be set", {
  ambiguous <- data.frame(`Station number` = "1", Date = c("03/04/2020", "05/06/2020"), Time = "10:00",
                          Stage = "1", Flow = "2", check.names = FALSE)
  expect_warning(read_gaugings(ambiguous, quiet = TRUE), "both day-first and month-first")

  out <- expect_no_warning(read_gaugings(ambiguous, date_format = "%m/%d/%Y", quiet = TRUE))
  expect_equal(format(out$observation_time, "%Y-%m-%d"), c("2020-03-04", "2020-05-06"))
})

test_that("an unreadable date is noted, not dropped, and implausible years are flagged", {
  d <- data.frame(`Station number` = "1", Date = c("03/02/1970", "not a date", "", "03/02/1700"),
                  Time = "10:00", Stage = "1", Flow = "2", check.names = FALSE)
  out <- read_gaugings(d, date_format = "%d/%m/%Y", quiet = TRUE)

  expect_equal(nrow(out), 4L)
  expect_equal(out$read_issue[2], "date not read")
  expect_true(is.na(out$observation_time[2]))
  expect_equal(out$read_issue[3], "date missing")
  expect_equal(out$read_issue[4], "date outside 1800 to next year")
})

test_that("column names can be mapped, and an optional time can be omitted", {
  d <- data.frame(id = c("a", "b"), when = c("01/02/2000", "02/02/2000"), h = c("1.5", "2.5"),
                  q = c("10", "20"), nm = c("A", "B"))
  out <- read_gaugings(d, station_id = "id", station_name = "nm", date = "when", time = NULL,
                       stage = "h", discharge = "q", date_format = "%d/%m/%Y", quiet = TRUE)
  expect_equal(out$stage_m, c(1.5, 2.5))
  expect_equal(out$station_name, c("A", "B"))
  expect_true(all(is.na(out$read_issue)))
  expect_equal(format(out$observation_time, "%H:%M"), c("00:00", "00:00"))
})

test_that("a missing column is named, with the columns that exist", {
  d <- data.frame(a = 1, b = 2)
  expect_error(read_gaugings(d), "column\\(s\\) not found: 'Station number'.*The columns are: 'a', 'b'")
  expect_error(read_gaugings("no/such/file.csv"), "file not found")
  expect_error(read_gaugings(1:3), "file path or a data.frame")
})

test_that("a byte-order mark, quoted commas and a data.frame all read the same", {
  path <- tempfile(fileext = ".csv")
  writeBin(c(as.raw(c(0xef, 0xbb, 0xbf)), charToRaw(paste0(paste(archive_lines, collapse = "\n"), "\n"))), path)
  from_file <- read_gaugings(path, quiet = TRUE)
  from_frame <- read_gaugings(data.table::fread(text = paste(archive_lines, collapse = "\n"), colClasses = "character"), quiet = TRUE)
  # Only the label of where the data came from differs.
  attr(from_file, "read_info") <- attr(from_frame, "read_info") <- NULL
  expect_equal(from_file, from_frame)
  expect_equal(names(from_file)[2], "station_id")
})

test_that("the summary message counts rows and stations and names common problems", {
  expect_message(read_gaugings(write_csv_text(archive_lines)), "6 rows, 2 stations")
  expect_message(read_gaugings(write_csv_text(archive_lines)), "stage missing")
})

test_that("the input data.frame is not modified", {
  d <- data.frame(`Station number` = "1", Date = "13/02/2000", Time = "10:00", Stage = "1.5", Flow = "10",
                  check.names = FALSE)
  before <- d
  read_gaugings(d, quiet = TRUE)
  expect_identical(d, before)
})

test_that("dates that read the same either way are not called ambiguous", {
  same <- data.frame(`Station number` = "1", Date = c("01/01/2000", "02/02/2000", "11/11/2011"), Time = "10:00",
                     Stage = "1", Flow = "2", check.names = FALSE)
  expect_no_warning(read_gaugings(same, quiet = TRUE))
})
