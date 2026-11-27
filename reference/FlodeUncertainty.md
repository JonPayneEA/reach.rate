# A rating's uncertainty, source by source (S7)

What
[`rating_uncertainty()`](https://jonpayneea.github.io/reach.rate/reference/rating_uncertainty.md)
returns.

- `bands`: one row per stage and source, with `stage_m`, `source`
  (`"sampling"`, `"gauging"`, `"combined"` or `"structure"`), `lower`,
  `median` and `upper` for the intervals, `min` and `max` with
  `variant_min` and `variant_max` for structure (a range, never an
  interval), `rating_cms` (the rating itself) and `support`
  (`"observed"` or `"extrapolation"`, beyond the gauged range, not to be
  read as reliable).

- `assessed`: one row per source, whether it was assessed and, if not,
  why.

- `settings`: the draws, the level, the seed, the group column, the `u`
  used for each group and where it came from.

- `draws_failed`: per source, the draws that could not be refitted.

- `variants`: the structural variants tried, and whether each fitted.

None of it is a complete uncertainty budget: stage error is not
modelled.

## Usage

``` r
FlodeUncertainty(
  bands = data.table(),
  assessed = data.table(),
  settings = list(),
  draws_failed = data.table(),
  variants = data.table()
)
```

## Arguments

- bands, assessed, draws_failed, variants:

  Tables, as above.

- settings:

  A list, as above.

## Value

A `FlodeUncertainty`.

## See also

[`rating_uncertainty()`](https://jonpayneea.github.io/reach.rate/reference/rating_uncertainty.md),
[`uncertainty_bands()`](https://jonpayneea.github.io/reach.rate/reference/uncertainty_bands.md)

## Examples

``` r
set.seed(1)
stage_m <- sort(runif(25, 0.3, 3))
fit <- fit_rating(data.frame(stage_m = stage_m,
                             discharge_cms = 3 * stage_m^1.6 * exp(rnorm(25, sd = 0.05))), quiet = TRUE)
u <- rating_uncertainty(fit, n_draws = 100, sources = "sampling", seed = 1)
u@assessed
#>      source assessed reason
#>      <char>   <lgcl> <char>
#> 1: sampling     TRUE   <NA>
```
