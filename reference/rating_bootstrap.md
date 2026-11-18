# Bootstrap draws of a rating

The per-draw coefficients from a fit made with `n_boot > 0`: one row per
draw and limb, with the limb's stage range alongside, in the shape
[`apply_rating_interval()`](https://jonpayneea.github.io/reach.rate/reference/apply_rating_interval.md)
takes. Replaces
[`bootstrap_to_table()`](https://jonpayneea.github.io/reach.rate/reference/bootstrap_to_table.md).

## Usage

``` r
rating_bootstrap(x, successful_only = TRUE)
```

## Arguments

- x:

  A
  [FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md)
  fitted with `rate_optimise(..., n_boot = )`. The other rating classes
  carry no bootstrap.

- successful_only:

  Logical. Drop draws that failed or were rejected (default `TRUE`).
  With `FALSE` every requested draw is returned, with `success` and
  `reason` columns saying what became of it; a failed draw has `NA`
  coefficients.

## Value

A data.table with `limb`, `draw`, `lower_stage_m`, `upper_stage_m`, `C`,
`a` and `n` (plus `success` and `reason` when
`successful_only = FALSE`). Errors, saying how to get one, if the fit
has no bootstrap draws or none succeeded.

## See also

[`apply_rating_interval()`](https://jonpayneea.github.io/reach.rate/reference/apply_rating_interval.md),
[`rating_coefficients()`](https://jonpayneea.github.io/reach.rate/reference/rating_coefficients.md)

## Examples

``` r
set.seed(1)
stage_m <- seq(0.5, 2.5, by = 0.05)
discharge_cms <- 5 * stage_m^1.6 + rnorm(length(stage_m), sd = 0.02)
fit <- rate_optimise(discharge_cms, stage_m, n_boot = 50L, boot_seed = 1L)
head(rating_bootstrap(fit))
#> Key: <limb>
#>     limb  draw lower_stage_m upper_stage_m        C             a        n
#>    <int> <int>         <num>         <num>    <num>         <num>    <num>
#> 1:     1     1           0.5           2.5 5.026513  3.269676e-03 1.596470
#> 2:     1     2           0.5           2.5 5.018405  2.894183e-03 1.598703
#> 3:     1     3           0.5           2.5 4.994507 -1.934379e-05 1.600895
#> 4:     1     4           0.5           2.5 4.987080 -1.924049e-03 1.601480
#> 5:     1     5           0.5           2.5 4.975609 -3.532390e-03 1.602635
#> 6:     1     6           0.5           2.5 4.931092 -8.918307e-03 1.609525
```
