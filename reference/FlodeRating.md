# A fitted multi-limb rating curve (S7)

The result of
[`rate_optimise()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise.md)
(or
[`rate_optimise_constrained()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise_constrained.md)):
one row per limb in `@limbs` (bounds, coefficients `C`/`a`/`n`, fit
diagnostics, and – when produced by
[`rate_optimise_constrained()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise_constrained.md)
– alignment provenance), the raw gaugings in `@gaugings`, and bootstrap
draws in `@bootstrap` when `rate_optimise(..., n_boot = )` was used.

## Usage

``` r
FlodeRating(
  gaugings = data.table(),
  fit_starts = NULL,
  status = "independently_fitted",
  provenance = list(),
  previous = NULL,
  limbs = data.table(),
  bootstrap = NULL
)
```

## Arguments

- gaugings:

  Data.table with `discharge_cms` and `stage_m` columns – the gaugings
  the fit was built from. May optionally include a `gauging_datetime`
  column (`Date` or `POSIXct`) recording when each spot gauging was
  taken. Nothing in the package currently reads this column – it's
  groundwork for a future age-aware fitting option (see issue \#9). A
  gauging's own measurement method (current- meter, ADCP, salt-dilution,
  index-velocity, ...) is not currently recorded either – every gauging
  is treated identically regardless of source.

- fit_starts:

  Data.table of multi-start fitting attempts, or `NULL` if the fit
  wasn't produced with `multi_start = TRUE`.

- status:

  Character. One of `"independently_fitted"`, `"post_fit_aligned"`, or
  `"constrained_refit"`.

- provenance:

  List recording how the fit was made (fitting method, controls, bounds,
  tool version).

- previous:

  The exact pre-amendment `FlodeRating` this was built from (e.g. by
  [`align_limb_equations()`](https://jonpayneea.github.io/reach.rate/reference/align_limb_equations.md)/[`align_limb_boundaries()`](https://jonpayneea.github.io/reach.rate/reference/align_limb_boundaries.md)),
  or `NULL` (default) for an independently-fitted result.

- limbs:

  Data.table, one row per limb: bounds, coefficients `C`/`a`/`n`, and
  fit diagnostics.

- bootstrap:

  Data.table of per-draw bootstrap coefficients, or `NULL` if the fit
  wasn't produced with `n_boot > 0`.

## Examples

``` r
# A FlodeRating normally comes from rate_optimise(); read it through
# the accessors.
set.seed(1)
stage_m <- seq(0.5, 3, by = 0.1)
discharge_cms <- 3.2 * stage_m^1.6 * exp(rnorm(length(stage_m), sd = 0.03))
fit <- rate_optimise(discharge_cms, stage_m)
fit
#> <FlodeRating> 1 limb(s), status: independently_fitted
#>     limb lower_stage_m upper_stage_m        C          a        n  rmse_cms
#>    <int>         <num>         <num>    <num>      <num>    <num>     <num>
#> 1:     1           0.5             3 3.520861 0.05580791 1.538393 0.2765406
#>    r_squared
#>        <num>
#> 1: 0.9973271
rating_limbs(fit)
#>     limb lower_stage_m upper_stage_m        C          a        n
#>    <int>         <num>         <num>    <num>      <num>    <num>
#> 1:     1           0.5             3 3.520861 0.05580791 1.538393
head(rating_evidence(fit))
#>    stage_m discharge_cms  limb
#>      <num>         <num> <int>
#> 1:     0.5      1.035953     1
#> 2:     0.6      1.420969     1
#> 3:     0.7      1.763679     1
#> 4:     0.8      2.348976     1
#> 5:     0.9      2.730430     1
#> 6:     1.0      3.122196     1

# The constructor checks its input, so a malformed object cannot exist:
# here the limb table is missing its stage bounds.
try(FlodeRating(
  limbs = data.table::data.table(limb = 1, C = 1, a = 0, n = 1),
  gaugings = data.table::data.table(discharge_cms = 1, stage_m = 1)
))
#> Error : <reach.rate::FlodeRating> object is invalid:
#> - limbs is missing required column(s): lower_stage_m, upper_stage_m
```
