# Plot a rating comparison: curves and their discharge difference

Two-panel figure for a
[`compare_ratings()`](https://jonpayneea.github.io/reach.rate/reference/compare_ratings.md)
result. The top panel overlays the old and new rating curves (dashed vs
solid, the same convention
[`plot_rc_gaps()`](https://jonpayneea.github.io/reach.rate/reference/plot_rc_gaps.md)
uses for before/after), so the shape of the change is visible directly.
The bottom panel plots the discharge difference against stage, so it's
clear not just *that* an amendment changed the rating but *where in the
stage range* it actually matters – a coefficient change that only bites
at high flows looks very different from one that shifts the whole curve
evenly.

## Usage

``` r
plot_rating_comparison(cmp, old_label = "Old", new_label = "New")
```

## Arguments

- cmp:

  The list returned by
  [`compare_ratings()`](https://jonpayneea.github.io/reach.rate/reference/compare_ratings.md).

- old_label, new_label:

  Character. Legend labels for the two ratings. Defaults `"Old"` and
  `"New"`.

## Value

The combined grob from
[`gridExtra::grid.arrange()`](https://rdrr.io/pkg/gridExtra/man/arrangeGrob.html),
invisibly. Printed as a side effect.

## See also

[`compare_ratings()`](https://jonpayneea.github.io/reach.rate/reference/compare_ratings.md)

## Examples

``` r
rating_old_dt <- data.table::data.table(
  lower_level = c(0.0, 1.2), upper_level = c(1.2, 3.0),
  C = c(2.5, 4.1), a = c(0, 0), n = c(1.5, 1.7)
)
rating_new_dt <- data.table::data.table(
  lower_level = c(0.0, 1.2), upper_level = c(1.2, 3.0),
  C = c(2.6, 4.0), a = c(0, 0), n = c(1.5, 1.7)
)
cmp <- compare_ratings(rating_old_dt, rating_new_dt)
plot_rating_comparison(cmp)

```
