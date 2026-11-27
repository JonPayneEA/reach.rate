# Check a rating from the flow record

Archived flow is stage passed through whichever rating was applied at
the time, so the archived pairs of stage and flow carry that rating.
`check_flow_record()` reads it back, period by period, and checks it for
what gaugings cannot show: when it changed, where the record departs
from it, how much flow came from above its top, and how far a stage
error moves the flow. It fits nothing, never edits the record, and never
sets a number the caller did not give: a check whose input is missing is
reported as not assessed, with the reason.

The method, its failure behaviour and its limitations are set out in
`design/E3_record_checks.md`.

## Usage

``` r
check_flow_record(
  record,
  top_stage_m = NULL,
  bankfull_stage_m = NULL,
  stage_uncertainty_m = NULL,
  dry = NULL,
  ratings = NULL,
  tolerance = 0.01,
  abs_tolerance = 0.002,
  stage_resolution_m = 0.001,
  max_gap_m = 0.01,
  min_days = 2L,
  off_curve_share = 0.01,
  above_top_share = 0.05,
  known_fit_share = 0.05,
  dry_rise_m_per_day = 0.001,
  min_period_steps = 100L
)
```

## Arguments

- record:

  A data frame or data.table, one row per step, with `time` (POSIXct,
  UTC, the step's start), `stage_m` (metres above the gauge datum),
  `discharge_cms` (archived flow, m3/s) and, optionally, `quality` (the
  archive's quality code for the flow). Times must increase, by whole
  multiples of the shortest step; a gap is a run of missing steps.

- top_stage_m:

  The highest stage the rating is founded on: the highest gauging, or
  the stated limit of its top limb. Enables `record_above_top`.

- bankfull_stage_m:

  The stage above which water may bypass the section. Enables
  `record_above_bankfull`.

- stage_uncertainty_m:

  A stage error, as a systematic offset in metres. Enables
  `record_stage_error`.

- dry:

  Logical, one per row of `record`: `TRUE` where the caller judges no
  rain has fallen on the catchment long enough to matter. Enables
  `record_dry_rises`. On a permeable catchment, flow can go on rising
  for days after rain as the groundwater answers it: weed grows in
  summer, so a rise in a winter month is more likely the catchment than
  the channel.

- ratings:

  Known ratings: a named list of
  [FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md)
  or
  [FlodeRatingTable](https://jonpayneea.github.io/reach.rate/reference/FlodeRatingTable.md),
  or the output of
  [`operational_rating_tables()`](https://jonpayneea.github.io/reach.rate/reference/operational_rating_tables.md).
  Enables `record_known_ratings`.

- tolerance, abs_tolerance:

  A step departs from the curve by more than
  `max(tolerance * C, abs_tolerance)`. Defaults 1% and 0.002 m3/s: flow
  stored to three decimals is 1% out from rounding alone at 0.05 m3/s.

- stage_resolution_m:

  The resolution stage is archived to.

- max_gap_m:

  The widest gap between curve stages a step may be interpolated across.

- min_days:

  Departing days in a row that make a revision.

- off_curve_share:

  Share of a period's flow volume off the curve above which
  `record_off_curve` warns.

- above_top_share:

  Share of flow volume above `top_stage_m` above which
  `record_above_top` warns.

- known_fit_share:

  Share of a period's steps that may depart from a known rating for it
  still to fit.

- dry_rise_m_per_day:

  The mean rise of stage over a month's dry steps, metres a day, above
  which `record_dry_rises` warns.

- min_period_steps:

  A period with fewer tested steps is listed but not assessed.

## Value

A list of class `flode_record_check`:

- assessment:

  A
  [FlodeAssessment](https://jonpayneea.github.io/reach.rate/reference/FlodeAssessment.md),
  one row per check.

- periods:

  One row per period: `period`, `start`, `end`, `steps`, `tested`,
  `stage_min_m`, `stage_max_m`, `assessed`, and the known rating
  matched, where `ratings` is given.

- curves:

  A list of data.tables (`stage_m`, `discharge_cms`), one per period:
  the rating read back.

- revisions:

  One row per revision: `time`, `from_period`, `to_period`, `kind`
  (`"stage shift"` or `"change of shape"`), `shift_m`, `flow_change` (at
  the new period's median stage, as a fraction).

- off_curve:

  One row per run of departing steps: `period`, `start`, `end`, `steps`,
  `volume_share`, `quality`.

- above:

  Peaks above the top and bankfull stages: `limit`, `start`, `end`,
  `peak_time`, `peak_stage_m`, `peak_discharge_cms`; with the shares of
  volume in attribute `shares`.

- stage_error:

  By year and flow band: the volume change from the offset raised and
  lowered, m3 and as a share.

- dry_rises:

  By month: dry steps, mean stage change and flow change a day.

- steps:

  The record with `period`, `curve_cms`, `tested` and `departs` added.

- counts:

  Steps in, missing stage, missing flow, tested, untested.

- settings:

  Every argument, as used.

## Details

The thresholds are best-endeavours defaults, not EA policy (limitation
L02).

## How the rating is read back

An applied rating is exact: the archived flow at a stage is the rating's
flow there, less rounding. A step **departs** when
`|Q - C(h)| > max(tolerance * C(h), abs_tolerance)`, with `C` the curve
read back for the step's period. The curve is, at each distinct stage
(to `stage_resolution_m`), the median flow recorded there, linearly
interpolated between stages at most `max_gap_m` apart. A step at a stage
the period has not yet seen is untested; nothing is extrapolated.

The record is read a day at a time. A day **departs** when more than
half its tested steps depart. A departing day followed by departing
days, making `min_days` in a row, closes the period: a **revision**,
dated at the first departing step of the first such day. Shorter runs
are reported as off the curve. Each revision is classed as a **stage
shift** of `d` metres when the new curve is the old one moved by `d`
(`C_new(h) = C_old(h + d)` at 95% of the stages both cover), or a
**change of shape** otherwise.

## See also

[`compare_gaugings_to_rating()`](https://jonpayneea.github.io/reach.rate/reference/compare_gaugings_to_rating.md),
which tests a rating against gaugings: the record shows the rating as
applied, the gaugings whether it is right.

## Examples

``` r
# A year of a known rating, Q = 5 (h - 0.1)^1.6, with a revision part way:
# from 1 July the flow is the same rating read 0.05 m higher.
time <- seq(as.POSIXct("2024-01-01", tz = "UTC"), by = 900, length.out = 35136)
stage <- round(0.45 + 0.25 * sin(2 * pi * seq_along(time) / 672), 3)
shifted <- time >= as.POSIXct("2024-07-01", tz = "UTC")
flow <- round(5 * (stage + 0.05 * shifted - 0.1)^1.6, 3)
out <- check_flow_record(data.frame(time = time, stage_m = stage, discharge_cms = flow))
out$revisions
#>          time from_period to_period        kind shift_m flow_change
#>        <POSc>       <int>     <int>      <char>   <num>       <num>
#> 1: 2024-07-01           1         2 stage shift    0.05   0.2337526
assessment_checks(out$assessment)[, .(check_id, status)]
#>                 check_id       status
#>                   <char>       <char>
#> 1:         record_tested         pass
#> 2:      record_revisions      warning
#> 3:      record_off_curve         pass
#> 4:      record_above_top not_assessed
#> 5: record_above_bankfull not_assessed
#> 6:    record_stage_error not_assessed
#> 7:      record_dry_rises not_assessed
#> 8:  record_known_ratings not_assessed
```
