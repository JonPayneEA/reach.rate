# Read an operational ratings export

Reads an export of operational power-law ratings, one row per limb, into
a table with the package's own names. Each row's equation is
`Q = C (H - A)^B`: the export's `A` becomes `a` (the stage of zero
flow), `B` becomes `n` (the exponent) and `C` stays `C`. Nothing is
reinterpreted. As with
[`read_gaugings()`](https://jonpayneea.github.io/reach.rate/reference/read_gaugings.md),
everything is read as text, parsed explicitly, and anything that did not
parse is noted on its row in `read_issue` and not dropped.

Ratings flagged as grid-to-grid model output (`G2G` is `TRUE`) are
omitted by default, because they are model estimates and not operational
ratings; the message says how many rows went. Set `omit_g2g = FALSE` to
keep them and filter on the `g2g` column. The export's `Flag` is carried
through as `flag` with no meaning assumed.

The export marks an open-ended top limb with an upper level of `999`;
`open_ended` is `TRUE` for those rows and the level itself is left as it
is.

## Usage

``` r
read_operational_ratings(
  x,
  rating_id = "ID",
  station_id = "FFFSLocID",
  station_name = "FFFSLocName",
  qualifier = "Qualifier",
  season = "Season",
  start_date = "StartDate",
  end_date = "EndDate",
  curve_id = "RatingCurveID",
  source_id = "SourceID",
  lower_level = "LowerLevel",
  upper_level = "UpperLevel",
  offset = "A",
  exponent = "B",
  scale = "C",
  flag = "Flag",
  ea = "EA",
  g2g = "G2G",
  omit_g2g = TRUE,
  open_ended_level = 999,
  date_format = NULL,
  quiet = FALSE
)
```

## Arguments

- x:

  A file path to a delimited text file, or a data.frame.

- rating_id, station_id, station_name, qualifier, season, curve_id,
  source_id, flag, ea, g2g:

  Character. Names of the export's columns. The defaults match the
  export (`ID`, `FFFSLocID`, `FFFSLocName`, `Qualifier`, `Season`,
  `RatingCurveID`, `SourceID`, `Flag`, `EA`, `G2G`). A column that is
  absent under its default name is simply skipped; one you name yourself
  must exist. `NULL` skips a column.

- start_date, end_date:

  Character. Columns holding the dates the rating applies from and to.

- lower_level, upper_level:

  Character. Columns holding each limb's stage range (m).

- offset, exponent, scale:

  Character. Columns holding `A`, `B` and `C`. Defaults `"A"`, `"B"`,
  `"C"`.

- omit_g2g:

  Logical. Drop rows where `g2g` is `TRUE`. Default `TRUE`.

- open_ended_level:

  Numeric. An upper level at or above this marks an open-ended limb.
  Default `999`.

- date_format:

  A [`strptime()`](https://rdrr.io/r/base/strptime.html) format for both
  date columns, or `NULL` (default) to detect each column's format.

- quiet:

  Logical. `TRUE` suppresses the summary message.

## Value

A data.table, one row per limb, with `source_row`, `rating_key` (the
rating id and the curve id together, which identifies one rating),
`rating_id`, `station_id`, `station_name`, `qualifier`, `season`,
`start_date`, `end_date`, `end_before_start` (`TRUE` where the end date
is earlier than the start date, which in this export is how an open end
appears; left for you to interpret), `curve_id`, `source_id`,
`lower_level`, `upper_level`, `open_ended`, `C`, `a`, `n`, `flag`, `ea`,
`g2g` and `read_issue`.

## Notes the function can add

`station id missing`, `lower level missing`, `upper level missing`,
`A missing`, `B missing`, `C missing`, `a value not a number` (for any
of those columns), `upper level not above lower level`,
`C not positive`, `B not positive`, `G2G not read`, and `date not read`.

## See also

[`operational_rating_tables()`](https://jonpayneea.github.io/reach.rate/reference/operational_rating_tables.md)
to turn the limbs into rating tables;
[`read_gaugings()`](https://jonpayneea.github.io/reach.rate/reference/read_gaugings.md).

## Examples

``` r
raw <- data.frame(
  ID = rep(c("r1", "r2"), c(3, 2)), FFFSLocID = rep(c("4761", "29004"), c(3, 2)),
  FFFSLocName = rep(c("Spinney Hill Park", "Ancholme Bishopbridge"), c(3, 2)),
  Qualifier = "Power", Season = "All",
  StartDate = "01/01/2000 00:00", EndDate = "12/31/1999 12:00:00 AM",
  RatingCurveID = rep(c("c1", "c2"), c(3, 2)), SourceID = "s1",
  LowerLevel = c(0, 0.241, 0.897, 0, 0.314), UpperLevel = c(0.241, 0.897, 999, 0.314, 999),
  A = c(0, 0.1, 0.4, 0, 0.01), B = c(1.254, 1.541, 0.8265, 1.5042, 2.2279),
  C = c(3.114, 10.717, 13.462, 4.711, 11.7052),
  Flag = c(0, 0, 3, 0, 0), EA = TRUE, G2G = c(FALSE, FALSE, FALSE, TRUE, TRUE)
)
limbs <- read_operational_ratings(raw)
#> read_operational_ratings(): 3 limbs in 1 ratings at 1 stations.
#>   G2G rows omitted: 2. Rows with a note: 0. Most common: none.
limbs[, c("rating_key", "station_id", "lower_level", "upper_level", "C", "a", "n", "open_ended")]
#>    rating_key station_id lower_level upper_level      C     a      n open_ended
#>        <char>     <char>       <num>       <num>  <num> <num>  <num>     <lgcl>
#> 1:      r1/c1       4761       0.000       0.241  3.114   0.0 1.2540      FALSE
#> 2:      r1/c1       4761       0.241       0.897 10.717   0.1 1.5410      FALSE
#> 3:      r1/c1       4761       0.897     999.000 13.462   0.4 0.8265       TRUE
```
