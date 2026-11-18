# Post-fit invariants of a rating

Checks a rating's own equations, as a
[FlodeAssessment](https://jonpayneea.github.io/reach.rate/reference/FlodeAssessment.md),
without reference to the gaugings it was fitted to. It answers whether
the equations are mathematically usable. It does not say whether the
rating is a good one; that is for
[`validate_gaugings()`](https://jonpayneea.github.io/reach.rate/reference/validate_gaugings.md)
and, later, a full assessment.

**Technical checks** can fail:

- `coefficients_finite`: every `C`, `a` and `n` is finite, and `C` and
  `n` are positive;

- `limbs_ordered`: stage ranges are finite, ascending and contiguous
  (for a segmented fit, the breakpoints strictly ascend);

- `predictions_finite`: discharge is finite and not negative at 25
  stages in each limb;

- `monotone_discharge`: discharge does not decrease as stage rises
  within a limb;

- `monotone_across_junctions`: the discharge at the top of each limb is
  no lower than at the top of the limb before, so each discharge belongs
  to one limb (blocks the inverse only);

- `inverse_consistent`: discharge to stage and back reproduces the
  discharge to within 1e-6 (blocks the inverse only);

- `interval_ordering` (a fit with bootstrap draws): for every parameter
  the lower, median and upper bootstrap bounds are in order;

- `bounds_respected` (a fit made directly by the optimiser): each fitted
  parameter is inside the bounds it was given.

**Hydrometric checks** can warn:

- `domain_valid`: in each limb the zero-flow stage `a` is not above the
  limb's lower stage. Discharge is zero at and below `a`, so a limb that
  starts below it is legitimate, but part of it then carries no flow;

- `stage_gaps_overlaps`: no gap or overlap between adjacent limbs' stage
  ranges;

- `limb_continuity`: discharge is continuous across each junction,
  within `continuity_tol`.

A check that cannot be run is `not_assessed`, never `pass`.

**A rating that fails a technical check is not applied.** A failure
stops the operation it makes meaningless, and says which check failed,
because a number from such a rating would look like any other.
[`apply_rating()`](https://jonpayneea.github.io/reach.rate/reference/apply_rating.md)
stops for any failure except the two marked as blocking the inverse
only;
[`apply_rating_inverse()`](https://jonpayneea.github.io/reach.rate/reference/apply_rating_inverse.md)
stops for every failure. A drop in discharge at a junction, for example,
leaves stage to discharge well defined but makes the inverse ambiguous.
Warnings never block. The invariants are evaluated when asked for, so
they always describe the rating as it now stands, including after any
change to it.

## Usage

``` r
rating_invariants(x, continuity_tol = 0.01)
```

## Arguments

- x:

  A
  [FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md),
  [FlodeSegmentedRating](https://jonpayneea.github.io/reach.rate/reference/FlodeSegmentedRating.md)
  or
  [FlodeRatingTable](https://jonpayneea.github.io/reach.rate/reference/FlodeRatingTable.md).

- continuity_tol:

  Number. The relative jump in discharge at a junction above which
  `limb_continuity` warns. Default 0.01.

## Value

A
[FlodeAssessment](https://jonpayneea.github.io/reach.rate/reference/FlodeAssessment.md)
with subject `"rating"`, one row per check.

## See also

[FlodeAssessment](https://jonpayneea.github.io/reach.rate/reference/FlodeAssessment.md),
[`assessment_checks()`](https://jonpayneea.github.io/reach.rate/reference/assessment_checks.md),
[`validate_gaugings()`](https://jonpayneea.github.io/reach.rate/reference/validate_gaugings.md),
[`vignette("mathematical_contract")`](https://jonpayneea.github.io/reach.rate/articles/mathematical_contract.md)

## Examples

``` r
set.seed(1)
stage_m <- seq(0.4, 3, by = 0.05)
discharge_cms <- 3.2 * stage_m^1.6 * exp(rnorm(length(stage_m), sd = 0.03))
fit <- rate_optimise(discharge_cms, stage_m, control = 1.5)
rating_invariants(fit)
#> <FlodeAssessment> rating, 2 row(s) assessed. Overall: warning
#>   9 pass, 1 warning, 0 fail, 1 not assessed
#>   [warning] limb_continuity: Discharge jumps by more than 1% at the junction above limb 1 (largest: 3.84%).
#>   [not_assessed] interval_ordering: No bootstrap draws, so interval ordering could not be checked.

# A rating that cannot be applied: its exponent is negative.
broken <- FlodeRatingTable(table = data.table::data.table(
  lower_level = 0, upper_level = 3, C = 2, a = 0, n = -1
))
assessment_checks(rating_invariants(broken))[status == "fail", .(check_id, message)]
#>               check_id
#>                 <char>
#> 1: coefficients_finite
#>                                                                       message
#>                                                                        <char>
#> 1: limb 1: a coefficient is missing or not finite, or C or n is not positive.
```
