# Rating methods research

Research and proposal only – no code, tests, or vignettes are touched by
this document. It evaluates five directions Jonathan raised against
`reach.rate`’s actual architecture (`R/flode_classes.R`,
`R/rate_optimise.R`, `R/rate_optimise_segmented.R`, `R/gap_check.R`,
`R/apply_rating.R`), in the same spirit as
[ROADMAP.md](https://jonpayneea.github.io/reach.rate/ROADMAP.md) and
[ROBUST_FITTING.md](https://jonpayneea.github.io/reach.rate/ROBUST_FITTING.md):
one section per idea, a concrete recommendation, and a short “what this
would take” note. Citations are included for every substantive claim;
where a claim could not be verified (a paywalled standard, an
inaccessible page) that is stated rather than guessed at.

## 1. Weir/flume equations, with uncertainty

**What the literature says.** Standard weir and flume discharge formulae
are physically-derived equations from structure geometry, not fitted
curves: sharp-crested rectangular and V-notch/triangular weirs are
covered by ISO 1438:2017 (rectangular and triangular thin-plate weirs);
Cipoletti weirs (trapezoidal, sides sloped 1 horizontal to 4 vertical,
compensating for side contraction so the calibration matches an
equivalent suppressed rectangular weir) and Parshall/H-flumes are
covered in the USBR *Water Measurement Manual*. I did not verify a
specific ISO number for flumes in this pass – treat that as an open
question, not an established fact.

Uncertainty for these structures is **analytic, not empirical**: ISO
1438 expresses it as a percentage-uncertainty budget – `u*(Cd)`
(uncertainty in the discharge coefficient), `u*(h1)` (uncertainty in
measured head), and an expanded combined uncertainty `U` – combined in
quadrature (a standard GUM/ISO-GUM propagation, not a statistical fit to
gaugings). A 2021 Parshall-flume study (Ferreira et al.,
*ScienceDirect*, S2665-9174(21)000714) quantified this concretely with
Monte Carlo propagation: well-built lab flumes reach roughly ±2%, but
realistic field installations run ±3-5% once dimensional tolerance,
approach turbulence, and debris/maintenance are accounted for, and the
choice of fixed vs. correlated model parameters alone shifted results by
up to 12% in their comparison.

**Fit to `reach.rate`’s architecture.** This genuinely is not a rating
in the sense `FlodeRating`/`FlodeRatingTable` represent: there are no
gaugings to fit against, `C` isn’t estimated by NLS, and the uncertainty
comes from a coefficient table and a propagation formula, not a
bootstrap or a covariance matrix. It doesn’t extend either class
cleanly. It composes well with the toolkit at the table level, though: a
weir equation expressed as a single-row
`lower_level, upper_level, C, a, n` limb is exactly the shape
`FlodeRatingTable`,
[`apply_rating()`](https://jonpayneea.github.io/reach.rate/reference/apply_rating.md),
and – concretely – the just-shipped
[`graft_rating()`](https://jonpayneea.github.io/reach.rate/reference/graft_rating.md)
already expect. A weir-controlled low-flow limb with a fitted upper limb
above it is a real station configuration, and
[`graft_rating()`](https://jonpayneea.github.io/reach.rate/reference/graft_rating.md)
already does the joining; it just has no source of a *structural*
(non-fitted) low limb to graft yet.

**Recommendation.** A new, small, standalone module (e.g.
`R/weir_equations.R`) with one function per structure type
([`weir_discharge_rectangular()`](https://jonpayneea.github.io/reach.rate/reference/weir_discharge_rectangular.md),
[`weir_discharge_vnotch()`](https://jonpayneea.github.io/reach.rate/reference/weir_discharge_vnotch.md),
[`weir_discharge_cipoletti()`](https://jonpayneea.github.io/reach.rate/reference/weir_discharge_cipoletti.md),
[`flume_discharge_parshall()`](https://jonpayneea.github.io/reach.rate/reference/flume_discharge_parshall.md),
…), each taking head and geometry, returning discharge plus an
uncertainty band computed by quadrature propagation of the structure’s
own coefficient and head uncertainties – not a new subclass. A thin
bridge function converting one of these into a one-row
`FlodeRatingTable`-shaped table would let it be handed straight to
[`graft_rating()`](https://jonpayneea.github.io/reach.rate/reference/graft_rating.md),
[`apply_rating()`](https://jonpayneea.github.io/reach.rate/reference/apply_rating.md),
and
[`compare_ratings()`](https://jonpayneea.github.io/reach.rate/reference/compare_ratings.md)
without any of those needing to know a weir equation produced it.

**What this would take.** Medium. The uncertainty-propagation mechanics
are simple and reusable across structure types; the real cost is
sourcing and correctly transcribing each standard’s actual coefficient
tables and uncertainty components, which are only partially accessible
from open search (ISO/BS documents are paywalled past their preview
pages) and deserve a careful, correctness-first pass rather than being
inferred.

## 2. Bayesian methods

**What the literature says.** BaRatin (Le Coz et al. 2014, already cited
in `rating_curves_guide.Rmd`) builds a rating from hydraulic priors on
each control’s power-law parameters, reviewed gaugings, and MCMC
posterior sampling – three explicit steps (define priors, validate
gaugings, infer). Its reference software, BaRatinAGE, is not R. Hodson
et al. (2024)’s `ratingcurve` (Python, already cited, and the source of
[`rate_optimise_segmented()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise_segmented.md)’s
own parameterisation) is the other tool the package already references.

**A closer, previously-unreferenced match: `bdrc`.** *Bayesian Discharge
Rating Curves* (Hrafnkelsson et al. 2022, package on CRAN) is an R
package implementing Bayesian fitting of both the classical power-law
and a *generalized* power-law (exponent `n` varying smoothly with stage
rather than fixed per limb) via four model variants – `plm0`/`plm`
(constant vs. stage-varying log-error variance) and `gplm0`/`gplm` (the
generalized form, same variance choice). This is materially closer prior
art than either BaRatin or `ratingcurve`: it is R, on CRAN, and actively
maintained, so an interop path is far cheaper to build and to keep
working than one to Python or standalone software.

**What `n_bounds` + bootstrap already approximate, and what they
don’t.** `ROBUST_FITTING.md` already states the distinction correctly:
`n_bounds` is a hard/soft box constraint on a frequentist NLS fit, not a
prior – the constrained region is ruled out entirely, not merely
down-weighted – and the bootstrap resamples gaugings and refits,
approximating sampling variability under repeated gauging rather than a
true posterior that starts from hydraulic knowledge and lets sparse data
update it only as far as the data actually supports. That gap is real
and matches exactly what issue \#11 already describes as the package’s
largest, not-yet-started roadmap item.

**Recommendation.** Given `bdrc` already exists, maintained, in R,
building `reach.rate`’s own MCMC engine from scratch is probably not the
best use of effort relative to the value. Two options, independent of
each other: - (a) A bridge, e.g. `from_bdrc()`, wrapping a fitted `bdrc`
object’s posterior summary into a `FlodeRating`-shaped result (or a new
`@posterior` property alongside `@bootstrap`) so the rest of the toolkit
–
[`rating_plot()`](https://jonpayneea.github.io/reach.rate/reference/rating_plot.md),
[`apply_rating()`](https://jonpayneea.github.io/reach.rate/reference/apply_rating.md),
gap-checking – works on a Bayesian-fitted curve too, with `bdrc` in
`Suggests`, not a hard dependency. - (b) At minimum, and independent of
(a) ever being built: cross-reference `bdrc` from
`non_standard_optimisation.Rmd` and `n_bounds_guide.Rmd` as “if you need
a true Bayesian treatment, `reach.rate` doesn’t do this yet – see
`bdrc`.” Zero risk, immediately actionable.

**What this would take.** (a) is medium-to-large – the design work is in
faithfully representing MCMC draws inside `FlodeRating`’s existing
uncertainty conventions without pretending they’re bootstrap draws. (b)
is trivial, a documentation change only.

## 3. Better statistics on curve fitting

**What’s there now.** Per-limb `rmse_cms`, `r_squared`,
`mean_error_cms`, `median_abs_error_cms`, `max_abs_error_cms`, `n_obs`,
`n_unique_stage`, `residual_df`, and (only when `n_boot > 0`)
bootstrap-derived coefficient SEs. There is currently no SE at all when
`n_boot = 0` – an unforced gap, since
[`minpack.lm::nlsLM`](https://rdrr.io/pkg/minpack.lm/man/nlsLM.html)’s
fit object already carries what a standard asymptotic covariance-based
SE needs, at no extra fitting cost.

**What the literature offers beyond this.** - **Heteroscedasticity-aware
reporting.** `bdrc`’s `plm`/`gplm` variants make stage-varying error
variance an explicit, checkable model choice rather than something
inferred only by switching `objective`. A cheap, unconditional
complement: report a relative/percentage RMSE alongside the existing
absolute `rmse_cms` regardless of which `objective` was used to fit –
the vignette already notes both objectives are compared on the absolute
scale, so nothing today shows the relative-error picture directly. -
**An external reference point for “is this fit good.”** WMO’s *Manual on
Stream Gauging* (WMO-No. 1044, 2010), Table I.10.1, gives standard
errors attributable to individual gauging measurement components. A
fitted rating’s own `rmse_cms` currently has no external yardstick;
comparing it against what individual-gauging measurement uncertainty
alone would predict is a genuinely new diagnostic – is the scatter
explained by measurement noise, or does it exceed that (indicating
unmodelled curve-shape error). - **Per-gauging influence, not just
per-limb residuals.** Classical regression leverage/influence
diagnostics (Cook 1977; standard regression-diagnostics theory) are not
rating-curve-specific but are directly adaptable: the NLS design already
used for the covariance-based SE above gives a local linearisation, so
leverage and a leave-one-out-style influence measure are a natural,
tractable addition – currently
[`plot_rating_residuals()`](https://jonpayneea.github.io/reach.rate/reference/plot_rating_residuals.md)
shows every point but not which ones are disproportionately steering a
limb’s fit. - **A practical caution, not a statistic.** New Zealand’s
National Environmental Monitoring Standard for rating curves explicitly
warns against “over-refinement… to obtain good statistical fit” at the
expense of hydraulic validity – worth folding into
`rating_curves_guide.Rmd`’s existing “Guidance: reading a fit, in order”
section as prose, not a new statistic.

**Recommendation.** (1) closed-form asymptotic parameter SEs from the
NLS covariance matrix as an always-available fallback when `n_boot = 0`;
(2) an unconditional relative-RMSE column; (3) a leave-one-out/leverage
diagnostic as its own function; (4) the NEMS caution as a documentation
addition.

**What this would take.** (1) and (2) are small – both derive from
information the fit already computes. (3) is medium, a genuinely new
function. (4) is trivial.

## 4. Inverse application: discharge to stage

**What’s there now.**
[`apply_rating()`](https://jonpayneea.github.io/reach.rate/reference/apply_rating.md)
only converts stage to discharge.

**Why the inverse is mostly straightforward, and where it isn’t.**
Within one limb, `H = a + (Q/C)^(1/n)` is a safe, closed-form inverse:
the package’s own validators already require `C > 0` and `n > 0` for
every limb, which makes `Q = C(H-a)^n` strictly monotonic increasing
over that limb’s domain. The real pitfalls are elsewhere: - **Limb
selection by discharge, not stage.**
[`apply_rating()`](https://jonpayneea.github.io/reach.rate/reference/apply_rating.md)‘s
forward direction picks a limb by where stage falls in
`[lower_level, upper_level]` via
[`findInterval()`](https://rdrr.io/r/base/findInterval.html). The
inverse needs the equivalent lookup on the discharge axis – evaluate
each limb’s own bounds to get its implied discharge range, then find
which range a query discharge falls in. A residual junction gap (exactly
what
[`detect_rc_gaps()`](https://jonpayneea.github.io/reach.rate/reference/detect_rc_gaps.md)
exists to catch) makes this ambiguous in a way the forward direction
never is, since two adjacent limbs’ discharge ranges can then overlap or
leave a hole. - **Genuine non-monotonicity is out of scope, and should
say so.** Tidal or strong-backwater reaches can produce a
stage-discharge relationship that is not single-valued at all (a
documented failure mode in the literature, distinct from anything a
closed-form per-limb inverse can fix). This should be a stated
limitation, not something the function silently mishandles. -
**Uncertainty propagates through the local derivative.** The standard
approach (confirmed in the rating-curve-uncertainty literature) is to
propagate discharge-side uncertainty through the inverse via the local
sensitivity `dH/dQ = 1/(dQ/dH) = 1/(C n (H-a)^{n-1})` – a delta-method
step, not a new fitting exercise, and one that composes with whatever
uncertainty (bootstrap SEs, or a future Bayesian posterior) the forward
fit already carries.

**Recommendation.** A new function,
e.g. `apply_rating_inverse(fit, discharge_dt, ...)`, dispatched the same
way
[`apply_rating()`](https://jonpayneea.github.io/reach.rate/reference/apply_rating.md)
is (matching
[`as_rating_table()`](https://jonpayneea.github.io/reach.rate/reference/as_rating_table.md)’s
own stated preference for a named, tested function per operation over a
mode-switching argument). Require – or at minimum warn loudly on – a
`FlodeRatingTable` that hasn’t been confirmed gap-free via
[`detect_rc_gaps()`](https://jonpayneea.github.io/reach.rate/reference/detect_rc_gaps.md),
since an unresolved gap is exactly what makes the discharge-side lookup
ambiguous. Document the non-monotonic (tidal/backwater) case as
explicitly out of scope rather than leaving it to fail confusingly.

**What this would take.** Small-to-medium. The per-limb algebra is
trivial; the real design decision is the gap-free precondition and its
failure message, not the maths.

## 5. Continuous index/ultrasonic data alongside stage

**What the literature says.** The USGS index-velocity method (Levesque &
Oberg, *Computing Discharge Using the Index Velocity Method*, USGS TM
3-A23) separates discharge into two independent ratings multiplied
together: an index-velocity rating (mean channel velocity as a function
of a measured index velocity – usually simple linear regression, though
more complex forms exist) and a stage-area rating (cross-sectional area
from surveyed geometry as a function of stage), giving
`Q = V(index) x A(stage)`. It is recommended specifically for sites
where a simple stage-discharge power law cannot work at all – backwater,
unsteady or reversing flow, confluences, near hydraulic structures –
which includes the tidal/non-monotonic case flagged in section 4. USGS
reported roughly 470 gauging stations operated this way as of a 2011
source; the true current count is very likely higher and was not
independently verified here.

**Fit to `reach.rate`’s architecture.** This is a genuinely different
model form, not a variant of the existing one: two independent
regressions multiplied, rather than one `Q = C(H-a)^n` equation per
limb. It does not fit as an extension of
`FlodeRating`/`FlodeRatingTable` – their `@limbs`/`@table` shape assumes
exactly one such equation per limb. It does fit the package’s existing
“one generic, several classes” pattern
([`rating_plot()`](https://jonpayneea.github.io/reach.rate/reference/rating_plot.md),
[`apply_rating()`](https://jonpayneea.github.io/reach.rate/reference/apply_rating.md),
[`as_rating_table()`](https://jonpayneea.github.io/reach.rate/reference/as_rating_table.md)
already dispatch on class): a new sibling class under `FlodeRatingBase`
(reusing `@gaugings`/`@status`/`@provenance`/`@previous`) with its own
two-part fit and its own
[`apply_rating()`](https://jonpayneea.github.io/reach.rate/reference/apply_rating.md)
method (taking an index-velocity column alongside stage, not stage
alone) is the natural shape.

**Recommendation, staged.** The full model is a large undertaking; a
much smaller, immediately useful step doesn’t require it at all. Where a
station already has continuous ultrasonic/index data *alongside* its
existing power-law rating, the first genuinely useful “analytics along a
continuous series” is a comparison, not a new fitting method: run
[`apply_rating()`](https://jonpayneea.github.io/reach.rate/reference/apply_rating.md)
on the stage series as today, and diff the result against the
independent continuous discharge series over the same period. That
reuses the existing architecture entirely and surfaces exactly the
question the continuous data is there to answer – is the current
power-law rating still tracking reality – without committing to the
larger class-level investment up front. Build this first; let it justify
(or not) the full `FlodeIndexRating` class based on what it actually
finds at real stations.

**What this would take.** The comparison function: small, entirely
existing machinery. The full index-velocity class: large – a new class,
a new two-part fitting routine, a new
[`apply_rating()`](https://jonpayneea.github.io/reach.rate/reference/apply_rating.md)
method with a different input signature, and new diagnostics suited to
linear regression rather than power-law NLS.

## Other findings

- **The generalized power-law model** (Hrafnkelsson et al. 2022, `bdrc`)
  lets the exponent vary smoothly with stage (continuous `n(h)` and
  `n'(h)`) instead of
  [`rate_optimise()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise.md)’s
  hard breakpoints. This solves the same problem
  [`rate_optimise_segmented()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise_segmented.md)
  (Hodson et al. 2024) already addresses – no junction gap by
  construction – by a different route (smooth exponent vs. joint
  multi-segment formula). Worth a comparison note the next time
  [`rate_optimise_segmented()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise_segmented.md)’s
  own docs are revisited, rather than a new feature on its own; it
  overlaps heavily with section 2’s `bdrc` bridge.
- **Weir equations and
  [`graft_rating()`](https://jonpayneea.github.io/reach.rate/reference/graft_rating.md)
  compound naturally**: a standard-derived, non-fitted low-flow limb
  (section 1) grafted onto a fitted upper rating is exactly the scenario
  [`graft_rating()`](https://jonpayneea.github.io/reach.rate/reference/graft_rating.md)
  (shipped this week) already handles, once such a limb exists to graft.
- **Closed-form asymptotic SEs** (section 3) are worth doing regardless
  of anything else here – pure upside, no new dependency, no design
  risk.

## Suggested priority order

Revised to fold in the further candidate areas above, ranked by effort
against real value rather than by section order.

**Tier 1 – do now (trivial/small, no real downside)**

1.  **Bayesian doc cross-reference to `bdrc`** – trivial, closes the “no
    Bayesian option” gap in the guidance vignettes at zero code risk.
2.  **NEMS over-refinement caution** in the guide vignette – trivial,
    one paragraph.
3.  **Closed-form asymptotic SEs + relative-RMSE column** – small, fixes
    a real gap (currently no SE at all when `n_boot = 0`), free once
    already fitting.
4.  **Salt-dilution/tracer note** in the gaugings docs – small, low
    stakes, notes that a gauging’s source method isn’t currently
    recorded.

**Tier 2 – strongest candidates (modest effort, clear fit)**

5.  **[`apply_rating_inverse()`](https://jonpayneea.github.io/reach.rate/reference/apply_rating_inverse.md)**
    – small-medium, fills a real one-directional gap, dispatches the
    same way everything else already does.
6.  **Review against the EA’s own SW6-061 extrapolation manual** –
    medium, but it’s the organisation’s own standard governing how this
    package’s users would extend a curve; do this before anything
    fancier on extrapolation.

**Tier 3 – good value, less urgent**

7.  **Continuous-series rating-check function** (index/ultrasonic vs.
    existing rating) – medium, high value, but only pays off at stations
    that actually have ultrasonic data.
8.  **Multi-station regionalisation** (donor station’s `C`/`a`/`n` as a
    starting point) – medium, composes with `n_bounds`, speculative
    until a genuinely sparse station needs it.
9.  **Weir/flume equations with GUM-style uncertainty** – medium, real
    value but correctness-critical (needs careful standard
    transcription, not just architecture work), and only applicable at
    weir-controlled stations.
10. **Leverage/influence diagnostics** – medium, a nice-to-have, not
    solving an active problem.

**Tier 4 – bigger investment, defer until demand is proven**

11. **`bdrc` bridge function** – medium-large, build once (1) shows
    people actually want it.
12. **ML-predicted rating parameters** as a starting-value heuristic –
    large as a research question first, small once/if the research
    question is settled.
13. **Full `FlodeIndexRating` index-velocity class** – large, only after
    7.  demonstrates the need at a real station.

**Tier 5 – low priority or likely out of scope**

14. **Hydraulic/hydrodynamic model-derived ratings** – large, probably
    belongs outside this package.
15. **Sediment- and ice-affected ratings** – large and speculative, low
    relevance to most EA lowland stations.
16. **Real-time stage QC/anomaly detection** – large, arguably a
    different tool’s job, and the literature found doesn’t clearly
    transfer to stage records specifically.
17. **Satellite altimetry discharge** – not viable yet (~50% median bias
    on smaller rivers); revisit in a few years.

## Further candidate areas

A lighter survey pass – one paragraph each, not the full treatment the
five sections above got. Excludes anything already covered above or
already tracked in `ROADMAP.md`/`ROBUST_FITTING.md`.

- **Rating extrapolation and design-flood guidance.** Extending a curve
  beyond its gauged range is where rating uncertainty is largest and
  matters most (design flood peaks feed flood frequency analysis
  directly), and the UK’s own Extension of Rating Curves at Gauging
  Stations *Best Practice Guidance Manual* (Environment Agency/Defra
  R&D, report SW6-061) covers this specifically for EA-operated stations
  – directly relevant to how `reach.rate` is actually used, and worth
  reading in full before anything else on this list. Hydraulic modelling
  (see below) is the main non-statistical extension route the wider
  literature discusses; a review of that manual’s own recommended
  practice against what
  `n_bounds`/[`rate_optimise_constrained()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise_constrained.md)
  already do would be a natural, low-risk first step. Medium (mostly a
  careful reading and gap-comparison exercise, not new code by default).
- **Hydraulic/hydrodynamic model-derived ratings.** Deriving a
  stage-discharge relationship from a calibrated hydraulic model
  (HEC-RAS and similar) rather than – or alongside – fitted gaugings,
  particularly for extending high-flow ratings where few or no gaugings
  exist. Genuinely useful for cross-checking an extrapolated curve, but
  it needs channel geometry and a calibrated model as *input*, which
  `reach.rate` has no machinery to build or hold – this is a different
  kind of tool feeding a rating, not a fitting method
  [`rate_optimise()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise.md)
  could grow into. Large, and probably outside this package’s scope
  rather than a feature to build; more relevant as a cross-check
  workflow than as new `reach.rate` code.
- **Salt-dilution and other tracer gauging.** An independent
  discharge-measurement method (not a rating method at all), typically
  more accurate than velocity-area gauging on steep, turbulent streams
  where a current meter or ADCP struggles, though it overestimates low
  flows by up to 10% if lateral mixing isn’t complete (USBR *Water
  Measurement Manual*, ch. 12). Relevant to `reach.rate` only as another
  possible *source* of a `discharge_cms` gauging value feeding
  [`rate_optimise()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise.md)
  – no different in shape from any other gauging once it exists, so
  there is no code gap here, only a possible note in the gaugings
  documentation that a gauging’s *source method* isn’t currently
  recorded. Small, if done at all.
- **Sediment- and ice-affected ratings.** Both are cases where the
  physical control itself changes with something other than stage –
  sediment deposition/scour shifting the bed, or ice cover displacing
  the open-water rating and only bounding discharge from above (USGS WSP
  2378; Beltaos 2011 on winter slope-area methods). Ice effects are a
  low-priority fit for most EA-operated lowland stations specifically;
  sediment-affected ratings are more broadly relevant (a
  shifting-control problem, similar in spirit to what
  [`align_limb_boundaries()`](https://jonpayneea.github.io/reach.rate/reference/align_limb_boundaries.md)/
  [`graft_rating()`](https://jonpayneea.github.io/reach.rate/reference/graft_rating.md)
  already handle for a *known* shift, but here the shift is continuous
  and needs detecting, not just reconciling once known). Large, and
  speculative until a station with this problem is identified.
- **Remote-sensing / satellite altimetry discharge estimation.** SWOT
  and similar missions now deliver discharge estimates for thousands of
  ungauged reaches globally, but a 2025 assessment against 65 gauged
  reaches found a median bias around 50%, concentrated on smaller rivers
  (Byrd Polar and Climate Research Center, summarising the mission’s own
  first-15-months validation). Not a good fit for `reach.rate` today –
  the accuracy gap is large precisely on the scale of river this package
  is used for, and satellite-derived discharge is itself typically
  calibrated *against* a conventional rating rather than replacing one.
  Worth revisiting in a few years as the method matures, not now.
- **Machine-learning approaches to rating parameters.** The genuinely
  interesting recent work (Scientific Reports, 2025, on interpretable ML
  predicting rating-curve parameters from channel geometry and
  hydrological attributes across the US) predicts the *parameters of a
  physically-meaningful rating* rather than discharge directly end to
  end, which is a much better match to how `reach.rate` already thinks
  about a rating (`C`/`a`/`n` per limb) than a black-box discharge
  predictor would be – and other recent comparisons found simpler models
  outperforming deep learning (LSTM) for this kind of estimation anyway.
  A plausible, narrow future direction: an ML-informed *starting-values*
  or *prior-range* generator for
  [`rate_optimise()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise.md)’s
  existing multi-start fitting, not a replacement for NLS fitting
  itself. Large as a research question, small as a possible future
  starting-value heuristic once the research question is settled.
- **Real-time stage-record QC / anomaly detection.** Sensor drift and
  missing/erroneous data upstream of any rating application is a real
  problem, but the literature found here is water-quality-sensor and
  general time-series anomaly detection (deep-learning and concept-drift
  methods), not hydrometric-stage-specific – treat that gap as
  unverified for this specific application rather than assumed to
  transfer directly. `reach.rate` currently assumes clean stage input
  throughout; this would be upstream of the package’s own scope (data QC
  before fitting or applying a rating) rather than a rating-curve
  feature itself. Large, and arguably a different tool’s job.
- **Multi-station regionalisation / transfer.** Transferring a rating
  (or its parameters) from a gauged station to a hydraulically similar
  ungauged one, via nearest-neighbour donor selection or regression on
  catchment attributes – an active research area (Pool et al. 2021, a
  large comparative study, is the most substantial single reference
  found). This is the one candidate here that composes naturally with
  what `reach.rate` already has: `n_bounds` already lets known
  channel-control theory anchor a fit, and a “donor station’s fitted
  `C`/`a`/`n` as a starting point or prior range for a new, sparsely
  gauged station” is a small, natural extension of that same idea, not a
  new architecture. Medium.
