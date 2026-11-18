# Coefficients of a rating, with their uncertainty

Every fitted parameter on its own row, in long form, with whatever
uncertainty the fit carries: the asymptotic standard error from the
least-squares fit, and the bootstrap standard error and quantiles when
the fit was made with `n_boot > 0`. Uncertainty that was not computed is
`NA`, never zero.

## Usage

``` r
rating_coefficients(x)
```

## Arguments

- x:

  A
  [FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md),
  [FlodeSegmentedRating](https://jonpayneea.github.io/reach.rate/reference/FlodeSegmentedRating.md)
  or
  [FlodeRatingTable](https://jonpayneea.github.io/reach.rate/reference/FlodeRatingTable.md).

## Value

A data.table with columns `limb` (integer; `NA` for a
[FlodeSegmentedRating](https://jonpayneea.github.io/reach.rate/reference/FlodeSegmentedRating.md),
whose parameters belong to the joint model), `parameter`, `estimate`,
`unit`, `se_asymptotic`, `se_bootstrap`, `q025`, `q50` and `q975` (the
bootstrap 2.5, 50 and 97.5 per cent quantiles). Parameters are `C`, `a`
and `n` for each limb of a
[FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md)
or
[FlodeRatingTable](https://jonpayneea.github.io/reach.rate/reference/FlodeRatingTable.md),
and `C`, then `bp1`, `n1`, `bp2`, `n2` and so on for a
[FlodeSegmentedRating](https://jonpayneea.github.io/reach.rate/reference/FlodeSegmentedRating.md).
Units: `C` is cumecs per metre to the power `n`, `a` and the breakpoints
are stage in metres, `n` has no unit (`"1"`).

## See also

[`rating_limbs()`](https://jonpayneea.github.io/reach.rate/reference/rating_limbs.md),
[`rating_diagnostics()`](https://jonpayneea.github.io/reach.rate/reference/rating_diagnostics.md),
[`rating_bootstrap()`](https://jonpayneea.github.io/reach.rate/reference/rating_bootstrap.md)

## Examples

``` r
set.seed(1)
stage_m <- seq(0.5, 2.5, by = 0.05)
discharge_cms <- 5 * stage_m^1.6 + rnorm(length(stage_m), sd = 0.02)
fit <- rate_optimise(discharge_cms, stage_m, n_boot = 50L, boot_seed = 1L)
rating_coefficients(fit)
#>     limb parameter    estimate        unit se_asymptotic se_bootstrap
#>    <int>    <char>       <num>      <char>         <num>        <num>
#> 1:     1         C  4.99130515 cms per m^n   0.033147599  0.029634924
#> 2:     1         a -0.00144775           m   0.004272234  0.003844260
#> 3:     1         n  1.60089865           1   0.004548600  0.004024928
#>            q025          q50        q975
#>           <num>        <num>       <num>
#> 1:  4.932304029  4.987083468 5.031973553
#> 2: -0.008904218 -0.001792158 0.004936103
#> 3:  1.596019204  1.601228358 1.609215851
```
