# The gaugings a rating was fitted to

The evidence behind a fit: one row per gauging, as it was used. For a
fit made with `age_halflife`, the recency weight each gauging received
is included.

## Usage

``` r
rating_evidence(x)
```

## Arguments

- x:

  A
  [FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md)
  or
  [FlodeSegmentedRating](https://jonpayneea.github.io/reach.rate/reference/FlodeSegmentedRating.md).
  A
  [FlodeRatingTable](https://jonpayneea.github.io/reach.rate/reference/FlodeRatingTable.md)
  holds equations only and has no gaugings.

## Value

A data.table with `gauging_datetime` (when the fit was given one),
`stage_m`, `discharge_cms`, `limb` (the limb each gauging fell in, for a
[FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md))
and `age_weight` (when recency weighting was used). A copy.

## See also

[`rating_support()`](https://jonpayneea.github.io/reach.rate/reference/rating_support.md),
[`flag_influential_gaugings()`](https://jonpayneea.github.io/reach.rate/reference/flag_influential_gaugings.md)

## Examples

``` r
set.seed(1)
stage_m <- seq(0.5, 2.5, by = 0.05)
discharge_cms <- 5 * stage_m^1.6 + rnorm(length(stage_m), sd = 0.02)
fit <- rate_optimise(discharge_cms, stage_m)
head(rating_evidence(fit))
#>    stage_m discharge_cms  limb
#>      <num>         <num> <int>
#> 1:    0.50      1.636856     1
#> 2:    0.55      1.924774     1
#> 3:    0.60      2.191353     1
#> 4:    0.65      2.541661     1
#> 5:    0.70      2.832295     1
#> 6:    0.75      3.139089     1
```
