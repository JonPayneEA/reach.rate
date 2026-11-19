# State the stage range a rating may be applied over

A rating made by
[`fit_rating()`](https://jonpayneea.github.io/reach.rate/reference/fit_rating.md)
is applied only within the stage range it was gauged over, until the
range it may be used over is stated here. That range is a decision, not
a property of the data: it might be the gauged range, a structure's
limit, a hydraulic argument for extrapolating to a stated stage, or a
review outcome. Saying it, and saying why, is what makes a wider
application defensible.

The rating is returned as a new version. Its earlier state is kept in
[`rating_history()`](https://jonpayneea.github.io/reach.rate/reference/rating_history.md),
and its lifecycle goes back to `"draft"`, since a change to where a
rating may be used is a change a reviewer should see. Stages outside the
limits are refused by
[`apply_rating()`](https://jonpayneea.github.io/reach.rate/reference/apply_rating.md);
stages inside them but beyond the gauged range are computed and flagged
`extrapolated`.

## Usage

``` r
set_operational_limits(x, lower_stage_m, upper_stage_m, basis = NA_character_)
```

## Arguments

- x:

  A
  [FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md)
  or
  [FlodeSegmentedRating](https://jonpayneea.github.io/reach.rate/reference/FlodeSegmentedRating.md).

- lower_stage_m, upper_stage_m:

  The stage range in metres, lower below upper.

- basis:

  Character. Why this range.

## Value

A copy of `x` with the limits in its provenance.

## See also

[`fit_rating()`](https://jonpayneea.github.io/reach.rate/reference/fit_rating.md),
[`rating_provenance()`](https://jonpayneea.github.io/reach.rate/reference/rating_provenance.md),
[`rating_history()`](https://jonpayneea.github.io/reach.rate/reference/rating_history.md)

## Examples

``` r
set.seed(2)
stage_m <- seq(0.5, 3, length.out = 15)
fit <- fit_rating(
  data.frame(stage_m = stage_m, discharge_cms = 3 * stage_m^1.6 * exp(rnorm(15, sd = 0.03))),
  quiet = TRUE
)
limited <- set_operational_limits(fit, 0.4, 3.2, basis = "gauged range plus 0.2 m of judgement")
rating_provenance(limited)$operational_limits
#> $lower_stage_m
#> [1] 0.4
#> 
#> $upper_stage_m
#> [1] 3.2
#> 
#> $basis
#> [1] "gauged range plus 0.2 m of judgement"
#> 
rating_history(limited)[, .(class, lifecycle, note)]
#>          class lifecycle
#>         <char>    <char>
#> 1: FlodeRating     draft
#> 2: FlodeRating     draft
#>                                                                             note
#>                                                                           <char>
#> 1:                                                                          <NA>
#> 2: operational limits set to 0.4 to 3.2 m (gauged range plus 0.2 m of judgement)
```
