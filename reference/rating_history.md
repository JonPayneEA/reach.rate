# The audit chain of a rating

Where a rating came from. A fit or table that was produced by amending
an earlier one (for example by
[`align_limb_equations()`](https://jonpayneea.github.io/reach.rate/reference/align_limb_equations.md)
or
[`graft_rating()`](https://jonpayneea.github.io/reach.rate/reference/graft_rating.md))
keeps the exact earlier object, and that one may keep another. This
lists the whole chain, oldest first, so the steps between a first fit
and the rating in use can be read off.

## Usage

``` r
rating_history(x)
```

## Arguments

- x:

  A
  [FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md),
  [FlodeSegmentedRating](https://jonpayneea.github.io/reach.rate/reference/FlodeSegmentedRating.md)
  or
  [FlodeRatingTable](https://jonpayneea.github.io/reach.rate/reference/FlodeRatingTable.md).

## Value

A data.table with one row per step, oldest first: `step` (1 is the
earliest), `class`, `status` and `n_limbs` (the number of segments for a
[FlodeSegmentedRating](https://jonpayneea.github.io/reach.rate/reference/FlodeSegmentedRating.md)).
The last row is `x` itself. A rating with no earlier version has one
row.

## See also

[`rating_provenance()`](https://jonpayneea.github.io/reach.rate/reference/rating_provenance.md)

## Examples

``` r
table <- FlodeRatingTable(table = data.table::data.table(
  lower_level = c(0, 1), upper_level = c(1, 3), C = c(2, 2.5), a = 0, n = 1.5
))
aligned <- align_limb_equations(table)
rating_history(aligned)
#>     step            class           fit_origin lifecycle n_limbs
#>    <int>           <char>               <char>    <char>   <int>
#> 1:     1 FlodeRatingTable independently_fitted     draft       2
#> 2:     2 FlodeRatingTable     post_fit_aligned     draft       2
```
