# Relocate a junction to where two limb equations actually cross

[`align_limb_equations()`](https://jonpayneea.github.io/reach.rate/reference/align_limb_equations.md)
and
[`resolve_rc_gaps()`](https://jonpayneea.github.io/reach.rate/reference/resolve_rc_gaps.md)
both close a junction gap by changing a *value* (a rescaled `C`, or a
patched discharge) at a *fixed* junction stage.
`align_limb_boundaries()` does the opposite: it leaves every limb's
`C`/`a`/`n` completely untouched, and instead moves the junction stage
itself to wherever the two limbs' curves genuinely cross – the stage `H`
solving `C_lower*(H-a_lower)^ n_lower = C_upper*(H-a_upper)^n_upper`. At
that stage the two unchanged curves already agree, so nothing about
either equation needs to change.

Unlike
[`align_limb_equations()`](https://jonpayneea.github.io/reach.rate/reference/align_limb_equations.md)'s
rescale (which needs a fixed anchor limb and propagates outward, since
rescaling one limb changes the reference point for the next), boundary
relocation has no such dependency: because no equation is ever changed,
junction `i`'s crossing depends only on limbs `i` and `i + 1`,
regardless of what happens at any other junction. Every junction is
resolved independently – there is no `anchor_limb` argument. By default
every junction is attempted; pass `junctions` to restrict this to
specific ones, leaving every other junction's boundary untouched (and
silent – no "no crossing" warning is possible for a junction that was
never attempted).

The search for a crossing is bounded to the union of the two limbs' own
existing stage ranges (never extrapolated further than either limb was
actually fitted over), and above both limbs' zero-flow stage so
`(H - a)^n` stays real-valued. When no crossing exists in that range –
the curves may not cross at all, or only outside where either was fitted
– that junction is left unchanged and a warning is issued rather than
the whole call failing.

## Usage

``` r
align_limb_boundaries(rating_dt, junctions = NULL)
```

## Arguments

- rating_dt:

  A
  [FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md),
  a
  [FlodeRatingTable](https://jonpayneea.github.io/reach.rate/reference/FlodeRatingTable.md),
  or a plain data.frame/data.table with columns `lower_level`,
  `upper_level`, `C`, `a`, `n` (the same shape expected by
  [`expand_rating_table()`](https://jonpayneea.github.io/reach.rate/reference/expand_rating_table.md)
  and
  [`align_limb_equations()`](https://jonpayneea.github.io/reach.rate/reference/align_limb_equations.md)).
  Limbs must be contiguous: `upper_level[i]` must equal
  `lower_level[i + 1]`.

- junctions:

  Integer vector, or `NULL` (default). Which junctions to attempt,
  numbered the same way as
  [`detect_rc_gaps()`](https://jonpayneea.github.io/reach.rate/reference/detect_rc_gaps.md)'s
  `junction` column (`1` = between limbs 1 and 2, `2` = between limbs 2
  and 3, and so on). `NULL` attempts every junction, as before. Any
  other junction is left completely unchanged – useful for leaving a
  junction alone deliberately (a known-good join, or one better handled
  by
  [`align_limb_equations()`](https://jonpayneea.github.io/reach.rate/reference/align_limb_equations.md)
  instead) even where a crossing exists.

## Value

If `rating_dt` was a
[FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md),
a new
[FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md)
with `@status` `"post_fit_aligned"`, `@previous` referencing the exact
original fit, `@gaugings` with `limb` **reclassified** against the
relocated boundaries (a moved junction can shift which limb a gauging
belongs to, on either side of it), and `@limbs` diagnostics recomputed
from those reclassified gaugings – never left describing a limb's old
gauging composition. `@bootstrap`/ `@fit_starts` are dropped (with a
warning if either was present), since they describe a fit that no longer
applies. Otherwise (a plain table or an already-constructed
[FlodeRatingTable](https://jonpayneea.github.io/reach.rate/reference/FlodeRatingTable.md)),
a
[FlodeRatingTable](https://jonpayneea.github.io/reach.rate/reference/FlodeRatingTable.md)
with `@status` `"post_fit_aligned"` and `@previous` referencing the
exact pre-alignment object this was built from (`NULL` if `rating_dt`
was a plain table with no prior `FlodeRatingTable` identity).

Either way, `@limbs`/`@table` gains columns:
`lower_level_original`/`upper_level_original` (renamed
`lower_stage_m_original`/`upper_stage_m_original` on a `FlodeRating`
result, to match its own naming) – the input boundaries, unchanged – and
`boundary_adjusted` (logical; `TRUE` for a limb whose boundary actually
moved). `C`, `a`, and `n` are always unchanged – only the boundaries are
ever moved. Neither the input nor the output is ever mutated in place.

## See also

[`align_limb_equations()`](https://jonpayneea.github.io/reach.rate/reference/align_limb_equations.md)
for closing a junction by rescaling `C` at a fixed stage instead of
moving the stage;
[`resolve_rc_gaps()`](https://jonpayneea.github.io/reach.rate/reference/resolve_rc_gaps.md)
for the discretised-table-only equivalent;
[`expand_rating_table()`](https://jonpayneea.github.io/reach.rate/reference/expand_rating_table.md)

## Examples

``` r
# A small, realistic gap at the breakpoint (limb 2 reads ~5% high there)
rating_dt <- data.table::data.table(
  lower_level = c(0.0, 1.2),
  upper_level = c(1.2, 4.0),
  C = c(2.5, 2.554),
  a = c(0.0, 0.0),
  n = c(1.50, 1.65)
)
relocated_result <- align_limb_boundaries(rating_dt)
relocated_result@table[, .(lower_level, upper_level, boundary_adjusted)]
#>    lower_level upper_level boundary_adjusted
#>          <num>       <num>            <lgcl>
#> 1:   0.0000000   0.8672163              TRUE
#> 2:   0.8672163   4.0000000              TRUE

# A three-limb table, restricting relocation to junction 2 only (between
# limbs 2 and 3) -- junction 1 is left untouched even though a crossing
# exists there too
rating_dt3 <- data.table::data.table(
  lower_level = c(0.0, 1.2, 2.5),
  upper_level = c(1.2, 2.5, 4.0),
  C = c(2.5, 2.554, 2.337325),
  a = c(0.0, 0.0, 0.0),
  n = c(1.50, 1.65, 1.80)
)
partial_result <- align_limb_boundaries(rating_dt3, junctions = 2L)
partial_result@table[, .(lower_level, upper_level, boundary_adjusted)]
#>    lower_level upper_level boundary_adjusted
#>          <num>       <num>            <lgcl>
#> 1:    0.000000    1.200000             FALSE
#> 2:    1.200000    1.805837              TRUE
#> 3:    1.805837    4.000000              TRUE
```
