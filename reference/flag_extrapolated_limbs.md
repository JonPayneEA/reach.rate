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

## See also

[`rating_support()`](https://jonpayneea.github.io/reach.rate/reference/rating_support.md)
for the same unsupported extents without a tolerance applied.

## Examples

``` r
set.seed(42)
stage_m <- seq(0.3, 3.2, by = 0.06)
discharge_cms <- ifelse(stage_m < 1.5, 3.2 * stage_m^1.6,
                        3.2 * 1.5^1.6 * (stage_m / 1.5)^2.1) *
  exp(rnorm(length(stage_m), sd = 0.04))

# No gaugings between 1.2 and 1.8 m, where the limbs meet
keep <- !(stage_m > 1.2 & stage_m < 1.8)
fit <- rate_optimise(discharge_cms[keep], stage_m[keep], control = 1.5)

# Each limb stretches well beyond its nearest gauging at the junction,
# and the operational range (to 4 m) is above the highest gauging
flagged <- flag_extrapolated_limbs(fit, operational_upper_m = 4)
rating_limbs(flagged, all_columns = TRUE)[,
  c("limb", "lower_unsupported_frac", "upper_unsupported_frac",
    "extrapolates_above_range", "doubtful")]
#>     limb lower_unsupported_frac upper_unsupported_frac extrapolates_above_range
#>    <int>                  <num>                  <num>                   <lgcl>
#> 1:     1              0.0000000                   0.25                     TRUE
#> 2:     2              0.1785714                   0.00                     TRUE
#>    doubtful
#>      <lgcl>
#> 1:     TRUE
#> 2:     TRUE
```
