# E2 Separated uncertainty sources

| | |
|---|---|
| Status | IMPLEMENTED, as amended below. Approved by the maintainer on 27 November 2026 ("Go for E2"); the amendment to the gauging source approved the same day |
| Release | E (advanced capability) |
| Date | 22 November 2026 |
| Reader | The maintainer, and the reviewer who will assess the method against the Release E gate |
| Closes | Limitation L04, in part |

## Summary

The package reports one kind of uncertainty: the effect of having only these gaugings,
by bootstrap. It says so, and says what it leaves out. What it leaves out is most of the
budget. A rating's uncertainty has several sources, they behave differently, and a
single band hides which one dominates.

This definition adds one function, `rating_uncertainty()`, that reports **each source
on its own and the combination**, so a reviewer can see what a band is made of. Two of
the sources are intervals. One is a range and is never turned into an interval.
Nothing changes for any existing function.

## The sources

| Source | What it is | Reported as | Built here |
|---|---|---|---|
| **Sampling** | The rating would differ with a different set of gaugings | Interval | Yes. The existing bootstrap, by case resampling |
| **Gauging error** | Each gauging is itself an estimate of discharge, with its own error | Interval | Yes. New. Needs the error supplied |
| **Structure** | Another reasonable choice of limbs, breakpoints, objective or model would give a different curve | **Range**, not an interval | Yes, from the variants `rating_sensitivity()` already fits |
| **Stage error** | Stage is read with error, so the fit is an errors-in-variables problem | | **No.** See Out of scope |
| **Scatter** | The spread of a single new observation about the curve | | **No.** That is a prediction interval, a different question |

The separation matters because the sources answer different questions, and because they
cannot honestly be added. Sampling and gauging error can be combined, by joint
simulation. Structure cannot: it has no probability, only a spread of defensible
choices. A rating that quoted structure as a 95% band would claim a precision the
analyst does not have.

## Definition

### Sampling

As now: case resampling of the gaugings used, refitting each draw, with the same
settings. `n_draws` replaces `n_boot` in the new function. The existing `n_boot` and
the `@bootstrap` slot are untouched.

### Gauging error

Each gauging `i` has a relative standard uncertainty `u_i` (a fraction, such as 0.05).
Each draw perturbs the discharges:

```
Q*_i = Q_i * exp(e_i),   e_i ~ Normal(0, u_i^2)
```

and refits. The log-normal form keeps discharge positive, and gives a relative error,
which is how gauging error is normally stated. The envelope over draws is the interval.

**The package does not invent `u_i`.** A default would be a number the analyst did not
choose and could not defend. `u_i` comes from, in order of precedence:

1. A new optional evidence column, `discharge_uncertainty`, a fraction per gauging. A
   record that carries its own stated uncertainty uses it.
2. The argument `gauging_uncertainty`, one fraction for all gaugings, stated by the
   caller and recorded.

With neither, the gauging-error source is reported as **not assessed**, with the
reason. It is never reported as zero.

### Combined

Joint simulation: each draw resamples the rows, then perturbs the sampled discharges,
then refits. The combined interval is the envelope over those draws. The package does
not add the two intervals or their variances. The assumption is that sampling and
gauging error are independent.

### Structure

The range, at each stage, across the variants `rating_sensitivity()` fits: the
alternative objective, the dropped limbs and the shifted breakpoints it already
covers. Reported as a minimum and a maximum with the variant that produced each. The
list of variants is part of the record. A structural range depends entirely on which
alternatives were considered, and the output says so.

## Interface

```r
rating_uncertainty(rating, stage = NULL, n_draws = 500, gauging_uncertainty = NULL,
                   sources = c("sampling", "gauging", "structure"),
                   level = 0.95, seed = NULL)
```

It takes a `FlodeRating` and returns a `FlodeUncertainty` object, not a bare table. It
holds:

| Part | Content |
|---|---|
| `bands` | Long table: `stage_m`, `source` (`sampling`, `gauging`, `combined`, `structure`), `lower`, `upper`, `median` for the intervals, and `min`, `max` for structure |
| `assessed` | One row per source: whether it was assessed, and if not, why |
| `settings` | `n_draws`, `level`, `seed`, the `u_i` used, where each came from |
| `draws_failed` | Count of refits that failed, per source |
| `variants` | The structural variants, with their effect |

`print()` states first which sources were assessed and which were not. `autoplot()`
shows the sources as separate bands on one axis, so the dominant one is visible. Both
methods say, on every output, that the result is not a complete budget.

`apply_rating_interval()` is unchanged.

## Input requirements

- A `FlodeRating`, independent limbs or segmented. Segmented ratings run the sampling
  and gauging sources and are refused for structure, as `compare_ratings()` refuses
  them.
- At least 10 usable gaugings for any resampling source. Below that the bands are not
  meaningful, and the function says so and stops.
- For the gauging source, `u_i` as above, each in `(0, 0.5]`.

## Failure behaviour

| Condition | Behaviour |
|---|---|
| No uncertainty supplied for the gauging source | Source reported **not assessed**, with a message saying how to supply it. Not an error, not zero |
| `u_i` outside `(0, 0.5]`, or not finite | Error naming the gauging |
| Fewer than 10 usable gaugings | Error |
| More than 20% of refits fail for a source | That source is withheld with a warning. A band from the survivors would be biased towards easy data |
| `n_draws` below 100 | Error. A band needs draws |
| No variants can be fitted for structure | Structure reported not assessed |
| A `FlodeRatingTable` | Refused: a table has no evidence to resample |

Every message says what failed, why it matters and what to do.

## Reference examples

The only honest test of an uncertainty method is whether its intervals cover the truth
as often as they claim. The package has simulated stations with known truth, so this
can be tested.

1. **Coverage with known gauging error.** Simulate a station with 5% gauging error,
   fit, and ask whether the 95% interval of each source covers the true curve over the
   range. Repeat over many stations. Expected: the sampling interval alone covers
   **less** than 95%, because it ignores the 5%, and the combined interval covers
   close to 95%. This is the example the method exists to pass.
2. **No gauging error.** Data with negligible error and `gauging_uncertainty = 0.001`.
   The gauging band must be narrow and the combined band must be close to sampling
   alone.
3. **Structure is a range.** A two-limb station where one-limb and two-limb fits
   differ. The structural range must be wide and labelled a range, and no probability
   must appear anywhere in it.

Coverage is a property of a population of stations, so example 1 is a simulation, not
a single fit. The test runs a modest number in CI. The vignette reports a larger run,
with the number of repeats and the seed stated.

## Mathematical changes

None to any existing result. The function is new. `fit_rating()`, `rate_optimise()` and
the bootstrap are unchanged, and tests assert it.

## Limitations

- **Shared gauging error is assumed log-normal, the same for every gauging in a group,
  and independent between groups** (amendment 1). Gaugings that share a meter but are
  grouped apart, or a group whose members do not truly share an error, misstate it.
- **The result is only as good as `u_i`.** The package propagates a number it is
  given. A poor `u_i` gives a confident wrong band. The analyst takes the figure from
  the gauging record or the method (for example the stated uncertainty of the
  technique), not from this package.
- **Structure depends on the variants tried.** It cannot find a structure nobody
  thought of.
- **Stage error is not modelled.** The combined interval is narrower than the truth by
  that amount.
- **It is a budget for the curve, not for a forecast.** It says nothing about
  extrapolation beyond the gauged range, which `support` classes and operational
  limits handle separately. Bands beyond the gauged range are labelled
  `extrapolation` and should not be read as reliable.
- **It has not been tested on a real station** (L01).

## Out of scope

- **Stage measurement error.** It needs an errors-in-variables fit, which is a new
  optimiser. Release E's gate excludes new fitting engines until A and B are done.
- **Prediction intervals for a new observation.** A different question, with a
  different object.
- **Bayesian fitting** (issue #11). It would replace sampling with a posterior. That is
  a larger design, and is deferred.
- **Time-varying uncertainty.** It belongs with temporal ratings.

## Decisions needed

1. Whether a per-gauging `discharge_uncertainty` column is added to the evidence
   schema. It is a schema change: a new optional column, and a schema version bump with
   a migration (the mechanism exists). Proposed: yes, optional, default absent.
2. The refusal to supply a default `u_i`. Proposed: refuse, and report not assessed.
3. Structure as a range only. Proposed: yes, never as an interval.
4. Whether `FlodeUncertainty` is stored in the export folder. Proposed: not yet.

## Amendments made in building it

1. **The gauging source is error shared between gaugings, not independent per gauging.**
   As defined, each draw perturbed every gauging independently, on top of resampling.
   Random error in each gauging is already the scatter of the gaugings about the curve,
   which resampling carries into the band, so this counted it twice. A simulation of 12
   stations with 5% random error showed it: the combined band covered the true curve
   99.2% of the time, against 91.6% for sampling alone (40 stations). What resampling
   cannot see is error **shared** between gaugings, a meter or method reading high or low
   for all of them, which leaves no scatter. Each draw now moves every gauging in a group
   by one shared factor `exp(e)`, `e ~ Normal(0, u^2)`; `group_by` names the column (a
   method, a meter) whose values share an error, and without it every gauging shares one.
   A group's `u` is the median of its gaugings' `discharge_uncertainty`, or
   `gauging_uncertainty`. Approved by the maintainer before any code was written.
2. **Reference example 1 is amended to match.** Stations carry 5% random scatter and a
   shared bias from `Normal(0, 0.05^2)`, with `u = 0.05` stated. Over 30 stations, 100
   draws each, the 95% bands covered the true curve: sampling 0.525, gauging 0.913,
   combined 0.938. With no shared bias and `u = 0.001` (10 stations): sampling 0.866,
   gauging 0.138 (a band of about +-0.2%, as it should be), combined 0.910. The test
   runs the first 12 of the 30, with the same seeds.
3. **One group needs no refits for the gauging source.** A shared factor `k` on every
   discharge scales the fitted `C` by exactly `k` and leaves `a` and `n` as they were,
   under either objective, so the curve is multiplied by `k`. With groups, or with
   `protect_above` (a threshold in discharge, which scaling moves gaugings across), every
   draw is refitted. A test asserts the scaling on a refit.
4. **The structural variants are built here.** `rating_sensitivity()` fits shifted
   breakpoints but not the other objective or a limb fewer, which the definition said it
   already covered. `rating_uncertainty()` fits all three: the other objective, each
   breakpoint dropped, and each moved by 5% of the gauged range either way.
5. **No schema change was needed** (decision 1). Evidence already keeps columns beyond the
   canonical ones, and a fit keeps them in its gaugings, so `discharge_uncertainty` is
   read where present. The schema version stays 2.
6. **A segmented rating's structure is reported not assessed**, not refused with an error,
   so the default `sources` work on every fit.

Decisions 2 to 4 were taken as proposed: no default `u`, structure as a range only, and
nothing stored in the export folder yet.

One limitation is sharpened: **random gauging error is in the sampling source**, and a
`u` that includes it double counts; state the shared part only.

## Version history

| Version | Date | Change |
|---|---|---|
| 0.1 | 22 November 2026 | First definition |
| 0.2 | 27 November 2026 | Implemented; the gauging source amended to shared error |
