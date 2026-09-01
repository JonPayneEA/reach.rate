# Apply a versioned rating to a stage time series

Real ratings shift over time – bed erosion, deposition, vegetation
growth, a channel realignment – which is exactly why gauging stations
get re-rated periodically (Hodson et al. 2024, citing Mansanarez et al.
2019, "Shift Happens!").
[`apply_rating()`](https://jonpayneea.github.io/reach.rate/reference/apply_rating.md)
assumes a single, static rating for an entire stage series; this instead
selects, for each stage observation, whichever rating version was in
effect at that observation's timestamp, then applies that version's
equation – composing
[`apply_rating()`](https://jonpayneea.github.io/reach.rate/reference/apply_rating.md)
once per version rather than reimplementing the discharge calculation.

## Usage

``` r
apply_rating_versioned(
  stage_dt,
  rating_history_dt,
  stage_col = "stage",
  datetime_col = "datetime",
  out_col = "discharge"
)
```

## Arguments

- stage_dt:

  Data.frame or data.table with a stage column and a datetime column.

- rating_history_dt:

  Data.table with one row per (version, limb): `version`,
  `effective_from`, `effective_to` (both POSIXct or Date;
  `effective_to = NA` means "still current", and only the most recent
  version may have `NA` here), `lower_level`, `upper_level`, `C`, `a`,
  `n`. Version date ranges must not overlap.

- stage_col, datetime_col:

  Character. Column names in `stage_dt`. Defaults `"stage"`,
  `"datetime"`.

- out_col:

  Character. Default `"discharge"`.

## Value

`stage_dt` as a data.table with `out_col`, `extrapolated`, and `version`
(which rating version was applied to that row; `NA` if no version was in
effect at that timestamp, in which case `out_col` is also `NA` for that
row and a warning is issued) columns added.

## See also

[`apply_rating()`](https://jonpayneea.github.io/reach.rate/reference/apply_rating.md)

## Examples

``` r
rating_history_dt <- data.table::data.table(
  version = c("v1", "v2"),
  effective_from = as.POSIXct(c("2024-01-01", "2025-06-01"), tz = "UTC"),
  effective_to = as.POSIXct(c("2025-06-01", NA), tz = "UTC"),
  lower_level = c(0.0, 0.0), upper_level = c(3.0, 3.0),
  C = c(3.0, 3.4), a = c(0, 0), n = c(1.6, 1.6)
)
stage_dt <- data.table::data.table(
  datetime = as.POSIXct(c("2024-06-01", "2025-12-01"), tz = "UTC"),
  stage = c(1.5, 1.5)
)
apply_rating_versioned(stage_dt, rating_history_dt)
#>      datetime stage version discharge extrapolated
#>        <POSc> <num>  <char>     <num>       <lgcl>
#> 1: 2024-06-01   1.5      v1  5.739410        FALSE
#> 2: 2025-12-01   1.5      v2  6.504665        FALSE
```
