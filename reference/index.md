# Package index

## Reading data

Bring a gauging archive and an operational ratings export into R without
cleaning them. Every row is kept; what did not parse is noted on the
row. match_stations() links the two files’ station ids, with a table you
supply where the ids differ, and check_operational_ratings() compares
every rating with its gaugings and lists what could not be compared.
read_gaugings() takes delimited text, a spreadsheet or a data.frame, and
read_summary() reports what it found as a table.

- [`read_gaugings()`](https://jonpayneea.github.io/reach.rate/reference/read_gaugings.md)
  : Read a spot-gauging archive
- [`read_summary()`](https://jonpayneea.github.io/reach.rate/reference/read_summary.md)
  : What a read found, as a table
- [`read_operational_ratings()`](https://jonpayneea.github.io/reach.rate/reference/read_operational_ratings.md)
  : Read an operational ratings export
- [`operational_rating_tables()`](https://jonpayneea.github.io/reach.rate/reference/operational_rating_tables.md)
  : Turn operational rating limbs into rating tables
- [`match_stations()`](https://jonpayneea.github.io/reach.rate/reference/match_stations.md)
  : Match gauging stations to rating stations
- [`check_operational_ratings()`](https://jonpayneea.github.io/reach.rate/reference/check_operational_ratings.md)
  : Check every operational rating against its gaugings

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

## Accessors

Read a rating without reaching inside it. Each accessor works on every
rating class that holds the information, returns a copy as a data.table
with unit-suffixed columns (or a documented list), and says plainly when
a class does not hold it.

- [`rating_limbs()`](https://jonpayneea.github.io/reach.rate/reference/rating_limbs.md)
  : Limbs of a rating
- [`rating_coefficients()`](https://jonpayneea.github.io/reach.rate/reference/rating_coefficients.md)
  : Coefficients of a rating, with their uncertainty
- [`rating_evidence()`](https://jonpayneea.github.io/reach.rate/reference/rating_evidence.md)
  : The gaugings a rating was fitted to
- [`rating_diagnostics()`](https://jonpayneea.github.io/reach.rate/reference/rating_diagnostics.md)
  : Fit diagnostics of a rating
- [`rating_support()`](https://jonpayneea.github.io/reach.rate/reference/rating_support.md)
  : Gauged support for a rating
- [`rating_bootstrap()`](https://jonpayneea.github.io/reach.rate/reference/rating_bootstrap.md)
  : Bootstrap draws of a rating
- [`rating_history()`](https://jonpayneea.github.io/reach.rate/reference/rating_history.md)
  : The audit chain of a rating
- [`rating_provenance()`](https://jonpayneea.github.io/reach.rate/reference/rating_provenance.md)
  : How a rating was made

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
- [`extend_rating_low()`](https://jonpayneea.github.io/reach.rate/reference/extend_rating_low.md)
  : Add a linear limb below the lowest limb of a rating

## Diagnostics

Residuals, extrapolation, influence, a rating checked against a set of
gaugings, and the discharge gaps left where independently-fitted limbs
meet.

- [`plot_rating_residuals()`](https://jonpayneea.github.io/reach.rate/reference/plot_rating_residuals.md)
  : Plot rating fit residuals by limb
- [`compare_gaugings_to_rating()`](https://jonpayneea.github.io/reach.rate/reference/compare_gaugings_to_rating.md)
  : Compare a rating with a set of gaugings
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

The S7 classes behind every fit. Read them through the accessors above,
not by property; vignette(“s7_objects_guide”) is the maintainer’s guide
to how they are built.

- [`FlodeRatingBase()`](https://jonpayneea.github.io/reach.rate/reference/FlodeRatingBase.md)
  : Abstract base class for a fitted rating (S7)
- [`FlodeRating()`](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md)
  : A fitted multi-limb rating curve (S7)
- [`FlodeSegmentedRating()`](https://jonpayneea.github.io/reach.rate/reference/FlodeSegmentedRating.md)
  : A fitted segmented rating curve, Hodson et al. (2024)
  parameterisation (S7)
- [`FlodeRatingTable()`](https://jonpayneea.github.io/reach.rate/reference/FlodeRatingTable.md)
  : A rating equation table (S7), gap_check's native representation
- [`FlodeEvidence()`](https://jonpayneea.github.io/reach.rate/reference/FlodeEvidence.md)
  : Evidence a rating rests on (S7)
- [`as_flode_evidence()`](https://jonpayneea.github.io/reach.rate/reference/as_flode_evidence.md)
  : Make evidence from a plain table
- [`evidence_source_types()`](https://jonpayneea.github.io/reach.rate/reference/evidence_source_types.md)
  : The controlled vocabulary for where evidence came from
- [`rating_schema_version()`](https://jonpayneea.github.io/reach.rate/reference/rating_schema_version.md)
  : The schema version of rating objects

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
- [`bootstrap_to_table()`](https://jonpayneea.github.io/reach.rate/reference/bootstrap_to_table.md)
  : Convert a fit's bootstrap draws into apply_rating_interval()'s input
