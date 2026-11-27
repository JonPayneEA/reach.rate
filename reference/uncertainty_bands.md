# The bands of a rating's uncertainty

The bands of a rating's uncertainty

## Usage

``` r
uncertainty_bands(x)
```

## Arguments

- x:

  A
  [FlodeUncertainty](https://jonpayneea.github.io/reach.rate/reference/FlodeUncertainty.md).

## Value

A data.table, one row per stage and source: see
[FlodeUncertainty](https://jonpayneea.github.io/reach.rate/reference/FlodeUncertainty.md).

## See also

[`rating_uncertainty()`](https://jonpayneea.github.io/reach.rate/reference/rating_uncertainty.md)

## Examples

``` r
set.seed(1)
stage_m <- sort(runif(25, 0.3, 3))
fit <- fit_rating(data.frame(stage_m = stage_m,
                             discharge_cms = 3 * stage_m^1.6 * exp(rnorm(25, sd = 0.05))), quiet = TRUE)
head(uncertainty_bands(rating_uncertainty(fit, n_draws = 100, sources = "sampling", seed = 1)))
#>      stage_m   source     lower    median     upper   min   max variant_min
#>        <num>   <char>     <num>     <num>     <num> <num> <num>      <char>
#> 1: 0.4668229 sampling 0.7936890 0.8721211 0.9518481    NA    NA        <NA>
#> 2: 0.5180744 sampling 0.9587895 1.0308260 1.1019940    NA    NA        <NA>
#> 3: 0.5693259 sampling 1.1344226 1.1979083 1.2592477    NA    NA        <NA>
#> 4: 0.6205774 sampling 1.3200598 1.3756470 1.4245560    NA    NA        <NA>
#> 5: 0.6718289 sampling 1.5152478 1.5612537 1.5987846    NA    NA        <NA>
#> 6: 0.7230804 sampling 1.7195927 1.7584162 1.7889645    NA    NA        <NA>
#>    variant_max rating_cms  support
#>         <char>      <num>   <char>
#> 1:        <NA>  0.8716025 observed
#> 2:        <NA>  1.0308769 observed
#> 3:        <NA>  1.2001219 observed
#> 4:        <NA>  1.3789810 observed
#> 5:        <NA>  1.5671396 observed
#> 6:        <NA>  1.7643174 observed
```
