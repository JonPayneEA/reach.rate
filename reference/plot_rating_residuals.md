# Plot rating fit residuals by limb

Residual (observed minus fitted discharge) against stage, one facet per
limb. Not an S7 generic method –
[FlodeSegmentedRating](https://jonpayneea.github.io/reach.rate/reference/FlodeSegmentedRating.md)
has no equivalent yet – so this takes a plain
[`inherits()`](https://rdrr.io/r/base/class.html) check.

## Usage

``` r
plot_rating_residuals(fit)
```

## Arguments

- fit:

  A
  [FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md)
  instance.

## Value

A `ggplot` object, invisibly.

## See also

[`rating_plot()`](https://jonpayneea.github.io/reach.rate/reference/rating_plot.md)
for the curve against the gaugings,
[`plot_rating_leverage()`](https://jonpayneea.github.io/reach.rate/reference/plot_rating_leverage.md)
for which gaugings steer the fit.

## Examples

``` r
set.seed(42)
stage_m <- seq(0.3, 3.2, by = 0.06)
discharge_cms <- ifelse(stage_m < 1.5, 3.2 * stage_m^1.6,
                        3.2 * 1.5^1.6 * (stage_m / 1.5)^2.1) *
  exp(rnorm(length(stage_m), sd = 0.04))
fit <- rate_optimise(discharge_cms, stage_m, control = 1.5)

# Residuals scatter around zero when a limb fits well; a curve or a fan
# in one facet says that limb's equation is wrong or its spread grows
# with flow.
plot_rating_residuals(fit)

```
