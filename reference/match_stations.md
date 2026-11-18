# Match gauging stations to rating stations

Links the stations in a gauging archive to the stations in an
operational ratings export, so each rating can be checked against its
own gaugings. The two files name stations differently, so the link is
made in two ways, and you decide how much of each to use:

- **A table you supply** (`crosswalk`): one row per link, with the
  rating's station id (`FFFSLocID`) and the matching gauging reference
  (the gauging file's station number). This is the reliable route, and
  it takes priority. A rating station can map to several references, and
  several rating stations to one.

- **The ids as they stand** (`direct = TRUE`, the default): for a rating
  station that the table does not link to a gauging station, the station
  id is compared with the gauging file's station ids directly. Case and
  surrounding spaces are ignored; nothing else is altered, so `065006`
  does not match `065006_TG_802` unless the table says so.

Nothing is guessed. What does not match is reported, on both sides, so
the table can be extended until the matches you expect are there.

## Usage

``` r
match_stations(
  gaugings,
  ratings,
  crosswalk = NULL,
  crosswalk_station = "FFFSLocID",
  crosswalk_reference = "Reference",
  direct = TRUE,
  quiet = FALSE
)
```

## Arguments

- gaugings:

  A data.table from
  [`read_gaugings()`](https://jonpayneea.github.io/reach.rate/reference/read_gaugings.md),
  or any table with a `station_id` column (and, optionally,
  `station_name`, `observation_time`).

- ratings:

  A data.table from
  [`read_operational_ratings()`](https://jonpayneea.github.io/reach.rate/reference/read_operational_ratings.md),
  or any table with a `station_id` column (and, optionally,
  `station_name` and `rating_key`).

- crosswalk:

  A data.frame with one column of rating station ids and one of gauging
  references, or `NULL` (default) to match on the ids alone.

- crosswalk_station, crosswalk_reference:

  Character. Names of the two columns of `crosswalk`. Defaults
  `"FFFSLocID"` and `"Reference"`. Names are matched ignoring case.

- direct:

  Logical. Also match ids directly where the table gives no link.
  Default `TRUE`.

- quiet:

  Logical. `TRUE` suppresses the summary message.

## Value

A list of four data.tables.

- `links`: one row per link, with `station_id` (the rating side),
  `gauging_station_id` and `link` (`"crosswalk"` or `"direct"`).

- `unmatched_ratings`: rating stations with no gauging station, with
  `station_id`, `station_name`, `n_ratings` and `n_limbs`.

- `unmatched_gaugings`: gauging stations with no rating station, with
  `station_id`, `station_name`, `n_gaugings` and, when the gaugings have
  an `observation_time`, `first_gauging` and `last_gauging`.

- `crosswalk_unused`: rows of `crosswalk` that could not be used, with
  the `reason`: the station is not in the ratings, the reference is not
  in the gaugings, or neither, or a value is missing.

## See also

[`check_operational_ratings()`](https://jonpayneea.github.io/reach.rate/reference/check_operational_ratings.md)
to run the comparison for every matched rating.

## Examples

``` r
gaugings <- data.frame(
  station_id = c("10250", "10250", "F2405", "684500007", "SD47651250"),
  station_name = c("BATHFORD", "BATHFORD", "Skelton", "WHITE MILL", "TAWD")
)
ratings <- data.frame(
  station_id = c("10250", "10250", "065006_TG_802", "684500007", "29004"),
  station_name = c("Bathford", "Bathford", "Pelic Seiont", "White Mill", "Ancholme"),
  rating_key = c("a/1", "a/1", "b/1", "c/1", "d/1")
)

# Without a table, only identical ids match
match_stations(gaugings, ratings)$unmatched_ratings
#> match_stations(): 2 of 4 rating stations matched (0 by table, 2 directly); 2 of 4 gauging stations matched.
#>   Unmatched: 2 rating stations, 2 gauging stations. Table rows not used: 0.
#>       station_id station_name n_ratings n_limbs
#>           <char>       <char>     <int>   <int>
#> 1: 065006_TG_802 Pelic Seiont         1       1
#> 2:         29004     Ancholme         1       1

# A table links what the ids alone cannot, and reports a row that fails
crosswalk <- data.frame(
  FFFSLocID = c("065006_TG_802", "29004", "99999"),
  Reference = c("F2405", "NOT_IN_GAUGINGS", "10250")
)
result <- match_stations(gaugings, ratings, crosswalk)
#> match_stations(): 3 of 4 rating stations matched (1 by table, 2 directly); 3 of 4 gauging stations matched.
#>   Unmatched: 1 rating stations, 1 gauging stations. Table rows not used: 2.
result$links
#>       station_id gauging_station_id      link
#>           <char>             <char>    <char>
#> 1: 065006_TG_802              F2405 crosswalk
#> 2:         10250              10250    direct
#> 3:     684500007          684500007    direct
result$crosswalk_unused
#>      row station       reference                    reason
#>    <int>  <char>          <char>                    <char>
#> 1:     2   29004 NOT_IN_GAUGINGS reference not in gaugings
#> 2:     3   99999           10250    station not in ratings
result$unmatched_gaugings
#>    station_id station_name n_gaugings
#>        <char>       <char>      <int>
#> 1: SD47651250         TAWD          1
```
