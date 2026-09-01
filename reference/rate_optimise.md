# Fit a multi-limb power-law rating curve

Fits the rating equation \\Q = C(H - a)^n\\ by Levenberg-Marquardt
non-linear least squares
([`minpack.lm::nlsLM`](https://rdrr.io/pkg/minpack.lm/man/nlsLM.html)).
A single limb is fitted across the full stage range when `control` is
`NULL`; otherwise the gaugings are split into limbs at each stage in
`control` and each limb is fitted independently – this fits each limb
separately, not a single globally-optimised multi-limb model (see
[`rate_optimise_segmented()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise_segmented.md)
for that).

## Usage

``` r
rate_optimise(
  discharge_cms,
  stage_m,
  gauging_datetime = NULL,
  control = NULL,
  n_boot = 0L,
  boot_seed = NULL,
  min_boot_success = 0.8,
  multi_start = TRUE,
  n_bounds = NULL,
  objective = c("absolute", "relative"),
  age_halflife = NULL,
  age_min_weight = 0.1,
  reference_datetime = NULL,
  ...
)
```

## Arguments

- discharge_cms:

  Numeric vector. Gauged discharge, m\\^3\\/s.

- stage_m:

  Numeric vector. Gauged stage, m. Same length as `discharge_cms`.

- gauging_datetime:

  `Date`/`POSIXct` vector or `NULL`. When each gauging in
  `discharge_cms`/`stage_m` was taken, same length as `discharge_cms` if
  supplied. Stored on the returned rating's `@gaugings`; only affects
  the fit itself if `age_halflife` is also supplied (see below). Default
  `NULL`: no dates recorded, matching today's behaviour.

- control:

  Numeric vector or `NULL`. Stage breakpoints separating rating limbs,
  e.g. `c(1.6, 2.2)` for three limbs. `NULL` (default) fits a single
  limb across the full range.

- n_boot:

  Integer. Number of bootstrap refits per limb, for coefficient
  uncertainty. Default `0L`: no bootstrap.

- boot_seed:

  Integer or `NULL`. Passed to
  [`set.seed()`](https://rdrr.io/r/base/Random.html) before
  bootstrapping, with the caller's prior RNG state saved and restored
  afterward. Default `NULL`.

- min_boot_success:

  Numeric in `[0, 1]`. Warn if the successful-draw fraction for a limb
  falls below this. Default `0.8`.

- multi_start:

  Logical. If `TRUE` (default), each limb is fitted from several
  starting-value combinations and the best converged, domain-valid
  result is kept. Set `FALSE` for the original single-start behaviour.

- n_bounds:

  Numeric vector `c(lower, upper)`, or `NULL` (default). Box-constrains
  the exponent `n` for every limb, e.g. to a theoretical range implied
  by known channel-control hydraulics (roughly 1.5 for a rectangular
  control, 2.5 for triangular/V-notch). The top of a rating is usually
  the least-gauged part of the record, so this lets known geometry keep
  the fit realistic there without more data. Set `lower == upper` to fix
  `n` outright. `NULL` (default) keeps today's effectively unconstrained
  `n > 0`. Not a default constraint – most callers don't know their
  channel-control type, and an unconstrained fit remains the default
  behaviour.

- objective:

  Character. `"absolute"` (default) minimises absolute discharge error,
  as before. `"relative"` fits `log(discharge_cms)` residuals instead –
  gauging error is typically proportional (a percentage of the reading)
  rather than a fixed absolute amount, so this can better balance low-
  and high-flow structure than absolute error does. Requires
  `discharge_cms` to be strictly positive. Reported diagnostics
  (`rmse_cms`, `r_squared`, and the error columns) are always recomputed
  on the natural discharge scale regardless of `objective`, so they stay
  comparable between the two. Not a default – existing callers see no
  change in behaviour.

- age_halflife:

  Single positive number of days, or `NULL` (default). Opt-in recency
  weighting: each gauging's residual is weighted by
  `age_min_weight + (1 - age_min_weight) * 0.5^(age_days / age_halflife)`,
  where `age_days` is its age (clamped at 0) relative to
  `reference_datetime`. `NULL` (default) fits unweighted, exactly as
  before – supplying `gauging_datetime` alone, with `age_halflife` left
  `NULL`, changes nothing about the fit. Requires `gauging_datetime`.
  See
  [`vignette("recency_weighting_guide")`](https://jonpayneea.github.io/reach.rate/articles/recency_weighting_guide.md)
  for the full derivation and a worked example.

- age_min_weight:

  Single number in `[0, 1)`. The weight floor a gauging's age can never
  fall below, however old – prevents an old-but-genuinely-informative
  gauging (e.g. a limb's one high-flow flood) from being weighted to
  near-zero purely for being old. Not magnitude-aware: an old extreme
  gauging and an old ordinary one decay identically. Default `0.1`.
  Ignored if `age_halflife` is `NULL`.

- reference_datetime:

  `Date`/`POSIXct` or `NULL` (default). The "as of" point ages are
  measured back from. `NULL` uses `max(gauging_datetime)` – age relative
  to this dataset's own most recent gauging. Ignored if `age_halflife`
  is `NULL`.

- ...:

  Passed to
  [`minpack.lm::nlsLM()`](https://rdrr.io/pkg/minpack.lm/man/nlsLM.html)
  itself for the primary fit only, not the bootstrap refits.

## Value

A
[FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md)
instance. `@limbs` has one row per limb with bounds, coefficients
`C`/`a`/`n`, fit diagnostics – including `rmse_pct` (a
relative/percentage RMSE alongside the absolute `rmse_cms`, always
computed regardless of `objective`) and
`C_se_asymp`/`a_se_asymp`/`n_se_asymp` (closed-form asymptotic parameter
standard errors from the fit's own NLS covariance matrix, always
computed, `NA` if that covariance matrix is singular – distinct from the
bootstrap-only `C_se`/`a_se`/`n_se` columns below) – and multi-start
bookkeeping. When `n_boot > 0`, `@bootstrap` holds every draw and
`@limbs` gains `C_se`/`a_se`/`n_se`/percentile/ success-count columns;
prefer these over `*_se_asymp` when present, since they don't rely on
the NLS asymptotic approximation. `@gaugings` holds the input data with
a `limb` column (and `gauging_datetime` if supplied, and `age_weight` if
`age_halflife` was supplied). `@fit_starts` holds every multi-start
attempt when `multi_start = TRUE`. `@status` is
`"independently_fitted"`.

## See also

[`rating_plot()`](https://jonpayneea.github.io/reach.rate/reference/rating_plot.md),
[`plot_rating_residuals()`](https://jonpayneea.github.io/reach.rate/reference/plot_rating_residuals.md),
[`flag_extrapolated_limbs()`](https://jonpayneea.github.io/reach.rate/reference/flag_extrapolated_limbs.md),
[`suggest_breakpoints()`](https://jonpayneea.github.io/reach.rate/reference/suggest_breakpoints.md),
[`rate_optimise_constrained()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise_constrained.md)

## Examples

``` r
discharge_cms <- c(177.685, 240.898, 221.954, 205.55, 383.051, 154.061, 216.582)
stage_m <- c(1.855, 2.109, 2.037, 1.972, 2.574, 1.748, 2.016)
fit <- rate_optimise(discharge_cms, stage_m)
fit@limbs[, .(limb, C, a, n, rmse_cms, r_squared)]
#>     limb        C         a       n     rmse_cms r_squared
#>    <int>    <num>     <num>   <num>        <num>     <num>
#> 1:     1 63.15769 0.2209874 2.10651 8.711563e-05         1
```
