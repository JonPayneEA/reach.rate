# Fit a rating curve with Hodson et al. (2024)'s segmented parameterisation

The rest of this toolkit
([`rate_optimise()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise.md))
fits each limb of a rating independently over disjoint stage ranges.
This is a structurally different model, adapted from the log-additive
segmented power law in Hodson et al. (2024): every segment contributes
multiplicatively across the whole fitted range rather than owning a
disjoint stage band –

\$\$Q = C \cdot \max(H - bp_1, 0)^{n_1} \cdot \prod\_{j \ge 2} (\max(H -
bp_j, 0) + 1)^{n_j}\$\$

`bp_1` is the stage of zero flow. Each later factor equals exactly 1 (no
effect) at and below its own breakpoint `bp_j`. Continuity is therefore
automatic, not imposed afterward.

**What this does not reproduce**: Hodson et al. fit this model by full
Bayesian inference. This function fits by ordinary nonlinear least
squares (`nlsLM`) instead – no priors, no posterior. `C`, `bp_1`, and
every exponent are genuine free parameters. The interior breakpoints
`bp_2..bp_k` are held fixed at `control` by default; set
`estimate_breakpoints = TRUE` to free them too, at the cost of the
non-convexity their paper warns about.

## Usage

``` r
rate_optimise_segmented(
  discharge_cms,
  stage_m,
  gauging_datetime = NULL,
  control = NULL,
  estimate_breakpoints = FALSE,
  multi_start = TRUE,
  objective = c("absolute", "relative"),
  ...
)
```

## Arguments

- discharge_cms, stage_m:

  Numeric vectors, as in
  [`rate_optimise()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise.md).

- gauging_datetime:

  `Date`/`POSIXct` vector or `NULL`, as in
  [`rate_optimise()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise.md).
  Default `NULL`.

- control:

  Numeric vector or `NULL`. Interior segment breakpoints.

- estimate_breakpoints:

  Logical. If `TRUE`, interior breakpoints are refit as free parameters.
  Default `FALSE`.

- multi_start:

  Logical. If `TRUE` (default), fits from several starting-value
  profiles and keeps the best converged, domain-valid result. This
  matters more here than for
  [`rate_optimise()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise.md)'s
  independent-limb fits: this model's loss surface is genuinely
  non-convex.

- objective:

  Character. `"absolute"` (default) minimises absolute discharge error,
  as before. `"relative"` fits `log(discharge_cms)` residuals instead –
  see
  [`rate_optimise()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise.md)
  for the rationale. Requires `discharge_cms` to be strictly positive.
  Reported diagnostics (`rmse_cms`, `r_squared`) are always recomputed
  on the natural discharge scale regardless of `objective`. Not a
  default – existing callers see no change in behaviour.

- ...:

  Passed to
  [`minpack.lm::nls.lm.control()`](https://rdrr.io/pkg/minpack.lm/man/nls.lm.control.html).

## Value

A
[FlodeSegmentedRating](https://jonpayneea.github.io/reach.rate/reference/FlodeSegmentedRating.md)
instance. `@coefficients` is a one-row data.table: `C`, `bp1..bpk`,
`n1..nk`, `rmse_cms`, `r_squared`, `n_obs`, `n_starts_attempted`,
`n_starts_converged`, `selected_start_id`. `@gaugings` holds the input
data (and `gauging_datetime` if supplied). `@fit_starts` holds every
multi-start attempt when `multi_start = TRUE`.

## See also

[`rate_optimise()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise.md)
for this toolkit's usual independent-limb fit;
[`rating_plot()`](https://jonpayneea.github.io/reach.rate/reference/rating_plot.md)
and
[`apply_rating()`](https://jonpayneea.github.io/reach.rate/reference/apply_rating.md)
(both in `flode_classes`) for the generics this class's methods are
registered against

## Examples

``` r
set.seed(1)
stage_m <- seq(0.3, 3.5, by = 0.03)
true_bp1 <- 0.1
q1 <- 4 * pmax(stage_m - true_bp1, 0)^1.55
q2 <- (pmax(stage_m - 1.6, 0) + 1)^0.9
q3 <- (pmax(stage_m - 2.4, 0) + 1)^1.1
discharge_cms <- q1 * q2 * q3 * exp(rnorm(length(stage_m), sd = 0.03))
fit_seg <- rate_optimise_segmented(discharge_cms, stage_m, control = c(1.6, 2.4))
fit_seg@coefficients
#>           C        bp1    n1        n2       n3   bp2   bp3 rmse_cms r_squared
#>       <num>      <num> <num>     <num>    <num> <num> <num>    <num>     <num>
#> 1: 1.750914 -0.3204674 2.266 0.6593678 1.030696   1.6   2.4 1.394804 0.9987926
#>    n_obs n_starts_attempted n_starts_converged selected_start_id
#>    <int>              <int>              <int>             <int>
#> 1:   107                  4                  4                 1
```
