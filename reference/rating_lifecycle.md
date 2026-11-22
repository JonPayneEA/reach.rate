# The record of lifecycle changes for a rating

Who changed a rating's lifecycle, from what to what, when and why,
oldest first. A rating that has never been moved on from `"draft"` has
no records.

Only changes made with
[`set_lifecycle()`](https://jonpayneea.github.io/reach.rate/reference/set_lifecycle.md)
are here. A rating that was amended after it was reviewed (its limits
set, its limbs aligned) is back to `draft` without a record, since no
person said so: see
[`rating_history()`](https://jonpayneea.github.io/reach.rate/reference/rating_history.md),
where its lifecycle column shows the step.

## Usage

``` r
rating_lifecycle(x)
```

## Arguments

- x:

  A
  [FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md),
  [FlodeSegmentedRating](https://jonpayneea.github.io/reach.rate/reference/FlodeSegmentedRating.md)
  or
  [FlodeRatingTable](https://jonpayneea.github.io/reach.rate/reference/FlodeRatingTable.md).
  A table has no record to keep, so it always returns an empty one.

## Value

A `data.table` with `from`, `to`, `by`, `reason` and `at` (UTC).

## See also

[`set_lifecycle()`](https://jonpayneea.github.io/reach.rate/reference/set_lifecycle.md),
[`rating_history()`](https://jonpayneea.github.io/reach.rate/reference/rating_history.md).

## Examples

``` r
set.seed(1)
stage <- seq(0.3, 3, length.out = 25)
gaugings <- data.frame(stage_m = stage,
                       discharge_cms = 3 * stage^1.6 * exp(rnorm(25, sd = 0.03)))
fit <- fit_rating(gaugings, quiet = TRUE)
rating_lifecycle(fit)
#> Empty data.table (0 rows and 5 cols): from,to,by,reason,at
```
