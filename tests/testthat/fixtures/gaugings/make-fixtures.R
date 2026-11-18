# Regenerates every file in this directory. Run from the package root:
#   Rscript tests/testthat/fixtures/gaugings/make-fixtures.R
# The files are committed so the tests do not depend on this script or on
# writexl; it is here so each fixture can be audited and rebuilt.
dir <- "tests/testthat/fixtures/gaugings"
w <- function(name, lines, sep = "\n", bom = FALSE, encoding = NULL) {
  txt <- paste0(paste(lines, collapse = sep), sep)
  raw <- if (is.null(encoding)) charToRaw(txt) else charToRaw(iconv(txt, "UTF-8", encoding))
  writeBin(c(if (bom) as.raw(c(0xef, 0xbb, 0xbf)), raw), file.path(dir, name))
}
hdr <- "Station number,Date,Time,Stage,Flow"

w("01_clean_wiski.csv", c(hdr,
  "10250,13/02/1970,12:47:00,1.600,53.3371",
  "10250,05/05/1970,13:02:00,0.850,6.6824",
  "F2405,06/01/1960,00:00:00,1.885,104.189"))

w("02_semicolon_decimal_comma.csv", c("Station number;Date;Time;Stage;Flow",
  "10250;13/02/1970;12:47:00;1,6;53,3371",
  "10250;05/05/1970;13:02:00;0,85;6,6824"))

w("03_tab_delimited.tsv", c("Station number\tDate\tTime\tStage\tFlow",
  "10250\t13/02/1970\t12:47:00\t1.6\t53.3371",
  "10250\t05/05/1970\t13:02:00\t0.85\t6.6824"))

w("04_pipe_delimited.txt", c("Station number|Date|Time|Stage|Flow",
  "10250|13/02/1970|12:47:00|1.6|53.3371",
  "10250|05/05/1970|13:02:00|0.85|6.6824"))

w("05_placeholders.csv", c(hdr,
  "10250,13/02/1970,12:47:00,---,53.3",
  "10250,05/05/1970,13:02:00,0.85,NULL",
  "10250,06/05/1970,13:02:00,N/A,",
  "10250,07/05/1970,13:02:00,0.9,7.1"))

w("06_unparseable_numbers.csv", c(hdr,
  "10250,13/02/1970,12:47:00,1.6m,53.3",
  "10250,05/05/1970,13:02:00,0.85,abc",
  "10250,06/05/1970,13:02:00,\"1,6\",9.9",
  "10250,07/05/1970,13:02:00,0.9,7.1"))

w("07_blank_station.csv", c(hdr,
  ",13/02/1970,12:47:00,1.6,53.3",
  "10250,05/05/1970,13:02:00,0.85,6.7"))

w("08_month_first_dates.csv", c(hdr,
  "10250,03/25/1970,12:47:00,1.6,53.3",
  "10250,05/05/1970,13:02:00,0.85,6.7"))

w("09_ambiguous_dates.csv", c(hdr,
  "10250,03/04/2020,12:47:00,1.6,53.3",
  "10250,05/06/2020,13:02:00,0.85,6.7"))

w("10_iso_dates.csv", c(hdr,
  "10250,1970-02-03,12:47:00,1.6,53.3",
  "10250,1970-05-05,13:02:00,0.85,6.7"))

w("11_datetime_single_column.csv", c("Station number,When,Stage,Flow",
  "10250,2020-03-04 12:30:00,1.6,53.3",
  "10250,2020-03-05 08:15:30,0.85,6.7"))

w("12_missing_time.csv", c(hdr,
  "10250,13/02/1970,,1.6,53.3",
  "10250,05/05/1970,13:02:00,0.85,6.7"))

w("13_bad_time.csv", c(hdr,
  "10250,13/02/1970,25:99:00,1.6,53.3",
  "10250,05/05/1970,13:02:00,0.85,6.7"))

w("14_date_out_of_range.csv", c(hdr,
  "10250,13/02/1799,12:47:00,1.6,53.3",
  "10250,05/05/2999,13:02:00,0.85,6.7",
  "10250,07/05/1970,13:02:00,0.9,7.1"))

w("15_extra_columns_and_repeated_header.csv", c("Station number,Date,Time,Stage,Flow,Flag,Flag,Remark",
  "10250,13/02/1970,12:47:00,1.6,53.3,A,x,FALLING",
  "10250,05/05/1970,13:02:00,0.85,6.7,,y,"))

w("16_custom_headers.csv", c("Site,When,Clock,Level (m),Q (m3/s)",
  "10250,13/02/1970,12:47:00,1.6,53.3",
  "10250,05/05/1970,13:02:00,0.85,6.7"))

# 17: a spreadsheet, with real Excel date cells and an unrelated first sheet.
if (requireNamespace("writexl", quietly = TRUE)) {
  writexl::write_xlsx(list(
    Notes = data.frame(Comment = "not the data"),
    Gaugings = data.frame(
      `Station number` = c("10250", "10250", "F2405"),
      Date = as.Date(c("1970-02-13", "1970-05-05", "1960-01-06")),
      Time = c("12:47:00", "13:02:00", "00:00:00"),
      Stage = c(1.6, 0.85, 1.885), Flow = c("53.3371", "---", "104.189"),
      check.names = FALSE
    )
  ), file.path(dir, "17_spreadsheet.xlsx"))
}

w("18_bom_quotes_blank_lines_crlf.csv", c(hdr, "",
  "10250,13/02/1970,12:47:00,1.6,53.3",
  "", "\"10,250\",05/05/1970,13:02:00,0.85,6.7", ""), sep = "\r\n", bom = TRUE)

# Two extra cases beyond the eighteen: nothing but a header, and Latin-1.
w("19_header_only.csv", hdr)
w("20_latin1_station_name.csv", c("Station number,Station name,Date,Time,Stage,Flow",
  "10250,Café Bridge,13/02/1970,12:47:00,1.6,53.3"), encoding = "latin1")
