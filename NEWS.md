# reach.rate (development)

* `inst/examples/walkthrough.R` gains steps 22-26, covering functions
  that shipped after its last pass: `rate_from_cross_section()` (with
  the `plot_rating_cross_section()` overlay actually shown, not just the
  fitted coefficients), the weir/flume equations, `flag_influential_
  gaugings()`/`plot_rating_leverage()`, `age_halflife` recency weighting
  on a drifting-channel example, and `apply_rating_inverse()` round-
  tripped against `apply_rating()`.

* New `vignette("s7_objects_guide")`: the last gap from the same
  vignette-coverage audit. Covers the class hierarchy (`FlodeRatingBase`
  abstract, `FlodeRating`/`FlodeSegmentedRating` as children,
  `FlodeRatingTable` separate), `@`-access and `print()`, a validator
  catching a malformed construction, `S7_inherits()` for writing code
  that accepts either a fit or a table, walking the `@status`/`@previous`
  audit chain with real code, and the three shared generics
  (`rating_plot()`/`apply_rating()`/`as_rating_table()`). Previously the
  entire documentation set had exactly one sentence on any of this.

* `rate_optimise()` and `rate_optimise_segmented()` gain opt-in recency
  weighting: `age_halflife`, `age_min_weight`, `reference_datetime`.
  Each gauging's residual is weighted by exponential decay from its age
  (relative to `reference_datetime`, defaulting to the dataset's own
  most recent gauging) down to a floor (`age_min_weight`) that stops any
  gauging -- including a limb's one high-flow flood -- ever being
  weighted to near-zero purely for being old; not magnitude-aware (an
  old extreme and an old ordinary gauging decay identically), so this is
  a partial answer to issue #9, not the full one. `age_halflife = NULL`
  (default) fits unweighted, exactly as before -- supplying
  `gauging_datetime` alone still changes nothing about the fit.
  `rate_optimise_constrained()` forwards the new arguments through `...`,
  same as `gauging_datetime` itself already does. `@gaugings` gains an
  `age_weight` column when `age_halflife` is used. New
  `vignette("recency_weighting_guide")` covers the full formula and a
  worked example on a station whose channel has genuinely drifted.

* New `vignette("objective_guide")`: absolute vs. relative fitting
  objectives, with a diagram of the implied per-gauging weight each one
  uses (flat for absolute; approximately `1/Q^2` for relative, via the
  standard first-order log-residual approximation) -- the mechanism
  behind `non_standard_optimisation.Rmd`'s existing `objective =
  "relative"` coverage, not previously diagrammed.

* New `vignette("segmented_model_guide")`: how
  `rate_optimise_segmented()`'s multiplicative segments actually compose,
  with each factor plotted separately to show the "inert until its own
  breakpoint" property the formula states but didn't previously
  illustrate, and a side-by-side comparison against independently-fitted
  limbs showing why the segmented model has no junction gap to reconcile.

* New functions `flag_influential_gaugings()` and `plot_rating_leverage()`:
  per-gauging leverage and Cook's distance, adapted to `rate_optimise()`'s
  nonlinear fit via the standard local-linearisation trick (the fitted
  model's Jacobian w.r.t. `C`/`a`/`n`, evaluated at each gauging, in place
  of a design matrix). Answers a question `plot_rating_residuals()`
  can't: not how far off a gauging ends up after fitting, but how much
  it shaped the fit to begin with -- a gauging isolated at the sparse end
  of a limb can have high leverage regardless of how small its residual
  looks. `flag_influential_gaugings()` returns a new `FlodeRating` with
  `@gaugings` columns added (`leverage`, `cooks_distance`, `influential`,
  using standard rule-of-thumb cutoffs); `plot_rating_leverage()` plots
  both quantities per limb. New `vignette("leverage_influence_guide")`
  explains the two diagnostics in plain language, with a worked example
  showing how much a single flagged gauging can move a fitted
  coefficient.

* New module `R/weir_equations.R`: four standard weir/flume discharge
  functions -- `weir_discharge_rectangular()` (Rehbock, full-width
  sharp-crested; ISO 1438:2017), `weir_discharge_vnotch()`
  (Kindsvater-Shen triangular notch), `weir_discharge_cipoletti()`
  (trapezoidal, USBR), and `flume_discharge_parshall()` (standard 1-8 ft
  throat widths). Physically-derived from structure geometry, not fitted
  to gaugings -- deliberately outside `FlodeRating`/`FlodeRatingTable`.
  Each propagates a GUM-style (JCGM 100:2008) uncertainty from a
  required `u_cd` (discharge coefficient's relative standard
  uncertainty) and `u_head_m` (head measurement's absolute standard
  uncertainty) -- both required, not defaulted, since a fabricated
  default would look authoritative without being traceable to anything.
  `flume_discharge_parshall()` also checks the standard free-flow
  submergence limit when a downstream head is supplied, erroring rather
  than silently applying the free-flow equation to submerged conditions.
  New `vignette("weir_flume_guide")` covers the four structures (with
  diagrams), the equations and their sourcing, and the GUM propagation
  in detail.

* New function `rate_from_cross_section()`: derives a theoretical rating
  from a surveyed channel cross-section via Manning's equation, with no
  gaugings required. Wetted area and perimeter are found by trapezoidal
  integration of the surveyed points at a dense sequence of stages, and
  the resulting synthetic `(stage, discharge)` series is fitted through
  `rate_optimise()`'s own pipeline, so the result is an ordinary
  `FlodeRating` -- distinguished from a gauged fit only by
  `provenance$source == "cross_section_theoretical"`. A standalone
  diagnostic for now (a first-cut rating at an ungauged site, or a
  physically-grounded check on a surveyed section's implied shape);
  composes directly with `plot_rating_cross_section()`, since both take
  the same `cross_section` object.

* New function `apply_rating_inverse()`: the other direction from
  `apply_rating()` -- given a discharge series, finds the stage that
  produced it. Requires a gap-free `FlodeRatingTable` (checked directly
  from the equations at each junction, erroring and naming the junction
  otherwise, rather than guessing at an ambiguous inverse); discharge
  `<= 0` returns `NA` with a warning, since it has no unique inverse
  stage. Not valid for tidal/backwater stations where stage-discharge
  isn't single-valued -- a documented limitation.

* `rate_optimise()`'s `@limbs` gains `rmse_pct` (a relative/percentage
  RMSE alongside the existing absolute `rmse_cms`, always computed
  regardless of `objective`) and `C_se_asymp`/`a_se_asymp`/`n_se_asymp`
  (closed-form asymptotic parameter standard errors from the fit's own
  NLS covariance matrix, always computed -- a free fallback when
  `n_boot = 0`, distinct from the bootstrap-only `C_se`/`a_se`/`n_se`).
  `rate_optimise_constrained()` recomputes all four for any limb it
  actually refits (via the delta method for the SEs, since that refit's
  own model has only `a`/`n` as free parameters) and leaves
  `anchor_limb`'s untouched; `align_limb_equations()`/
  `align_limb_boundaries()` recompute `rmse_pct` and NA out the three
  `*_se_asymp` columns, the same discipline already applied to
  `near_bound`.

* New function `plot_rating_cross_section()`: overlays a real surveyed
  channel cross-section on a real fitted rating's own plot, rescaling
  the survey's distance onto the discharge axis (with a secondary axis
  giving the true distance scale back) so the channel's shape and the
  rating's shape sit on one figure. Complements
  `demo_cross_section_rating()`, which stays a fixed synthetic
  illustration.

* New function `graft_rating()`: joins a freshly-fitted rating onto a
  pre-existing one used above the newly gauged range, finding the stage
  where the two curves actually cross (reusing the same crossing search
  `align_limb_boundaries()` uses for a junction inside one table) and
  combining them into one contiguous `FlodeRatingTable`. Distinct from
  `align_limb_equations()`/`align_limb_boundaries()`, which reconcile a
  junction within one already-built table rather than joining two
  independently-sourced ratings.

* New vignette `n_bounds_guide`: a visual companion to
  `non_standard_optimisation`'s `n_bounds` demonstration, with idealised
  cross-section diagrams for the rectangular/V-notch/wide-channel control
  families, a log-log plot showing why the control's shape sets the
  exponent, a compound-channel diagram illustrating why distinct regimes
  need separate `n_bounds` calls, and a practical starting-bounds table.

* New bundled example dataset `station_gaugings`: a real spot-gauging
  record for a UK gauging station, 1974-2024 (223 gaugings), included to
  demonstrate `rate_optimise()` against actual station messiness rather
  than only synthetic data -- irregular gauging intervals, decades-long
  gaps, and one gauging recorded at zero stage. See `?station_gaugings`.

* **Breaking change**: `align_limb_equations()` and
  `align_limb_boundaries()`, given a `FlodeRating` (the bridge added in a
  previous release this same development cycle), now return a new
  `FlodeRating` instead of downgrading to a `FlodeRatingTable`. This
  keeps the amendment inside `FlodeRating` -- gaugings, an audit chain,
  and diagnostics -- rather than losing all of that the moment a rating
  gets aligned.
  - `@gaugings` is carried forward (`limb` membership **reclassified**
    against relocated boundaries for `align_limb_boundaries()`, since a
    moved junction can shift which limb a gauging belongs to; unchanged
    for `align_limb_equations()`, which never moves boundaries).
  - `@limbs` diagnostics (`rmse_cms`, `r_squared`, `n_obs`, and friends)
    are recomputed against the amended equations, never left describing
    the pre-amendment fit.
  - `@bootstrap` and `@fit_starts` are dropped (with a warning if either
    was present) -- they describe a fit that no longer applies, the same
    discipline `rate_optimise_constrained()` already applies to its own
    refit.
  - `@previous` references the exact original `FlodeRating` (a new
    `previous` property added to `FlodeRatingBase`, so `FlodeRating` and
    `FlodeSegmentedRating` both now carry this).
  - A plain data.frame/data.table or an already-constructed
    `FlodeRatingTable` input is unaffected -- still returns a
    `FlodeRatingTable`, exactly as before.
  - Direct payoff: `rating_plot()` and `plot_rating_residuals()` (both
    written for `FlodeRating`) now work immediately on an aligned result,
    with no new arguments or functions needed.
* `expand_rating_table()` now accepts a `FlodeRating` directly (bridged
  via `as_rating_table()`), matching `align_limb_equations()`/
  `align_limb_boundaries()`'s existing bridge.

* **Breaking change**: `rate_optimise()` and `rate_optimise_constrained()`
  now fit `Q = C(H - a)^n` instead of `Q = C(H + a)^n`. This unifies the
  fitting engine's convention with `FlodeRatingTable`'s equation-table
  representation (`gap_check`, `apply_rating`), which already used
  `Q = C(H - a)^n` -- the two sides of the toolkit previously used
  opposite-signed offsets, bridged by an explicit (and easy to get
  backwards) sign flip inside `as_rating_table()`/`bootstrap_to_table()`.
  That bridge is now a straight, unflipped copy.
  - Every `a` coefficient a fit reports (`fit@limbs$a`, bootstrap draws,
    `@fit_starts`) is the negative of what the same data would have
    produced before this change. `C` and `n` are unaffected.
  - If you have saved `FlodeRating` objects, re-fit them rather than
    reusing the stored coefficients under the new convention.
  - `FlodeRatingTable`'s own coefficients, `apply_rating()`,
    `expand_rating_table()`, `align_limb_equations()`, and
    `align_limb_boundaries()` are unaffected -- they already used this
    convention.

# reach.rate 0.1.0

* Initial release: the `rating_curves` toolkit, converted from a set of
  standalone `box` modules into the `reach.rate` package.
  - `rate_optimise()` / `rate_optimise_constrained()`: multi-limb
    power-law rating fitting by nonlinear least squares, with
    multi-start fitting and bootstrap coefficient uncertainty.
  - `rate_optimise_segmented()`: a joint segmented parameterisation
    after Hodson et al. (2024), with no junction gap to reconcile.
  - `expand_rating_table()`, `detect_rc_gaps()`, `resolve_rc_gaps()`,
    `align_limb_equations()`, `plot_rc_gaps()`: junction-gap detection
    and resolution between independently-fitted limbs.
  - `apply_rating()`, `apply_rating_interval()`,
    `apply_rating_versioned()`: convert a fitted rating (or a bootstrap
    of one, or a rating history) into a discharge time series.
  - `compare_ratings()` / `plot_rating_comparison()`: document a rating
    amendment.
  - `FlodeRating`, `FlodeSegmentedRating`, `FlodeRatingTable`: S7
    classes carrying gaugings, fitting bookkeeping, and provenance
    alongside every fitted rating.
  - `demo_cross_section_rating()`, `rating_curve_explorer()`: worked
    examples and an interactive Shiny explorer of the rating equation.
  - `vignette("rating_curves_guide")`: the full theory-and-usage guide.
