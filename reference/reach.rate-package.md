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

## Examples

``` r
# The core route: gaugings in, a rating out, discharge from stage.
set.seed(1)
stage_m <- seq(0.3, 3, by = 0.06)
discharge_cms <- 3.2 * stage_m^1.6 * exp(rnorm(length(stage_m), sd = 0.04))

fit <- rate_optimise(discharge_cms, stage_m)
rating_limbs(fit)                 # the equation, Q = C (H - a)^n
#>     limb lower_stage_m upper_stage_m        C           a        n
#>    <int>         <num>         <num>    <num>       <num>    <num>
#> 1:     1           0.3             3 3.239463 0.003173067 1.588281
rating_diagnostics(fit)           # how well it fits
#>     limb rmse_cms rmse_pct r_squared n_obs n_unique_stage mean_error_cms
#>    <int>    <num>    <num>     <num> <int>          <int>          <num>
#> 1:     1 0.276629 3.402609  0.997422    46             46   2.225893e-05
#>    median_abs_error_cms max_abs_error_cms residual_df n_starts_attempted
#>                   <num>             <num>       <int>              <int>
#> 1:            0.1435385         0.6700753          43                  6
#>    n_starts_converged selected_start_id near_bound converged convergence_code
#>                 <int>             <int>     <lgcl>    <lgcl>            <int>
#> 1:                  6                 1      FALSE      TRUE                1
#>                                        convergence_message iterations
#>                                                     <char>      <int>
#> 1: Relative error in the sum of squares is at most `ftol'.          8
#>    objective_value bound_hits multi_start_spread parameter_correlation
#>              <num>     <char>              <num>                 <num>
#> 1:        3.520085                  4.685671e-07             0.9904851
#>    condition_number
#>               <num>
#> 1:         49.30602
rating_support(fit)               # how much rests on gaugings
#>          range lower_stage_m upper_stage_m n_evidence
#>         <char>         <num>         <num>      <int>
#> 1:    observed           0.3  3.000000e+00         46
#> 2:    modelled            NA            NA          0
#> 3:      fitted           0.3  3.000000e+00         NA
#> 4: operational            NA            NA         NA
#> 5:   numerical          -Inf 5.745585e+193         NA
#>                                                                                                  basis
#>                                                                                                 <char>
#> 1:                                                         gaugings: evidence of source type 'gauging'
#> 2: evidence of any other source type (modelled, cross-section, structure equation, operational rating)
#> 3:                                                     the stage range the equations are declared over
#> 4:                                                            not stated; see set_operational_limits()
#> 5:                         where the equations give a finite discharge; beyond it apply_rating() fails

apply_rating(fit, c(0.8, 1.6, 2.4))
#>    stage discharge extrapolated                support
#>    <num>     <num>       <lgcl>                 <char>
#> 1:   0.8  2.258455        FALSE interpolation_observed
#> 2:   1.6  6.812454        FALSE interpolation_observed
#> 3:   2.4 12.985023        FALSE interpolation_observed
rating_plot(fit)

```
