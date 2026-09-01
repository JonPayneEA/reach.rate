# Expand a rating equation table into a stage-discharge data.table

Evaluates the rating equation \\Q = C \cdot (h - a)^b\\ for every limb
defined in a rating table and returns a single stage-discharge
`data.table` ready for use with
[`detect_rc_gaps`](https://jonpayneea.github.io/reach.rate/reference/detect_rc_gaps.md),
[`resolve_rc_gaps`](https://jonpayneea.github.io/reach.rate/reference/resolve_rc_gaps.md),
and
[`plot_rc_gaps`](https://jonpayneea.github.io/reach.rate/reference/plot_rc_gaps.md).

Each limb is defined by a row in `rating_dt` containing a lower and
upper stage bound, the three equation parameters (C, a, n), and an
optional *doubtful* flag (commonly set for upper limbs derived from
flood-frequency estimates rather than direct gauging).

## Usage

``` r
expand_rating_table(
  rating_dt,
  step = 0.01,
  max_stage = NULL,
  lower_col = "lower_level",
  upper_col = "upper_level",
  c_col = "C",
  a_col = "a",
  b_col = "n",
  doubtful_col = "doubtful"
)
```

## Arguments

- rating_dt:

  A
  [FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md)
  (converted via
  [`as_rating_table()`](https://jonpayneea.github.io/reach.rate/reference/as_rating_table.md)
  first), a
  [FlodeRatingTable](https://jonpayneea.github.io/reach.rate/reference/FlodeRatingTable.md),
  or a data.frame/data.table with one row per limb. The latter two must
  contain the columns named by `lower_col`, `upper_col`, `c_col`,
  `a_col`, and `b_col`. An optional doubtful flag column named by
  `doubtful_col` is carried through to the output if present.

- step:

  Numeric. Stage increment for generating evaluation points within each
  limb (default `0.01`). The upper bound of each limb is always included
  regardless of rounding.

- max_stage:

  Numeric or `NULL`. Upper bound applied to every limb before generating
  stage sequences. Useful when the last limb uses a sentinel value such
  as `999` to indicate an open-ended upper limit. When `NULL` (default)
  the raw `upper_col` values are used unchanged. A warning is issued for
  any limb whose upper level exceeds `max_stage`.

- lower_col, upper_col:

  Character. Column names for the lower and upper stage limits of each
  limb (defaults `"lower_level"` and `"upper_level"`).

- c_col, a_col, b_col:

  Character. Column names for the equation parameters C (multiplier), a
  (offset / zero-flow level), and n (exponent). Defaults `"C"`, `"a"`,
  `"n"`.

- doubtful_col:

  Character. Column name for the doubtful flag (default `"doubtful"`).
  Ignored if the column is absent from `rating_dt`.

## Value

A `data.table` with columns:

- stage:

  Stage values at which Q was evaluated.

- discharge:

  Computed discharge (m\\^3\\/s). Stages at or below the zero-flow
  offset `a` are returned as `0`.

- limb:

  Integer limb ID (row index of `rating_dt`).

- doubtful:

  Logical flag carried from `rating_dt` (only present when
  `doubtful_col` exists in `rating_dt`).

## Details

The breakpoint stage shared between two adjacent limbs (the upper limit
of limb \\n\\ equals the lower limit of limb \\n+1\\) is included in
*both* limbs. This lets
[`detect_rc_gaps()`](https://jonpayneea.github.io/reach.rate/reference/detect_rc_gaps.md)
compare the end discharge of the lower limb against the start discharge
of the upper limb at the exact same stage, which is where gaps are most
visible.

Because each limb is fitted independently, the discharge values at a
shared breakpoint stage will generally differ – that difference is the
gap that
[`detect_rc_gaps()`](https://jonpayneea.github.io/reach.rate/reference/detect_rc_gaps.md)
measures and
[`resolve_rc_gaps()`](https://jonpayneea.github.io/reach.rate/reference/resolve_rc_gaps.md)
corrects.

## See also

[`detect_rc_gaps`](https://jonpayneea.github.io/reach.rate/reference/detect_rc_gaps.md),
[`resolve_rc_gaps`](https://jonpayneea.github.io/reach.rate/reference/resolve_rc_gaps.md),
[`plot_rc_gaps`](https://jonpayneea.github.io/reach.rate/reference/plot_rc_gaps.md)

## Examples

``` r
# Three-limb rating with independent C/a/n parameters.
rating_dt <- data.table::data.table(
  lower_level = c(0.0, 1.2, 2.5),
  upper_level = c(1.2, 2.5, 4.0),
  C = c(2.5, 4.1, 7.8),
  a = c(0.0, 0.0, 0.0),
  n = c(1.50, 1.70, 2.00),
  doubtful = c(FALSE, FALSE, TRUE)
)
rc_dt <- expand_rating_table(rating_dt)
gaps_dt <- detect_rc_gaps(rc_dt)
#> INFO [2026-09-01 09:53:17] Checked 2 junction(s): 2 gap(s) flagged.
rc_fixed_dt <- resolve_rc_gaps(rc_dt)
#> INFO [2026-09-01 09:53:17] Checked 2 junction(s): 2 gap(s) flagged.
#> INFO [2026-09-01 09:53:17] Junction 1 (limbs 1/2, stage 1.2): gap 3.29 -> 5.59 | agreed Q = 4.438
#> INFO [2026-09-01 09:53:17] Junction 2 (limbs 2/3, stage 2.5): gap 19.47 -> 48.75 | agreed Q = 34.1081
```
