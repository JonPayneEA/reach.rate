# Overlay multiple fitted ratings' curves for quick comparison

Plots the curves from any number of fitted ratings on one figure –
discharge on the x-axis, stage on the y-axis, matching every other
plotting function in this toolkit – so you can eyeball how they differ
without reaching for
[`compare_ratings()`](https://jonpayneea.github.io/reach.rate/reference/compare_ratings.md)'s
more detailed (but two-rating-only, table-representation-only) diff.

Accepts
[FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md),
[FlodeSegmentedRating](https://jonpayneea.github.io/reach.rate/reference/FlodeSegmentedRating.md),
and
[FlodeRatingTable](https://jonpayneea.github.io/reach.rate/reference/FlodeRatingTable.md)
instances in any mix: comparing a segmented fit against an
independent-limb fit, or a fitted rating against an imported legacy
table, works the same way as comparing two of the same class.

## Usage

``` r
plot_rating_curves(..., n_points = 200L)
```

## Arguments

- ...:

  Any number of
  [FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md),
  [FlodeSegmentedRating](https://jonpayneea.github.io/reach.rate/reference/FlodeSegmentedRating.md),
  or
  [FlodeRatingTable](https://jonpayneea.github.io/reach.rate/reference/FlodeRatingTable.md)
  instances. Name an argument to use that name as its legend label
  (`plot_rating_curves(Before = fit1, After = fit2)`); unnamed arguments
  are labelled `"Rating 1"`, `"Rating 2"`, and so on in the order
  supplied.

- n_points:

  Integer. Points used to draw each limb/segment of each curve. Default
  `200L`.

## Value

A `ggplot` object, invisibly. Printed as a side effect.

## See also

[`compare_ratings()`](https://jonpayneea.github.io/reach.rate/reference/compare_ratings.md)
and
[`plot_rating_comparison()`](https://jonpayneea.github.io/reach.rate/reference/plot_rating_comparison.md)
for a two-rating comparison that also reports the discharge difference
and requires a table representation for both sides.

## Examples

``` r
set.seed(1)
stage_m <- seq(0.5, 3.5, by = 0.05)
discharge_cms <- 5 * stage_m^1.6 + rnorm(length(stage_m), sd = 0.05)
fit_plain <- rate_optimise(discharge_cms, stage_m, control = c(1.6, 2.5))
fit_constrained <- rate_optimise_constrained(discharge_cms, stage_m, control = c(1.6, 2.5))
plot_rating_curves(Independent = fit_plain, Constrained = fit_constrained)

```
