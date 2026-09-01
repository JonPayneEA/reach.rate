# Invert a rating: convert discharge back to stage

The other direction from
[`apply_rating()`](https://jonpayneea.github.io/reach.rate/reference/apply_rating.md):
given a discharge series, find the stage that produced it. Within one
limb this is safe and closed-form – `H = a + (Q/C)^(1/n)` – since
[FlodeRatingTable](https://jonpayneea.github.io/reach.rate/reference/FlodeRatingTable.md)'s
own validator already requires `C > 0` and `n > 0` for every limb, which
makes `Q = C(H-a)^n` strictly monotonic increasing over that limb's
domain.

The real risk is at a junction: if two adjacent limbs' equations don't
actually agree at their shared boundary stage (a discharge "gap," the
same thing
[`detect_rc_gaps()`](https://jonpayneea.github.io/reach.rate/reference/detect_rc_gaps.md)
exists to catch), the discharge axis has either an overlap (a query
discharge could belong to either limb) or a hole (a query discharge
belongs to neither) – both make the inverse genuinely ambiguous, not
just cosmetically imperfect. This function checks every junction
directly from the equations (not by discretising first) before doing
anything else, using the same `tol_abs`/`tol_rel` combination
[`detect_rc_gaps()`](https://jonpayneea.github.io/reach.rate/reference/detect_rc_gaps.md)
defaults to, and errors – rather than guessing – if any junction is
flagged. Close the gap first with
[`resolve_rc_gaps()`](https://jonpayneea.github.io/reach.rate/reference/resolve_rc_gaps.md),
[`align_limb_equations()`](https://jonpayneea.github.io/reach.rate/reference/align_limb_equations.md),
[`align_limb_boundaries()`](https://jonpayneea.github.io/reach.rate/reference/align_limb_boundaries.md),
or
[`graft_rating()`](https://jonpayneea.github.io/reach.rate/reference/graft_rating.md),
as appropriate.

`discharge <= 0` has no unique inverse (any `H <= a` gives `Q = 0`):
`out_col` is `NA` for those rows, with a warning, rather than guessing a
boundary convention.

This function assumes a genuinely monotonic power-law rating –
guaranteed within a single limb, and across limbs once the junction
check above passes. It is **not valid for tidal or strongly
backwater-affected stations**, where the true stage-discharge
relationship is not single-valued at all; no data available from a table
alone can detect that condition, so this is a documented limitation, not
a runtime check. Uncertainty propagation through the inverse (via the
local derivative `dH/dQ = 1/(C n (H-a)^{n-1})`) is not included in this
first version.

## Usage

``` r
apply_rating_inverse(
  fit,
  discharge_dt,
  discharge_col = "discharge",
  out_col = "stage",
  tol_abs = 0.5,
  tol_rel = 0.02
)
```

## Arguments

- fit:

  A
  [FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md)
  or
  [FlodeRatingTable](https://jonpayneea.github.io/reach.rate/reference/FlodeRatingTable.md).
  A `FlodeRating` is bridged via
  [`as_rating_table()`](https://jonpayneea.github.io/reach.rate/reference/as_rating_table.md)
  first, the same one-line pattern
  [`align_limb_equations()`](https://jonpayneea.github.io/reach.rate/reference/align_limb_equations.md)/[`graft_rating()`](https://jonpayneea.github.io/reach.rate/reference/graft_rating.md)
  already use.

- discharge_dt:

  Data.frame or data.table with a discharge column (named by
  `discharge_col`, default `"discharge"`); any other columns are carried
  through unchanged.

- discharge_col, out_col:

  Character. Column names for the input discharge and the output stage.
  Defaults `"discharge"`/`"stage"`.

- tol_abs, tol_rel:

  Numeric. The same junction-gap tolerance combination
  [`detect_rc_gaps()`](https://jonpayneea.github.io/reach.rate/reference/detect_rc_gaps.md)
  defaults to (`0.5`, `0.02`) – a junction is flagged if the discharge
  mismatch there exceeds *either* the absolute or the relative
  tolerance.

## Value

`discharge_dt` as a data.table with two columns added: `out_col` (the
inverted stage; `NA` where `discharge <= 0`) and `extrapolated`
(logical; `TRUE` where the discharge fell outside every limb's own range
and was extrapolated from the nearest one; `NA` where `discharge <= 0`,
since no lookup was attempted there).

## See also

[`apply_rating()`](https://jonpayneea.github.io/reach.rate/reference/apply_rating.md)
for the forward direction;
[`detect_rc_gaps()`](https://jonpayneea.github.io/reach.rate/reference/detect_rc_gaps.md)
for the same junction check with more diagnostic detail.

## Examples

``` r
# C on the upper limb (2.410481) is chosen so the two equations agree
# exactly at their shared boundary stage (1.2) -- a genuinely gap-free
# table, the precondition this function checks for.
rating_dt <- data.table::data.table(
  lower_level = c(0.0, 1.2), upper_level = c(1.2, 2.5),
  C = c(2.5, 2.410481), a = c(0, 0), n = c(1.5, 1.7)
)
rating_table <- FlodeRatingTable(table = rating_dt)
discharge_dt <- data.table::data.table(discharge = c(1.0, 5.0, 20.0))
apply_rating_inverse(rating_table, discharge_dt)
#> INFO [2026-09-01 13:45:17] apply_rating_inverse(): 1 of 3 discharge value(s) fell outside the rating and were extrapolated.
#>    discharge     stage extrapolated
#>        <num>     <num>       <lgcl>
#> 1:         1 0.5428835        FALSE
#> 2:         5 1.5360025        FALSE
#> 3:        20 3.4717214         TRUE
```
