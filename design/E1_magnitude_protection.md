# E1 Magnitude protection for recency weighting

| | |
|---|---|
| Status | IMPLEMENTED, as amended below. Approved by the maintainer on 22 November 2026 ("Go") |
| Release | E (advanced capability), issue #9 |
| Date | 22 November 2026 |
| Reader | The maintainer, and the reviewer who will assess the method against the Release E gate |

## Summary

Recency weighting already exists. It down-weights old gaugings and keeps a floor so no
gauging reaches zero. What it cannot do is tell an old flood from an old routine
gauging. Both decay alike (limitation L10).

This definition adds one opt-in argument pair that **protects large gaugings from age
decay**. A protected gauging keeps its full weight however old it is. Everything else
behaves as it does today. Nothing changes unless the caller asks.

## What issue #9 proposed, and what is kept

The issue proposed `w = w_time × w_magnitude`, and dropped the floor as redundant.
This definition departs from it in two ways.

| Issue #9 | This definition | Reason |
|---|---|---|
| Multiply an age term by a magnitude term | **Blend** them: protected gaugings return to weight 1 | A product can only lower a weight. Protection needs to raise one |
| Drop the floor | **Keep the floor** | It ships, it is documented, and removing it would change existing fits |
| Unbounded or steep magnitude power | A smooth logistic ramp, bounded in [0, 1] | A bounded weight cannot let one anomalous point dominate the fit |

## Definition

Let `w_age,i` be the existing weight:

```
w_age,i = f + (1 - f) * 0.5^(age_i / h)
```

with floor `f` (`age_min_weight`) and half-life `h` (`age_halflife`).

Let `p_i` in [0, 1] be the protection of gauging `i`, from its discharge `Q_i`:

```
p_i = 1 / (1 + exp(-(Q_i - q0) / s))
```

where `q0` is the protection threshold and `s` is the ramp width. The final weight is:

```
w_i = p_i + (1 - p_i) * w_age,i
```

Properties, each of which needs a test:

1. `p_i = 0` gives `w_i = w_age,i`. With no protection, the result is today's.
2. `p_i = 1` gives `w_i = 1`. A fully protected gauging ignores age.
3. `w_age,i <= w_i <= 1`. Protection never lowers a weight and never exceeds 1.
4. `w_i` is monotone non-decreasing in `Q_i` at fixed age.
5. Two gaugings of similar size get similar weight. There is no cliff.

## Interface

Three new arguments on `fit_rating()`, `rate_optimise()` and `rate_optimise_segmented()`:

| Argument | Meaning | Default |
|---|---|---|
| `protect_above` | The threshold `q0`: a single discharge in m3/s | `NULL`: no protection |
| `protect_quantile` | The threshold as a quantile of the gauged discharges, strictly between 0 and 1. Give this or `protect_above`, not both | `NULL` |
| `protect_width` | The ramp width `s`, as a fraction of the discharge range of the evidence | `0.05` |

`protect_above` and `protect_quantile` are the switch, as `age_halflife` is for
recency. Either requires `age_halflife`. Supplying one alone is an error, because there is no age decay to
protect against.

**Where the threshold comes from.** A quantile of the evidence is simple and needs no
outside data, but it moves when gaugings are added. A fixed discharge, or a return
period, is stable and needs a person to supply it. The definition accepts a fixed
value or a quantile. A return period is not accepted, because the package holds no
flood frequency analysis. Which to use is a judgement the caller states and the fit
records.

**Whole record, not per limb.** The threshold applies to the whole evidence set. A
per-limb threshold would protect the top of a low limb, which is not a flood.

## Provenance

The fitted object's provenance records `protect_above` as resolved to a discharge in
m3/s (so a quantile is recorded as the value it produced), `protect_width`, and the
number of gaugings with `p_i > 0.5`. The reference time is already recorded. Refitting
years apart with a different reference time gives a different fit, and the record shows
why.

## Input requirements

- `gauging_datetime` for every gauging used (as for `age_halflife`).
- Finite, positive discharge.
- At least one gauging above the threshold. Otherwise nothing is protected.

## Failure behaviour

| Condition | Behaviour |
|---|---|
| `protect_above` without `age_halflife` | Error: protection has nothing to protect against |
| `protect_above` not a positive number or a valid quantile | Error naming the argument and what is valid |
| `protect_width` not positive | Error |
| No gauging above the threshold | **Warning**, not an error: the fit runs, equal to recency weighting alone, and says so |
| Every gauging protected | Warning: protection has made recency weighting inert |
| Segmented fit | Supported, with the same weights, since both fitters share the weight function |

Every message states what failed, why it matters, and what to do next.

## Reference examples

Two examples, each run in `tests/testthat/test-age_weighting.R`:

1. **Old flood, changed channel.** A set where the low-stage relation has shifted since
   the old gaugings and the high-stage relation has not. Age weighting alone loses the
   old high-stage gaugings. Protection recovers the top of the curve: the largest
   relative error is under half that of age weighting alone. The same example is
   worked in `vignette("recency_weighting_guide")`.
2. **Nothing to protect.** A set whose large gaugings are all recent. Protection
   changes predictions by under 1%. This is the test that the method does no harm.

A third check: with both arguments `NULL` the fit is identical to the previous release.

**Amendment.** The definition proposed adding these to `reference_cases()`. They are
kept out, so that the ten cases, which Release C and the target-environment test
(document 07 of the governance pack) are written around, stay ten. They are tests and a
worked example, not catalogue entries. Both examples are one realisation each, chosen
and tuned by the author, and show the mechanism, not that it is right at a real
station. On other seeds the gain varies: protection was never worse in eight
trials, and the error fell by between 3% and 72%.

## Mathematical changes

None to any existing result. The new weight is reached only through the new argument.
Before and after predictions for all ten reference cases and the shipped example are
compared, and must match to tolerance zero.

## Limitations

- It protects by size, not by importance. A large gauging in a bad measurement is
  protected as well as a good one. `validate_gaugings()` and the influence diagnostics
  still apply, and protection does not replace them.
- The threshold is a judgement, and the fit is sensitive to it. `rating_sensitivity()`
  should be run across thresholds before a rating is approved.
- Protecting the high end can **raise** leverage there. The assessment's influence
  checks will show it, and a reviewer should read them.
- It does not distinguish a genuine flood from a changed channel at high stage. It
  assumes the old high gaugings are still true. That assumption is the user's.
- It has not been tested on a real station (L01).

## Decisions taken

1. Threshold form: a fixed discharge or a quantile, as two arguments (amended from one).
2. Default ramp width: `0.05` of the discharge range.
3. The floor is kept.

## Version history

| Version | Date | Change |
|---|---|---|
| 0.1 | 22 November 2026 | First definition |
| 0.2 | 22 November 2026 | Implemented. Quantile as a separate argument; examples kept as tests, not catalogue cases |
