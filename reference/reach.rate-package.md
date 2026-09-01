# reach.rate: fit, diagnose, and apply hydrometric rating curves

Tools for fitting multi-limb power-law stage-discharge rating curves by
nonlinear least squares
([`rate_optimise()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise.md)),
diagnosing fit quality
([`plot_rating_residuals()`](https://jonpayneea.github.io/reach.rate/reference/plot_rating_residuals.md),
[`flag_extrapolated_limbs()`](https://jonpayneea.github.io/reach.rate/reference/flag_extrapolated_limbs.md)),
detecting and resolving discontinuities between independently-fitted
limbs
([`detect_rc_gaps()`](https://jonpayneea.github.io/reach.rate/reference/detect_rc_gaps.md),
[`resolve_rc_gaps()`](https://jonpayneea.github.io/reach.rate/reference/resolve_rc_gaps.md),
[`align_limb_equations()`](https://jonpayneea.github.io/reach.rate/reference/align_limb_equations.md)),
converting a fitted rating into a discharge time series
([`apply_rating()`](https://jonpayneea.github.io/reach.rate/reference/apply_rating.md)),
and documenting rating amendments
([`compare_ratings()`](https://jonpayneea.github.io/reach.rate/reference/compare_ratings.md)).
[`rate_optimise_segmented()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise_segmented.md)
offers a structurally different, joint segmented parameterisation after
Hodson et al. (2024), with no junction gap to reconcile in the first
place.

Fitted ratings are represented as S7 classes
([FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md),
[FlodeSegmentedRating](https://jonpayneea.github.io/reach.rate/reference/FlodeSegmentedRating.md),
[FlodeRatingTable](https://jonpayneea.github.io/reach.rate/reference/FlodeRatingTable.md))
that carry their own gaugings, fitting bookkeeping, and provenance – see
[`vignette("rating_curves_guide", package = "reach.rate")`](https://jonpayneea.github.io/reach.rate/articles/rating_curves_guide.md)
for the full walkthrough and the hydrological reasoning behind the
toolkit's design choices.

## See also

Useful links:

- <https://github.com/JonPayneEA/reach.rate>

- <https://jonpayneea.github.io/reach.rate/>

- Report bugs at <https://github.com/JonPayneEA/reach.rate/issues>

## Author

**Maintainer**: Jonathan Payne <jonathan.payne1988@gmail.com>
