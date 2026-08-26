# reach.rate (development)

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
