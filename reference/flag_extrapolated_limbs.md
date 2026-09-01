# Flag rating limbs that extrapolate substantially beyond their gaugings

Assesses support within each limb's own declared bounds (unsupported
distance at an internal breakpoint) and, separately, whether the whole
fitted rating's combined span fails to reach an operational range if
supplied, else the complete gauged range.

## Usage

``` r
flag_extrapolated_limbs(
  fit,
  tol_frac = 0.05,
  operational_lower_m = NULL,
  operational_upper_m = NULL
)
```

## Arguments

- fit:

  A
  [FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md)
  instance.

- tol_frac:

  Numeric. Fraction of a limb's stage width the unsupported gap may
  reach before being flagged. Default `0.05`.

- operational_lower_m, operational_upper_m:

  Numeric or `NULL`.

## Value

A new
[FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md)
instance with `@limbs` columns added:
`gauged_min_stage_m`/`gauged_max_stage_m`, `lower_unsupported_m`/
`upper_unsupported_m`, `lower_unsupported_frac`/
`upper_unsupported_frac`, `extrapolates_below_range`/
`extrapolates_above_range` (identical on every row – a whole-fit
property, not per-limb), and `doubtful`.
