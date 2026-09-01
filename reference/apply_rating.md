# Apply a fitted rating to a stage series (S7 generic)

Dispatches on the fit's class:
[FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md)
and
[FlodeSegmentedRating](https://jonpayneea.github.io/reach.rate/reference/FlodeSegmentedRating.md)
each provide their own method. Replaces the previous separate
`apply_rating()`/`apply_segmented_rating()` pair – one name, dispatched
by what you're holding.

## Usage

``` r
apply_rating(fit, ...)
```

## Arguments

- fit:

  A `FlodeRating` or `FlodeSegmentedRating` object.

- ...:

  Passed to the class-specific method – typically `stage_dt` (a
  data.frame or data.table with a stage column) plus
  `stage_col`/`out_col`; see the individual methods' examples.
