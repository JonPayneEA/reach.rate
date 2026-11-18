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
  fit_origin = "independently_fitted",
  lifecycle = "draft",
  schema_version = 2L,
  previous = NULL
)
```

## Arguments

- table:

  Data.table with `lower_level`, `upper_level`, `C`, `a`, `n` columns,
  one row per limb, contiguous. Same names and sign convention as
  [FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md)'s
  `@limbs` (`Q = C(H - a)^n`).

- fit_origin:

  Character. How the table came to be, for example
  `"independently_fitted"`, `"post_fit_aligned"`, `"extended_low"` or
  `"grafted"`. Read-only `@status` returns the same value.

- lifecycle:

  Character. `"draft"` (default), `"under_review"`, `"approved"`,
  `"superseded"` or `"withdrawn"`. The package never sets `"approved"`.

- schema_version:

  Integer. The layout version the object was made under; see
  [`rating_schema_version()`](https://jonpayneea.github.io/reach.rate/reference/rating_schema_version.md).
  Leave at the default.

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
#> <FlodeRatingTable> 2 limb(s), origin: independently_fitted, lifecycle: draft
#>   converged: not assessed (no optimiser record for this rating)
#>   valid: yes
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
#>     step            class           fit_origin lifecycle n_limbs   note
#>    <int>           <char>               <char>    <char>   <int> <char>
#> 1:     1 FlodeRatingTable independently_fitted     draft       2   <NA>

# Limbs must be contiguous, so a gap between them is refused.
try(FlodeRatingTable(table = data.table::data.table(
  lower_level = c(0, 1.5), upper_level = c(1.2, 3), C = 2, a = 0, n = 1.5
)))
#> Error : <reach.rate::FlodeRatingTable> object is invalid:
#> - limbs must be contiguous (upper_level[i] == lower_level[i+1])
```
