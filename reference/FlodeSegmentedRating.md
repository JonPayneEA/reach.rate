# A fitted segmented rating curve, Hodson et al. (2024) parameterisation (S7)

The result of
[`rate_optimise_segmented()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise_segmented.md):
a single joint model rather than independent limbs, so `@coefficients`
is one row (`C`, `bp1..bpk`, `n1..nk`, diagnostics), not one row per
segment.

## Usage

``` r
FlodeSegmentedRating(
  gaugings = FlodeEvidence(),
  fit_starts = NULL,
  fit_origin = "independently_fitted",
  lifecycle = "draft",
  schema_version = 2L,
  provenance = list(),
  previous = NULL,
  coefficients = data.table(),
  n_segments = integer(0),
  estimate_breakpoints = logical(0)
)
```

## Arguments

- gaugings:

  A
  [FlodeEvidence](https://jonpayneea.github.io/reach.rate/reference/FlodeEvidence.md)
  table of the observations the fit was built from. A plain `data.table`
  with `discharge_cms` and `stage_m` columns is accepted and converted
  by
  [`as_flode_evidence()`](https://jonpayneea.github.io/reach.rate/reference/as_flode_evidence.md),
  which generates evidence IDs and records what it assumed. A
  `gauging_datetime` column (`Date` or `POSIXct`) becomes
  `observation_time` and is used for age weighting.

- fit_starts:

  Data.table of multi-start fitting attempts, or `NULL` if the fit
  wasn't produced with `multi_start = TRUE`.

- fit_origin:

  Character. How the fit came to be: one of `"independently_fitted"`,
  `"post_fit_aligned"` or `"constrained_refit"`. Read-only `@status`
  returns the same value.

- lifecycle:

  Character. Where the rating stands in review: `"draft"` (default),
  `"under_review"`, `"approved"`, `"superseded"` or `"withdrawn"`. The
  package never sets `"approved"`; that is a decision for a person.

- schema_version:

  Integer. The layout version the object was made under; see
  [`rating_schema_version()`](https://jonpayneea.github.io/reach.rate/reference/rating_schema_version.md).
  Leave at the default.

- provenance:

  List recording how the fit was made (fitting method, controls, bounds,
  tool version).

- previous:

  The exact pre-amendment `FlodeSegmentedRating` this was built from, or
  `NULL` (default) for an independently-fitted result. Nothing in the
  package currently produces an amended `FlodeSegmentedRating` – this
  exists for parity with
  [FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md).

- coefficients:

  Single-row data.table: `C`, `bp1..bpk`, `n1..nk`, and fit diagnostics.

- n_segments:

  Integer. Number of segments `k`.

- estimate_breakpoints:

  Logical. Whether the interior breakpoints were refit as free
  parameters (`TRUE`) or held fixed at `control` (`FALSE`).

## Examples

``` r
# Three multiplicative segments, so there is no junction to reconcile.
set.seed(7)
stage_m <- seq(0.3, 3.5, by = 0.05)
discharge_cms <- 4 * pmax(stage_m - 0.1, 0)^1.55 * (pmax(stage_m - 1.6, 0) + 1)^0.9 *
  (pmax(stage_m - 2.4, 0) + 1)^1.1 * exp(rnorm(length(stage_m), sd = 0.03))
fit <- rate_optimise_segmented(discharge_cms, stage_m, control = c(1.6, 2.4))
fit
#> <FlodeSegmentedRating> 3 segment(s), origin: independently_fitted, lifecycle: draft, R² = 0.9994
#>   converged: yes
#>   valid: yes
#>          C        bp1       n1        n2       n3   bp2   bp3  rmse_cms
#>      <num>      <num>    <num>     <num>    <num> <num> <num>     <num>
#> 1: 2.37908 -0.1903062 1.986332 0.7764828 1.051703   1.6   2.4 0.9894296
#>    r_squared n_obs n_starts_attempted n_starts_converged selected_start_id
#>        <num> <int>              <int>              <int>             <int>
#> 1:  0.999443    65                  4                  4                 1
#>    converged convergence_code
#>       <lgcl>            <int>
#> 1:      TRUE                1
#>                                        convergence_message iterations
#>                                                     <char>      <int>
#> 1: Relative error in the sum of squares is at most `ftol'.         27
#>    objective_value bound_hits multi_start_spread parameter_correlation
#>              <num>     <char>              <num>                 <num>
#> 1:        63.63311       <NA>                 NA             0.9919157
#>    condition_number
#>               <num>
#> 1:         1124.155
rating_coefficients(fit)[, c("parameter", "estimate", "unit")]
#>    parameter   estimate         unit
#>       <char>      <num>       <char>
#> 1:         C  2.3790801 cms per m^n1
#> 2:       bp1 -0.1903062            m
#> 3:        n1  1.9863320            1
#> 4:       bp2  1.6000000            m
#> 5:        n2  0.7764828            1
#> 6:       bp3  2.4000000            m
#> 7:        n3  1.0517028            1
apply_rating(fit, c(0.5, 1.5, 3))
#>    stage discharge extrapolated
#>    <num>     <num>       <lgcl>
#> 1:   0.5  1.139443        FALSE
#> 2:   1.5  6.748761        FALSE
#> 3:   3.0 77.106058        FALSE
```
