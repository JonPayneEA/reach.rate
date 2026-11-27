# Convert a fit to gap_check's equation-table representation (S7 generic)

Turns a fitted
[FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md)
into the equation table (`lower_level`, `upper_level`, `C`, `a`, `n`,
one row per limb) that
[`expand_rating_table()`](https://jonpayneea.github.io/reach.rate/reference/expand_rating_table.md),
the gap-checking functions,
[`compare_ratings()`](https://jonpayneea.github.io/reach.rate/reference/compare_ratings.md)
and
[`apply_rating_inverse()`](https://jonpayneea.github.io/reach.rate/reference/apply_rating_inverse.md)
work with. Replaces `fitted_rating_to_table()`.

There is a method for
[FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md)
only. A
[FlodeSegmentedRating](https://jonpayneea.github.io/reach.rate/reference/FlodeSegmentedRating.md)
is one joint model with no independent limbs, so it has no table form; a
[FlodeRatingTable](https://jonpayneea.github.io/reach.rate/reference/FlodeRatingTable.md)
is already one.

## Usage

``` r
as_rating_table(fit, ...)
```

## Arguments

- fit:

  A
  [FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md).

- ...:

  Passed to the class-specific method; none are used.

## Value

A
[FlodeRatingTable](https://jonpayneea.github.io/reach.rate/reference/FlodeRatingTable.md)
with status `"independently_fitted"` and no previous version, ready for
[`expand_rating_table()`](https://jonpayneea.github.io/reach.rate/reference/expand_rating_table.md).
A `doubtful` column, if
[`flag_extrapolated_limbs()`](https://jonpayneea.github.io/reach.rate/reference/flag_extrapolated_limbs.md)
has added one, is kept.

## See also

[`rating_limbs()`](https://jonpayneea.github.io/reach.rate/reference/rating_limbs.md)
for the same equations as a plain table without the class.

## Examples

``` r
set.seed(1)
stage_m <- seq(0.5, 2.5, by = 0.05)
discharge_cms <- 5 * stage_m^1.6 + rnorm(length(stage_m), sd = 0.02)
fit <- rate_optimise(discharge_cms, stage_m)

rating_table <- as_rating_table(fit)
rating_table
#> <FlodeRatingTable> 1 limb(s), origin: independently_fitted, lifecycle: draft
#>   converged: not assessed (no optimiser record for this rating)
#>   valid: yes
#>    lower_level upper_level        C           a        n
#>          <num>       <num>    <num>       <num>    <num>
#> 1:         0.5         2.5 4.991305 -0.00144775 1.600899
apply_rating(rating_table, c(0.8, 1.6, 2.4))
#>    stage discharge extrapolated         support
#>    <num>     <num>       <lgcl>          <char>
#> 1:   0.8  3.502096        FALSE model_supported
#> 2:   1.6 10.607630        FALSE model_supported
#> 3:   2.4 20.291449        FALSE model_supported
```
