# Resolve discharge gaps between rating-curve limbs

Closes discharge discontinuities at limb junctions identified by
[`detect_rc_gaps`](https://jonpayneea.github.io/reach.rate/reference/detect_rc_gaps.md)
using one of five strategies (plus two deprecated aliases for backward
compatibility):

- `"midpoint"` (default):

  Both limbs' endpoint discharges are moved to the simple average of the
  two original endpoint values at the breakpoint stage. An earlier
  version of this function called this method `"interpolate"` and
  computed it via a linear-interpolation helper – but that helper was
  always evaluated at one of its own defining endpoints, which trivially
  returns that endpoint's value unchanged regardless of the other point
  supplied. The result was never anything other than the average of the
  two original endpoints; it was not using any interior point from
  either limb, despite the name. Renamed to describe what it actually
  computes.

- `"match_upper_to_lower"`:

  Only the upper limb's *first row* is changed: its discharge is set
  equal to the lower limb's last discharge. Use when the lower
  (typically gauged) limb is authoritative and you only need the single
  junction point to agree, not the whole upper curve reshaped.

- `"match_lower_to_upper"`:

  Only the lower limb's *last row* is changed: its discharge is set
  equal to the upper limb's first discharge. Use when the upper limb
  (e.g. a flood-frequency estimate) is authoritative and only the
  junction point needs to agree.

- `"extend_lower_to_upper"`:

  The lower limb's discharge is rescaled by a single constant factor
  across *every* one of its rows, chosen so its last value exactly
  matches the upper limb's first discharge – since \\Q = C(H+a)^n\\ is
  linear in \\C\\, this is equivalent to rescaling the lower limb's
  \\C\\ and preserves its curve shape. The upper limb is untouched, and
  (being unchanged) is what the lower limb's rescaled curve now "starts
  from" at the junction. Use when the upper limb is authoritative and
  the whole lower curve, not just its endpoint, should reflect that.

- `"extend_upper_to_lower"`:

  The mirror image of `"extend_lower_to_upper"`: the upper limb's
  discharge is rescaled across every row so its first value matches the
  lower limb's last discharge; the lower limb is untouched.

- `"snap_to_lower"`, `"snap_to_upper"` (deprecated):

  Old names for `"match_upper_to_lower"` and `"match_lower_to_upper"`
  respectively – kept working via a deprecation warning, but the names
  read backwards from what they do (`"snap_to_lower"` moves the *upper*
  limb, not the lower one) and new code should use the replacements.

Only junctions flagged by `detect_rc_gaps` (i.e. those exceeding
`tol_abs` or `tol_rel`) are modified. Whichever method is used, this
amends the discretised **table** at the junction rows only – it does not
touch the equations that produced them (see
[`align_limb_equations`](https://jonpayneea.github.io/reach.rate/reference/align_limb_equations.md)
for that).

On a rating with 3 or more limbs (2 or more junctions), each junction
reads the *current* discharge at its own endpoints rather than a value
captured before any junction was resolved, and – for the `"extend_*"`
methods specifically – junctions are resolved in whichever order keeps
each limb settling exactly once: top-down for `"extend_lower_to_upper"`
(a limb is only rescaled as a "lower" limb after it has already settled
as an "upper" one), bottom-up for `"extend_upper_to_lower"`. This
mirrors
[`align_limb_equations`](https://jonpayneea.github.io/reach.rate/reference/align_limb_equations.md)'s
outward propagation from an anchor limb; without it, a middle limb
rescaled to close the junction above it could silently reopen the
junction below.

## Usage

``` r
resolve_rc_gaps(
  rc_dt,
  stage_col = "stage",
  discharge_col = "discharge",
  limb_col = "limb",
  method = c("midpoint", "match_lower_to_upper", "match_upper_to_lower",
    "extend_lower_to_upper", "extend_upper_to_lower", "snap_to_lower", "snap_to_upper"),
  tol_abs = 0.5,
  tol_rel = 0.02
)
```

## Arguments

- rc_dt:

  A data.frame or data.table containing the rating curve.

- stage_col:

  Character. Name of the stage column. Default `"stage"`.

- discharge_col:

  Character. Name of the discharge column. Default `"discharge"`.

- limb_col:

  Character or `NULL`. Name of the limb-ID column. Auto-detected if
  absent. Default `"limb"`.

- method:

  Character. Resolution strategy: `"midpoint"`,
  `"match_lower_to_upper"`, `"match_upper_to_lower"`,
  `"extend_lower_to_upper"`, `"extend_upper_to_lower"`, or the
  deprecated `"snap_to_lower"`/`"snap_to_upper"` aliases. Default
  `"midpoint"`.

- tol_abs:

  Numeric. Absolute discharge tolerance passed to
  [`detect_rc_gaps`](https://jonpayneea.github.io/reach.rate/reference/detect_rc_gaps.md).
  Default `0.5`.

- tol_rel:

  Numeric. Relative discharge tolerance passed to
  [`detect_rc_gaps`](https://jonpayneea.github.io/reach.rate/reference/detect_rc_gaps.md).
  Default `0.02`.

## Value

The corrected `data.table` with the same columns as `rc_dt`, sorted by
`stage_col` ascending. If no gaps are flagged the input is returned
unchanged (as a data.table).

## See also

[`detect_rc_gaps`](https://jonpayneea.github.io/reach.rate/reference/detect_rc_gaps.md),
[`plot_rc_gaps`](https://jonpayneea.github.io/reach.rate/reference/plot_rc_gaps.md),
[`align_limb_equations`](https://jonpayneea.github.io/reach.rate/reference/align_limb_equations.md)
for correcting the equations themselves rather than just the discretised
table

## Examples

``` r
stage_seq1 <- seq(8.0, 10.0, by = 0.2)
limb1_dt <- data.table::data.table(
  stage = stage_seq1,
  discharge = 12 * (stage_seq1 - 8.0)^1.65,
  limb = 1L
)
stage_seq2 <- seq(10.0, 11.5, by = 0.2)
limb2_dt <- data.table::data.table(
  stage = stage_seq2,
  discharge = (tail(limb1_dt$discharge, 1) - 5) + 30 * (stage_seq2 - 10.0)^1.4,
  limb = 2L
)
rc_raw_dt <- data.table::rbindlist(list(limb1_dt, limb2_dt))
rc_fixed_dt <- resolve_rc_gaps(rc_raw_dt, method = "midpoint")
#> INFO [2026-09-01 15:45:16] Checked 1 junction(s): 1 gap(s) flagged.
#> INFO [2026-09-01 15:45:16] Junction 1 (limbs 1/2, stage 10): gap 37.66 -> 32.66 | agreed Q = 35.16
rc_matched_dt <- resolve_rc_gaps(rc_raw_dt, method = "match_upper_to_lower")
#> INFO [2026-09-01 15:45:16] Checked 1 junction(s): 1 gap(s) flagged.
#> INFO [2026-09-01 15:45:16] Junction 1 (limbs 1/2, stage 10): matching upper start 32.66 -> 37.66
rc_extended_dt <- resolve_rc_gaps(rc_raw_dt, method = "extend_lower_to_upper")
#> INFO [2026-09-01 15:45:16] Checked 1 junction(s): 1 gap(s) flagged.
#> INFO [2026-09-01 15:45:16] Junction 1 (limbs 1/2, stage 10): extending lower limb by a factor of 0.867233 to reach 32.66
```
