# Convert a rating's offset between the two sign conventions

This package writes a rating limb as \\Q = C (H - a)^n\\, so `a` is the
stage at which flow ceases. Some systems write \\Q = C (H + a)^n\\, in
which the same offset has the opposite sign. Using one system's `a` in
the other's equation shifts the whole curve, by twice the offset, with
nothing to say that it has happened.

`convert_offset_convention()` changes the sign of `a` and nothing else:
\\C\\, \\n\\ and the stage limits are untouched, because \\C (H + a')^n
= C (H - a)^n\\ exactly when \\a' = -a\\. Converting there and back
returns the original values.

It does not change a stage datum. If an external system measures stage
from a different zero (a gauge board against metres above ordnance
datum, say), the limits and `a` need shifting by that datum as well, and
that is not done here.

A rating object always uses the package's convention and is not changed.
Pass one to read its limbs in the other convention.

## Usage

``` r
convert_offset_convention(
  x,
  from = c("add", "subtract"),
  to = c("subtract", "add")
)
```

## Arguments

- x:

  A `data.frame` or `data.table` with a column `a`, or a
  [FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md)
  or
  [FlodeRatingTable](https://jonpayneea.github.io/reach.rate/reference/FlodeRatingTable.md),
  whose limbs are read with
  [`rating_limbs()`](https://jonpayneea.github.io/reach.rate/reference/rating_limbs.md).

- from, to:

  The convention of `x`, and the one wanted: `"subtract"` for \\Q = C
  (H - a)^n\\ (this package) or `"add"` for \\Q = C (H + a)^n\\. The
  defaults convert an external `H + a` table into this package's
  convention.

## Value

A data.table, a copy of `x` (or of its limbs) with `a` in the `to`
convention. The same table comes back unchanged when `from` and `to` are
the same.

## See also

[`rating_limbs()`](https://jonpayneea.github.io/reach.rate/reference/rating_limbs.md),
[`vignette("mathematical_contract")`](https://jonpayneea.github.io/reach.rate/articles/mathematical_contract.md)

## Examples

``` r
# A limb from a system that writes Q = C (H + a)^n, with a = -0.35.
external <- data.frame(
  lower_level = 0.5, upper_level = 3, C = 4.1, a = -0.35, n = 1.6
)
internal <- convert_offset_convention(external)
internal$a
#> [1] 0.35

# Both describe one curve: the same stage gives the same discharge.
stage <- 1.8
external$C * (stage + external$a)^external$n
#> [1] 7.429724
internal$C * (stage - internal$a)^internal$n
#> [1] 7.429724

# Converting back recovers the original.
convert_offset_convention(internal, from = "subtract", to = "add")$a
#> [1] -0.35
```
