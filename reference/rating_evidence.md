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
#> <FlodeEvidence> 6 row(s), 6 included, source type(s): gauging
#> Note: Converted from a plain table; filled evidence_id, site_id, observation_time, source_type, source_name, source_version, quality_code, notes, exclusion_reason, included, weight, source_row, metadata. source_type assumed 'gauging', weight assumed 1, included TRUE unless stage or discharge is missing. 
#>    evidence_id stage_m discharge_cms observation_time source_type included
#>         <char>   <num>         <num>           <POSc>      <char>   <lgcl>
#> 1:        G001    0.50      1.636856             <NA>     gauging     TRUE
#> 2:        G002    0.55      1.924774             <NA>     gauging     TRUE
#> 3:        G003    0.60      2.191353             <NA>     gauging     TRUE
#> 4:        G004    0.65      2.541661             <NA>     gauging     TRUE
#> 5:        G005    0.70      2.832295             <NA>     gauging     TRUE
#> 6:        G006    0.75      3.139089             <NA>     gauging     TRUE
```
