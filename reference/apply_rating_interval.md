# Apply a rating with bootstrap uncertainty to a stage series

Like
[`apply_rating()`](https://jonpayneea.github.io/reach.rate/reference/apply_rating.md),
but propagates per-limb bootstrap coefficient draws (from
`rate_optimise(..., n_boot = )`, bridged through
[`bootstrap_to_table()`](https://jonpayneea.github.io/reach.rate/reference/bootstrap_to_table.md))
to a discharge *prediction interval* at each stage, rather than a single
point value. For each stage row, discharge is computed once per
bootstrap draw using that draw's limb assignment and `C`/`a`/`n`, and
the draws are summarised into a mean, median, and geometric standard
error – the same summary Hodson et al. (2024)'s `ratingcurve` package
reports – plus a lower/upper interval at `conf_level`. This is a
bootstrap approximation, not a Bayesian posterior; treat the interval as
indicative of gauging-driven coefficient uncertainty, not a complete
uncertainty budget (it doesn't include stage measurement error, or
uncertainty in the equation form itself).

Limb bounds are assumed fixed across draws (only `C`/`a`/`n` vary),
which matches how `rate_optimise(..., n_boot = )` bootstraps: it
resamples gaugings and refits within each limb's fixed stage range, not
the breakpoints themselves.

## Usage

``` r
apply_rating_interval(
  stage_dt,
  rating_boot_dt,
  stage_col = "stage",
  conf_level = 0.95
)
```

## Arguments

- stage_dt:

  Data.frame or data.table with a stage column.

- rating_boot_dt:

  Data.table of per-draw coefficients, one row per (limb, draw): columns
  `limb`, `draw`, `lower_level`, `upper_level`, `C`, `a`, `n`. See
  [`bootstrap_to_table()`](https://jonpayneea.github.io/reach.rate/reference/bootstrap_to_table.md)
  (in `rating_curve_demo`) for building this from a
  `rate_optimise(..., n_boot = )` fit.

- stage_col:

  Character. Default `"stage"`.

- conf_level:

  Numeric in (0, 1). Width of the prediction interval. Default `0.95`.

## Value

`stage_dt` as a data.table with columns added: `discharge_mean`,
`discharge_median`, `discharge_gse` (geometric standard error),
`discharge_lower`, `discharge_upper`, and `extrapolated`.

## See also

[`apply_rating()`](https://jonpayneea.github.io/reach.rate/reference/apply_rating.md)

## Examples

``` r
rating_boot_dt <- data.table::data.table(
  limb = rep(1L, 20), draw = 1:20,
  lower_level = 0.0, upper_level = 3.0,
  C = rnorm(20, 3, 0.1), a = 0, n = rnorm(20, 1.6, 0.02)
)
stage_dt <- data.table::data.table(stage = c(0.5, 1.5, 2.5))
apply_rating_interval(stage_dt, rating_boot_dt)
#>    stage extrapolated discharge_mean discharge_median discharge_gse
#>    <num>       <lgcl>          <num>            <num>         <num>
#> 1:   0.5        FALSE       0.979211        0.9878797      1.038741
#> 2:   1.5        FALSE       5.681217        5.6838653      1.040993
#> 3:   2.5        FALSE      12.868992       12.8965057      1.045910
#>    discharge_lower discharge_upper
#>              <num>           <num>
#> 1:       0.9201418        1.042176
#> 2:       5.2805646        6.055316
#> 3:      11.8205638       13.848566
```
