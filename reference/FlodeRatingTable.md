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
  table = (structure(function (.data) 

    stop2(sprintf("S3 class <%s> doesn't have a constructor.", "data.table"), call =
    NULL), class = "S7_constructor"))(),
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
