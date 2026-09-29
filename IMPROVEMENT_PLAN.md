# Improvement plan

This plan turns `reach.rate` from a broad analytical toolkit into a
governed system for building, testing, reviewing and applying
stage-discharge ratings. It replaces `ROADMAP.md`. Each Release A and B
tranche has its own issue; Releases C (#53), D (#54) and E (#55) have
one tracking issue each, to be split once the earlier gates are passed.

The first successful outcome is not another rating method. It is a safe
route from a real user file to validated evidence, a simple guided API,
and an assessment that separates convergence from acceptability. New
fitting methods wait until Releases A and B pass their gates.

## 1. Where the package stands

The analytical breadth is real. The foundation under it is thin.

| Area | State at `dcc6cab` |
|----|----|
| Exports | 40, all at one level. No primary workflow. [`rate_optimise()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise.md) takes bare vectors. |
| Tests | 17 files, 239 `test_that()` blocks. Every export except [`rating_curve_explorer()`](https://jonpayneea.github.io/reach.rate/reference/rating_curve_explorer.md) has at least one test file. |
| Evidence | `@gaugings` holds `stage_m`, `discharge_cms`, optional `gauging_datetime`. No evidence ID, source type, quality code or exclusion record. |
| Status | `@status` records fit origin only (`independently_fitted`, `post_fit_aligned`, `constrained_refit`). No lifecycle. |
| Provenance | A free-form list. No schema version. |
| Convergence | Partial: `n_starts_converged`, `selected_start_id`, `near_bound` (exponent only), asymptotic SEs. No stable status vocabulary, no multi-start spread, no parameter correlation. |
| Docs | 11 vignettes and a walkthrough script. About 69 direct `@` accesses in README, vignettes and the walkthrough; 199 more in tests. [`vignette("s7_objects_guide")`](https://jonpayneea.github.io/reach.rate/articles/s7_objects_guide.md) teaches `@` access. |
| CI | pkgdown build only. No `R CMD check`, no Windows, no coverage. |
| Silent recovery | [`rate_optimise_constrained()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise_constrained.md) warns and keeps the unconstrained fit when a constrained refit returns a bad `C` (`R/rate_optimise.R:926`). The fallback is recorded only in a warning. |
| Parity gap | `FlodeSegmentedRating` has no equivalent of the four diagnostic functions or [`as_rating_table()`](https://jonpayneea.github.io/reach.rate/reference/as_rating_table.md). |

Package checks could not be run in the session that wrote this plan,
because the container had no R installation. Tranche A1 records the true
baseline.

### Baseline (A1)

Recorded from the first CI run on PR \#56 (head `ef71aa1`, 29 September
2026).

| Matrix cell         | `R CMD check` | Tests                         |
|---------------------|---------------|-------------------------------|
| Windows, R release  | ERROR         | 698 pass, 3 fail, 15 warnings |
| Windows, R oldrel-1 | ERROR         | 698 pass, 3 fail, 12 warnings |
| Ubuntu, R release   | ERROR         | 691 pass, 4 fail, 16 warnings |
| Ubuntu, R oldrel-1  | ERROR         | 691 pass, 4 fail, 12 warnings |

The test errors dominated the first run’s output. Once they were fixed,
two further findings from earlier check stages surfaced on every cell:

- **WARNING, codoc mismatch** in the four S7 class Rd files. The
  `data.table` properties had no explicit default, so S7 supplied a call
  to a placeholder constructor whose deparsed form changed between S7
  releases. The Rd `\usage` recorded one form; CI’s S7 produced another.
- **NOTE, undeclared globals**: data.table column names used in
  non-standard evaluation (`age_weight`, `stage_m`, `limb` and others),
  the `.()` alias, and
  [`stats::uniroot`](https://rdrr.io/r/stats/uniroot.html) missing from
  the imports.

**One root cause for every failure.** Plot labels contain characters
outside Latin-1: `\u0394` (Greek capital delta), `\u2212` (minus sign),
`\u2080` (subscript zero) and `\u2014` (em dash). R’s default
[`pdf()`](https://rdrr.io/r/grDevices/pdf.html) device, which
`R CMD check` uses for tests, cannot encode them, and R 4.5 turns the
conversion failure into an error. `\u00b3`, `\u00b2` and `\u00b7` are
Latin-1 and render correctly. Any user saving these plots to PDF hits
the same fault. Failing tests:

- `test-compare_ratings.R:84`:
  [`plot_rating_comparison()`](https://jonpayneea.github.io/reach.rate/reference/plot_rating_comparison.md)
  y-axis label (`R/compare_ratings.R:211-212`).
- `test-gap_check.R:275` and `test-rating_curve_demo.R:54`:
  [`plot_rc_gaps()`](https://jonpayneea.github.io/reach.rate/reference/plot_rc_gaps.md)
  gap labels and title (`R/gap_check.R:1502,1535`).
- `test-cross_section_rating_dual_plot.R:10` (Ubuntu only): subtitle and
  title in
  [`demo_cross_section_rating()`](https://jonpayneea.github.io/reach.rate/reference/demo_cross_section_rating.md)
  (`R/cross_section_rating_dual_plot.R:312,316`).

Fixed in PR \#56: the glyphs became Latin-1 text and plotting tests now
fail on any PDF conversion warning; the four classes gained an explicit
`data.table()` default, so their usage deparses identically on every S7
release. The globals NOTE does not fail CI and is left for A2, which
already touches the namespace.

**Warnings worth tracking.** `geom_label(label.size = )` and
`sec_axis(trans = )` are deprecated since ggplot2 3.5.0 and will break
in a later ggplot2 release. The remaining warnings are the package’s
own, expected by the tests that raise them.

**Coverage.** 85.7% line coverage; all 707 tests pass under covr, which
does not render to PDF. Weakest files: `rating_curve_explorer_app.R`
(0%, the Shiny app), `zzz.R` (0%, `.onLoad`), `flode_classes.R` (35.6%,
print methods and validators).

## 2. Decisions taken

These were settled before writing. Each tranche assumes them.

1.  **Object model: extend, add two classes.** `FlodeRating`,
    `FlodeSegmentedRating` and `FlodeRatingTable` remain the fit
    objects. Two classes are added: `FlodeEvidence` (the canonical
    evidence table) and `FlodeAssessment` (structured checks).
    `@gaugings` becomes a `FlodeEvidence`. Limbs, history and provenance
    stay as tables and lists inside the fit. The brief’s eight-class
    hierarchy is not built; section 13 of the brief warns against
    exactly that.
2.  **Status splits in two.** `fit_origin` keeps the existing three
    values. `lifecycle` is new: `draft` (default), `under_review`,
    `approved`, `superseded`, `withdrawn`. The package never sets
    `approved` itself.
3.  **Exports: staged deprecation.**
    [`suggested_breakpoints_vector()`](https://jonpayneea.github.io/reach.rate/reference/suggested_breakpoints_vector.md)
    folds into
    [`suggest_breakpoints()`](https://jonpayneea.github.io/reach.rate/reference/suggest_breakpoints.md)
    output;
    [`bootstrap_to_table()`](https://jonpayneea.github.io/reach.rate/reference/bootstrap_to_table.md)
    becomes an accessor. Both warn through base
    [`.Deprecated()`](https://rdrr.io/r/base/Deprecated.html) for one
    minor release, then leave the namespace.
    [`rating_curve_explorer()`](https://jonpayneea.github.io/reach.rate/reference/rating_curve_explorer.md)
    and
    [`run_demo()`](https://jonpayneea.github.io/reach.rate/reference/run_demo.md)
    stay exported under a “Teaching tools” reference heading, labelled
    as synthetic-data demonstrations. No `lifecycle` dependency.
4.  **Guided objective defaults to relative.** `fit_rating()` defaults
    to `objective = "relative"`, because gauging error scales roughly
    with discharge.
    [`rate_optimise()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise.md)
    keeps `"absolute"`, so existing expert code and results do not move.
    The mathematical contract states both equations and when they
    diverge.
5.  **CI matrix.** `R CMD check` on `windows-latest` and
    `ubuntu-latest`, each on R release and oldrel-1, plus coverage on
    Linux. Support below oldrel-1 is either proven or stated as
    untested.
6.  **Spreadsheets through `readxl` in Suggests.** `read_gaugings()`
    fails with an instruction to install it when given an `.xlsx`
    without it.
7.  **Old roadmap frozen as P3.** Issues \#9, \#10 and \#11 stay open,
    labelled `P3: deferred`, and wait for the Release E gate.

## 3. Implementation inventory

The P0.1 audit, one row per export. “Tests” and “Vignettes” count files
that mention the function. Recommended action maps each export onto the
API categories in section 4.

| Function or class | Source | Tests | Vignettes | Known risk | Action |
|----|----|----|----|----|----|
| [`rate_optimise()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise.md) | rate_optimise.R | 10 | 11 | Vector input; no evidence IDs; absolute default | Advanced modelling; called by `fit_rating()` |
| [`rate_optimise_constrained()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise_constrained.md) | rate_optimise.R | 3 | 4 | Fallback to unconstrained fit is recorded only in a warning | Advanced; record fallback in history |
| [`rate_optimise_segmented()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise_segmented.md) | rate_optimise_segmented.R | 3 | 6 | No diagnostic parity with `FlodeRating` | Advanced; close parity gap in B2 |
| [`rate_from_cross_section()`](https://jonpayneea.github.io/reach.rate/reference/rate_from_cross_section.md) | rate_from_cross_section.R | 1 | 3 | Output not yet evidence with `source_type = "cross_section"` | Advanced; emit `FlodeEvidence` |
| `weir_discharge_*()`, [`flume_discharge_parshall()`](https://jonpayneea.github.io/reach.rate/reference/flume_discharge_parshall.md) | weir_equations.R | 1 | 2-3 | As above, `structure_equation` | Specialist; emit `FlodeEvidence` |
| [`suggest_breakpoints()`](https://jonpayneea.github.io/reach.rate/reference/suggest_breakpoints.md) | rate_optimise.R | 1 | 2 | Output reads as a finding, not a candidate | Advanced; reframe in B5 |
| [`suggested_breakpoints_vector()`](https://jonpayneea.github.io/reach.rate/reference/suggested_breakpoints_vector.md) | rate_optimise.R | 1 | 2 | Reads an attribute; attributes are fragile | Deprecate; fold into return value |
| [`align_limb_equations()`](https://jonpayneea.github.io/reach.rate/reference/align_limb_equations.md), [`align_limb_boundaries()`](https://jonpayneea.github.io/reach.rate/reference/align_limb_boundaries.md) | gap_check.R | 1 | 3-4 | Coefficient changes need before/after reporting | Advanced; feed `check_limb_continuity()` |
| [`detect_rc_gaps()`](https://jonpayneea.github.io/reach.rate/reference/detect_rc_gaps.md), [`resolve_rc_gaps()`](https://jonpayneea.github.io/reach.rate/reference/resolve_rc_gaps.md), [`plot_rc_gaps()`](https://jonpayneea.github.io/reach.rate/reference/plot_rc_gaps.md) | gap_check.R | 1 | 2-3 | Single discharge-gap tolerance | Diagnostics; superseded in part by B6 |
| [`expand_rating_table()`](https://jonpayneea.github.io/reach.rate/reference/expand_rating_table.md) | gap_check.R | 1 | 3 | None material | Advanced gap tool; keep |
| [`graft_rating()`](https://jonpayneea.github.io/reach.rate/reference/graft_rating.md) | graft_rating.R | 1 | 4 | Coefficient change must reach history | Advanced; keep |
| [`flag_extrapolated_limbs()`](https://jonpayneea.github.io/reach.rate/reference/flag_extrapolated_limbs.md) | rate_optimise.R | 2 | 3 | One flag, no support classes | Diagnostics; extended by B3 |
| [`flag_influential_gaugings()`](https://jonpayneea.github.io/reach.rate/reference/flag_influential_gaugings.md), [`plot_rating_leverage()`](https://jonpayneea.github.io/reach.rate/reference/plot_rating_leverage.md) | rate_optimise.R | 1 | 2 | Links by row, not evidence ID | Diagnostics; feed B4 |
| [`plot_rating_residuals()`](https://jonpayneea.github.io/reach.rate/reference/plot_rating_residuals.md) | rate_optimise.R | 2 | 4 | None material | Plotting; B7 grammar |
| [`apply_rating()`](https://jonpayneea.github.io/reach.rate/reference/apply_rating.md), [`apply_rating_inverse()`](https://jonpayneea.github.io/reach.rate/reference/apply_rating_inverse.md) | apply_rating.R | 3, 1 | 3 | No support classification on output | Primary (application); B3 |
| [`apply_rating_interval()`](https://jonpayneea.github.io/reach.rate/reference/apply_rating_interval.md), [`plot_rating_interval()`](https://jonpayneea.github.io/reach.rate/reference/plot_rating_interval.md) | apply_rating.R, rating_curve_demo.R | 1 | 1-2 | Interval meaning not stated | Advanced; mathematical contract |
| [`apply_rating_versioned()`](https://jonpayneea.github.io/reach.rate/reference/apply_rating_versioned.md) | apply_rating.R | 1 | 2 | Precursor of temporal ratings | Advanced; freeze until P3.2 |
| [`as_rating_table()`](https://jonpayneea.github.io/reach.rate/reference/as_rating_table.md) | flode_classes.R | 5 | 4 | Missing for segmented fits | Conversion |
| [`bootstrap_to_table()`](https://jonpayneea.github.io/reach.rate/reference/bootstrap_to_table.md) | rating_curve_demo.R | 1 | 2 | Helper exposed as API | Deprecate; replace with accessor |
| [`compare_ratings()`](https://jonpayneea.github.io/reach.rate/reference/compare_ratings.md), [`plot_rating_comparison()`](https://jonpayneea.github.io/reach.rate/reference/plot_rating_comparison.md) | compare_ratings.R | 1 | 1-2 | Name already matches the brief | Primary; extend in Release C |
| [`rating_plot()`](https://jonpayneea.github.io/reach.rate/reference/rating_plot.md), [`plot_rating_curves()`](https://jonpayneea.github.io/reach.rate/reference/plot_rating_curves.md) | flode_classes.R, plot_rating_curves.R | 3, 1 | 1-4 | Two plotting entry points | Plotting; consolidate behind [`plot()`](https://rdrr.io/r/graphics/plot.default.html) in B7 |
| [`plot_rating_cross_section()`](https://jonpayneea.github.io/reach.rate/reference/plot_rating_cross_section.md), [`demo_cross_section_rating()`](https://jonpayneea.github.io/reach.rate/reference/demo_cross_section_rating.md) | plot_rating_cross_section.R, cross_section_rating_dual_plot.R | 2, 1 | 1-2 | Demo exported beside real tool | Specialist; demo to Teaching tools |
| [`rating_curve_explorer()`](https://jonpayneea.github.io/reach.rate/reference/rating_curve_explorer.md) | rating_curve_explorer_app.R | 0 | 1 | Untested; duplicates workflow | Teaching tools |
| [`run_demo()`](https://jonpayneea.github.io/reach.rate/reference/run_demo.md) | rating_curve_demo.R | 1 | 0 | Synthetic data only | Teaching tools |
| `FlodeRatingBase`, `FlodeRating`, `FlodeSegmentedRating`, `FlodeRatingTable` | flode_classes.R | 1-10 | 2-5 | Internals taught directly | Object access through accessors only |

## 4. Target public API

A novice completes the common workflow with six functions:

``` r

gaugings   <- read_gaugings("site_gaugings.csv", stage = "Stage", discharge = "Flow")
checks     <- validate_gaugings(gaugings)
rating     <- fit_rating(gaugings)
assessment <- assess_rating(rating)
plot(rating)
export_rating(rating, assessment, path = "site_rating")
```

Reference sections, in order: Primary workflow; Accessors; Diagnostics;
Plotting; Advanced modelling; Specialist hydraulics; Conversion and
export; Teaching tools; Deprecated.

Accessors: `rating_limbs()`, `rating_coefficients()`,
`rating_evidence()`, `rating_diagnostics()`, `rating_history()`,
`rating_provenance()`, `rating_support()`, `rating_bootstrap()`. Each
returns a `data.table` with unit-suffixed columns, or a documented list.

## 5. Release A: Foundation (P0)

Nine tranches, each one pull request. Order matters: CI comes first
because nothing after it can be proved without it.

**A1. Baseline and CI** (#36). Add `R-CMD-check.yaml` (matrix in
decision 5) and `test-coverage.yaml`. Build vignettes in check. Record
the baseline: failing tests, check notes, coverage figure. Fix nothing
yet except CI plumbing. *Done when* CI runs on every PR and the baseline
is written into this file.

**A2. Public API and reference index** (#37). Restructure `_pkgdown.yml`
to section 4. Apply the deprecations in decision 3. Rewrite the README
to lead with the primary workflow, marking unbuilt functions as planned.
Clear the globals NOTE left by A1. *Done when* every export sits in one
category and deprecated functions warn. *As delivered:* the index groups
exports by job; sections with no members yet (primary workflow,
accessors) are described in the section text rather than listed empty.
[`suggested_breakpoints_vector()`](https://jonpayneea.github.io/reach.rate/reference/suggested_breakpoints_vector.md)
is deprecated in favour of a `selected` column on
[`suggest_breakpoints()`](https://jonpayneea.github.io/reach.rate/reference/suggest_breakpoints.md)
output.
[`bootstrap_to_table()`](https://jonpayneea.github.io/reach.rate/reference/bootstrap_to_table.md)
moves to A3, because its replacement, `rating_bootstrap()`, is an
accessor: deprecating it before the replacement exists would leave users
with a warning and nowhere to go.

**A3. Accessors** (#38). Add the eight accessors with success and
failure tests. Replace every `@` access in README, vignettes and
`walkthrough.R`. Rewrite
[`vignette("s7_objects_guide")`](https://jonpayneea.github.io/reach.rate/articles/s7_objects_guide.md)
as a maintainer guide. Tests may keep `@` where they test the class
itself. *Done when* `grep '@[a-z]' README.md vignettes/ inst/examples/`
finds no property access.

**A4. `FlodeEvidence` and the status split** (#39). New class with the
canonical schema: `evidence_id`, `site_id`, `stage_m`, `discharge_cms`,
`observation_time`, `source_type`, `source_name`, `source_version`,
`quality_code`, `included`, `exclusion_reason`, `weight`, `notes`, plus
a `source_row` link and a list column for source-specific metadata.
Controlled `source_type` vocabulary per the brief. `@gaugings` takes a
`FlodeEvidence`; a plain `data.table` passed to a fitter converts with
generated IDs and a recorded conversion note. Split `@status` into
`fit_origin` and `lifecycle`. Add `schema_version` to provenance. Bump
to 0.2.0; NEWS states the break. *Done when* evidence IDs survive fit,
diagnostics, [`saveRDS()`](https://rdrr.io/r/base/readRDS.html) and
[`readRDS()`](https://rdrr.io/r/base/readRDS.html), and the validator
rejects a read-back object with a missing or future schema version.

**A5. `read_gaugings()`** (#40). CSV and delimited text through
[`data.table::fread()`](https://rdrr.io/pkg/data.table/man/fread.html),
spreadsheets through `readxl`. Explicit column mapping; original names,
values and row numbers kept; problem rows returned with reasons; nothing
removed. Prints the brief’s summary, backed by a structured table. *Done
when* the 18 input cases in P0.5 of the brief each have a test fixture
under `tests/testthat/fixtures/`.

**A6. `validate_gaugings()` and `FlodeAssessment`** (#41). Introduce the
check-table schema here: `check_id`, `domain`, `severity`, `status`
(`pass`, `warning`, `fail`, `not_assessed`), `message`,
`affected_evidence`, `affected_stage_min_m`, `affected_stage_max_m`,
`recommendation`. Technical checks fail; hydrometric checks warn and
never exclude. [`print()`](https://rdrr.io/r/base/print.html) and
[`plot()`](https://rdrr.io/r/graphics/plot.default.html) methods. *Done
when* each check has its own pass and fail test, and `assess_rating()`
can reuse the class unchanged.

**A7. Mathematical contract** (#42). New vignette
`mathematical_contract`: exact equation (`Q = C(H - a)^n`, internal
convention), units of `C`, `a`, `n`, both objective functions written as
equations, weighting (including age weighting), zero and negative
handling, starting-value strategy, multi-start selection rule,
convergence criteria, and what each interval means. Add
`convert_offset_convention()` if an external system uses `H + a`. *Done
when* printed equations match the implemented ones by test, conversion
round-trips in both directions, and each objective has a hand-checkable
test.

**A8. Post-fit invariants** (#43). One internal `.check_invariants()`
run after every fitter: finite coefficients and predictions, domain
validity, monotonicity, ordered limbs, declared gaps and overlaps,
continuity within tolerance, inverse consistency, interval ordering,
bound compliance. Results stored as `FlodeAssessment` rows on the fit.
Hard failures block
[`apply_rating()`](https://jonpayneea.github.io/reach.rate/reference/apply_rating.md)
and export.
[`rate_optimise_constrained()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise_constrained.md)’s
fallback becomes a recorded history entry, not only a warning. *Done
when* each invariant has a failure test and
[`print()`](https://rdrr.io/r/base/print.html) shows “converged” and
“valid” as separate lines.

**A9. Convergence and identifiability** (#44). Stable per-limb columns:
`converged`, `convergence_code`, `convergence_message`, `iterations`,
`objective_value`, `bound_hits` (all parameters, not only `n`),
`multi_start_spread`, `parameter_correlation`, `condition_number`. `NA`
with `not_assessed` where `nlsLM` does not supply a value. *Done when*
tests cover convergence, non-convergence, bound hits and divergent
multi-start solutions.

**Release A gate.** A user imports an untidy real file, receives precise
feedback, and fits a simple rating without touching an S7 property. CI
is green on all four matrix cells; vignettes build; no test fails.

## 6. Release B: Guided workflow (P1)

**B1. `fit_rating()`** (#45). Orchestrates
[`rate_optimise()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise.md)
and
[`rate_optimise_segmented()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise_segmented.md).
One limb by default. Multiple limbs only with explicit `controls` or
`limbs = "suggest"`, and suggested boundaries stay advisory. Relative
objective by default. Stores the call, the seed and every attempted fit.
Operational limits required before unrestricted application.

**B2. `assess_rating()`** (#46). Five domains (data, numerical,
statistical, hydraulic, operational) plus provenance, built on A6 and
A8. No summary score. Closes the segmented-fit diagnostic gap so both
fit classes assess alike.

**B3. Support and extrapolation** (#47). `rating_support()` returns
observed, modelled, fitted, operational and numerical stage ranges.
[`apply_rating()`](https://jonpayneea.github.io/reach.rate/reference/apply_rating.md)
gains a `support` column: `interpolation_observed`,
`interpolation_mixed`, `model_supported`, `extrapolation`,
`outside_operational_range`; beyond the numerical range it fails.
Supersedes the single flag in
[`flag_extrapolated_limbs()`](https://jonpayneea.github.io/reach.rate/reference/flag_extrapolated_limbs.md).

**B4. `rating_sensitivity()`** (#48). Leave-one-out,
leave-high-flow-out, starting values, boundary shift. Reports
consequences in discharge space, linked to evidence IDs. Reuses the
leverage code in `.rating_leverage_dt()`.

**B5. Breakpoint candidates** (#49).
[`suggest_breakpoints()`](https://jonpayneea.github.io/reach.rate/reference/suggest_breakpoints.md)
returns candidates with evidence on each side, improvement over the
simpler model and failed fits. Accepted boundaries record their origin
(`field_evidence`, `cross_section`, `structure_geometry`,
`user_judgement`, `statistical_candidate`, `existing_rating`, `other`).

**B6. `check_limb_continuity()`** (#50). Absolute and relative discharge
tolerance plus stage tolerance, before and after alignment, derivative
difference where assessed. Builds on
[`detect_rc_gaps()`](https://jonpayneea.github.io/reach.rate/reference/detect_rc_gaps.md).

**B7. Plot grammar** (#51).
[`plot()`](https://rdrr.io/r/graphics/plot.default.html) method on each
fit class returning ggplot2. Shape by source type, muted exclusions,
bands for uncertainty, support ranges shaded, units on axes, status in
the caption. Fold
[`rating_plot()`](https://jonpayneea.github.io/reach.rate/reference/rating_plot.md)
and
[`plot_rating_curves()`](https://jonpayneea.github.io/reach.rate/reference/plot_rating_curves.md)
behind it with staged deprecation where they overlap.

**B8. Documentation rebuild** (#52). New “Start here” vignette that
opens with a user’s CSV. Each vignette declares its audience (novice,
practitioner, technical, specialist). Glossary. Mermaid diagrams for the
workflow. `station_gaugings` relabelled as teaching data.

**Release B gate.** A novice completes the six-function workflow; an
expert drops to
[`rate_optimise()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise.md)
without friction. Print output distinguishes candidate, converged,
valid, requiring review, reviewed and approved.

## 7. Releases C, D and E

**Release C: Review and reproducibility (P2), \#53.** Extend
[`compare_ratings()`](https://jonpayneea.github.io/reach.rate/reference/compare_ratings.md)
to evidence and support; `rating_report()` through a Quarto or R
Markdown template regenerated from stored objects; `export_rating()` and
`import_rating()` with round-trip tests; lifecycle metadata fields; a
reference-case suite of the ten cases in P2.1 of the brief, tested on
prediction envelopes rather than exact coefficients; schema migration; a
release and deprecation policy. *Gate:* a competent analyst reproduces
and reviews a rating without asking the author.

**Release D: Operational readiness (P2), \#54.** Mostly documents, not
code: ownership, dependency inventory, limitations register, runbook,
fallback and rollback, handover, target-environment test on EA managed
machines, independent review. The Tier 3 classification in the source
headers makes this gate mandatory before live forecasting use. *Gate:*
agreed governance requirements met; passing checks alone do not qualify.

**Release E: Advanced capability (P3), \#55.** Evidence weighting
(explicit, never automatic), temporal ratings (builds on
[`apply_rating_versioned()`](https://jonpayneea.github.io/reach.rate/reference/apply_rating_versioned.md)),
hysteresis only with time-ordered evidence, separated uncertainty
sources, rating inventory. Issues \#9, \#10 and \#11 live here. *Gate:*
each method has a formal definition, input requirements, failure
behaviour, reference examples and stated limitations.

## 8. Definition of done

Every tranche PR carries: implementation; input validation; stable
output schema; roxygen docs; errors stating what failed, why it matters,
which input caused it and what to do next; success, failure and
adversarial tests; a worked example; a NEWS entry; a note on
mathematical changes, or an explicit statement that there are none;
before-and-after prediction comparison for any refactor of fitting code;
green CI.

## 9. Not before Releases A and B

New optimisation engines, Bayesian fitting, automatic approval,
automatic model or breakpoint selection, quality scores, automatic
weighting, dashboards, further Shiny work, operational-system
integration, and unprofiled performance work.
