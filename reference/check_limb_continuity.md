# Check that the limbs of a rating meet

At each junction between two limbs, measures how far apart the two
equations are at the stage they share, three ways:

- the **discharge gap**, in m\\^3\\/s (`gap_cms`) and as a fraction of
  the discharge below the junction (`gap_rel`);

- the **stage gap** (`stage_gap_m`): how far the upper limb would have
  to move sideways to meet the lower one, which is the number a gauge
  reader sees as the rating jumping at that stage. It is negative when
  the upper limb is the higher curve;

- the **change of slope** (`slope_change_pct`): the difference in
  \\dQ/dH\\ across the junction. A change of slope at a breakpoint is
  normal, because that is what a breakpoint is for, so it is reported
  but judged only if you give `tol_slope`.

A junction is `continuous` when the discharge gap and the stage gap are
both within tolerance. The discharge gap passes if it is within
`tol_abs` **or** within `tol_rel`, so a tiny flow is not failed on a
percentage and a large flow does not need a fraction of a cumec; the
stage gap passes if it is within `tol_stage`.

It works from the equations, exactly at the shared stage, where
[`detect_rc_gaps()`](https://jonpayneea.github.io/reach.rate/reference/detect_rc_gaps.md)
scans a discretised rating table. With `after` it reports the same
measures before and after an alignment
([`align_limb_equations()`](https://jonpayneea.github.io/reach.rate/reference/align_limb_equations.md)
or
[`align_limb_boundaries()`](https://jonpayneea.github.io/reach.rate/reference/align_limb_boundaries.md)),
so the effect of the amendment is on the table and not only claimed.

A single limb has no junction, and a
[FlodeSegmentedRating](https://jonpayneea.github.io/reach.rate/reference/FlodeSegmentedRating.md)
is continuous by construction (every later factor of its joint equation
is exactly 1 at its breakpoint), so each gives a table with no rows.

## Usage

``` r
check_limb_continuity(
  x,
  after = NULL,
  tol_abs = 0.05,
  tol_rel = 0.01,
  tol_stage = 0.005,
  tol_slope = NULL
)
```

## Arguments

- x:

  A
  [FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md)
  or
  [FlodeRatingTable](https://jonpayneea.github.io/reach.rate/reference/FlodeRatingTable.md).

- after:

  `NULL` (default), or the same rating after an alignment, with the same
  number of limbs, to compare with `x`.

- tol_abs:

  Number, m\\^3\\/s. Default 0.05.

- tol_rel:

  Number. Default 0.01 (1%).

- tol_stage:

  Number, metres. Default 0.005, about the resolution of a gauge.

- tol_slope:

  Number or `NULL`. A change of slope larger than this fraction (0.1 is
  10%) is reported as `slope_ok = FALSE`. `NULL` (default): the slope is
  reported, not judged, and `slope_ok` is `NA`.

## Value

A data.table, one row per junction, with `junction`, `stage_m`,
`limb_below`, `limb_above`, `q_below_cms`, `q_above_cms`, `gap_cms`,
`gap_rel`, `stage_gap_m`, `slope_below`, `slope_above`,
`slope_change_pct`, `discharge_ok`, `stage_ok`, `slope_ok` and
`continuous`.

With `after`, one row per junction with `junction` and, for `stage_m`,
`gap_cms`, `gap_rel`, `stage_gap_m`, `slope_change_pct` and
`continuous`, a `_before` and an `_after` column, and `improved`, `TRUE`
where the discharge gap shrank. Boundaries can move in
[`align_limb_boundaries()`](https://jonpayneea.github.io/reach.rate/reference/align_limb_boundaries.md),
so the junction stage is given for both.

## See also

[`detect_rc_gaps()`](https://jonpayneea.github.io/reach.rate/reference/detect_rc_gaps.md),
[`align_limb_equations()`](https://jonpayneea.github.io/reach.rate/reference/align_limb_equations.md),
[`align_limb_boundaries()`](https://jonpayneea.github.io/reach.rate/reference/align_limb_boundaries.md),
[`rating_invariants()`](https://jonpayneea.github.io/reach.rate/reference/rating_invariants.md)
for the same question as a warning

## Examples

``` r
# Two limbs that do not quite meet at 1 m.
rating <- FlodeRatingTable(table = data.table::data.table(
  lower_level = c(0.2, 1), upper_level = c(1, 3),
  C = c(2, 2.1), a = c(0, 0), n = c(1.5, 1.6)
))
check_limb_continuity(rating)[, .(stage_m, gap_cms, gap_rel, stage_gap_m, continuous)]
#>    stage_m gap_cms gap_rel stage_gap_m continuous
#>      <num>   <num>   <num>       <num>     <lgcl>
#> 1:       1     0.1    0.05 -0.03003361      FALSE

# Before and after closing the gap.
aligned <- align_limb_equations(rating)
check_limb_continuity(rating, after = aligned)[, .(gap_cms_before, gap_cms_after, improved)]
#>    gap_cms_before gap_cms_after improved
#>             <num>         <num>   <lgcl>
#> 1:            0.1             0     TRUE
```
