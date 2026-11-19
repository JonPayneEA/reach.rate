# Fit a rating from evidence

The guided way to a rating. Give it evidence and it fits one, with
defaults chosen so that a careful analyst would not argue, and it
records what it did. An expert who wants more control can still call
[`rate_optimise()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise.md)
or
[`rate_optimise_segmented()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise_segmented.md)
directly; this function calls them.

What it decides for you, and where to change it:

- **One limb.** A single equation \\Q = C(H - a)^n\\ across the whole
  range, unless you supply `controls` (breakpoint stages) or ask for
  `limbs = "suggest"`. A rating with several limbs is a modelling
  decision and is never made silently.

- **Suggested breakpoints are advisory.** With `limbs = "suggest"` the
  function uses
  [`suggest_breakpoints()`](https://jonpayneea.github.io/reach.rate/reference/suggest_breakpoints.md),
  records that the breakpoints came from a statistical search and not
  from field evidence, and says so each time the rating is printed. They
  are candidates for a person to review. Breakpoints you give in
  `controls` are recorded as yours.

- **The relative objective.** Gauging error is typically proportional to
  the reading, so the fit minimises error in log discharge. Use
  `objective = "absolute"` for
  [`rate_optimise()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise.md)'s
  own default. See
  [`vignette("mathematical_contract")`](https://jonpayneea.github.io/reach.rate/articles/mathematical_contract.md)
  for both.

- **What is used.** Rows marked `included = FALSE`, rows with a missing
  or non-finite stage or discharge, negative discharge, and (for the
  relative objective) zero discharge are not used. Each is listed with
  its reason in the rating's provenance, and none is deleted from your
  evidence.

- **Where it may be applied.** A rating made here can be applied only
  within the stage range it was gauged over until you state the range it
  may be used over, with `operational_limits` or
  [`set_operational_limits()`](https://jonpayneea.github.io/reach.rate/reference/set_operational_limits.md).
  That states the decision, and its basis, to use the rating there.

The rating stores the call, the seed, every starting point tried, and
the evidence it used with each row's `evidence_id`, so it can be
reproduced and checked.

## Usage

``` r
fit_rating(
  evidence,
  controls = NULL,
  limbs = c("one", "suggest"),
  model = c("independent", "segmented"),
  objective = c("relative", "absolute"),
  age_halflife = NULL,
  age_min_weight = 0.1,
  reference_time = NULL,
  n_boot = 0L,
  seed = NULL,
  operational_limits = NULL,
  operational_basis = NA_character_,
  quiet = FALSE
)
```

## Arguments

- evidence:

  A
  [FlodeEvidence](https://jonpayneea.github.io/reach.rate/reference/FlodeEvidence.md),
  or a `data.frame` or `data.table` that
  [`as_flode_evidence()`](https://jonpayneea.github.io/reach.rate/reference/as_flode_evidence.md)
  accepts, including the table
  [`read_gaugings()`](https://jonpayneea.github.io/reach.rate/reference/read_gaugings.md)
  returns.

- controls:

  Numeric vector of breakpoint stages, or `NULL` (default) for one limb.
  Each must lie inside the stage range of the evidence used.

- limbs:

  `"one"` (default) or `"suggest"`. `"suggest"` finds breakpoints with
  [`suggest_breakpoints()`](https://jonpayneea.github.io/reach.rate/reference/suggest_breakpoints.md)
  and uses those it selects, marked as advisory. Not allowed together
  with `controls`.

- model:

  `"independent"` (default) fits each limb separately with
  [`rate_optimise()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise.md).
  `"segmented"` fits one joint equation with
  [`rate_optimise_segmented()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise_segmented.md).

- objective:

  `"relative"` (default) or `"absolute"`.

- age_halflife, age_min_weight, reference_time:

  Optional recency weighting, as in
  [`rate_optimise()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise.md):
  a half-life in days, the weight floor, and the time ages are measured
  from (`NULL` is the latest gauging). Needs an `observation_time` on
  every row used.

- n_boot:

  Number of bootstrap refits per limb for coefficient uncertainty.
  Default 0. Only for `model = "independent"`.

- seed:

  Integer or `NULL`. Used for the bootstrap, and recorded so a fit can
  be repeated.

- operational_limits:

  `NULL` (default) or `c(lower, upper)`: the stage range, in metres,
  over which the rating may be applied.

- operational_basis:

  Character. Why that range: for example the gauged range, a structure's
  limit, or a review decision.

- quiet:

  Logical. `TRUE` suppresses the summary message.

## Value

A
[FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md)
(or
[FlodeSegmentedRating](https://jonpayneea.github.io/reach.rate/reference/FlodeSegmentedRating.md)
for `model = "segmented"`) whose `@gaugings` is the evidence that was
used, with each row's `evidence_id`, and whose provenance records the
call, seed, exclusions, breakpoint origin and operational limits (read
it with
[`rating_provenance()`](https://jonpayneea.github.io/reach.rate/reference/rating_provenance.md)).
Its lifecycle is `"draft"`.

## See also

[`read_gaugings()`](https://jonpayneea.github.io/reach.rate/reference/read_gaugings.md),
[`validate_gaugings()`](https://jonpayneea.github.io/reach.rate/reference/validate_gaugings.md),
[`set_operational_limits()`](https://jonpayneea.github.io/reach.rate/reference/set_operational_limits.md),
[`rate_optimise()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise.md),
[`rating_provenance()`](https://jonpayneea.github.io/reach.rate/reference/rating_provenance.md)

## Examples

``` r
set.seed(1)
gaugings <- data.frame(stage_m = round(seq(0.4, 3, length.out = 20), 3))
gaugings$discharge_cms <- round(3.2 * gaugings$stage_m^1.6 * exp(rnorm(20, sd = 0.03)), 3)
fit <- fit_rating(gaugings)
#> fit_rating(): 20 of 20 rows used; relative objective, independent model, one limb.
#>   No operational limits set: the rating applies only within the gauged range. See set_operational_limits().
fit
#> <FlodeRating> 1 limb(s), origin: independently_fitted, lifecycle: draft
#>   converged: yes (1 of 1 limb)
#>   valid: yes
#>   breakpoints: one limb
#>   evidence: 20 of 20 rows used
#>   operational limits: not set; applies only within the gauged range 0.4 to 3 m
#>     limb lower_stage_m upper_stage_m        C          a        n  rmse_cms
#>    <int>         <num>         <num>    <num>      <num>    <num>     <num>
#> 1:     1           0.4             3 3.286169 0.01254205 1.588275 0.2498467
#>    r_squared
#>        <num>
#> 1: 0.9980051

# The rating can be applied within the range it was gauged over.
apply_rating(fit, c(0.8, 1.5, 2.5))
#>    stage discharge extrapolated                support
#>    <num>     <num>       <lgcl>                 <char>
#> 1:   0.8  2.248384        FALSE interpolation_observed
#> 2:   1.5  6.174183        FALSE interpolation_observed
#> 3:   2.5 13.972011        FALSE interpolation_observed

# To apply it more widely, state the range and why.
wider <- set_operational_limits(fit, 0.2, 3.5, basis = "channel control confirmed to 3.5 m")
apply_rating(wider, c(0.3, 3.4))
#> INFO [2026-11-19 05:31:20] apply_rating(): 2 of 2 stage value(s) fell outside the rating and were extrapolated.
#>    stage  discharge extrapolated       support
#>    <num>      <num>       <lgcl>        <char>
#> 1:   0.3  0.4536877         TRUE extrapolation
#> 2:   3.4 22.8178884         TRUE extrapolation

# What the fit recorded.
str(rating_provenance(fit)$fit_rating[c("call", "model", "objective", "n_used")])
#> List of 4
#>  $ call     : chr "fit_rating(evidence = gaugings)"
#>  $ model    : chr "independent"
#>  $ objective: chr "relative"
#>  $ n_used   : int 20
```
