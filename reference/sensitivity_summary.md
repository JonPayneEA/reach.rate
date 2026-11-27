# The per-variant summary of a sensitivity analysis

The per-variant summary of a sensitivity analysis

## Usage

``` r
sensitivity_summary(x)
```

## Arguments

- x:

  A
  [FlodeSensitivity](https://jonpayneea.github.io/reach.rate/reference/FlodeSensitivity.md).

## Value

A data.table, one row per variant: see
[FlodeSensitivity](https://jonpayneea.github.io/reach.rate/reference/FlodeSensitivity.md).

## See also

[`rating_sensitivity()`](https://jonpayneea.github.io/reach.rate/reference/rating_sensitivity.md)

## Examples

``` r
set.seed(1)
stage_m <- seq(0.4, 3, length.out = 16)
fit <- fit_rating(data.frame(stage_m = stage_m,
                             discharge_cms = 3.2 * stage_m^1.6 * exp(rnorm(16, sd = 0.04))), quiet = TRUE)
sensitivity_summary(rating_sensitivity(fit, tests = "leave_high_out", stages = c(1, 3)))
#>              test                           variant        evidence_ids status
#>            <char>                            <char>              <list> <char>
#> 1: leave_high_out  without the highest 1 (top 6.2%)                G016     ok
#> 2: leave_high_out without the highest 2 (top 12.5%)           G016,G015     ok
#> 3: leave_high_out without the highest 4 (top 25.0%) G016,G015,G014,G013     ok
#>    max_abs_change_cms max_abs_change_pct stage_at_max_m leverage cooks_distance
#>                 <num>              <num>          <num>    <num>          <num>
#> 1:         0.02523195          0.1368095              3       NA             NA
#> 2:         0.36440412          1.9758261              3       NA             NA
#> 3:         0.59699813          3.2369681              3       NA             NA
#>      note
#>    <char>
#> 1:   <NA>
#> 2:   <NA>
#> 3:   <NA>
```
