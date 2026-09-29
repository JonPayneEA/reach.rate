# Suggest candidate stage breakpoints for a multi-limb rating fit

A heuristic aid for choosing `control` in
[`rate_optimise()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise.md).
Reuses
[`rate_optimise()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise.md)
directly: for each candidate stage, fits a two-limb rating there and
compares its AIC against the current best model (penalising the extra
parameters, unlike raw RSS). A candidate must also clear
`min_improvement`, a minimum relative RSS reduction, to be eligible.
Multiple breakpoints are found iteratively and greedily, respecting
`min_gap`. Not a claim that a statistically-supported breakpoint
corresponds to a real physical control change – that judgement remains
yours.

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

A `data.table`, one row per candidate evaluated across every round, with
`candidate_stage`, `score`, `improvement`, `n_obs_lower`, `n_obs_upper`,
`round`, `fit_status`, `rank` and `selected`. `selected` is `TRUE` for
the candidate each round adopted; extract the selected stages with
`sort(result[selected == TRUE, candidate_stage])`. The same stages
remain attached as the `"selected_breaks"` attribute for code written
against earlier versions, but an attribute can be lost under ordinary
data.table operations, so prefer the column.

## See also

[`rate_optimise()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise.md)
