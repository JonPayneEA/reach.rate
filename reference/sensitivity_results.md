# The full results of a sensitivity analysis

The full results of a sensitivity analysis

## Usage

``` r
sensitivity_results(x)
```

## Arguments

- x:

  A
  [FlodeSensitivity](https://jonpayneea.github.io/reach.rate/reference/FlodeSensitivity.md).

## Value

A data.table, one row per variant and stage: see
[FlodeSensitivity](https://jonpayneea.github.io/reach.rate/reference/FlodeSensitivity.md).

## See also

[`rating_sensitivity()`](https://jonpayneea.github.io/reach.rate/reference/rating_sensitivity.md)

## Examples

``` r
set.seed(1)
stage_m <- seq(0.4, 3, length.out = 16)
fit <- fit_rating(data.frame(stage_m = stage_m,
                             discharge_cms = 3.2 * stage_m^1.6 * exp(rnorm(16, sd = 0.04))), quiet = TRUE)
head(sensitivity_results(rating_sensitivity(fit, tests = "leave_high_out", stages = c(1, 3))))
#>              test                           variant        evidence_ids stage_m
#>            <char>                            <char>              <list>   <num>
#> 1: leave_high_out  without the highest 1 (top 6.2%)                G016       1
#> 2: leave_high_out  without the highest 1 (top 6.2%)                G016       3
#> 3: leave_high_out without the highest 2 (top 12.5%)           G016,G015       1
#> 4: leave_high_out without the highest 2 (top 12.5%)           G016,G015       3
#> 5: leave_high_out without the highest 4 (top 25.0%) G016,G015,G014,G013       1
#> 6: leave_high_out without the highest 4 (top 25.0%) G016,G015,G014,G013       3
#>     base_cms variant_cms   change_cms  change_pct status   note
#>        <num>       <num>        <num>       <num> <char> <char>
#> 1:  3.246849    3.248161  0.001311242  0.04038505     ok   <NA>
#> 2: 18.443127   18.417895 -0.025231950 -0.13680950     ok   <NA>
#> 3:  3.246849    3.263082  0.016232822  0.49995612     ok   <NA>
#> 4: 18.443127   18.078723 -0.364404120 -1.97582614     ok   <NA>
#> 5:  3.246849    3.231009 -0.015839981 -0.48785697     ok   <NA>
#> 6: 18.443127   19.040125  0.596998128  3.23696808     ok   <NA>
```
