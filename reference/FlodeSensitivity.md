# The outcome of a sensitivity analysis (S7)

What
[`rating_sensitivity()`](https://jonpayneea.github.io/reach.rate/reference/rating_sensitivity.md)
returns. It holds two tables:

- `results`: one row per variant and stage, with `test`, `variant` (what
  was changed, in words), `evidence_ids` (a list column: the gaugings
  left out, empty for a test that leaves none out), `stage_m`,
  `base_cms` and `variant_cms` (discharge before and after),
  `change_cms`, `change_pct`, `status` and `note`;

- `summary`: one row per variant, with the largest change in discharge
  and the stage it occurs at, and, for `leave_one_out`, the gauging's
  leverage and Cook's distance on the scale the fit minimised.

`status` is `"ok"`, `"not_converged"` (the variant's own refit did not
converge) or `"refit_failed"` (it could not be made, with the reason in
`note`).

## Usage

``` r
FlodeSensitivity(
  results = data.table(),
  summary = data.table(),
  stages = numeric(0),
  tests = character(0)
)
```

## Arguments

- results, summary:

  The two tables above.

- stages:

  The stages the comparison was made at.

- tests:

  The tests that were run.

## Value

A `FlodeSensitivity`.

## See also

[`rating_sensitivity()`](https://jonpayneea.github.io/reach.rate/reference/rating_sensitivity.md),
[`sensitivity_summary()`](https://jonpayneea.github.io/reach.rate/reference/sensitivity_summary.md),
[`sensitivity_results()`](https://jonpayneea.github.io/reach.rate/reference/sensitivity_results.md)

## Examples

``` r
set.seed(1)
stage_m <- seq(0.4, 3, length.out = 16)
fit <- fit_rating(data.frame(stage_m = stage_m,
                             discharge_cms = 3.2 * stage_m^1.6 * exp(rnorm(16, sd = 0.04))), quiet = TRUE)
sens <- rating_sensitivity(fit, tests = "leave_high_out", stages = c(1, 2, 3))
class(sens)
#> [1] "reach.rate::FlodeSensitivity" "S7_object"                   
sensitivity_summary(sens)
#>              test                           variant        evidence_ids status
#>            <char>                            <char>              <list> <char>
#> 1: leave_high_out  without the highest 1 (top 6.2%)                G016     ok
#> 2: leave_high_out without the highest 2 (top 12.5%)           G016,G015     ok
#> 3: leave_high_out without the highest 4 (top 25.0%) G016,G015,G014,G013     ok
#>    max_abs_change_cms max_abs_change_pct stage_at_max_m leverage cooks_distance
#>                 <num>              <num>          <num>    <num>          <num>
#> 1:         0.02523206          0.1368101              3       NA             NA
#> 2:         0.36440423          1.9758267              3       NA             NA
#> 3:         0.59699802          3.2369675              3       NA             NA
#>      note
#>    <char>
#> 1:   <NA>
#> 2:   <NA>
#> 3:   <NA>
```
