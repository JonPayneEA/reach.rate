# Gauged support for a rating

How much of each limb rests on gaugings: how many fall inside it, the
stage range they cover, and how far the limb extends beyond them at
either end. A limb that stretches well past its highest gauging is an
extrapolation there, whatever its fit statistics say.

## Usage

``` r
rating_support(x)
```

## Arguments

- x:

  A
  [FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md)
  or
  [FlodeSegmentedRating](https://jonpayneea.github.io/reach.rate/reference/FlodeSegmentedRating.md).
  A
  [FlodeRatingTable](https://jonpayneea.github.io/reach.rate/reference/FlodeRatingTable.md)
  holds equations only, with no gaugings to measure support against.

## Value

A data.table. For a
[FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md),
one row per limb: `limb`, `lower_stage_m`, `upper_stage_m`,
`n_gaugings`, `gauged_min_stage_m`, `gauged_max_stage_m`,
`lower_unsupported_m` and `upper_unsupported_m` (how far the limb
extends below its lowest and above its highest gauging, m), and the same
as a fraction of the limb's width, `lower_unsupported_frac` and
`upper_unsupported_frac`. A limb with no gaugings has `n_gaugings` 0 and
`NA` elsewhere. For a
[FlodeSegmentedRating](https://jonpayneea.github.io/reach.rate/reference/FlodeSegmentedRating.md),
one row with `n_gaugings`, `gauged_min_stage_m` and
`gauged_max_stage_m`.

## See also

[`flag_extrapolated_limbs()`](https://jonpayneea.github.io/reach.rate/reference/flag_extrapolated_limbs.md)
for the same measures with a tolerance applied;
[`rating_evidence()`](https://jonpayneea.github.io/reach.rate/reference/rating_evidence.md)

## Examples

``` r
set.seed(1)
stage_m <- seq(0.5, 2.5, by = 0.05)
discharge_cms <- 5 * stage_m^1.6 + rnorm(length(stage_m), sd = 0.02)
fit <- rate_optimise(discharge_cms, stage_m)
rating_support(fit)
#>     limb lower_stage_m upper_stage_m n_gaugings gauged_min_stage_m
#>    <int>         <num>         <num>      <int>              <num>
#> 1:     1           0.5           2.5         41                0.5
#>    gauged_max_stage_m lower_unsupported_m upper_unsupported_m
#>                 <num>               <num>               <num>
#> 1:                2.5                   0                   0
#>    lower_unsupported_frac upper_unsupported_frac
#>                     <num>                  <num>
#> 1:                      0                      0
```
