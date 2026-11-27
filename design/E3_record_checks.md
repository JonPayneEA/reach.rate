# E3 Rating checks from the flow record

| | |
|---|---|
| Status | IMPLEMENTED, as amended below. Approved by the maintainer on 27 November 2026 ("Go") |
| Release | E (advanced capability) |
| Date | 26 November 2026; implemented 27 November 2026 |
| Reader | The maintainer, and the reviewer who will assess the method against the Release E gate |
| Closes | Nothing in the register. It adds a check where none exists |

## Summary

Every check in the package starts from gaugings. Many users do not have them, and
those who do have a few dozen, while the archive holds hundreds of thousands of
stage and flow pairs. Archived flow is stage passed through whichever rating was
applied at the time, so the pairs carry that rating. Read back, it can be checked
for what the gaugings cannot show: when it changed, where the record departs from
it, how much flow came from above its top, and how far a stage error moves the
flow.

This definition adds one function, `check_flow_record()`. It reads the applied
rating back from the record, period by period, and reports six checks as a
`FlodeAssessment`, with the tables behind them. It never fits a rating, never edits
the record and never sets a number the caller did not give. Nothing changes for
any existing function.

The first user is a water balance: deciding whether a runoff deficit comes from the
rain, the rating or the catchment. The checks answer the rating's part of that.

## Input

`record`: a data frame or data.table, one row per step, with

| Column | Meaning | Required |
|---|---|---|
| `time` | POSIXct, UTC, the step's start | Yes |
| `stage_m` | Stage, metres above the gauge datum | Yes |
| `discharge_cms` | Archived flow, m3/s | Yes |
| `quality` | The archive's quality code for the flow | No |

Steps must be regular and in order. A step with stage but no flow, or flow but no
stage, is kept and counted, never used.

The optional inputs, each recorded in the result when given and reported as **not
assessed**, with the reason, when not:

| Argument | Meaning | Check it enables |
|---|---|---|
| `top_stage_m` | The highest stage the rating is founded on: the highest gauging, or the stated limit of the top limb | Above the top |
| `bankfull_stage_m` | The stage above which water may bypass the section | Above bankfull |
| `stage_uncertainty_m` | A stage error, as a systematic offset in metres | Stage error to flow |
| `dry` | Logical, one per step: `TRUE` where the caller judges no rain has fallen on the catchment long enough to matter | Dry-weather rises |
| `ratings` | Known ratings: a named list of `FlodeRating` or `FlodeRatingTable`, or the output of `operational_rating_tables()` | Matched to known ratings |

The package does not invent any of these. A default top stage, uncertainty or dry
mask would be a number the analyst did not choose and could not defend, which is
the rule E2 sets out.

## Definition

### Tolerance

An applied rating is exact: the archived flow at a stage is the rating's flow there,
less rounding. A departure is therefore a step where

```
|Q - C(h)| > max(tolerance * C(h), abs_tolerance)
```

with `C` the curve read back for the step's period, `tolerance = 0.01` (1%) and
`abs_tolerance = 0.002` m3/s, both arguments. The absolute term covers flow stored to
three decimals: at 0.05 m3/s, rounding alone is 1%.

### The curve read back

Stage is archived to the millimetre, so a period's pairs fall on distinct stage
values. The curve `C` for a period is, at each distinct stage, the median of the
flows recorded there, linearly interpolated between them. A step is **tested** only
where its stage is one already on the curve, or lies between two curve stages at most
`max_gap_m = 0.01` m apart. Elsewhere it is **untested**: the record has not yet seen
that stage in this period, and nothing is extrapolated.

### Periods and revisions

The record is split into periods in one pass, a day at a time:

1. The first day opens a period, and its pairs start the curve.
2. Each later day is tested against the open period's curve. The day **departs** if
   more than half its tested steps depart.
3. A day that departs, followed by `min_days = 2` departing days in a row (the day
   itself counts), closes the period. A **revision** is dated at the first departing
   step of the first such day. A new period opens there.
4. A shorter run of departing days does not close the period. Its steps are reported
   as off the curve (below).
5. A day that does not depart adds its pairs to the curve, so the curve grows with
   the stages the record reaches.

The result is a table of periods, each with its start, end, steps, and stage range,
and each period's curve as a `FlodeRatingTable` (stage, discharge), so it can be
plotted or set beside a known rating.

### What kind of revision

For each revision, the new period's curve is compared with the old one over the
stages both have seen. If a single stage shift `d` makes them agree,

```
C_new(h) = C_old(h + d)   to within the tolerance, over the shared stages
```

the revision is a **stage shift** of `d` metres: a change of datum, or of the control
by a constant height. Otherwise it is a **change of shape**. `d` is found by a
one-dimensional search over `|d| <= 0.5` m.

### The six checks

| Check | What it reports | Status |
|---|---|---|
| `record_revisions` | Each revision: date, kind, shift where it is one, the flow change at the period's median stage | `warning` if any; `pass` if none |
| `record_off_curve` | Runs of tested steps that depart, outside a revision: start, end, steps, share of the period's flow volume, and the quality codes in the run | `warning` if they hold more than 1% of the volume; `pass` otherwise |
| `record_above_top` | Steps and share of flow volume with stage above `top_stage_m`; the peaks above it | `warning` if more than 5% of volume; `pass` otherwise; `not_assessed` without `top_stage_m` |
| `record_above_bankfull` | The same above `bankfull_stage_m` | `warning` if any peak is above it; `not_assessed` without it |
| `record_stage_error` | The flow volume change, year by year and by flow band, from a stage offset of `+stage_uncertainty_m` and `-stage_uncertainty_m`, each passed through the period's curve | Always `pass` when assessed: it is a size, not a finding; `not_assessed` without the uncertainty |
| `record_dry_rises` | Month by month, the mean change of stage per day over dry steps, and the flow that change makes | `warning` for any month whose dry stage rises on average; `not_assessed` without `dry` |

The 1% and 5% thresholds are arguments. They are best-endeavours defaults, not EA
policy, as with every limit in the package (limitation L02).

With `ratings` given, each period is also matched to the known rating that departs
from it at the fewest of its steps, reported as `record_known_ratings`: the rating's
name, the share of steps that depart from it, and `warning` for a period that no known
rating fits.

### Stage error to flow

The offset is applied to every step of a period, through that period's curve,
interpolated in log flow. A systematic offset is the relevant case for a water
balance: random stage noise averages out over a year, a datum error does not. Steps
the offset carries off the curve's range are not extrapolated, and are counted.

### Dry-weather rises

A healthy recession falls. Over dry steps, a rising stage means water held back: weed,
a blockage, or backwater. The archived flow follows the stage up, so it is overstated.
The check reports the rise and the flow it makes, and leaves the cause to a person.

## Output

A list with class `flode_record_check`:

| Element | Contents |
|---|---|
| `assessment` | A `FlodeAssessment`, one row per check above |
| `periods` | One row per period |
| `curves` | A list of `FlodeRatingTable`, one per period |
| `revisions` | One row per revision |
| `off_curve` | One row per run of departing steps |
| `above` | Steps above the top and bankfull stages, with the peaks |
| `stage_error` | Volume change by year and flow band, where assessed |
| `dry_rises` | By month, where assessed |
| `counts` | Steps in, steps with stage or flow missing, tested, untested |
| `settings` | Every argument, as used |

`plot()` draws the stage-flow pairs coloured by period, with the curves, the
departures and the top and bankfull stages.

## Failure behaviour

- A record without the three required columns, with times out of order, or with
  irregular steps: an error naming the column or the first bad row.
- Fewer than seven days with stage and flow: an error, since no curve can be read.
- A period with fewer than 100 tested steps: reported in `periods` and its checks
  marked `not_assessed` for that period, never extrapolated from a neighbour.
- A record that is mostly untested (over half its steps): every check still runs on
  the tested steps, and the assessment says how few they are.
- Negative stage is allowed, since a datum can sit above the bed. Negative flow is an
  error.

## Reference examples

Synthetic, from a known two-limb rating, 15-minute steps, two years, stage and flow
rounded as the archive rounds them. Each test states its expected value from the
construction:

1. **One rating throughout:** one period, no revisions, no departures.
2. **A stage shift of 0.05 m on a known day:** one revision, dated to that day's
   first step, kind stage shift, `d` within 2 mm of 0.05.
3. **A change of shape** (the top limb's exponent changed): one revision, kind change
   of shape.
4. **A day of infilled flow** (linearly interpolated across a gap): one run off the
   curve, exactly those steps, marked as estimated where `quality` says so.
5. **Above the top:** with `top_stage_m` set below the largest peaks, the share of
   volume above it equals the hand sum over the steps above.
6. **Stage error:** on a single power-law limb `Q = a (h - h0)^b`, the volume change
   from an offset `u` equals the sum over steps of `a (h - h0 + u)^b - Q`, worked out
   directly.
7. **Dry-weather rises:** a recession with a steady rise of 2 mm a day added over
   marked dry steps in one month gives a mean rise of 2 mm a day in that month and no
   other.
8. **Matched to known ratings:** given the two ratings used in example 2, each period
   is matched to the one that made it, with no departures.

## Limitations

- **A reprocessed archive hides its history.** When an archive is rebuilt with the
  current rating over past years, the record shows one rating throughout, and no
  revision can be found. The check reports what was applied to the record as it
  stands, not what was in force at the time.
- **It tests the rating as applied, not as true.** A rating can be applied perfectly
  and still be wrong. Only gaugings test that, through
  `compare_gaugings_to_rating()`.
- **A revision is seen only where the record returns to stages the old rating
  covered.** A change confined to stages the later record never reaches is missed.
- **Gradual datum drift is invisible.** Flow follows stage, so a slow drift moves
  both together, and the pairs stay on the curve.
- **A single-valued rating is assumed.** Hysteresis or a looped rating applied in the
  archive will show as departures.
- **Dry means what the caller says.** The check cannot tell a weed rise from rain
  missed by the dry mask. Nor from groundwater: on a permeable catchment, flow can go on
  rising for days after rain as the aquifer answers it, so a dry mask of a day or two
  flags winter months that have no weed in them. Weed grows in summer; a winter rise is
  more likely the catchment than the channel.

## Amendments made in building it

Each is a change from the definition above, made because the definition could not be
built as written, or would have failed on real records.

1. **Curves are tables, not `FlodeRatingTable`.** A `FlodeRatingTable` holds power-law
   limbs. A curve read back is a table of points, so `curves` holds data.tables of
   `stage_m` and `discharge_cms`. Matching to a known rating sets those points beside
   its limbs.
2. **Gaps in time are allowed.** Real downloads drop missing steps. Times must still
   increase, by whole multiples of the shortest step; a gap is filled as missing steps
   and counted. A step that is not a whole multiple is the error.
3. **A coverage check, `record_tested`.** "The assessment says how few they are" is
   made a check of its own, in the `data` domain: it warns when under half the steps
   could be tested.
4. **Dry-weather rises have a threshold.** "Rises on average" would flag the noise of
   millimetre rounding on a flat recession. `record_dry_rises` warns above
   `dry_rise_m_per_day = 0.001` (1 mm a day), an argument. A pair of steps belongs to
   the month of its first step.
5. **Fitting a known rating has a threshold.** A period fits a known rating when at
   most `known_fit_share = 0.05` of its steps depart from it, an argument.
6. **A stage shift needs 95% of the shared stages.** "To within the tolerance, over
   the shared stages" is taken as at least 95% of them, so a few rounding departures
   at the curve's ends do not turn a shift into a change of shape.
7. **Steps are tested twice.** The pass a day at a time uses the first flow seen at
   each stage, which is fast. Once every period is closed, each step is tested again
   against its period's finished curve, the median at each stage, and that second
   test is what `off_curve` and the counts report.
8. **The reference example for infill.** A day of flow linearly interpolated across a
   gap stays close to the curve at both ends of the day, so "exactly those steps" was
   not a fair test. The example sets a day's flow 20% high, marked Estimated: every
   step of it departs, and that is what is tested.

One limitation added: **infill at a stage the period has seen nowhere else cannot be
told from the rating**, since the curve at that stage is made from the infill itself.

## Not in scope

- Fitting a rating to the record. The record is not evidence of discharge; it is the
  rating's own output.
- Correcting the record. The check reports; a hydrometrist decides.
- Fetching stage or flow. That belongs to `reach.io`.
