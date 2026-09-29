# Package index

## Using a rating

Apply a fitted rating to a stage record, invert it, and compare it with
the rating it replaces. The guided workflow (read_gaugings(),
validate_gaugings(), fit_rating(), assess_rating(), export_rating()) is
planned; see IMPROVEMENT_PLAN.md.

- [`apply_rating()`](https://jonpayneea.github.io/reach.rate/reference/apply_rating.md)
  : Apply a fitted rating to a stage series (S7 generic)
- [`apply_rating_inverse()`](https://jonpayneea.github.io/reach.rate/reference/apply_rating_inverse.md)
  : Invert a rating: convert discharge back to stage
- [`compare_ratings()`](https://jonpayneea.github.io/reach.rate/reference/compare_ratings.md)
  : Compare two rating equation tables
- [`plot_rating_comparison()`](https://jonpayneea.github.io/reach.rate/reference/plot_rating_comparison.md)
  : Plot a rating comparison: curves and their discharge difference

## Advanced modelling

Direct control over fitting. Until fit_rating() arrives, rate_optimise()
is the entry point. suggest_breakpoints() proposes statistical
candidates only; whether a breakpoint marks a real change of control is
a hydraulic judgement.

- [`rate_optimise()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise.md)
  : Fit a multi-limb power-law rating curve
- [`rate_optimise_constrained()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise_constrained.md)
  : Fit a multi-limb rating with junction continuity built into the fit
- [`rate_optimise_segmented()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise_segmented.md)
  : Fit a rating curve with Hodson et al. (2024)'s segmented
  parameterisation
- [`suggest_breakpoints()`](https://jonpayneea.github.io/reach.rate/reference/suggest_breakpoints.md)
  : Suggest candidate stage breakpoints for a multi-limb rating fit
- [`align_limb_equations()`](https://jonpayneea.github.io/reach.rate/reference/align_limb_equations.md)
  : Align rating-curve limb equations so junctions match exactly
- [`align_limb_boundaries()`](https://jonpayneea.github.io/reach.rate/reference/align_limb_boundaries.md)
  : Relocate a junction to where two limb equations actually cross
- [`graft_rating()`](https://jonpayneea.github.io/reach.rate/reference/graft_rating.md)
  : Graft a freshly-fitted rating onto a pre-existing one above its
  gauged range

## Diagnostics

Residuals, extrapolation, influence, and the discharge gaps left where
independently-fitted limbs meet.

- [`plot_rating_residuals()`](https://jonpayneea.github.io/reach.rate/reference/plot_rating_residuals.md)
  : Plot rating fit residuals by limb
- [`flag_extrapolated_limbs()`](https://jonpayneea.github.io/reach.rate/reference/flag_extrapolated_limbs.md)
  : Flag rating limbs that extrapolate substantially beyond their
  gaugings
- [`flag_influential_gaugings()`](https://jonpayneea.github.io/reach.rate/reference/flag_influential_gaugings.md)
  : Flag gaugings that disproportionately steer their limb's fit
- [`plot_rating_leverage()`](https://jonpayneea.github.io/reach.rate/reference/plot_rating_leverage.md)
  : Plot each gauging's leverage against its influence on the fit
- [`detect_rc_gaps()`](https://jonpayneea.github.io/reach.rate/reference/detect_rc_gaps.md)
  : Detect discharge gaps between rating-curve limbs
- [`plot_rc_gaps()`](https://jonpayneea.github.io/reach.rate/reference/plot_rc_gaps.md)
  : Diagnostic plot for rating-curve gap detection and resolution

## Uncertainty

Bootstrap coefficient draws propagated to a discharge interval.

- [`apply_rating_interval()`](https://jonpayneea.github.io/reach.rate/reference/apply_rating_interval.md)
  : Apply a rating with bootstrap uncertainty to a stage series
- [`plot_rating_interval()`](https://jonpayneea.github.io/reach.rate/reference/plot_rating_interval.md)
  : Plot a fitted rating curve with a bootstrap prediction interval
- [`bootstrap_to_table()`](https://jonpayneea.github.io/reach.rate/reference/bootstrap_to_table.md)
  : Convert a fit's bootstrap draws into apply_rating_interval()'s input

## Plotting

- [`rating_plot()`](https://jonpayneea.github.io/reach.rate/reference/rating_plot.md)
  : Plot a fitted rating curve (S7 generic)
- [`plot_rating_curves()`](https://jonpayneea.github.io/reach.rate/reference/plot_rating_curves.md)
  : Overlay multiple fitted ratings' curves for quick comparison

## Specialist hydraulics

Ratings and discharges derived from channel or structure geometry rather
than fitted to gaugings: Manning’s equation on a surveyed cross-section,
and standard weir and flume equations with GUM-style propagated
uncertainty.

- [`rate_from_cross_section()`](https://jonpayneea.github.io/reach.rate/reference/rate_from_cross_section.md)
  : Derive a theoretical rating from a surveyed cross-section (Manning's
  equation)
- [`plot_rating_cross_section()`](https://jonpayneea.github.io/reach.rate/reference/plot_rating_cross_section.md)
  : Overlay a surveyed cross-section on a fitted rating's own plot
- [`weir_discharge_rectangular()`](https://jonpayneea.github.io/reach.rate/reference/weir_discharge_rectangular.md)
  : Discharge over a full-width (suppressed) rectangular sharp-crested
  weir
- [`weir_discharge_vnotch()`](https://jonpayneea.github.io/reach.rate/reference/weir_discharge_vnotch.md)
  : Discharge over a V-notch (triangular) sharp-crested weir
- [`weir_discharge_cipoletti()`](https://jonpayneea.github.io/reach.rate/reference/weir_discharge_cipoletti.md)
  : Discharge over a Cipoletti (trapezoidal) sharp-crested weir
- [`flume_discharge_parshall()`](https://jonpayneea.github.io/reach.rate/reference/flume_discharge_parshall.md)
  : Discharge through a standard Parshall flume (free flow)

## Conversion and rating tables

Move between a fitted rating and its equation-table form, patch junction
gaps at table level, and apply ratings that changed over time.

- [`as_rating_table()`](https://jonpayneea.github.io/reach.rate/reference/as_rating_table.md)
  : Convert a fit to gap_check's equation-table representation (S7
  generic)
- [`expand_rating_table()`](https://jonpayneea.github.io/reach.rate/reference/expand_rating_table.md)
  : Expand a rating equation table into a stage-discharge data.table
- [`resolve_rc_gaps()`](https://jonpayneea.github.io/reach.rate/reference/resolve_rc_gaps.md)
  : Resolve discharge gaps between rating-curve limbs
- [`apply_rating_versioned()`](https://jonpayneea.github.io/reach.rate/reference/apply_rating_versioned.md)
  : Apply a versioned rating to a stage time series

## Rating objects

The S7 classes behind every fit. Accessor functions (planned) will
replace direct property access in user code.

- [`FlodeRatingBase()`](https://jonpayneea.github.io/reach.rate/reference/FlodeRatingBase.md)
  : Abstract base class for a fitted rating (S7)
- [`FlodeRating()`](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md)
  : A fitted multi-limb rating curve (S7)
- [`FlodeSegmentedRating()`](https://jonpayneea.github.io/reach.rate/reference/FlodeSegmentedRating.md)
  : A fitted segmented rating curve, Hodson et al. (2024)
  parameterisation (S7)
- [`FlodeRatingTable()`](https://jonpayneea.github.io/reach.rate/reference/FlodeRatingTable.md)
  : A rating equation table (S7), gap_check's native representation

## Teaching tools

Demonstrations on synthetic data, for learning the package rather than
building a rating from your own evidence.

- [`run_demo()`](https://jonpayneea.github.io/reach.rate/reference/run_demo.md)
  : Run the fit -\> flag -\> expand -\> detect -\> resolve -\> plot
  pipeline
- [`rating_curve_explorer()`](https://jonpayneea.github.io/reach.rate/reference/rating_curve_explorer.md)
  : Launch the interactive rating curve explorer
- [`demo_cross_section_rating()`](https://jonpayneea.github.io/reach.rate/reference/demo_cross_section_rating.md)
  : Demonstrate a river cross-section against its rating curve
- [`station_gaugings`](https://jonpayneea.github.io/reach.rate/reference/station_gaugings.md)
  : Spot gaugings for a real UK gauging station

## Deprecated

Still working, but scheduled for removal. Each page names its
replacement.

- [`suggested_breakpoints_vector()`](https://jonpayneea.github.io/reach.rate/reference/suggested_breakpoints_vector.md)
  : Extract the selected breakpoints from suggest_breakpoints() as a
  vector
