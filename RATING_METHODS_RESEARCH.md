# Rating methods research

Research and proposal only -- no code, tests, or vignettes are touched by
this document. It evaluates five directions Jonathan raised against
`reach.rate`'s actual architecture (`R/flode_classes.R`, `R/rate_optimise.R`,
`R/rate_optimise_segmented.R`, `R/gap_check.R`, `R/apply_rating.R`), in the
same spirit as [ROADMAP.md](ROADMAP.md) and
[ROBUST_FITTING.md](ROBUST_FITTING.md): one section per idea, a concrete
recommendation, and a short "what this would take" note. Citations are
included for every substantive claim; where a claim could not be verified
(a paywalled standard, an inaccessible page) that is stated rather than
guessed at.

## 1. Weir/flume equations, with uncertainty

**What the literature says.** Standard weir and flume discharge formulae
are physically-derived equations from structure geometry, not fitted
curves: sharp-crested rectangular and V-notch/triangular weirs are covered
by ISO 1438:2017 (rectangular and triangular thin-plate weirs); Cipoletti
weirs (trapezoidal, sides sloped 1 horizontal to 4 vertical, compensating
for side contraction so the calibration matches an equivalent suppressed
rectangular weir) and Parshall/H-flumes are covered in the USBR *Water
Measurement Manual*. I did not verify a specific ISO number for flumes in
this pass -- treat that as an open question, not an established fact.

Uncertainty for these structures is **analytic, not empirical**: ISO 1438
expresses it as a percentage-uncertainty budget -- `u*(Cd)` (uncertainty in
the discharge coefficient), `u*(h1)` (uncertainty in measured head), and an
expanded combined uncertainty `U` -- combined in quadrature (a standard
GUM/ISO-GUM propagation, not a statistical fit to gaugings). A 2021
Parshall-flume study (Ferreira et al., *ScienceDirect*, S2665-9174(21)000714)
quantified this concretely with Monte Carlo propagation: well-built lab
flumes reach roughly ±2%, but realistic field installations run ±3-5%
once dimensional tolerance, approach turbulence, and debris/maintenance
are accounted for, and the choice of fixed vs. correlated model parameters
alone shifted results by up to 12% in their comparison.

**Fit to `reach.rate`'s architecture.** This genuinely is not a rating in
the sense `FlodeRating`/`FlodeRatingTable` represent: there are no
gaugings to fit against, `C` isn't estimated by NLS, and the uncertainty
comes from a coefficient table and a propagation formula, not a bootstrap
or a covariance matrix. It doesn't extend either class cleanly. It composes
well with the toolkit at the table level, though: a weir equation expressed
as a single-row `lower_level, upper_level, C, a, n` limb is exactly the
shape `FlodeRatingTable`, `apply_rating()`, and -- concretely -- the
just-shipped `graft_rating()` already expect. A weir-controlled low-flow
limb with a fitted upper limb above it is a real station configuration,
and `graft_rating()` already does the joining; it just has no source of
a *structural* (non-fitted) low limb to graft yet.

**Recommendation.** A new, small, standalone module (e.g.
`R/weir_equations.R`) with one function per structure type
(`weir_discharge_rectangular()`, `weir_discharge_vnotch()`,
`weir_discharge_cipoletti()`, `flume_discharge_parshall()`, ...), each
taking head and geometry, returning discharge plus an uncertainty band
computed by quadrature propagation of the structure's own coefficient and
head uncertainties -- not a new subclass. A thin bridge function converting
one of these into a one-row `FlodeRatingTable`-shaped table would let it
be handed straight to `graft_rating()`, `apply_rating()`, and
`compare_ratings()` without any of those needing to know a weir equation
produced it.

**What this would take.** Medium. The uncertainty-propagation mechanics
are simple and reusable across structure types; the real cost is sourcing
and correctly transcribing each standard's actual coefficient tables and
uncertainty components, which are only partially accessible from open
search (ISO/BS documents are paywalled past their preview pages) and
deserve a careful, correctness-first pass rather than being inferred.

## 2. Bayesian methods

**What the literature says.** BaRatin (Le Coz et al. 2014, already cited
in `rating_curves_guide.Rmd`) builds a rating from hydraulic priors on
each control's power-law parameters, reviewed gaugings, and MCMC posterior
sampling -- three explicit steps (define priors, validate gaugings,
infer). Its reference software, BaRatinAGE, is not R. Hodson et al.
(2024)'s `ratingcurve` (Python, already cited, and the source of
`rate_optimise_segmented()`'s own parameterisation) is the other tool the
package already references.

**A closer, previously-unreferenced match: `bdrc`.** *Bayesian Discharge
Rating Curves* (Hrafnkelsson et al. 2022, package on CRAN) is an R
package implementing Bayesian fitting of both the classical power-law and
a *generalized* power-law (exponent `n` varying smoothly with stage rather
than fixed per limb) via four model variants -- `plm0`/`plm` (constant vs.
stage-varying log-error variance) and `gplm0`/`gplm` (the generalized
form, same variance choice). This is materially closer prior art than
either BaRatin or `ratingcurve`: it is R, on CRAN, and actively
maintained, so an interop path is far cheaper to build and to keep
working than one to Python or standalone software.

**What `n_bounds` + bootstrap already approximate, and what they don't.**
`ROBUST_FITTING.md` already states the distinction correctly: `n_bounds`
is a hard/soft box constraint on a frequentist NLS fit, not a prior --
the constrained region is ruled out entirely, not merely down-weighted --
and the bootstrap resamples gaugings and refits, approximating sampling
variability under repeated gauging rather than a true posterior that
starts from hydraulic knowledge and lets sparse data update it only as
far as the data actually supports. That gap is real and matches exactly
what issue #11 already describes as the package's largest, not-yet-started
roadmap item.

**Recommendation.** Given `bdrc` already exists, maintained, in R,
building `reach.rate`'s own MCMC engine from scratch is probably not the
best use of effort relative to the value. Two options, independent of
each other:
- (a) A bridge, e.g. `from_bdrc()`, wrapping a fitted `bdrc` object's
  posterior summary into a `FlodeRating`-shaped result (or a new
  `@posterior` property alongside `@bootstrap`) so the rest of the
  toolkit -- `rating_plot()`, `apply_rating()`, gap-checking -- works on
  a Bayesian-fitted curve too, with `bdrc` in `Suggests`, not a hard
  dependency.
- (b) At minimum, and independent of (a) ever being built: cross-reference
  `bdrc` from `non_standard_optimisation.Rmd` and `n_bounds_guide.Rmd` as
  "if you need a true Bayesian treatment, `reach.rate` doesn't do this
  yet -- see `bdrc`." Zero risk, immediately actionable.

**What this would take.** (a) is medium-to-large -- the design work is in
faithfully representing MCMC draws inside `FlodeRating`'s existing
uncertainty conventions without pretending they're bootstrap draws. (b) is
trivial, a documentation change only.

## 3. Better statistics on curve fitting

**What's there now.** Per-limb `rmse_cms`, `r_squared`, `mean_error_cms`,
`median_abs_error_cms`, `max_abs_error_cms`, `n_obs`, `n_unique_stage`,
`residual_df`, and (only when `n_boot > 0`) bootstrap-derived coefficient
SEs. There is currently no SE at all when `n_boot = 0` -- an unforced gap,
since `minpack.lm::nlsLM`'s fit object already carries what a standard
asymptotic covariance-based SE needs, at no extra fitting cost.

**What the literature offers beyond this.**
- **Heteroscedasticity-aware reporting.** `bdrc`'s `plm`/`gplm` variants
  make stage-varying error variance an explicit, checkable model choice
  rather than something inferred only by switching `objective`. A cheap,
  unconditional complement: report a relative/percentage RMSE alongside
  the existing absolute `rmse_cms` regardless of which `objective` was
  used to fit -- the vignette already notes both objectives are compared
  on the absolute scale, so nothing today shows the relative-error picture
  directly.
- **An external reference point for "is this fit good."** WMO's *Manual
  on Stream Gauging* (WMO-No. 1044, 2010), Table I.10.1, gives standard
  errors attributable to individual gauging measurement components. A
  fitted rating's own `rmse_cms` currently has no external yardstick;
  comparing it against what individual-gauging measurement uncertainty
  alone would predict is a genuinely new diagnostic -- is the scatter
  explained by measurement noise, or does it exceed that (indicating
  unmodelled curve-shape error).
- **Per-gauging influence, not just per-limb residuals.** Classical
  regression leverage/influence diagnostics (Cook 1977; standard
  regression-diagnostics theory) are not rating-curve-specific but are
  directly adaptable: the NLS design already used for the covariance-based
  SE above gives a local linearisation, so leverage and a
  leave-one-out-style influence measure are a natural, tractable addition
  -- currently `plot_rating_residuals()` shows every point but not which
  ones are disproportionately steering a limb's fit.
- **A practical caution, not a statistic.** New Zealand's National
  Environmental Monitoring Standard for rating curves explicitly warns
  against "over-refinement... to obtain good statistical fit" at the
  expense of hydraulic validity -- worth folding into
  `rating_curves_guide.Rmd`'s existing "Guidance: reading a fit, in
  order" section as prose, not a new statistic.

**Recommendation.** (1) closed-form asymptotic parameter SEs from the NLS
covariance matrix as an always-available fallback when `n_boot = 0`; (2)
an unconditional relative-RMSE column; (3) a leave-one-out/leverage
diagnostic as its own function; (4) the NEMS caution as a documentation
addition.

**What this would take.** (1) and (2) are small -- both derive from
information the fit already computes. (3) is medium, a genuinely new
function. (4) is trivial.

## 4. Inverse application: discharge to stage

**What's there now.** `apply_rating()` only converts stage to discharge.

**Why the inverse is mostly straightforward, and where it isn't.** Within
one limb, `H = a + (Q/C)^(1/n)` is a safe, closed-form inverse: the
package's own validators already require `C > 0` and `n > 0` for every
limb, which makes `Q = C(H-a)^n` strictly monotonic increasing over that
limb's domain. The real pitfalls are elsewhere:
- **Limb selection by discharge, not stage.** `apply_rating()`'s forward
  direction picks a limb by where stage falls in `[lower_level,
  upper_level]` via `findInterval()`. The inverse needs the equivalent
  lookup on the discharge axis -- evaluate each limb's own bounds to get
  its implied discharge range, then find which range a query discharge
  falls in. A residual junction gap (exactly what `detect_rc_gaps()`
  exists to catch) makes this ambiguous in a way the forward direction
  never is, since two adjacent limbs' discharge ranges can then overlap
  or leave a hole.
- **Genuine non-monotonicity is out of scope, and should say so.** Tidal
  or strong-backwater reaches can produce a stage-discharge relationship
  that is not single-valued at all (a documented failure mode in the
  literature, distinct from anything a closed-form per-limb inverse can
  fix). This should be a stated limitation, not something the function
  silently mishandles.
- **Uncertainty propagates through the local derivative.** The standard
  approach (confirmed in the rating-curve-uncertainty literature) is to
  propagate discharge-side uncertainty through the inverse via the local
  sensitivity `dH/dQ = 1/(dQ/dH) = 1/(C n (H-a)^{n-1})` -- a delta-method
  step, not a new fitting exercise, and one that composes with whatever
  uncertainty (bootstrap SEs, or a future Bayesian posterior) the forward
  fit already carries.

**Recommendation.** A new function, e.g. `apply_rating_inverse(fit,
discharge_dt, ...)`, dispatched the same way `apply_rating()` is (matching
`as_rating_table()`'s own stated preference for a named, tested function
per operation over a mode-switching argument). Require -- or at minimum
warn loudly on -- a `FlodeRatingTable` that hasn't been confirmed
gap-free via `detect_rc_gaps()`, since an unresolved gap is exactly what
makes the discharge-side lookup ambiguous. Document the non-monotonic
(tidal/backwater) case as explicitly out of scope rather than leaving it
to fail confusingly.

**What this would take.** Small-to-medium. The per-limb algebra is
trivial; the real design decision is the gap-free precondition and its
failure message, not the maths.

## 5. Continuous index/ultrasonic data alongside stage

**What the literature says.** The USGS index-velocity method (Levesque
& Oberg, *Computing Discharge Using the Index Velocity Method*, USGS
TM 3-A23) separates discharge into two independent ratings multiplied
together: an index-velocity rating (mean channel velocity as a function
of a measured index velocity -- usually simple linear regression, though
more complex forms exist) and a stage-area rating (cross-sectional area
from surveyed geometry as a function of stage), giving `Q = V(index) x
A(stage)`. It is recommended specifically for sites where a simple
stage-discharge power law cannot work at all -- backwater, unsteady or
reversing flow, confluences, near hydraulic structures -- which includes
the tidal/non-monotonic case flagged in section 4. USGS reported roughly
470 gauging stations operated this way as of a 2011 source; the true
current count is very likely higher and was not independently verified
here.

**Fit to `reach.rate`'s architecture.** This is a genuinely different
model form, not a variant of the existing one: two independent
regressions multiplied, rather than one `Q = C(H-a)^n` equation per limb.
It does not fit as an extension of `FlodeRating`/`FlodeRatingTable` --
their `@limbs`/`@table` shape assumes exactly one such equation per limb.
It does fit the package's existing "one generic, several classes"
pattern (`rating_plot()`, `apply_rating()`, `as_rating_table()` already
dispatch on class): a new sibling class under `FlodeRatingBase` (reusing
`@gaugings`/`@status`/`@provenance`/`@previous`) with its own two-part fit
and its own `apply_rating()` method (taking an index-velocity column
alongside stage, not stage alone) is the natural shape.

**Recommendation, staged.** The full model is a large undertaking; a much
smaller, immediately useful step doesn't require it at all. Where a
station already has continuous ultrasonic/index data *alongside* its
existing power-law rating, the first genuinely useful "analytics along a
continuous series" is a comparison, not a new fitting method: run
`apply_rating()` on the stage series as today, and diff the result against
the independent continuous discharge series over the same period. That
reuses the existing architecture entirely and surfaces exactly the
question the continuous data is there to answer -- is the current
power-law rating still tracking reality -- without committing to the
larger class-level investment up front. Build this first; let it justify
(or not) the full `FlodeIndexRating` class based on what it actually
finds at real stations.

**What this would take.** The comparison function: small, entirely
existing machinery. The full index-velocity class: large -- a new class,
a new two-part fitting routine, a new `apply_rating()` method with a
different input signature, and new diagnostics suited to linear
regression rather than power-law NLS.

## Other findings

- **The generalized power-law model** (Hrafnkelsson et al. 2022, `bdrc`)
  lets the exponent vary smoothly with stage (continuous `n(h)` and
  `n'(h)`) instead of `rate_optimise()`'s hard breakpoints. This solves
  the same problem `rate_optimise_segmented()` (Hodson et al. 2024)
  already addresses -- no junction gap by construction -- by a different
  route (smooth exponent vs. joint multi-segment formula). Worth a
  comparison note the next time `rate_optimise_segmented()`'s own docs
  are revisited, rather than a new feature on its own; it overlaps
  heavily with section 2's `bdrc` bridge.
- **Weir equations and `graft_rating()` compound naturally**: a
  standard-derived, non-fitted low-flow limb (section 1) grafted onto a
  fitted upper rating is exactly the scenario `graft_rating()` (shipped
  this week) already handles, once such a limb exists to graft.
- **Closed-form asymptotic SEs** (section 3) are worth doing regardless of
  anything else here -- pure upside, no new dependency, no design risk.

## Suggested priority order

1. **Inverse application** (`apply_rating_inverse()`) -- small-medium,
   fits the architecture cleanly, no new dependency.
2. **Closed-form asymptotic SEs + relative-RMSE column** -- small, cheap,
   pure upside.
3. **Weir/flume equations with GUM-style uncertainty** -- medium, composes
   with `graft_rating()` immediately.
4. **Bayesian doc cross-reference to `bdrc`** -- trivial, do regardless of
   whether a bridge function ever gets built.
5. **Continuous-series rating-check function** (index/ultrasonic vs.
   existing rating) -- medium, high practical value, a real pilot before
   committing further.
6. **Leverage/influence diagnostics** -- medium.
7. **`bdrc` bridge function** -- medium-large, do once (4) shows real
   demand.
8. **Full `FlodeIndexRating` index-velocity class** -- large, only after
   (5) demonstrates the need at real stations.
9. **NEMS over-refinement caution in the guide vignette** -- trivial,
   documentation only.
