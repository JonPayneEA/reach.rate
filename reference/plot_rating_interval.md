# Plot a fitted rating curve with a bootstrap prediction interval

Like
[`rating_plot()`](https://jonpayneea.github.io/reach.rate/reference/rating_plot.md),
but for a fit produced with `rate_optimise(..., n_boot = )`: draws the
mean discharge curve with a shaded prediction-interval band (from
[`apply_rating_interval()`](https://jonpayneea.github.io/reach.rate/reference/apply_rating_interval.md))
instead of a single point-estimate line, and overlays the gauged points.
This is the plot Hodson et al. (2024)'s Figure 1 shows for their
Bayesian fits; the band here is the bootstrap approximation to the same
idea, not a Bayesian posterior.

## Usage

``` r
plot_rating_interval(fit, conf_level = 0.95, n_points = 150L)
```

## Arguments

- fit:

  A
  [FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md)
  instance from `rate_optimise(..., n_boot > 0)`.

- conf_level:

  Numeric in (0, 1). Width of the shaded interval. Default `0.95`.

- n_points:

  Integer. Stage points per limb used to draw the band. Default `150L`.

## Value

A `ggplot` object, invisibly. Printed as a side effect.

## See also

[`rate_optimise()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise.md),
[`bootstrap_to_table()`](https://jonpayneea.github.io/reach.rate/reference/bootstrap_to_table.md),
[`apply_rating_interval()`](https://jonpayneea.github.io/reach.rate/reference/apply_rating_interval.md)
(in the `apply_rating` module)

## Examples

``` r
set.seed(1)
stage_m <- seq(0.5, 3.5, by = 0.1)
discharge_cms <- 5 * stage_m^1.6 + rnorm(length(stage_m), sd = 0.05)
fit <- rate_optimise(discharge_cms, stage_m, n_boot = 200L, boot_seed = 1L)
plot_rating_interval(fit)

```
