# Suggest candidate stage breakpoints for a multi-limb rating fit

Puts forward **candidates** for a breakpoint, for a person to review. It
is not a finding. A statistical search sees only the gaugings; it cannot
know where a channel control changes, a weir drowns or a bank is
overtopped. A candidate that fits better has not thereby been shown to
be a real change of hydraulic control, and one the search does not put
forward may still be real. Use the table to decide where to look, then
say where a breakpoint came from when you adopt it (see the
`breakpoint_origin` argument of
[`fit_rating()`](https://jonpayneea.github.io/reach.rate/reference/fit_rating.md)).

For each candidate stage the function fits a two-limb rating there with
[`rate_optimise()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise.md)
and compares its AIC against the current best model (penalising the
extra parameters, unlike raw RSS). A candidate must also clear
`min_improvement`, a minimum relative RSS reduction, to be put forward.
Multiple breakpoints are found iteratively and greedily, respecting
`min_gap`.

## Usage

``` r
suggest_breakpoints(
  discharge_cms,
  stage_m,
  max_breaks = 2L,
  min_obs_per_side = 5L,
  min_improvement = 0.02,
  min_gap = NULL,
  max_candidates = 200L
)
```

## Arguments

- discharge_cms, stage_m:

  Numeric vectors, as in
  [`rate_optimise()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise.md).

- max_breaks:

  Integer. Maximum breakpoints to search for. Default `2L`.

- min_obs_per_side:

  Integer. Minimum gaugings required on each side of a candidate.
  Default `5L`.

- min_improvement:

  Numeric. Minimum relative RSS reduction required. Default `0.02`.

- min_gap:

  Numeric or `NULL`. Minimum stage distance between selected
  breakpoints. Default `NULL` (5% of the stage range).

- max_candidates:

  Integer. Candidates evaluated per round, capped and thinned if
  exceeded. Default `200L`.

## Value

A `data.table`, one row per candidate evaluated across every round. For
each candidate:

- `candidate_stage`, and the `round` it was considered in;

- `score`, the improvement in AIC over the simpler model (positive is
  better), and `improvement`, the fraction by which the residual sum of
  squares falls;

- the evidence on each side: `n_obs_lower` and `n_obs_upper` (how many
  gaugings), and `lower_min_m`, `lower_max_m`, `upper_min_m` and
  `upper_max_m` (the stage range they cover). A candidate resting on a
  few gaugings crowded at one end is weak however good its score;

- `fit_status`: `"ok"`, `"failed"` (the two-limb fit raised an error) or
  `"insufficient_obs"` (too few gaugings on one side), and
  `failure_reason` saying why when it is not `"ok"`. A candidate that
  could not be fitted is listed, not dropped, because the stage where
  fits fail can itself be informative;

- `rank` within its round, and `preferred`, `TRUE` for the candidate
  each round put forward as the best by the scoring rule. It is a
  preference, not a finding: see the top of this page. Extract those
  stages with `sort(result[preferred == TRUE, candidate_stage])`.
  `selected` holds the same values and is the earlier name for this
  column, kept for code that already uses it and **superseded**: it will
  warn in a later release and then go. The same stages remain attached
  as the `"selected_breaks"` attribute for code written against earlier
  versions, but an attribute can be lost under ordinary data.table
  operations, so prefer the column.

## See also

[`rate_optimise()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise.md),
[`fit_rating()`](https://jonpayneea.github.io/reach.rate/reference/fit_rating.md)
and
[`breakpoint_origins()`](https://jonpayneea.github.io/reach.rate/reference/breakpoint_origins.md)
to record where an adopted breakpoint came from

## Examples

``` r
# Gaugings whose rating changes character above about 2.4 m
set.seed(7)
stage_m <- seq(0.3, 3.5, by = 0.05)
discharge_cms <- 4 * pmax(stage_m - 0.1, 0)^1.55 * (pmax(stage_m - 1.6, 0) + 1)^0.9 *
  (pmax(stage_m - 2.4, 0) + 1)^1.1 * exp(rnorm(length(stage_m), sd = 0.03))

candidates <- suggest_breakpoints(discharge_cms, stage_m, max_breaks = 1L)

# The candidate each round put forward, how much it improved the fit, and
# how many gaugings stand on each side of it
candidates[preferred == TRUE, c("round", "candidate_stage", "improvement", "n_obs_lower", "n_obs_upper")]
#>    round candidate_stage improvement n_obs_lower n_obs_upper
#>    <int>           <num>       <num>       <int>       <int>
#> 1:     1            2.45   0.8679528          44          21

# The stages themselves, ready to pass to rate_optimise()
breaks <- sort(candidates[preferred == TRUE, candidate_stage])
breaks
#> [1] 2.45
fit <- rate_optimise(discharge_cms, stage_m, control = breaks)
#> Warning: rate_optimise(): limb 1 -- the best fit found did not converge (Number of iterations has reached `maxiter' == 100.). It has the lowest objective of the 6 starts, but the optimiser stopped before settling, so treat the limb with caution.
rating_limbs(fit)
#>     limb lower_stage_m upper_stage_m           C          a        n
#>    <int>         <num>         <num>       <num>      <num>    <num>
#> 1:     1          0.30          2.45 0.001006872 -2.5641810 6.309658
#> 2:     2          2.45          3.50 1.871309888  0.4782094 4.017815

# These are candidates only. Whether a stage marks a real change of
# hydraulic control is a judgement for you, not the data.
```
