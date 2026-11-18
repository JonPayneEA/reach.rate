# What a read found, as a table

The structured form of the summary
[`read_gaugings()`](https://jonpayneea.github.io/reach.rate/reference/read_gaugings.md)
prints: one row for each kind of problem noted, with how many rows carry
it and what share of the file that is. Counts are of rows, and a row
with two problems counts once under each. The table carries the headline
figures as attributes: `source`, `rows`, `stations`, `date_format` and
`rows_with_note`.

The information is attached to the table as it was read and describes
that table. If rows have since been added or removed, so that the count
no longer matches, `read_summary()` stops and says so, because the
figures would no longer describe what is left. Read the summary before
filtering.

## Usage

``` r
read_summary(x)
```

## Arguments

- x:

  A table returned by
  [`read_gaugings()`](https://jonpayneea.github.io/reach.rate/reference/read_gaugings.md).

## Value

A data.table with columns `issue`, `n_rows` and `share_of_rows`, most
common first, and no rows when nothing was noted.

## See also

[`read_gaugings()`](https://jonpayneea.github.io/reach.rate/reference/read_gaugings.md)

## Examples

``` r
raw <- data.frame(
  `Station number` = c("10250", "10250", ""),
  Date = c("03/02/1970", "05/05/1970", "29/05/1970"),
  Time = c("12:47:00", "13:02:00", ""),
  Stage = c("1.6", "---", "0.85"), Flow = c("53.3", "9.7", "6.7"),
  check.names = FALSE
)
gaugings <- read_gaugings(raw, quiet = TRUE)
summary_table <- read_summary(gaugings)
summary_table
#>                             issue n_rows share_of_rows
#>                            <char>  <int>         <num>
#> 1:                  stage missing      1     0.3333333
#> 2:             station id missing      1     0.3333333
#> 3: time missing, midnight assumed      1     0.3333333
attr(summary_table, "rows")
#> [1] 3
```
