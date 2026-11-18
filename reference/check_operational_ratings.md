# Check every operational rating against its gaugings

Runs
[`compare_gaugings_to_rating()`](https://jonpayneea.github.io/reach.rate/reference/compare_gaugings_to_rating.md)
for every rating in an operational ratings export, against the gaugings
of the station it is matched to, and collects the results in one place.
It is the whole of the check in one call: build each rating as a table,
link ratings to gauging stations, compare, and report both the findings
and everything that could not be compared.

Nothing is excluded for being odd. A rating that cannot form a valid
table, a rating whose station has no gaugings, a gauging station with no
rating, and a row of the matching table that matched nothing are each
listed with the reason, so the picture is complete and the unmatched
part can be worked down.

By default every gauging of a matched station is compared with every
rating of that station, whatever its dates. A station that has had
several ratings over time will therefore show each rating against all of
its gaugings. Set `use_dates = TRUE` to compare each rating only with
gaugings taken while it was in force: from its `start_date` to its
`end_date`, where an end date is missing, or is earlier than the start
date (which the ratings export uses for "no end"), the rating is treated
as still in force.

## Usage

``` r
check_operational_ratings(
  gaugings,
  ratings,
  crosswalk = NULL,
  crosswalk_station = "FFFSLocID",
  crosswalk_reference = "Reference",
  direct = TRUE,
  use_dates = FALSE,
  tol_rel = 0.1,
  keep_gaugings = FALSE,
  quiet = FALSE
)
```

## Arguments

- gaugings:

  A table from
  [`read_gaugings()`](https://jonpayneea.github.io/reach.rate/reference/read_gaugings.md).

- ratings:

  A table from
  [`read_operational_ratings()`](https://jonpayneea.github.io/reach.rate/reference/read_operational_ratings.md).

- crosswalk, crosswalk_station, crosswalk_reference, direct:

  As in
  [`match_stations()`](https://jonpayneea.github.io/reach.rate/reference/match_stations.md).

- use_dates:

  Logical. Compare each rating only with the gaugings taken while it was
  in force. Default `FALSE`. Needs `observation_time` in `gaugings` and
  `start_date` and `end_date` in `ratings`.

- tol_rel:

  Numeric. Tolerance for `share_within_tol`, as in
  [`compare_gaugings_to_rating()`](https://jonpayneea.github.io/reach.rate/reference/compare_gaugings_to_rating.md).
  Default `0.10`.

- keep_gaugings:

  Logical. Also return every gauging with its residual against each
  rating it was compared with. Default `FALSE`: for a large archive this
  is a large table.

- quiet:

  Logical. `TRUE` suppresses the summary message.

## Value

A list with these elements.

- `ratings`: one row per rating, with `rating_key`, `station_id`,
  `station_name`, `n_limbs`, `status` (`"compared"`, `"no gaugings"` or
  `"not a valid table"`), `reason` (for a rating that is not a valid
  table), `n_gaugings` (compared), `n_inside` and `n_extrapolated`,
  `n_limbs_with_gaugings`, `top_limb_has_gaugings`, `gauged_max_stage`,
  `median_residual_pct` and `share_within_tol` over the gaugings inside
  the rating.

- `limbs`: one row per limb of every compared rating, with `rating_key`,
  `station_id`, the columns of
  [`compare_gaugings_to_rating()`](https://jonpayneea.github.io/reach.rate/reference/compare_gaugings_to_rating.md)'s
  `limbs`, and the export's `flag` and `open_ended` for that limb.
  `flag` is carried through so you can see whether it lines up with
  limbs that have no gaugings.

- `gaugings`: the per-gauging results, or `NULL` unless
  `keep_gaugings = TRUE`.

- `matches`: the list returned by
  [`match_stations()`](https://jonpayneea.github.io/reach.rate/reference/match_stations.md).

- `problems`: the ratings that are not valid tables, with the reason.

## See also

[`match_stations()`](https://jonpayneea.github.io/reach.rate/reference/match_stations.md),
[`compare_gaugings_to_rating()`](https://jonpayneea.github.io/reach.rate/reference/compare_gaugings_to_rating.md),
[`read_gaugings()`](https://jonpayneea.github.io/reach.rate/reference/read_gaugings.md),
[`read_operational_ratings()`](https://jonpayneea.github.io/reach.rate/reference/read_operational_ratings.md).

## Examples

``` r
# Two ratings and one archive of gaugings. Station "S1" has gaugings up to
# 2.3 m, so the top limb of its rating (to 4 m) has none. Station "S2" has
# a rating but no gaugings, and station "S3" has gaugings but no rating.
ratings <- data.frame(
  rating_key = rep(c("r1", "r2"), c(4, 2)), station_id = rep(c("S1", "S2"), c(4, 2)),
  station_name = rep(c("Bathford", "Skelton"), c(4, 2)),
  lower_level = c(0.30, 0.90, 1.70, 2.60, 0, 1), upper_level = c(0.90, 1.70, 2.60, 4.00, 1, 3),
  C = c(1.80000, 2.85549, 4.72355, 2.36038, 2, 2), a = c(0.10, 0.25, 0.55, 0.40, 0, 0),
  n = c(1.60, 1.90, 1.45, 2.20, 1.5, 1.5),
  flag = c(0, 0, 0, 3, 0, 0), open_ended = c(FALSE, FALSE, FALSE, TRUE, FALSE, TRUE)
)
set.seed(3)
stage_m <- sort(runif(40, 0.3, 2.3))
gaugings <- data.frame(
  station_id = c(rep("S1", 40), rep("S3", 3)),
  stage_m = c(stage_m, 1, 1.5, 2),
  discharge_cms = c(apply_rating(FlodeRatingTable(table = data.table::as.data.table(ratings[1:4, 4:8])),
                                 stage_m)$discharge * exp(rnorm(40, sd = 0.04)), 3, 5, 8)
)
check <- check_operational_ratings(gaugings, ratings)
#> check_operational_ratings(): 2 ratings: 1 compared, 1 with no gaugings, 0 not valid tables.
#>   Limbs with no gaugings: 1 of 4 in compared ratings. Unmatched: 1 rating stations, 1 gauging stations.
check$ratings[, c("rating_key", "status", "n_gaugings", "median_residual_pct")]
#>    rating_key      status n_gaugings median_residual_pct
#>        <char>      <char>      <int>               <num>
#> 1:         r1    compared         40          -0.7291611
#> 2:         r2 no gaugings          0                  NA
check$limbs[, c("rating_key", "limb", "n_gaugings", "has_gaugings", "flag")]
#>    rating_key  limb n_gaugings has_gaugings  flag
#>        <char> <int>      <int>       <lgcl> <num>
#> 1:         r1     1         14         TRUE     0
#> 2:         r1     2         17         TRUE     0
#> 3:         r1     3          9         TRUE     0
#> 4:         r1     4          0        FALSE     3
check$matches$unmatched_gaugings
#>    station_id station_name n_gaugings
#>        <char>       <char>      <int>
#> 1:         S3         <NA>          3
```
