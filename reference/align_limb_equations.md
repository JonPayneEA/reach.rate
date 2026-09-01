# Align rating-curve limb equations so junctions match exactly

[`resolve_rc_gaps()`](https://jonpayneea.github.io/reach.rate/reference/resolve_rc_gaps.md)
only patches the discretised stage-discharge table produced by
[`expand_rating_table()`](https://jonpayneea.github.io/reach.rate/reference/expand_rating_table.md).
That fix does not survive re-expanding the same rating equations, or
evaluating them directly – the underlying `C`/`a`/`n` triples are
untouched, so the gap reappears.

`align_limb_equations()` corrects the equations themselves instead. It
rescales the `C` coefficient of every limb except one fixed anchor,
propagating outward limb by limb: each limb's `C` is set so that its
discharge at the junction with its *already-corrected* neighbour matches
exactly. `a` and `n` are left untouched, so each limb keeps its fitted
shape and zero-flow datum; only the scale changes.

Because each limb is anchored on one junction and its other junction is
resolved by correcting the *next* limb along the chain, an interior limb
with gaps on both sides is handled without needing a stage- dependent
taper – every junction in the chain ends up exact.

The original `C` is always kept (as `C_original`) alongside the
corrected value, and an `aligned` flag marks which limbs were changed,
so the amendment is auditable rather than a silent overwrite.

## Usage

``` r
align_limb_equations(
  rating_dt,
  anchor_limb = 1L,
  on_align_failure = c("error", "skip")
)
```

## Arguments

- rating_dt:

  A
  [FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md),
  a
  [FlodeRatingTable](https://jonpayneea.github.io/reach.rate/reference/FlodeRatingTable.md),
  or a plain data.frame/data.table with columns `lower_level`,
  `upper_level`, `C`, `a`, `n` (the same shape expected by
  [`expand_rating_table()`](https://jonpayneea.github.io/reach.rate/reference/expand_rating_table.md);
  for a legacy rating with no prior `FlodeRatingTable` identity of its
  own). Limbs must be contiguous: `upper_level[i]` must equal
  `lower_level[i + 1]`.

- anchor_limb:

  Integer. Row index of the limb held fixed; every other limb is
  corrected relative to it, propagating outward in both directions along
  the chain. Default `1L` (the lowest limb, typically the best-gauged
  one).

- on_align_failure:

  Character. What to do when a limb's own fixed `a` (zero-flow datum)
  sits at or beyond the junction stage it would need to align to –
  `depth = junction_stage - a` non-positive, so no real-valued `C`
  solves `C * depth^n = target` – or the solved `C` comes out non-finite
  or non-positive. This is a real possibility whenever gaugings (and so
  `a`) can be negative, not a sign of malformed input:
  independently-fitted limbs can end up with a datum that just doesn't
  reach a neighbour's junction. `"error"` (default) stops immediately,
  as before. `"skip"` warns, leaves that limb's `C` at its original
  (unaligned) value, flags it in the new `align_failed` column, and
  continues aligning the rest of the chain from there – the same "keep
  what worked, don't discard everything over one bad limb" fallback
  [`rate_optimise_constrained()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise_constrained.md)
  already uses for its own refit failures.

## Value

If `rating_dt` was a
[FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md),
a new
[FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md)
with `@status` `"post_fit_aligned"`, `@previous` referencing the exact
original fit, `@gaugings` unchanged (equations were rescaled, not
boundaries, so gauging/limb membership never changes here), and `@limbs`
diagnostics (`rmse_cms`, `r_squared`, and friends) recomputed against
the amended `C` – never left stale. `@bootstrap`/ `@fit_starts` are
dropped (with a warning if either was present), since they describe a
fit that no longer applies. Otherwise (a plain table or an
already-constructed
[FlodeRatingTable](https://jonpayneea.github.io/reach.rate/reference/FlodeRatingTable.md)),
a
[FlodeRatingTable](https://jonpayneea.github.io/reach.rate/reference/FlodeRatingTable.md)
with `@status` `"post_fit_aligned"` and `@previous` referencing the
exact pre-alignment object this was built from (`NULL` if `rating_dt`
was a plain table with no prior `FlodeRatingTable` identity) – a genuine
audit chain, not an attribute someone has to remember to check.

Either way, `@limbs`/`@table` gains columns: `C_original` (the input
`C`, unchanged), `aligned` (logical; `TRUE` only for a limb that was
actually rescaled – `FALSE` for `anchor_limb` and, under
`on_align_failure = "skip"`, for any limb that failed to align),
`align_failed` (logical; `TRUE` for a skipped limb, always `FALSE` under
the default `on_align_failure = "error"` since that stops instead),
`scale_factor` (`C / C_original`), `pct_change` (percentage change in
`C`), `alignment_stage` (the junction stage this limb was aligned at),
and `target_discharge` (the discharge it was aligned to match). The last
four are `NA` wherever `aligned` is `FALSE`. `C` itself is replaced by
the aligned value for every successfully-aligned limb; `a` and `n` are
always unchanged. Neither the input nor the output is ever mutated in
place.

## See also

[`expand_rating_table()`](https://jonpayneea.github.io/reach.rate/reference/expand_rating_table.md),
[`resolve_rc_gaps()`](https://jonpayneea.github.io/reach.rate/reference/resolve_rc_gaps.md),
[`rate_optimise_constrained()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise_constrained.md)
(in the `rate_optimise` module) for a genuine constrained refit against
the raw gaugings, rather than this function's closed-form C-only rescale
of the already-fitted equations – use that instead when the raw gaugings
are available; this remains useful when only the fitted equations are
(an imported legacy rating, for instance)

## Examples

``` r
rating_dt <- data.table::data.table(
  lower_level = c(0.0, 1.2, 2.5),
  upper_level = c(1.2, 2.5, 4.0),
  C = c(2.5, 4.1, 7.8),
  a = c(0.0, 0.0, 0.0),
  n = c(1.50, 1.70, 2.00)
)
aligned_result <- align_limb_equations(rating_dt)
aligned_result
#> <FlodeRatingTable> 3 limb(s), status: post_fit_aligned
#>    lower_level upper_level        C     a     n C_original aligned align_failed
#>          <num>       <num>    <num> <num> <num>      <num>  <lgcl>       <lgcl>
#> 1:         0.0         1.2 2.500000     0   1.5        2.5   FALSE        FALSE
#> 2:         1.2         2.5 2.410481     0   1.7        4.1    TRUE        FALSE
#> 3:         2.5         4.0 1.831141     0   2.0        7.8    TRUE        FALSE
#>    scale_factor pct_change alignment_stage target_discharge
#>           <num>      <num>           <num>            <num>
#> 1:           NA         NA              NA               NA
#> 2:    0.5879223  -41.20777             1.2         3.286335
#> 3:    0.2347617  -76.52383             2.5        11.444630
aligned_result@status
#> [1] "post_fit_aligned"

# The aligned equations, re-expanded, have no junction gaps left --
# expand_rating_table() accepts the FlodeRatingTable directly
rc_dt <- expand_rating_table(aligned_result)
gaps_dt <- detect_rc_gaps(rc_dt)
#> INFO [2026-09-01 11:09:58] Checked 2 junction(s): 0 gap(s) flagged.
any(gaps_dt$gap_flagged)
#> [1] FALSE
```
