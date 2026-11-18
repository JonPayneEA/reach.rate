# Turn operational rating limbs into rating tables

Groups the limbs from
[`read_operational_ratings()`](https://jonpayneea.github.io/reach.rate/reference/read_operational_ratings.md)
into one
[FlodeRatingTable](https://jonpayneea.github.io/reach.rate/reference/FlodeRatingTable.md)
per rating. A rating whose limbs cannot form a valid table is not forced
into one and not dropped silently: it is listed in `problems` with the
reason, so a messy export gives you the good ratings and a precise list
of the rest.

A rating is rejected, with its reason, when a limb has a missing level
or coefficient, when a limb's upper level is not above its lower level,
when two limbs share a lower level, or when the limbs are not contiguous
(a gap or an overlap between one limb's upper level and the next limb's
lower level).

## Usage

``` r
operational_rating_tables(limbs, group_by = "rating_key")
```

## Arguments

- limbs:

  A data.table from
  [`read_operational_ratings()`](https://jonpayneea.github.io/reach.rate/reference/read_operational_ratings.md),
  or any table with `lower_level`, `upper_level`, `C`, `a`, `n` and the
  `group_by` column.

- group_by:

  Character. The column that identifies one rating. Default
  `"rating_key"`.

## Value

A list of two elements. `tables` is a named list of
[FlodeRatingTable](https://jonpayneea.github.io/reach.rate/reference/FlodeRatingTable.md)s,
named by the `group_by` value, with limbs in stage order. `problems` is
a data.table with one row per rejected rating: the `group_by` value,
`station_id` (when present), `n_limbs` and `reason`.

## See also

[`read_operational_ratings()`](https://jonpayneea.github.io/reach.rate/reference/read_operational_ratings.md),
[`compare_gaugings_to_rating()`](https://jonpayneea.github.io/reach.rate/reference/compare_gaugings_to_rating.md),
[`apply_rating()`](https://jonpayneea.github.io/reach.rate/reference/apply_rating.md).

## Examples

``` r
limbs <- data.frame(
  rating_key = c("a", "a", "b", "b"),
  lower_level = c(0, 1, 0, 1.5), upper_level = c(1, 3, 1, 3),
  C = 2, a = 0, n = 1.5
)
result <- operational_rating_tables(limbs)
names(result$tables)
#> [1] "a"
result$problems
#>    rating_key station_id n_limbs
#>        <char>     <char>   <int>
#> 1:          b       <NA>       2
#>                                                              reason
#>                                                              <char>
#> 1: limbs are not contiguous: gap of 0.5 m between limb 1 and limb 2
```
