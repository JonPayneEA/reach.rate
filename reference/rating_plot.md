# Plot a fitted rating curve (S7 generic)

Draws a rating with discharge on the horizontal axis and stage on the
vertical. Dispatches on the class of `fit`, so the same call works
whichever model produced the rating:

- [FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md):
  the gauged points with each limb's fitted curve drawn over them, one
  colour per limb, in base graphics.

- [FlodeSegmentedRating](https://jonpayneea.github.io/reach.rate/reference/FlodeSegmentedRating.md):
  the gauged points and the single joint curve, with dashed horizontal
  lines where each segment's factor turns on (`bp1` to `bpk`), as a
  ggplot2 figure.

- [FlodeRatingTable](https://jonpayneea.github.io/reach.rate/reference/FlodeRatingTable.md):
  each limb's curve in its own colour, so a kink or overlap at a
  junction can be seen, as a ggplot2 figure. A table holds no gaugings,
  so there are no points.

## Usage

``` r
rating_plot(fit, ...)
```

## Arguments

- fit:

  A
  [FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md),
  [FlodeSegmentedRating](https://jonpayneea.github.io/reach.rate/reference/FlodeSegmentedRating.md)
  or
  [FlodeRatingTable](https://jonpayneea.github.io/reach.rate/reference/FlodeRatingTable.md).

- ...:

  Options for the class-specific method:

  - `colours`
    ([FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md)
    only): plotting colours, one per limb, or `NULL` (default) for a
    single colour. A vector of the wrong length is ignored with a
    warning.

  - `n_points`: how many points are used to draw each limb's curve (the
    whole curve, for a segmented rating). Defaults to `200L`, or `300L`
    for a
    [FlodeSegmentedRating](https://jonpayneea.github.io/reach.rate/reference/FlodeSegmentedRating.md).

## Value

`NULL`, invisibly, for a
[FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md),
which draws in base graphics. For a
[FlodeSegmentedRating](https://jonpayneea.github.io/reach.rate/reference/FlodeSegmentedRating.md)
or a
[FlodeRatingTable](https://jonpayneea.github.io/reach.rate/reference/FlodeRatingTable.md),
the ggplot2 figure, invisibly, as well as drawing it.

## See also

[`plot_rating_residuals()`](https://jonpayneea.github.io/reach.rate/reference/plot_rating_residuals.md)
for how well each limb fits,
[`plot_rating_curves()`](https://jonpayneea.github.io/reach.rate/reference/plot_rating_curves.md)
to overlay several ratings, and
[`plot_rc_gaps()`](https://jonpayneea.github.io/reach.rate/reference/plot_rc_gaps.md)
for a before and after view of a closed junction.

## Examples

``` r
set.seed(42)
stage_m <- seq(0.3, 3.2, by = 0.06)
discharge_cms <- ifelse(stage_m < 1.5, 3.2 * stage_m^1.6,
                        3.2 * 1.5^1.6 * (stage_m / 1.5)^2.1) *
  exp(rnorm(length(stage_m), sd = 0.04))

# Two independent limbs: points, with each limb's curve over them
fit <- rate_optimise(discharge_cms, stage_m, control = 1.5)
rating_plot(fit)


# The same rating as an equation table: just the curves, one colour per limb
rating_plot(as_rating_table(fit))


# A joint segmented fit
fit_seg <- rate_optimise_segmented(discharge_cms, stage_m, control = 1.5)
rating_plot(fit_seg)

```
