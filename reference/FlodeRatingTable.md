# A rating equation table (S7), gap_check's native representation

Wraps the `lower_level`/`upper_level`/`C`/`a`/`n` equation table used
throughout the `gap_check` module. Unlike
[FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md),
this carries its own audit chain directly: `@status` and `@previous` let
[`align_limb_equations()`](https://jonpayneea.github.io/reach.rate/reference/align_limb_equations.md)
return a new object referencing the exact pre-alignment table it was
built from, rather than mutating a table in place and relying on a
column someone has to remember to check.

## Usage

``` r
FlodeRatingTable(
  table = data.table(),
  status = "independently_fitted",
  previous = NULL
)
```

## Arguments

- table:

  Data.table with `lower_level`, `upper_level`, `C`, `a`, `n` columns,
  one row per limb, contiguous. Same names and sign convention as
  [FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md)'s
  `@limbs` (`Q = C(H - a)^n`).

- status:

  Character. One of `"independently_fitted"`, `"post_fit_aligned"`.

- previous:

  The exact pre-amendment FlodeRatingTable this one was built from, or
  `NULL` if it has no such prior identity.

## Examples

``` r
# Two limbs that meet in discharge at stage 1.2
rating_table <- FlodeRatingTable(table = data.table::data.table(
  lower_level = c(0, 1.2), upper_level = c(1.2, 3),
  C = c(2.5, 2.410481), a = 0, n = c(1.5, 1.7)
))
rating_table
#> <FlodeRatingTable> 2 limb(s), status: independently_fitted
#>    lower_level upper_level        C     a     n
#>          <num>       <num>    <num> <num> <num>
#> 1:         0.0         1.2 2.500000     0   1.5
#> 2:         1.2         3.0 2.410481     0   1.7
apply_rating(rating_table, c(0.5, 1.5, 2.5))
#>    stage  discharge extrapolated
#>    <num>      <num>       <lgcl>
#> 1:   0.5  0.8838835        FALSE
#> 2:   1.5  4.8024058        FALSE
#> 3:   2.5 11.4446292        FALSE
rating_history(rating_table)
#>     step            class               status n_limbs
#>    <int>           <char>               <char>   <int>
#> 1:     1 FlodeRatingTable independently_fitted       2

# Limbs must be contiguous, so a gap between them is refused.
try(FlodeRatingTable(table = data.table::data.table(
  lower_level = c(0, 1.5), upper_level = c(1.2, 3), C = 2, a = 0, n = 1.5
)))
#> Error : <reach.rate::FlodeRatingTable> object is invalid:
#> - limbs must be contiguous (upper_level[i] == lower_level[i+1])
```
