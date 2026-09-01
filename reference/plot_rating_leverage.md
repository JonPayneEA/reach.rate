# Plot each gauging's leverage against its influence on the fit

A scatter of Cook's distance against leverage, one facet per limb, point
size scaled by Cook's distance and colour marking gaugings past
[`flag_influential_gaugings()`](https://jonpayneea.github.io/reach.rate/reference/flag_influential_gaugings.md)'s
default cutoffs – the two quantities behind that function's
`influential` flag, plotted directly rather than collapsed to one flag.
See
[`vignette("leverage_influence_guide")`](https://jonpayneea.github.io/reach.rate/articles/leverage_influence_guide.md)
for how to read this plot without the statistics background the terms
usually assume.

## Usage

``` r
plot_rating_leverage(fit, cooks_mult = 4, leverage_mult = 2)
```

## Arguments

- fit:

  A
  [FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md)
  instance.

- cooks_mult, leverage_mult:

  Single positive numbers. A gauging is flagged `influential` if its
  Cook's distance exceeds `cooks_mult / n_obs` (limb-specific `n_obs`)
  or its leverage exceeds `leverage_mult * 3 / n_obs` – the standard
  rule-of-thumb cutoffs (Cook 1977; Belsley, Kuh & Welsch 1980),
  computed per limb since `n_obs` varies by limb. Defaults `4` and `2`
  respectively.

## Value

A `ggplot` object, invisibly.

## See also

[`flag_influential_gaugings()`](https://jonpayneea.github.io/reach.rate/reference/flag_influential_gaugings.md),
[`plot_rating_residuals()`](https://jonpayneea.github.io/reach.rate/reference/plot_rating_residuals.md).
