# reach.rate

Tools for fitting, diagnosing, and applying hydrometric rating curves:
multi-limb power-law fitting by nonlinear least squares, junction-gap
detection and resolution between independently-fitted limbs, a segmented
joint-model alternative (Hodson et al. 2024), bootstrap and closed-form
coefficient uncertainty, leverage/influence diagnostics, opt-in
age-based recency weighting, versioned ratings, and rating-amendment
comparison. Beyond gauging-based fitting: a Manning’s-equation rating
from a surveyed cross-section alone, and standard weir/flume discharge
equations (rectangular, V-notch, Cipoletti, Parshall flume) with
GUM-style propagated uncertainty.

Fitted ratings are represented as
[S7](https://rconsortium.github.io/S7/) classes (`FlodeRating`,
`FlodeSegmentedRating`, `FlodeRatingTable`) that carry their own
gaugings, fitting bookkeeping, and provenance, so a rating is never
separated from the data and assumptions that produced it.

## Installation

This package is not on CRAN. Install the development version from
GitHub:

``` r

# install.packages("remotes")
remotes::install_github("JonPayneEA/reach.rate", build_vignettes = TRUE)
```

## Rating curve essentials

The essentials from
[`vignette("rating_curves_guide")`](https://jonpayneea.github.io/reach.rate/articles/rating_curves_guide.md)
– enough theory to read the example below against, not the full guide.

### What a rating curve is

A river gauging station measures water level continuously. It does not
measure flow. Level (stage) is cheap: a pressure transducer or a float
in a stilling well, logging every fifteen minutes for decades. Flow
(discharge) is expensive: someone has to stand in or above the river
with a current meter or an ADCP and measure it directly. A single
discharge measurement is called a gauging, and a typical station
accumulates a few dozen to a few hundred of them over its life.

The rating curve is the bridge between the two. It is a fitted
relationship that converts the continuous stage record into a continuous
discharge record, calibrated against the occasional gaugings. Every flow
statistic you have ever used from a gauging station, every QMED, every
flood peak in HiFlows, passed through a rating curve on its way to you.
The quality of the rating bounds the quality of everything downstream of
it.

**The equation.** This toolkit fits the standard hydrometric form:

``` math
Q = C\,(H - a)^{n}
```

where $`Q`$ is discharge (m³/s), $`H`$ is stage (m), and $`C`$, $`a`$,
$`n`$ are fitted coefficients. The offset $`a`$ deserves a moment. Stage
is measured against an arbitrary local datum, not against the point
where flow actually ceases. The quantity $`H - a`$ converts stage to
effective head above the level of zero flow, and it is head, not raw
stage, that drives flow through a control. When $`H - a \le 0`$ the
river is below its zero-flow level and $`Q = 0`$ by definition.

**Why a power law.** The power law is not a curve-fitting convenience –
it is what open-channel hydraulics predicts. Flow over a rectangular
weir goes as head to the power 1.5; over a V-notch, head to the power
2.5; Manning’s equation for a wide channel gives discharge roughly as
depth to the power 5/3. Every common control produces discharge as head
raised to some exponent between about 1.3 and 2.5, with $`C`$ absorbing
the geometry and roughness (Herschy 2009; Rantz et al. 1982). A useful
property follows: on log axes the power law is a straight line,
$`\log Q = \log C + n \log(H - a)`$, with slope $`n`$ – why a change of
slope on that plot signals a change of physical control.

**A convention.** Throughout this toolkit, plots put discharge on the x
axis and stage on the y axis – the hydrometric convention, reading the
rating the way the station uses it.

### Why ratings have limbs

A single power law describes a single control. Real channels change
control as they fill. At low flow the station may be controlled by a
gravel riffle or a weir crest immediately downstream (a section
control). As stage rises the riffle drowns out and the friction of the
channel itself takes over (channel control). Higher still, the river
tops its banks and the floodplain begins to convey flow, changing the
effective geometry entirely.

Each regime approximates a different power law. The standard response is
a multi-limb rating: the stage range is split at breakpoints, and each
limb gets its own $`C`$, $`a`$, $`n`$. The breakpoints should correspond
to real physical transitions – a berm, a bank top, a bypass channel
activating – and choosing them is a hydrological judgement, not a
statistical one
([`suggest_breakpoints()`](https://jonpayneea.github.io/reach.rate/reference/suggest_breakpoints.md),
covered in the full guide, is an aid, not a substitute).

### The objects

The toolkit represents its results as three
[S7](https://rconsortium.github.io/S7/) classes rather than bare tables.
The practical consequence for you as a user is small: you access
contents with `@` rather than `$`, and the objects carry more than
numbers.

- `FlodeRating` is the result of
  [`rate_optimise()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise.md).
  `@limbs` holds one row per limb (bounds, coefficients, diagnostics),
  `@gaugings` holds the data it was fitted to, `@bootstrap` and
  `@fit_starts` hold uncertainty and fitting bookkeeping when produced,
  `@status` records whether the fit is as fitted or has been amended,
  and `@provenance` records how it was made.
- `FlodeSegmentedRating` is the result of
  [`rate_optimise_segmented()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise_segmented.md),
  a structurally different joint model with no junction gap to reconcile
  (see the full guide).
- `FlodeRatingTable` is the equation-table representation used for gap
  checking and application: `lower_level`, `upper_level`, `C`, `a`, `n`
  per limb, same names and sign convention as `FlodeRating`’s `@limbs`.
  It carries `@status` and `@previous`, so an amended table references
  the exact object it was amended from – an audit trail by construction,
  not by discipline.

Three shared generics work across the classes:
[`rating_plot()`](https://jonpayneea.github.io/reach.rate/reference/rating_plot.md)
draws whichever fit you hand it,
[`apply_rating()`](https://jonpayneea.github.io/reach.rate/reference/apply_rating.md)
converts stage to discharge with whichever representation you hold, and
[`as_rating_table()`](https://jonpayneea.github.io/reach.rate/reference/as_rating_table.md)
converts a fit to the table form. The class system chooses the right
implementation; you use one name.

A fit remembers its own gaugings deliberately: every diagnostic,
residual plot, and bootstrap in this toolkit needs the original data,
and a rating separated from its gaugings is a rating you can no longer
question.

### Fitting: `rate_optimise()`

[`rate_optimise()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise.md)
fits each limb by nonlinear least squares: it finds the $`C`$, $`a`$,
$`n`$ minimising the residual sum of squares
$`\mathrm{RSS} = \sum_{i}\left(Q_i - C\,(H_i - a)^n\right)^2`$ over that
limb’s gaugings, using the Levenberg-Marquardt algorithm (Levenberg
1944; Marquardt 1963) as implemented in
[`minpack.lm::nlsLM`](https://rdrr.io/pkg/minpack.lm/man/nlsLM.html).

Why not just take logs and fit a straight line by ordinary regression?
Because the two minimise different things. Log-space regression
minimises relative error, which treats a 10% miss at 2 m³/s and a 10%
miss at 200 m³/s as equally bad. Least squares in real space minimises
absolute error, so the high-flow gaugings dominate the fit – for flood
forecasting, where the cost of error is concentrated at high flows,
real-space fitting is usually the right default, but be aware of the
choice you are inheriting: your low-flow fit is being traded for your
high-flow fit.

The fit is constrained so that $`C > 0`$, $`n > 0`$, and $`H - a > 0`$
for every gauging in the limb, fencing off territory where no valid
rating exists. By default (`multi_start = TRUE`) each limb is fitted
from several starting combinations rather than one, since a poor guess
can strand the optimiser in a local minimum; every attempt is recorded
in `@fit_starts`, and the `near_bound` column flags a fit whose `n` or
`a` finished pressed against its bound, worth a second look.

## Getting started

A complete, runnable example on synthetic data – a three-limb rating
station, gauged independently limb by limb (as real stations usually
are), which is exactly the situation that produces the junction gaps
[`detect_rc_gaps()`](https://jonpayneea.github.io/reach.rate/reference/detect_rc_gaps.md)
exists to catch:

``` r

library(reach.rate)
library(data.table)

# Pseudo gaugings for a three-limb rating station
set.seed(42)
stage_m <- seq(0.5, 3.5, by = 0.03)
true_limb <- cut(
  stage_m,
  breaks = c(0.5, 1.6, 2.2, 3.5),
  labels = FALSE, include.lowest = TRUE
)
true_coefs <- data.frame(C = c(3, 6, 10), a = c(0, 0.1, 0.2), n = c(1.4, 1.6, 1.8))
discharge_cms <- true_coefs$C[true_limb] *
  (stage_m - true_coefs$a[true_limb])^true_coefs$n[true_limb] +
  rnorm(length(stage_m), sd = 0.05)

# Fit a multi-limb power-law rating curve: Q = C(H - a)^n per limb
fit <- rate_optimise(discharge_cms, stage_m, control = c(1.6, 2.2))
fit@limbs[, .(limb, C, a, n, rmse_cms, r_squared)]

rating_plot(fit)

# Independently-fitted limbs rarely meet exactly at their junctions --
# detect the resulting discharge gap
rating_table <- as_rating_table(fit)
rc_dt <- expand_rating_table(rating_table, step = 0.01)
detect_rc_gaps(rc_dt)

# ...and close it, either at the table level or in the equations themselves
rc_fixed_dt <- resolve_rc_gaps(rc_dt)
aligned_table <- align_limb_equations(rating_table)

# Apply the (aligned) rating to a stage record to get a discharge record
hydrograph <- data.frame(stage = seq(0.8, 3.2, length.out = 10))
apply_rating(aligned_table, hydrograph)
```

For the full walkthrough – theory, every function, and the reasoning
behind the toolkit’s design choices – see:

``` r

vignette("rating_curves_guide", package = "reach.rate")
```

For one continuous worked example – spot gaugings to a single bad curve
to a checked, junction-aligned, physically-constrained multi-limb rating
– see:

``` r

vignette("rating_curve_walkthrough", package = "reach.rate")
```

For two flow diagrams showing which of the five ways to build a rating
fits your data, and what genuinely differs downstream between a
`FlodeRating` and a `FlodeSegmentedRating`, see:

``` r

vignette("rating_methods_overview", package = "reach.rate")
```

For when and why to reach for non-default fitting (`objective`,
`n_bounds`, and opt-in `age_halflife` recency weighting), see:

``` r

vignette("non_standard_optimisation", package = "reach.rate")
```

For what `objective = "relative"` actually does differently underneath,
with diagrams, see:

``` r

vignette("objective_guide", package = "reach.rate")
```

For how to read a channel cross-section into a starting `n_bounds`, with
diagrams of the canonical control shapes, see:

``` r

vignette("n_bounds_guide", package = "reach.rate")
```

For discharge from a weir or flume’s own published equation and
geometry, with GUM-style uncertainty, see:

``` r

vignette("weir_flume_guide", package = "reach.rate")
```

For which gaugings are quietly steering a fit, beyond what residuals
alone show, see:

``` r

vignette("leverage_influence_guide", package = "reach.rate")
```

For the maths behind `age_halflife`, on a station whose channel has
drifted over time, see:

``` r

vignette("recency_weighting_guide", package = "reach.rate")
```

For how
[`rate_optimise_segmented()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise_segmented.md)’s
multiplicative factors actually compose, with diagrams, see:

``` r

vignette("segmented_model_guide", package = "reach.rate")
```

For working with the package’s S7 classes – `@`-access, validators,
`S7_inherits()`, the `@status`/`@previous` audit chain – see:

``` r

vignette("s7_objects_guide", package = "reach.rate")
```

or run the linear, section-by-section script at:

``` r

system.file("examples", "walkthrough.R", package = "reach.rate")
```

## Development

This package was assembled from a set of standalone box modules; see
`NEWS.md` for a summary and each `R/` file’s header comment for the
file-by-file conversion notes. If you have R and roxygen2 available
locally, regenerate `NAMESPACE` and `man/` from the roxygen comments
already in `R/`:

``` r

devtools::document()
devtools::test()
devtools::check()
```
