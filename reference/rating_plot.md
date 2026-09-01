# Plot a fitted rating curve (S7 generic)

Dispatches on the fit's class:
[FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md)
and
[FlodeSegmentedRating](https://jonpayneea.github.io/reach.rate/reference/FlodeSegmentedRating.md)
each provide their own method, so the same call works regardless of
which model architecture produced the fit.

## Usage

``` r
rating_plot(fit, ...)
```

## Arguments

- fit:

  A `FlodeRating` or `FlodeSegmentedRating` object.

- ...:

  Passed to the class-specific method.
