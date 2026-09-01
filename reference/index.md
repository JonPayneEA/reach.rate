# Package index

## Fitting a rating

Fit a multi-limb power-law rating by nonlinear least squares, and find
breakpoints rather than guess them.

- [`rate_optimise()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise.md)
  : Fit a multi-limb power-law rating curve
- [`rate_optimise_constrained()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise_constrained.md)
  : Fit a multi-limb rating with junction continuity built into the fit
- [`suggest_breakpoints()`](https://jonpayneea.github.io/reach.rate/reference/suggest_breakpoints.md)
  : Suggest candidate stage breakpoints for a multi-limb rating fit
- [`suggested_breakpoints_vector()`](https://jonpayneea.github.io/reach.rate/reference/suggested_breakpoints_vector.md)
  : Extract the selected breakpoints from suggest_breakpoints() as a
  vector
- [`rate_from_cross_section()`](https://jonpayneea.github.io/reach.rate/reference/rate_from_cross_section.md)
  : Derive a theoretical rating from a surveyed cross-section (Manning's
  equation)

## Weir and flume equations

Physically-derived discharge from structure geometry, not fitted to
gaugings, with GUM-style propagated uncertainty.

- [`weir_discharge_rectangular()`](https://jonpayneea.github.io/reach.rate/reference/weir_discharge_rectangular.md)
  : Discharge over a full-width (suppressed) rectangular sharp-crested
  weir
- [`weir_discharge_vnotch()`](https://jonpayneea.github.io/reach.rate/reference/weir_discharge_vnotch.md)
  : Discharge over a V-notch (triangular) sharp-crested weir
- [`weir_discharge_cipoletti()`](https://jonpayneea.github.io/reach.rate/reference/weir_discharge_cipoletti.md)
  : Discharge over a Cipoletti (trapezoidal) sharp-crested weir
- [`flume_discharge_parshall()`](https://jonpayneea.github.io/reach.rate/reference/flume_discharge_parshall.md)
  : Discharge through a standard Parshall flume (free flow)

## The segmented alternative

A joint model with no junction gap to reconcile, after Hodson et
al. (2024).

- [`rate_optimise_segmented()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise_segmented.md)
  : Fit a rating curve with Hodson et al. (2024)'s segmented
  parameterisation

## Diagnosing a fit

- [`plot_rating_residuals()`](https://jonpayneea.github.io/reach.rate/reference/plot_rating_residuals.md)
  : Plot rating fit residuals by limb
- [`flag_extrapolated_limbs()`](https://jonpayneea.github.io/reach.rate/reference/flag_extrapolated_limbs.md)
  : Flag rating limbs that extrapolate substantially beyond their
  gaugings
- [`flag_influential_gaugings()`](https://jonpayneea.github.io/reach.rate/reference/flag_influential_gaugings.md)
  : Flag gaugings that disproportionately steer their limb's fit
- [`plot_rating_leverage()`](https://jonpayneea.github.io/reach.rate/reference/plot_rating_leverage.md)
  : Plot each gauging's leverage against its influence on the fit
- [`plot_rating_cross_section()`](https://jonpayneea.github.io/reach.rate/reference/plot_rating_cross_section.md)
  : Overlay a surveyed cross-section on a fitted rating's own plot
- [`demo_cross_section_rating()`](https://jonpayneea.github.io/reach.rate/reference/demo_cross_section_rating.md)
  : Demonstrate a river cross-section against its rating curve

## The junction gap problem

Independently-fitted limbs rarely meet exactly. Detect the resulting
discharge gap and close it — by patching the table, rescaling a limb’s
equation, or relocating the boundary to where the curves actually cross.

- [`detect_rc_gaps()`](https://jonpayneea.github.io/reach.rate/reference/detect_rc_gaps.md)
  : Detect discharge gaps between rating-curve limbs
- [`resolve_rc_gaps()`](https://jonpayneea.github.io/reach.rate/reference/resolve_rc_gaps.md)
  : Resolve discharge gaps between rating-curve limbs
- [`align_limb_equations()`](https://jonpayneea.github.io/reach.rate/reference/align_limb_equations.md)
  : Align rating-curve limb equations so junctions match exactly
- [`align_limb_boundaries()`](https://jonpayneea.github.io/reach.rate/reference/align_limb_boundaries.md)
  : Relocate a junction to where two limb equations actually cross
- [`plot_rc_gaps()`](https://jonpayneea.github.io/reach.rate/reference/plot_rc_gaps.md)
  : Diagnostic plot for rating-curve gap detection and resolution
- [`expand_rating_table()`](https://jonpayneea.github.io/reach.rate/reference/expand_rating_table.md)
  : Expand a rating equation table into a stage-discharge data.table
- [`graft_rating()`](https://jonpayneea.github.io/reach.rate/reference/graft_rating.md)
  : Graft a freshly-fitted rating onto a pre-existing one above its
  gauged range

## Coefficient uncertainty

Bootstrap resampling, propagated through to a discharge interval.

- [`bootstrap_to_table()`](https://jonpayneea.github.io/reach.rate/reference/bootstrap_to_table.md)
  : Convert a fit's bootstrap draws into apply_rating_interval()'s input
- [`plot_rating_interval()`](https://jonpayneea.github.io/reach.rate/reference/plot_rating_interval.md)
  : Plot a fitted rating curve with a bootstrap prediction interval
- [`apply_rating_interval()`](https://jonpayneea.github.io/reach.rate/reference/apply_rating_interval.md)
  : Apply a rating with bootstrap uncertainty to a stage series

## Using a rating

Convert between stage and discharge, and handle a rating that has
changed over time.

- [`apply_rating()`](https://jonpayneea.github.io/reach.rate/reference/apply_rating.md)
  : Apply a fitted rating to a stage series (S7 generic)
- [`apply_rating_inverse()`](https://jonpayneea.github.io/reach.rate/reference/apply_rating_inverse.md)
  : Invert a rating: convert discharge back to stage
- [`apply_rating_versioned()`](https://jonpayneea.github.io/reach.rate/reference/apply_rating_versioned.md)
  : Apply a versioned rating to a stage time series
- [`as_rating_table()`](https://jonpayneea.github.io/reach.rate/reference/as_rating_table.md)
  : Convert a fit to gap_check's equation-table representation (S7
  generic)

## Comparing ratings

- [`compare_ratings()`](https://jonpayneea.github.io/reach.rate/reference/compare_ratings.md)
  : Compare two rating equation tables
- [`plot_rating_comparison()`](https://jonpayneea.github.io/reach.rate/reference/plot_rating_comparison.md)
  : Plot a rating comparison: curves and their discharge difference

## Shared generics and classes

One name per operation, dispatched by whichever representation you’re
holding.

- [`rating_plot()`](https://jonpayneea.github.io/reach.rate/reference/rating_plot.md)
  : Plot a fitted rating curve (S7 generic)
- [`plot_rating_curves()`](https://jonpayneea.github.io/reach.rate/reference/plot_rating_curves.md)
  : Overlay multiple fitted ratings' curves for quick comparison
- [`FlodeRatingBase()`](https://jonpayneea.github.io/reach.rate/reference/FlodeRatingBase.md)
  : Abstract base class for a fitted rating (S7)
- [`FlodeRating()`](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md)
  : A fitted multi-limb rating curve (S7)
- [`FlodeSegmentedRating()`](https://jonpayneea.github.io/reach.rate/reference/FlodeSegmentedRating.md)
  : A fitted segmented rating curve, Hodson et al. (2024)
  parameterisation (S7)
- [`FlodeRatingTable()`](https://jonpayneea.github.io/reach.rate/reference/FlodeRatingTable.md)
  : A rating equation table (S7), gap_check's native representation

## Interactive tools and demos

- [`rating_curve_explorer()`](https://jonpayneea.github.io/reach.rate/reference/rating_curve_explorer.md)
  : Launch the interactive rating curve explorer
- [`run_demo()`](https://jonpayneea.github.io/reach.rate/reference/run_demo.md)
  : Run the fit -\> flag -\> expand -\> detect -\> resolve -\> plot
  pipeline

## Example data

- [`station_gaugings`](https://jonpayneea.github.io/reach.rate/reference/station_gaugings.md)
  : Spot gaugings for a real UK gauging station
