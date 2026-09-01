# Fit a multi-limb rating with junction continuity built into the fit

[`rate_optimise()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise.md)
fits each limb independently, which is exactly why junction gaps exist
to detect
([`detect_rc_gaps()`](https://jonpayneea.github.io/reach.rate/reference/detect_rc_gaps.md))
and two ways exist to close them
([`resolve_rc_gaps()`](https://jonpayneea.github.io/reach.rate/reference/resolve_rc_gaps.md)'s
table patch,
[`align_limb_equations()`](https://jonpayneea.github.io/reach.rate/reference/align_limb_equations.md)'s
`C`-only rescale). Neither of those two produces an *optimised* rating
once gaps are closed. This does the constrained version properly:
starting from
[`rate_optimise()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise.md)'s
independent fit, every limb except `anchor_limb` is *refit* against its
own gaugings, subject to matching its already-finalised neighbour's
discharge exactly at their shared junction stage – propagating outward
from the anchor exactly as
[`align_limb_equations()`](https://jonpayneea.github.io/reach.rate/reference/align_limb_equations.md)
does. The constraint is enforced by reparameterising the model:
`Q = Q_target * ((H - a) / (brk - a))^n`, which equals `Q_target` at
`H = brk` for any `a`/`n`, so `nlsLM` is free to optimise both over the
limb's own gaugings while continuity holds automatically.

## Usage

``` r
rate_optimise_constrained(
  discharge_cms,
  stage_m,
  control = NULL,
  anchor_limb = 1L,
  n_bounds = NULL,
  ...
)
```

## Arguments

- discharge_cms, stage_m, control, n_bounds:

  As in
  [`rate_optimise()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise.md).
  Unlike `objective`, `n_bounds` is honoured by *both* the initial fit
  and this function's own constrained refit, since a hydraulic bound on
  `n` should hold for every limb, not just the anchor.

- anchor_limb:

  Integer. Row index of the limb left unconstrained. Default `1L`.

- ...:

  Passed to
  [`rate_optimise()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise.md)'s
  initial (unconstrained) fit – this includes `gauging_datetime`, which
  needs no special handling here since it's simply stored on
  `@gaugings`, not used by either function's fitting itself. It also
  includes `objective`, which applies to the initial fit (and so to
  `anchor_limb`, which is never refit) – the constrained refit this
  function performs for every other limb uses its own reparameterised,
  absolute-residual-only formula regardless of `objective`. `n_boot` is
  accepted but the resulting bootstrap draws describe the
  *unconstrained* fit and are dropped with a warning rather than
  presented alongside updated point estimates; `fit_starts` is dropped
  silently for the same reason. `n_starts_attempted`/
  `n_starts_converged`/`selected_start_id` are set to `NA` and
  `near_bound`/`rmse_pct`/`C_se_asymp`/`a_se_asymp`/`n_se_asymp` are
  recomputed for any limb this function actually refits (the latter
  three via the delta method, since this refit's own model has only
  `a`/`n` as free parameters), since the constrained refit is always
  single-start. `anchor_limb`'s own diagnostics, including these, are
  untouched – it was never refit.

## Value

A
[FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md)
instance in the same shape as
[`rate_optimise()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise.md)'s,
plus an `aligned` logical column in `@limbs` (`FALSE` for `anchor_limb`,
`TRUE` for every refit limb) and `@status` `"constrained_refit"`. If a
constrained refit fails to converge for some limb, that limb's original
unconstrained fit is kept and a warning is issued.

## See also

[`rate_optimise()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise.md),
[`align_limb_equations()`](https://jonpayneea.github.io/reach.rate/reference/align_limb_equations.md)
(in the `gap_check` module) for the closed-form, no-refit alternative
