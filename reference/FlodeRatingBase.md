# Abstract base class for a fitted rating (S7)

Properties and validation shared by
[FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md)
and
[FlodeSegmentedRating](https://jonpayneea.github.io/reach.rate/reference/FlodeSegmentedRating.md):
the gaugings a fit was built from, multi-start fitting bookkeeping (if
any), a status flag distinguishing an independently-fitted result from a
post-fit amendment, a provenance list for auditability (fitting method,
controls, bounds, tool version), and a `previous` chain for amendments
produced from an earlier fit of the same class. Never constructed
directly – see
[FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md)
and
[FlodeSegmentedRating](https://jonpayneea.github.io/reach.rate/reference/FlodeSegmentedRating.md).

## Usage

``` r
FlodeRatingBase(
  gaugings = FlodeEvidence(),
  fit_starts = NULL,
  fit_origin = "independently_fitted",
  lifecycle = "draft",
  schema_version = 2L,
  provenance = list(),
  previous = NULL
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

  The exact pre-amendment fit this was built from (same class as this
  instance), or `NULL` (default) for a fit with no such history – an
  independently-fitted result, for instance. Mirrors
  [FlodeRatingTable](https://jonpayneea.github.io/reach.rate/reference/FlodeRatingTable.md)'s
  own `@previous` audit chain.

## Examples

``` r
# FlodeRatingBase is abstract: it holds what a FlodeRating and a
# FlodeSegmentedRating have in common, and is never built directly.
try(FlodeRatingBase())
#> Error in S7::new_object(S7::S7_object(), gaugings = gaugings, fit_starts = fit_starts,  : 
#>   Can't construct an object from abstract class <FlodeRatingBase>

# Every fit is one underneath.
set.seed(1)
stage_m <- seq(0.5, 3, by = 0.1)
fit <- rate_optimise(3.2 * stage_m^1.6 * exp(rnorm(length(stage_m), sd = 0.03)), stage_m)
S7::S7_inherits(fit, FlodeRatingBase)
#> [1] TRUE
S7::S7_inherits(fit, FlodeRating)
#> [1] TRUE
S7::S7_inherits(fit, FlodeSegmentedRating)
#> [1] FALSE
```
