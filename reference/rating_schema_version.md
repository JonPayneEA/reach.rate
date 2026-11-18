# The schema version of rating objects

The version of the layout in which
[FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md),
[FlodeSegmentedRating](https://jonpayneea.github.io/reach.rate/reference/FlodeSegmentedRating.md)
and
[FlodeRatingTable](https://jonpayneea.github.io/reach.rate/reference/FlodeRatingTable.md)
objects are stored. It changes when a stored property is added, removed
or changes meaning, not on every release, so it is the number to check
before trusting an object read back with
[`readRDS()`](https://rdrr.io/r/base/readRDS.html). Each rating records
the version it was made under in
[`rating_provenance()`](https://jonpayneea.github.io/reach.rate/reference/rating_provenance.md),
and refuses to validate if that version is missing or newer than this
one.

## Usage

``` r
rating_schema_version()
```

## Value

A single integer.

## See also

[`rating_provenance()`](https://jonpayneea.github.io/reach.rate/reference/rating_provenance.md)

## Examples

``` r
rating_schema_version()
#> [1] 2
```
