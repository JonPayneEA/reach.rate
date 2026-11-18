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

## Examples

``` r
set.seed(42)
stage_m <- seq(0.3, 3.2, by = 0.06)
discharge_cms <- ifelse(stage_m < 1.5, 3.2 * stage_m^1.6,
                        3.2 * 1.5^1.6 * (stage_m / 1.5)^2.1) *
  exp(rnorm(length(stage_m), sd = 0.04))
# One gauging recorded 70 per cent too high
discharge_cms[40] <- discharge_cms[40] * 1.7
fit <- rate_optimise(discharge_cms, stage_m, control = 1.5)

# Gaugings in the top-right of a facet combine high leverage with high
# influence on the fit
plot_rating_leverage(fit)


# The same gaugings as a table
flagged <- flag_influential_gaugings(fit)
rating_evidence(flagged)[influential == TRUE, c("stage_m", "discharge_cms", "cooks_distance")]
#>    stage_m discharge_cms cooks_distance
#>      <num>         <num>          <num>
#> 1:    0.30     0.4924475   9.774673e-04
#> 2:    1.32     4.4866368   2.256700e-01
#> 3:    1.38     4.8591607   2.990657e-01
#> 4:    1.44     6.0459240   7.298657e-01
#> 5:    1.50     6.0474061   7.121216e-02
#> 6:    1.56     6.1904399   6.197914e-05
#> 7:    2.64    34.1624517   5.858075e-01
#> 8:    3.18    29.1545480   8.555783e-03
```
