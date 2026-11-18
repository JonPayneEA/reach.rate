# Read a spot-gauging archive

Reads gaugings from a CSV file (or a data.frame) into a table with
standard column names, whatever the original headers were called. It
cleans nothing and removes nothing: every row of the file is returned,
in order. What it does is read every column as text, turn placeholder
text such as `---` into a missing value, parse stage, discharge, date
and time explicitly, and record in `read_issue` anything that did not
parse, so a bad row is visible and not silently lost or changed.

The defaults match the column names of the Environment Agency
WISKI-style gauging export (`Station number`, `Date`, `Time`, `Stage`,
`Flow`). Use the mapping arguments for any other headers.

Dates are detected, not assumed. The format that parses the most values
is used, day-first ahead of month-first when both fit (`04/05/1970` is
read as 4 May). The format chosen is reported in the message, with a
warning when the choice was a default and could be wrong. Pass
`date_format` (for example `"%d/%m/%Y"`) to settle it.

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
  date_format = NULL,
  tz = "UTC",
  quiet = FALSE
)
```

## Arguments

- x:

  A file path to a delimited text file, or a data.frame.

- station_id, station_name:

  Character. Columns holding the station identifier and name. The name
  is optional: it is skipped if the file has no column called
  `Station name`, or if `station_name = NULL`.

- date, time:

  Character. Columns holding the date and the time of day. `time = NULL`
  if there is none; a missing time is then midnight, with no note.

- stage, discharge:

  Character. Columns holding stage (m) and discharge (cumecs).

- date_format:

  A [`strptime()`](https://rdrr.io/r/base/strptime.html) format for the
  date column, or `NULL` (default) to detect it.

- tz:

  Time zone label for `observation_time`. Default `"UTC"`. The clock
  time in the file is used as it stands, with no daylight-saving
  adjustment, so it is only as good as the file's own convention.

- quiet:

  Logical. `TRUE` suppresses the summary message.

## Value

A data.table, one row per row of the input, with these columns first:
`source_row` (row of the data, header excluded), `station_id`,
`station_name`, `observation_time` (POSIXct), `stage_m`, `discharge_cms`
and `read_issue` (`NA` when the row parsed cleanly, otherwise the
problems separated by semicolons). Every other column of the input
follows unchanged, as text. The columns you mapped are not repeated; the
file still has their original values.

## Notes the function can add

`station id missing`, `stage missing`, `discharge missing`,
`stage not a number`, `discharge not a number`, `date missing`,
`date not read`, `date outside 1800 to next year`, `time not read` and
`time missing, midnight assumed`. A stage of zero, a zero discharge or a
discharge with no stage are not noted: they parse, and whether they are
acceptable is a hydrometric judgement for a later check.

## See also

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
#>                                            read_issue  Remark
#>                                                <char>  <char>
#> 1:                                               <NA>        
#> 2:                                      stage missing     dry
#> 3: station id missing; time missing, midnight assumed        
#> 4:                                               <NA> FALLING
#> 5:                                               <NA>        
gaugings[!is.na(gaugings$read_issue), c("source_row", "read_issue")]
#>    source_row                                         read_issue
#>         <int>                                             <char>
#> 1:          2                                      stage missing
#> 2:          3 station id missing; time missing, midnight assumed
```
