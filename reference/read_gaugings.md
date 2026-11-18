# Read a spot-gauging archive

Reads gaugings from delimited text (comma, semicolon, tab or pipe), a
spreadsheet (`.xlsx`, `.xls`) or a data.frame into a table with standard
column names, whatever the original headers were called. It cleans
nothing and removes nothing: every row of the file is returned, in
order. What it does is read every column as text, turn placeholder text
such as `---` into a missing value, parse stage, discharge, date and
time explicitly, and record in `read_issue` anything that did not parse,
so a bad row is visible and not silently lost or changed. The values as
they were written are kept beside the parsed ones.

The defaults match the column names of the Environment Agency
WISKI-style gauging export (`Station number`, `Date`, `Time`, `Stage`,
`Flow`). Use the mapping arguments for any other headers.

Dates are detected, not assumed. The format that parses the most values
is used, day-first ahead of month-first when both fit (`04/05/1970` is
read as 4 May). The format chosen is reported in the message, with a
warning when the choice was a default and could be wrong. Pass
`date_format` (for example `"%d/%m/%Y"`) to settle it. A spreadsheet's
date cells arrive as Excel serial numbers and are recognised as such.

Reading a spreadsheet needs the `readxl` package. Without it the
function stops and says so; saving the sheet as a CSV is the
alternative.

## Usage

``` r
read_gaugings(
  x,
  station_id = "Station number",
  station_name = "Station name",
  date = "Date",
  time = "Time",
  stage = "Stage",
  discharge = "Flow",
  datetime = NULL,
  date_format = NULL,
  tz = "UTC",
  sep = "auto",
  dec = ".",
  sheet = 1L,
  encoding = "unknown",
  keep_original = TRUE,
  quiet = FALSE
)
```

## Arguments

- x:

  A file path to a delimited text file or a spreadsheet, or a
  data.frame.

- station_id, station_name:

  Character. Columns holding the station identifier and name. The name
  is optional: it is skipped if the file has no column called
  `Station name`, or if `station_name = NULL`.

- date, time:

  Character. Columns holding the date and the time of day. `time = NULL`
  if there is none; a missing time is then midnight, with no note.

- stage, discharge:

  Character. Columns holding stage (m) and discharge (cumecs).

- datetime:

  Character, or `NULL` (default). The name of a single column holding
  date and time together, such as `2020-03-04 12:30:00`. When given,
  `date` and `time` are not used.

- date_format:

  A [`strptime()`](https://rdrr.io/r/base/strptime.html) format for the
  date column (or the date-time column), or `NULL` (default) to detect
  it.

- tz:

  Time zone label for `observation_time`. Default `"UTC"`. The clock
  time in the file is used as it stands: 12:00 in the file is 12:00 in
  `tz`, with no daylight-saving adjustment, so it is only as good as the
  file's own convention. A clock time that does not exist in `tz` (the
  hour skipped when clocks go forward) becomes `NA`.

- sep:

  The field separator for a text file. `"auto"` (default) detects it.

- dec:

  The decimal mark in stage and discharge: `"."` (default) or `","`. A
  thousands separator is not guessed at; a value that does not parse is
  noted, not reinterpreted.

- sheet:

  The sheet to read from a spreadsheet, by name or number. Ignored for
  text.

- encoding:

  The encoding of a text file: `"unknown"` (default), `"UTF-8"` or
  `"Latin-1"`.

- keep_original:

  Logical. `TRUE` (default) keeps the text of each mapped column as it
  was written, in `station_id_original`, `stage_original`,
  `discharge_original`, `date_original` and, where they exist,
  `time_original` and `datetime_original`.

- quiet:

  Logical. `TRUE` suppresses the summary message.

## Value

A data.table, one row per row of the input, with these columns first:
`source_row` (row of the data, header and blank lines excluded),
`station_id`, `station_name`, `observation_time` (POSIXct), `stage_m`,
`discharge_cms` and `read_issue` (`NA` when the row parsed cleanly,
otherwise the problems separated by semicolons). The `*_original`
columns follow, then every other column of the input unchanged, as text.
A repeated header is kept and made distinct (`Flag`, `Flag.1`). The
structured summary is attached; read it with
[`read_summary()`](https://jonpayneea.github.io/reach.rate/reference/read_summary.md).

## Notes the function can add

`station id missing`, `stage missing`, `discharge missing`,
`stage not a number`, `discharge not a number`, `date missing`,
`date not read`, `date outside 1800 to next year`, `time not read` and
`time missing, midnight assumed`. A stage of zero, a zero discharge or a
discharge with no stage are not noted: they parse, and whether they are
acceptable is a hydrometric judgement for a later check.

## See also

[`read_summary()`](https://jonpayneea.github.io/reach.rate/reference/read_summary.md)
for the structured summary,
[`as_flode_evidence()`](https://jonpayneea.github.io/reach.rate/reference/as_flode_evidence.md)
to turn the result into evidence,
[`read_operational_ratings()`](https://jonpayneea.github.io/reach.rate/reference/read_operational_ratings.md)
for the matching ratings export;
[`compare_gaugings_to_rating()`](https://jonpayneea.github.io/reach.rate/reference/compare_gaugings_to_rating.md)
to check a rating against the result.

## Examples

``` r
# A small archive as it might arrive: placeholder text, a blank
# station, an unreadable stage, and a stage of zero with a flow.
raw <- data.frame(
  `Station number` = c("10250", "10250", "", "F2405", "F2405"),
  Date  = c("03/02/1970", "05/05/1970", "29/05/1970", "06/01/1960", "12/01/1960"),
  Time  = c("12:47:00", "13:02:00", "", "00:00:00", "00:01:00"),
  Stage = c("1.6", "---", "0.85", "1.885", "0"),
  Flow  = c("53.3371", "9.738", "6.6824", "104.189", "0.425"),
  Remark = c("", "dry", "", "FALLING", ""),
  check.names = FALSE
)
gaugings <- read_gaugings(raw)
#> read_gaugings(): 5 rows, 2 stations, date format %d/%m/%Y.
#>   Rows with a note: 2. Most common: stage missing (1), station id missing (1), time missing, midnight assumed (1).
gaugings
#>    source_row station_id station_name    observation_time stage_m discharge_cms
#>         <int>     <char>       <char>              <POSc>   <num>         <num>
#> 1:          1      10250         <NA> 1970-02-03 12:47:00   1.600       53.3371
#> 2:          2      10250         <NA> 1970-05-05 13:02:00      NA        9.7380
#> 3:          3       <NA>         <NA> 1970-05-29 00:00:00   0.850        6.6824
#> 4:          4      F2405         <NA> 1960-01-06 00:00:00   1.885      104.1890
#> 5:          5      F2405         <NA> 1960-01-12 00:01:00   0.000        0.4250
#>                                            read_issue station_id_original
#>                                                <char>              <char>
#> 1:                                               <NA>               10250
#> 2:                                      stage missing               10250
#> 3: station id missing; time missing, midnight assumed                    
#> 4:                                               <NA>               F2405
#> 5:                                               <NA>               F2405
#>    stage_original discharge_original date_original time_original  Remark
#>            <char>             <char>        <char>        <char>  <char>
#> 1:            1.6            53.3371    03/02/1970      12:47:00        
#> 2:            ---              9.738    05/05/1970      13:02:00     dry
#> 3:           0.85             6.6824    29/05/1970                      
#> 4:          1.885            104.189    06/01/1960      00:00:00 FALLING
#> 5:              0              0.425    12/01/1960      00:01:00        
gaugings[!is.na(gaugings$read_issue), c("source_row", "read_issue")]
#>    source_row                                         read_issue
#>         <int>                                             <char>
#> 1:          2                                      stage missing
#> 2:          3 station id missing; time missing, midnight assumed

# A semicolon file with decimal commas, as a continental export writes it.
path <- tempfile(fileext = ".csv")
writeLines(c(
  "Station number;Date;Time;Stage;Flow",
  "10250;03/02/1970;12:47:00;1,6;53,3371",
  "10250;05/05/1970;13:02:00;0,85;6,6824"
), path)
read_gaugings(path, dec = ",", quiet = TRUE)[, .(stage_m, discharge_cms)]
#> Warning: read_gaugings(): every date fits both day-first and month-first, so %d/%m/%Y was used by default. If the file is month-first, pass date_format = "%m/%d/%Y".
#>    stage_m discharge_cms
#>      <num>         <num>
#> 1:    1.60       53.3371
#> 2:    0.85        6.6824

# What was found, as a table.
read_summary(gaugings)
#>                             issue n_rows share_of_rows
#>                            <char>  <int>         <num>
#> 1:                  stage missing      1           0.2
#> 2:             station id missing      1           0.2
#> 3: time missing, midnight assumed      1           0.2
```
