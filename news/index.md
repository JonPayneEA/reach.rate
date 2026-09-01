# Changelog

## reach.rate 0.1.0

- Initial release: the `rating_curves` toolkit, converted from a set of
  standalone `box` modules into the `reach.rate` package.
  - [`rate_optimise()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise.md)
    /
    [`rate_optimise_constrained()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise_constrained.md):
    multi-limb power-law rating fitting by nonlinear least squares, with
    multi-start fitting and bootstrap coefficient uncertainty.
  - [`rate_optimise_segmented()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise_segmented.md):
    a joint segmented parameterisation after Hodson et al. (2024), with
    no junction gap to reconcile.
  - [`expand_rating_table()`](https://jonpayneea.github.io/reach.rate/reference/expand_rating_table.md),
    [`detect_rc_gaps()`](https://jonpayneea.github.io/reach.rate/reference/detect_rc_gaps.md),
    [`resolve_rc_gaps()`](https://jonpayneea.github.io/reach.rate/reference/resolve_rc_gaps.md),
    [`align_limb_equations()`](https://jonpayneea.github.io/reach.rate/reference/align_limb_equations.md),
    [`plot_rc_gaps()`](https://jonpayneea.github.io/reach.rate/reference/plot_rc_gaps.md):
    junction-gap detection and resolution between independently-fitted
    limbs.
  - [`apply_rating()`](https://jonpayneea.github.io/reach.rate/reference/apply_rating.md),
    [`apply_rating_interval()`](https://jonpayneea.github.io/reach.rate/reference/apply_rating_interval.md),
    [`apply_rating_versioned()`](https://jonpayneea.github.io/reach.rate/reference/apply_rating_versioned.md):
    convert a fitted rating (or a bootstrap of one, or a rating history)
    into a discharge time series.
  - [`compare_ratings()`](https://jonpayneea.github.io/reach.rate/reference/compare_ratings.md)
    /
    [`plot_rating_comparison()`](https://jonpayneea.github.io/reach.rate/reference/plot_rating_comparison.md):
    document a rating amendment.
  - `FlodeRating`, `FlodeSegmentedRating`, `FlodeRatingTable`: S7
    classes carrying gaugings, fitting bookkeeping, and provenance
    alongside every fitted rating.
  - [`demo_cross_section_rating()`](https://jonpayneea.github.io/reach.rate/reference/demo_cross_section_rating.md),
    [`rating_curve_explorer()`](https://jonpayneea.github.io/reach.rate/reference/rating_curve_explorer.md):
    worked examples and an interactive Shiny explorer of the rating
    equation.
  - [`vignette("rating_curves_guide")`](https://jonpayneea.github.io/reach.rate/articles/rating_curves_guide.md):
    the full theory-and-usage guide.
