# Convert a fit to gap_check's equation-table representation (S7 generic)

Replaces `fitted_rating_to_table()`. Dispatches on the fit's class.

## Usage

``` r
as_rating_table(fit, ...)
```

## Arguments

- fit:

  A `FlodeRating` or `FlodeSegmentedRating` object.

- ...:

  Passed to the class-specific method.

## Value

A
[FlodeRatingTable](https://jonpayneea.github.io/reach.rate/reference/FlodeRatingTable.md).
