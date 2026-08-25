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
