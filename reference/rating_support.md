# What a rating rests on

The stage ranges a rating rests on, and which of them are evidence and
which are decision. There are five:

- **observed**: the stage range of the gaugings (evidence of source type
  `gauging`), with how many there are;

- **modelled**: the stage range of evidence that is not a measurement (a
  modelled value, a cross-section or structure computation, or a point
  read off another rating);

- **fitted**: the stage range the equations are declared over, which can
  be wider than the evidence after
  [`extend_rating_low()`](https://jonpayneea.github.io/reach.rate/reference/extend_rating_low.md)
  or
  [`graft_rating()`](https://jonpayneea.github.io/reach.rate/reference/graft_rating.md);

- **operational**: the range the rating may be used over, if stated (see
  [`set_operational_limits()`](https://jonpayneea.github.io/reach.rate/reference/set_operational_limits.md));
  `NA` if not;

- **numerical**: where the equations give a finite discharge. Beyond it
  [`apply_rating()`](https://jonpayneea.github.io/reach.rate/reference/apply_rating.md)
  fails.

[`apply_rating()`](https://jonpayneea.github.io/reach.rate/reference/apply_rating.md)
uses the same ranges to say, for every stage it computes, how well
supported that stage is (its `support` column).

With `by = "limb"` it gives instead how much of each limb rests on
gaugings: how many fall inside it, the stage range they cover, and how
far the limb extends beyond them at either end. A limb that stretches
well past its highest gauging is an extrapolation there, whatever its
fit statistics say.

## Usage

``` r
rating_support(x, by = "range")
```

## Arguments

- x:

  A
  [FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md),
  [FlodeSegmentedRating](https://jonpayneea.github.io/reach.rate/reference/FlodeSegmentedRating.md)
  or
  [FlodeRatingTable](https://jonpayneea.github.io/reach.rate/reference/FlodeRatingTable.md).
  A table holds equations only, so it has no observed or modelled range.

- by:

  `"range"` (default) for the five ranges, or `"limb"` for the per-limb
  table. `"limb"` needs gaugings, so a
  [FlodeRatingTable](https://jonpayneea.github.io/reach.rate/reference/FlodeRatingTable.md)
  is refused.

## Value

With `by = "range"`, a data.table of five rows with `range`,
`lower_stage_m`, `upper_stage_m`, `n_evidence` (gaugings or modelled
points, `NA` for the ranges that are not evidence) and `basis`, a
sentence on what the range is. A range that does not exist is `NA`.

With `by = "limb"`, for a
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

[`apply_rating()`](https://jonpayneea.github.io/reach.rate/reference/apply_rating.md)
for the `support` column;
[`set_operational_limits()`](https://jonpayneea.github.io/reach.rate/reference/set_operational_limits.md);
[`flag_extrapolated_limbs()`](https://jonpayneea.github.io/reach.rate/reference/flag_extrapolated_limbs.md),
which the support classes supersede;
[`rating_evidence()`](https://jonpayneea.github.io/reach.rate/reference/rating_evidence.md)

## Examples

``` r
set.seed(1)
stage_m <- seq(0.5, 2.5, by = 0.05)
discharge_cms <- 5 * stage_m^1.6 + rnorm(length(stage_m), sd = 0.02)
fit <- rate_optimise(discharge_cms, stage_m)
rating_support(fit)
#>          range lower_stage_m upper_stage_m n_evidence
#>         <char>         <num>         <num>      <int>
#> 1:    observed           0.5    2.5000e+00         41
#> 2:    modelled            NA            NA          0
#> 3:      fitted           0.5    2.5000e+00         NA
#> 4: operational            NA            NA         NA
#> 5:   numerical          -Inf   1.3029e+192         NA
#>                                                                                                  basis
#>                                                                                                 <char>
#> 1:                                                         gaugings: evidence of source type 'gauging'
#> 2: evidence of any other source type (modelled, cross-section, structure equation, operational rating)
#> 3:                                                     the stage range the equations are declared over
#> 4:                                                            not stated; see set_operational_limits()
#> 5:                         where the equations give a finite discharge; beyond it apply_rating() fails
rating_support(fit, by = "limb")
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
