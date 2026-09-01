# Graft a freshly-fitted rating onto a pre-existing one above its gauged range

Real stations are sometimes only re-gauged, and re-fitted, up to some
stage – extreme floods above that stay described by whatever rating was
already in force there. `graft_rating()` joins the two: it finds the
stage where `new_rating`'s top limb and `existing_rating`'s lowest
still-relevant limb actually cross (the same crossing search
[`align_limb_boundaries()`](https://jonpayneea.github.io/reach.rate/reference/align_limb_boundaries.md)
uses for a junction inside one table, here used to join two different
ones), trims/extends both limbs to that stage, and returns one
contiguous table.

This is deliberately different from
[`align_limb_equations()`](https://jonpayneea.github.io/reach.rate/reference/align_limb_equations.md)/
[`align_limb_boundaries()`](https://jonpayneea.github.io/reach.rate/reference/align_limb_boundaries.md),
which reconcile a junction *within* one already-built table.
`graft_rating()` combines two independently sourced ratings – one just
fitted, one pre-existing – into a new one.

The result is always a
[FlodeRatingTable](https://jonpayneea.github.io/reach.rate/reference/FlodeRatingTable.md),
even when `new_rating` was a
[FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md):
the grafted-on limbs come from `existing_rating`, which carries no
gaugings of its own, so a `FlodeRating` result would be honest about
some limbs and silently false about others. `new_rating` itself,
ungrafted, remains the right object for diagnostics on the newly-fitted
part.

## Usage

``` r
graft_rating(
  new_rating,
  existing_rating,
  search_range = NULL,
  on_no_crossing = c("error", "join_at_top")
)
```

## Arguments

- new_rating:

  A
  [FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md)
  or
  [FlodeRatingTable](https://jonpayneea.github.io/reach.rate/reference/FlodeRatingTable.md)
  – the freshly fitted rating, trusted only up to its own top boundary.

- existing_rating:

  A
  [FlodeRatingTable](https://jonpayneea.github.io/reach.rate/reference/FlodeRatingTable.md),
  or a plain data.frame/data.table with columns `lower_level`,
  `upper_level`, `C`, `a`, `n` (same shape as
  [`expand_rating_table()`](https://jonpayneea.github.io/reach.rate/reference/expand_rating_table.md)'s
  input). Only limbs whose `upper_level` exceeds `new_rating`'s top
  boundary are used; it is an error if none qualify.

- search_range:

  `NULL` (default), or a numeric `c(lower, upper)` bracket to search for
  the crossing stage, overriding the default
  `c(new_rating's top boundary, first retained existing limb's upper_level)`.

- on_no_crossing:

  Character. What to do when no crossing exists within `search_range`.
  `"error"` (default) stops. `"join_at_top"` joins exactly at
  `new_rating`'s top boundary instead, accepting whatever discontinuity
  results there, with a warning naming the resulting jump in discharge.

## Value

A
[FlodeRatingTable](https://jonpayneea.github.io/reach.rate/reference/FlodeRatingTable.md)
with `@status` `"grafted"`, `@previous` referencing `new_rating` exactly
as passed in, and `@table` gaining a `source` column
(`"new"`/`"existing"`) marking which side each limb came from.

## See also

[`align_limb_boundaries()`](https://jonpayneea.github.io/reach.rate/reference/align_limb_boundaries.md),
whose crossing search this function reuses, for reconciling a junction
within one table rather than joining two different ones.

## Examples

``` r
new_table <- data.table::data.table(
  lower_level = c(0.0, 1.5), upper_level = c(1.5, 3.41),
  C = c(2.5, 2.831), a = c(0.0, -0.886), n = c(1.50, 1.935)
)
existing_table <- data.table::data.table(
  lower_level = 3.41, upper_level = 6.0,
  C = 0.3128, a = 0, n = 4.095
)
grafted <- graft_rating(new_table, existing_table)
grafted@table[, .(lower_level, upper_level, C, a, n, source)]
#>    lower_level upper_level      C      a     n   source
#>          <num>       <num>  <num>  <num> <num>   <char>
#> 1:    0.000000    1.500000 2.5000  0.000 1.500      new
#> 2:    1.500000    3.410072 2.8310 -0.886 1.935      new
#> 3:    3.410072    6.000000 0.3128  0.000 4.095 existing
```
