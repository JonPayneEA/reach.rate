# Fit diagnostics of a rating

How well each limb fits its gaugings and how the fit was found: error
measures, the number of gaugings, multi-start and bootstrap bookkeeping,
and whether an exponent sits on a bound.

## Usage

``` r
rating_diagnostics(x)
```

## Arguments

- x:

  A
  [FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md)
  or
  [FlodeSegmentedRating](https://jonpayneea.github.io/reach.rate/reference/FlodeSegmentedRating.md).
  A
  [FlodeRatingTable](https://jonpayneea.github.io/reach.rate/reference/FlodeRatingTable.md)
  holds equations only and has no fit.

## Value

A data.table, one row per limb for a
[FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md)
and a single row for a
[FlodeSegmentedRating](https://jonpayneea.github.io/reach.rate/reference/FlodeSegmentedRating.md).
For a
[FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md):
`limb`, `rmse_cms` (cumecs), `rmse_pct`, `r_squared`, `n_obs`,
`n_unique_stage`, `mean_error_cms`, `median_abs_error_cms`,
`max_abs_error_cms`, `residual_df`, `n_starts_attempted`,
`n_starts_converged`, `selected_start_id`, `near_bound`,
`n_boot_requested`, `n_boot_success`, `n_boot_failed` and
`boot_success_fraction`; columns the fit did not produce are left out.
For a
[FlodeSegmentedRating](https://jonpayneea.github.io/reach.rate/reference/FlodeSegmentedRating.md):
`n_segments`, `rmse_cms`, `r_squared`, `n_obs` and the multi-start
columns.

## See also

[`rating_coefficients()`](https://jonpayneea.github.io/reach.rate/reference/rating_coefficients.md),
[`rating_support()`](https://jonpayneea.github.io/reach.rate/reference/rating_support.md)

## Examples

``` r
set.seed(1)
stage_m <- seq(0.5, 2.5, by = 0.05)
discharge_cms <- 5 * stage_m^1.6 + rnorm(length(stage_m), sd = 0.02)
fit <- rate_optimise(discharge_cms, stage_m)
rating_diagnostics(fit)
#>     limb   rmse_cms  rmse_pct r_squared n_obs n_unique_stage mean_error_cms
#>    <int>      <num>     <num>     <num> <int>          <int>          <num>
#> 1:     1 0.01726577 0.3547021 0.9999917    41             41  -5.693273e-05
#>    median_abs_error_cms max_abs_error_cms residual_df n_starts_attempted
#>                   <num>             <num>       <int>              <int>
#> 1:            0.0103407        0.04679095          38                  6
#>    n_starts_converged selected_start_id near_bound
#>                 <int>             <int>     <lgcl>
#> 1:                  6                 6      FALSE
```
