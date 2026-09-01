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
