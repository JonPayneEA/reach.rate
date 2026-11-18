# Limbs of a rating

One row per limb: its stage range and its equation `Q = C(H - a)^n`.
This is the part of a rating a reader needs to apply or compare it,
without the fit diagnostics (see
[`rating_diagnostics()`](https://jonpayneea.github.io/reach.rate/reference/rating_diagnostics.md))
or the uncertainty (see
[`rating_coefficients()`](https://jonpayneea.github.io/reach.rate/reference/rating_coefficients.md)).

## Usage

``` r
rating_limbs(x, all_columns = FALSE)
```

## Arguments

- x:

  A
  [FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md)
  or a
  [FlodeRatingTable](https://jonpayneea.github.io/reach.rate/reference/FlodeRatingTable.md).
  A
  [FlodeSegmentedRating](https://jonpayneea.github.io/reach.rate/reference/FlodeSegmentedRating.md)
  is one joint model and has no independent limbs: use
  [`rating_coefficients()`](https://jonpayneea.github.io/reach.rate/reference/rating_coefficients.md)
  for its parameters.

- all_columns:

  Logical. `FALSE` (default) returns the six stable columns below.
  `TRUE` returns everything the rating carries for each limb: for a fit,
  the diagnostics and uncertainty columns as well (`rmse_cms`,
  `r_squared`, `n_obs`, `C_se` and so on); for a rating that has been
  through
  [`flag_extrapolated_limbs()`](https://jonpayneea.github.io/reach.rate/reference/flag_extrapolated_limbs.md),
  [`align_limb_equations()`](https://jonpayneea.github.io/reach.rate/reference/align_limb_equations.md)
  or
  [`align_limb_boundaries()`](https://jonpayneea.github.io/reach.rate/reference/align_limb_boundaries.md),
  the columns those steps add (`doubtful`, `aligned`,
  `boundary_adjusted`, the `*_original` values). Select the columns you
  want by name: the set available varies with how the rating was made
  and can grow between releases.

## Value

A data.table with columns `limb` (integer, 1 is the lowest),
`lower_stage_m`, `upper_stage_m` (stage, m), `C`, `a` (stage of zero
flow, m) and `n` (exponent); with `all_columns = TRUE`, those first and
then the rest. A copy: changing it does not change the rating.

## See also

[`rating_coefficients()`](https://jonpayneea.github.io/reach.rate/reference/rating_coefficients.md),
[`rating_diagnostics()`](https://jonpayneea.github.io/reach.rate/reference/rating_diagnostics.md),
[`as_rating_table()`](https://jonpayneea.github.io/reach.rate/reference/as_rating_table.md)

## Examples

``` r
set.seed(1)
stage_m <- seq(0.5, 2.5, by = 0.05)
discharge_cms <- 5 * stage_m^1.6 + rnorm(length(stage_m), sd = 0.02)
fit <- rate_optimise(discharge_cms, stage_m)
rating_limbs(fit)
#>     limb lower_stage_m upper_stage_m        C            a        n
#>    <int>         <num>         <num>    <num>        <num>    <num>
#> 1:     1           0.5           2.5 4.991305 -0.001447794 1.600899
```
