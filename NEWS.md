# reach.rate (development)

* Release C: **`rating_report()`**, a self-contained HTML page for a reviewer.
  It shows the rating's status and lifecycle, its equations and plot, the
  evidence and what was left out, every assessment check that did not pass with
  what to look at, what each stage range rests on, how the rating was made and
  what has been done to it since, and a short list of questions for the reviewer.
  It is drawn from the stored objects only and never refits, so the same rating
  gives the same report from the live session or from a folder made by
  `export_rating()` (tested). It says on its first page that it does not approve
  the rating, and it never changes the lifecycle. The equation is plain text, not
  MathJax, so the page needs no network. It uses `rmarkdown`, `knitr` and pandoc,
  which stay suggested, and says what is missing if they are not there.

* Release C: **`export_rating()` and `import_rating()`**, the sixth step of the
  guided workflow. `export_rating(rating, assessment, path)` writes a folder a
  reviewer can read without R: the rating and assessment as `.rds` (the record),
  the same content as plain CSV tables (limbs, coefficients, evidence, history,
  support, assessment checks), a README, and a `manifest.csv` of file sizes and
  MD5 checksums. `import_rating(path)` checks every file against the manifest
  first, so a damaged or edited file is named and not read, then returns the
  rating as it went in, equal in every value with no tolerance (not `identical()`,
  which no R object passes after a write and read, because `data.table` keeps
  internal pointers that differ), with its assessment.
  Exporting never changes the rating or its lifecycle. The `.rds` is the record:
  evidence `metadata` is a list column and is left out of the CSV only. An
  existing export is not overwritten unless `overwrite = TRUE`, and then only
  the files this function writes are replaced. Schema migration has its
  mechanism in place (`import_rating()` refuses a rating from an older schema
  with no migration, and from a newer one, with the reason) but no migrations
  yet, since schema version 2 is the first. `tools` is now an import, for the
  checksums.

* Release C begins with **`vignette("thresholds")`**, a practitioner article
  on every limit in `validate_gaugings()` and `assess_rating()`: its default
  (read from the functions when the page is built, so it cannot drift), what it
  flags, and whether its basis is arithmetic, convention or judgement. It says
  plainly that **there is no Environment Agency guidance for these limits**, that
  the values are best endeavours and not policy, and that every one is an
  argument you can change. A worked example shows a stricter set of limits moving
  checks from pass to warning.

* **Behaviour change: extrapolation is flagged, not refused.** A rating from
  `fit_rating()` with no operational limits used to refuse any stage beyond
  its gauged range. Flood forecasting needs discharge above the highest
  gauging, so `apply_rating()` now returns the value, marks it `extrapolation`
  in the `support` column and warns once per call. A rating with stated
  limits still refuses stages outside them, since that range was a decision.
  The same applies to segmented ratings.

* **Fix: `autoplot()` under S7 1.0.0.** Registering S7 methods with
  `method(autoplot, Class) <- fn` assigns its result back to `autoplot`, and
  under S7 1.0.0 that result is a placeholder, which replaced the real
  function and left the exported `autoplot()` unusable (`print` and `plot`
  were replaced inside the namespace in the same way). Methods are now
  registered against separate handles in `R/s7_external.R`, which works on
  every S7 version. A test holds that the real functions stay in place.

* Tranche B8 of the improvement plan: the documentation, rebuilt around a
  reader. **`vignette("start_here")`** opens with a file, not with the
  package: it reads a CSV of gaugings (a synthetic station in the layout of an
  Environment Agency export, shipped as `inst/extdata/example_gaugings.csv`,
  with faults put in on purpose), checks it, fits a rating, draws it, assesses
  it, applies it with support classes and operational limits, and tests how
  much it depends on the highest gaugings. It uses the six-function workflow
  and says what is not built yet. **`vignette("glossary")`** explains the words.
  **Every vignette now declares its audience** (novice, practitioner,
  technical or specialist) on its first line, and a test holds that. The
  reference site has a new "Start here" group, and the workflow diagram is
  drawn with Mermaid on the site (in an installed vignette, without the
  script, it shows as readable source text).

  `station_gaugings` is relabelled **teaching data**, with a note that it is not
  to be used to build an operational rating, and the README leads with the
  starting point.

* Tranche B7 of the improvement plan: one plot grammar. **`autoplot()` and
  `plot()`** now draw a `FlodeRating`, `FlodeSegmentedRating` or
  `FlodeRatingTable` and return a ggplot2 object, so the plot can be added to,
  themed or saved like any other. `autoplot()` is re-exported, so it works
  without attaching ggplot2, and `plot()` gives the same plot. On the plot:
  the **gaugings shaped by source type** (a circle for a gauging, other shapes
  for modelled, cross-section, structure and operational-rating evidence, so
  evidence that is not a measurement cannot be mistaken for one); rows left out
  of the fit drawn **muted and never hidden**; a **95% bootstrap band** where
  the fit made draws; the **stage ranges the rating rests on** shaded (a tint
  over modelled evidence, a grey one where the curve is fitted but no evidence
  lies), with operational limits as dashed lines; **units on the axes**
  (discharge horizontal, stage vertical, the hydrological convention); and the
  rating's **status in the caption**: origin, lifecycle, whether it converged
  and whether it is valid. Evidence is told apart by shape and the status is
  written out, so nothing depends on colour alone. The curve is evaluated
  directly, so a rating that fails its invariants can still be drawn, which is
  how you find out why. `autoplot()` also works on an assessment and a
  sensitivity analysis, as `plot()` already did.

  `fit_rating()` now keeps the stage, discharge and source type of the rows it
  left out, with the reason, in `rating_provenance()$fit_rating$excluded`, so
  they can be shown muted on the plot and checked later. Before, only their ids
  and reasons were kept.

  **`rating_plot()` is superseded** by `autoplot()` and `plot()`. It still
  works and is unchanged, and its documentation says so; it will warn in a
  later release and then be removed. `plot_rating_curves()`, which overlays
  several ratings, does not overlap and stays.

* Tranche B6 of the improvement plan: `check_limb_continuity()`. At each
  junction between two limbs it measures how far the equations are apart at
  the stage they share, from the equations themselves and not from a
  discretised table (which is what `detect_rc_gaps()` scans): the
  **discharge gap** in m3/s and as a fraction, the **stage gap** (how far the
  upper limb would have to move sideways to meet the lower one, the number a
  gauge reader sees as the rating jumping), and the **change of slope**. A
  junction is `continuous` when the discharge gap and the stage gap are within
  tolerance. The discharge gap passes if within `tol_abs` **or** `tol_rel`, so
  a tiny flow is not failed on a percentage and a large one does not need a
  fraction of a cumec. The slope change is reported but judged only if you
  give `tol_slope`, because a change of slope at a breakpoint is what a
  breakpoint is for. A gap exactly on a tolerance passes; comparisons carry a
  1e-9 relative allowance so that floating-point representation error cannot
  fail them.

  With `after =`, it reports the same measures before and after an alignment
  (`align_limb_equations()` or `align_limb_boundaries()`), with the junction
  stage for both, since boundaries can move, and an `improved` flag, so the
  effect of an amendment is on the table and not only claimed. A single limb
  and a segmented fit (continuous by construction) have no junction and give
  an empty table.

* Tranche B5 of the improvement plan: breakpoint candidates.
  `suggest_breakpoints()` now reads as what it is: **candidates for a person to
  review, not findings**. A statistical search sees only the gaugings and cannot
  know where a channel control changes, and the documentation says so. Each
  candidate now carries the evidence on each side: the stage range
  (`lower_min_m`, `lower_max_m`, `upper_min_m`, `upper_max_m`) alongside the
  counts it already had, so a candidate resting on a few crowded gaugings is
  visible whatever its score. A candidate that could not be fitted, or has too
  few gaugings on a side, is listed with a `failure_reason` (the fitter's own
  message, or the counts) and not dropped. The existing columns and the
  `selected` flag are unchanged.

  **Accepted breakpoints record where they came from.** `fit_rating()` takes a
  `breakpoint_origin`, one value or one per breakpoint, from the new
  `breakpoint_origins()`: `field_evidence`, `cross_section`,
  `structure_geometry`, `user_judgement` (the default for `controls`),
  `statistical_candidate` (always the origin of `limbs = "suggest"`),
  `existing_rating` and `other`. It is kept with its stage in
  `rating_provenance()$fit_rating$breakpoints$origin`, shown when the rating is
  printed and in the fit message, and a rating with any statistical candidate
  among its breakpoints is marked advisory. An unknown origin is refused with
  the list of valid ones. The printed word for supplied breakpoints changes from
  "supplied" to the origin, for example `user_judgement`.

* Tranche B4 of the improvement plan: `rating_sensitivity()`. It refits a
  rating with something changed and reports the consequence in **discharge**,
  at stages you can name, in m3/s and as a percentage, linked to the
  `evidence_id`s concerned. Four tests: `leave_one_out` (each gauging in turn,
  with its leverage and Cook's distance alongside, so the influence diagnostic
  and the actual effect can be compared), `leave_high_out` (the top 5%, 10%
  and 20% of gaugings, which shows how far the top of the curve depends on the
  few gaugings taken there), `starting_values` (every other valid starting
  point the optimiser tried, from the record the fit kept, with no refit) and
  `boundary_shift` (each breakpoint moved up and down by a fraction of the
  gauged range, then refitted).

  Each refit reproduces the settings the rating recorded (objective, bounds,
  breakpoints, recency weighting and its reference time, multi-start), so the
  only difference is the change under test; every variant is tested against a
  refit made by hand. A refit that cannot be made, because a limb would be left
  with fewer than three gaugings for instance, is reported with its reason and
  never dropped. A rating that has been amended since it was fitted cannot be
  refitted faithfully and is refused; so is an equation table. A segmented fit
  supports leave-one-out, leave-high-out and (with fixed breakpoints) boundary
  shift. `leave_one_out` refuses more than `max_refits` (200) refits unless
  restricted with `evidence_ids`.

  The result is a `FlodeSensitivity`, with `sensitivity_summary()` (one row per
  variant: the largest change and the stage it happens at) and
  `sensitivity_results()` (every variant at every stage). `print()` gives the
  worst case for each test in words, and `plot()` draws the change in
  discharge against stage.

* Tranche B3 of the improvement plan: support and extrapolation.
  `apply_rating()` gains a **`support`** column saying what each stage rests
  on: `interpolation_observed` (inside the gaugings), `interpolation_mixed`
  (inside the evidence but outside the gaugings, so resting on modelled
  evidence), `model_supported` (inside the fitted range with no evidence
  there, as after `extend_rating_low()` or `graft_rating()`), `extrapolation`
  (beyond the fitted range) and `outside_operational_range` (beyond stated
  limits, which outranks the others). A stage beyond the **numerical range**,
  where the top limb's equation overflows, now fails with an error, since the
  result would not be a number. The existing `extrapolated` flag is
  unchanged.

  **`rating_support()` changes its default.** It now returns the five stage
  ranges a rating rests on (observed, modelled, fitted, operational,
  numerical) with how many pieces of evidence stand behind each. The per-limb
  table from tranche A3 is still there as `rating_support(x, by = "limb")`.
  Only gaugings count as observed; modelled, cross-section, structure and
  operational-rating evidence is the modelled range. It works for a
  `FlodeRatingTable` too (equations only, so no evidence ranges).
  `flag_extrapolated_limbs()` is kept for marking doubtful limbs, and says
  that the support classes supersede its single flag.

  **A gap closed in earlier tranches.** `apply_rating()` on a *segmented*
  fit now goes through the same post-fit invariant gate (A8) and, for a fit
  made by `fit_rating()`, the operational-limits requirement (B1). Neither
  applied to the segmented method before.

* Tranche B2 of the improvement plan: `assess_rating()`. It looks at a
  rating from six sides and returns what it found as a `FlodeAssessment`:
  **data** (`validate_gaugings()` on the evidence the rating used),
  **numerical** (the technical checks of `rating_invariants()`, and whether
  the optimiser converged), **statistical** (bias, spread and trend of the
  residuals per limb, limb support, parameter identifiability, multi-start
  agreement, parameters on a bound, influential gaugings), **hydraulic**
  (plausible exponents and zero-flow stage, and the hydrometric invariants),
  **operational** (whether limits are stated, how far they reach beyond the
  gauged range, whether the rating has been changed since it was fitted) and
  **provenance** (evidence sources, assumptions, how and with what version it
  was made, whether a bootstrap seed is recorded). There is **no summary
  score**: every check states what it measured and what to look at next, and
  a rating that passes everything is not thereby approved.

  An independent fit and a segmented fit are assessed with the same checks,
  closing the diagnostic gap between them: bias, spread, trend, support,
  identifiability and convergence now work for a segmented fit. Checks that
  cannot be computed for one of them, or for a rating that holds only
  equations, are `not_assessed` and say why, never `pass`.

  `FlodeAssessment` now holds eight domains. What a check can do follows
  from its **severity**, not its domain: a check with severity `error` can
  pass or fail, one with severity `warning` can only warn, so a single
  domain can hold both. `technical` and `hydrometric` keep their fixed
  severities. Printing shows each domain's counts.

  Influence is computed on the scale the fit minimised (log discharge for the
  relative objective, with any age weights), and warns only above a Cook's
  distance of 1. The existing `flag_influential_gaugings()` works on
  absolute residuals, which grow with flow, so on a relative-error fit it
  always flags the highest gauging; it is unchanged and documented for the
  absolute case.

  A segmented fit's invariants now list every check, with those that do not
  apply to one joint equation marked `not_assessed`, so the two fit classes
  produce the same check ids. `convergence` no longer reports a limb with no
  optimiser record (amended after fitting) as having failed to converge.

* Tranche B1 of the improvement plan: `fit_rating()`, the guided entry
  point, with `set_operational_limits()`. Give it evidence (a `FlodeEvidence`,
  a plain table, or the output of `read_gaugings()`) and it fits a rating
  with defaults chosen so that a careful analyst would not argue: **one
  limb**, **the relative objective**, an independent fit (or
  `model = "segmented"`). More than one limb needs an explicit choice, either
  `controls` (recorded as yours) or `limbs = "suggest"` (recorded as a
  statistical candidate, marked advisory, and said so each time the rating
  is printed).

  It records what it did, in `rating_provenance()$fit_rating`: the call, the
  seed, the model and objective, how many rows were used, and every row it
  left out with its `evidence_id` and reason (marked excluded, missing or
  non-finite, negative discharge, or zero discharge under the relative
  objective). Nothing is deleted from your evidence. The rating's
  `@gaugings` is the evidence that was used, with each row's `evidence_id`,
  source and notes, plus the fitter's own limb and age-weight columns. This
  is the first fitter to act on `included = FALSE`. Every starting point
  tried is in `@fit_starts`.

  **Operational limits.** A rating made by `fit_rating()` is applied only
  within the stage range it was gauged over until you state the range it may
  be used over, with `operational_limits` or `set_operational_limits()`, and
  say why. Stages outside the limits are refused by `apply_rating()`; stages
  inside them but beyond the gauged range are computed and flagged
  `extrapolated`. Setting limits makes a new version, returns the lifecycle
  to `draft`, and keeps the earlier one in `rating_history()` with a note. A
  rating from `rate_optimise()` is not restricted, and neither is its
  equation table: an expert calling those has taken that decision.

  Printing a guided rating shows its breakpoints and where they came from, how
  many rows were used, and its operational limits.

  `README.md` now lists `read_gaugings()`, `validate_gaugings()` and
  `fit_rating()` as available.

* Tranche A8 of the improvement plan: post-fit invariants.
  `rating_invariants()` checks a rating's own equations and returns a
  `FlodeAssessment` (subject `"rating"`) reusing the class from A6. Eight
  technical checks can fail: finite and positive coefficients, ordered and
  contiguous limbs, finite non-negative discharge, monotonic discharge
  within a limb, limb-top discharge that rises from limb to limb, an inverse
  that undoes the forward rating, bootstrap bounds in order, and fitted
  parameters inside their bounds. Three hydrometric checks only warn: gaps
  or overlaps between limbs, a step in discharge at a junction, and a limb
  that starts below its own zero-flow stage. Works on `FlodeRating`,
  `FlodeSegmentedRating` and `FlodeRatingTable`.

  **A rating that fails a technical check is not applied.** `apply_rating()`
  and `apply_rating_inverse()` stop and name the check, because a number
  from such a rating would look like any other. A failure stops the
  operation it makes meaningless: a drop in discharge at the top of a limb
  does not stop `apply_rating()` (stage to discharge is still well defined)
  but does stop the inverse. Warnings never block. The gate evaluates only
  the technical checks and adds about a millisecond to a call.

  Printing a rating now shows `converged:` and `valid:` as separate lines,
  since a fit can converge to an invalid equation and a valid equation can
  come from a fit that did not converge.

  `rate_optimise_constrained()` records, in the rating's provenance
  (`constrained_fallbacks`) and in a new `note` column of `rating_history()`,
  any limb that could not be refitted under the junction constraint and kept
  its unconstrained fit. It was a warning only.

  **A deliberate departure from the plan:** the plan says the results are
  stored on the fit. They are computed when asked for instead, so they
  cannot go stale when a rating is amended, nothing has to be migrated, and
  the schema version is unchanged. Say if a stored record is wanted.

* Tranche A9 of the improvement plan: convergence and identifiability.
  Every limb of a fit (and the segmented fit's coefficients) now records,
  in stable columns, how the optimiser ended and whether the data pin the
  parameters down: `converged`, `convergence_code`, `convergence_message`,
  `iterations`, `objective_value`, `bound_hits` (any parameter on a bound,
  not only `n`), `multi_start_spread`, `parameter_correlation` and
  `condition_number`. `NA` means not assessed. `rating_diagnostics()` shows
  them. In `@fit_starts`, `converged` is now the optimiser's own report and
  a new `valid` column holds the domain and monotonicity check that
  `converged` used to mean. Amending a limb clears the columns, since they
  described the fit it came from.

  A fit that did not converge is returned with a warning, as before in
  substance but no longer silently. This closes the limitation the
  mathematical contract described: the optimiser stopping at its limit used
  to be invisible. The single-start path (`multi_start = FALSE`) warns too,
  and on awkward data it often needs to.

  The attempt kept is still the valid one with the lowest objective, not the
  one that converged. On a worked case the only converged attempt sat on a
  bound with an objective ten times worse than five that had crept along a
  flat valley, so preferring convergence would have chosen the worse fit.

  The optimiser's default limit of 400 function calls bound before the
  documented 100 iterations, at about 94, so it is raised to twenty times
  the iteration limit. **No result changed.** On twelve simulated datasets
  the fitted coefficients and the breakpoints `suggest_breakpoints()`
  proposes were identical before and after, in every column.
  `suggest_breakpoints()` still scores candidates from a single start and no
  longer repeats the single-start warning for each one.

* Tranche A7 of the improvement plan: `vignette("mathematical_contract")`
  states what the package computes, exactly. It gives the equation
  `Q = C(H - a)^n`, the units, how a limb is chosen when fitting and when
  applying, both objectives as equations (absolute and relative) with a
  hand-worked example, the age-weight formula, which values are accepted or
  refused, the parameter bounds, the six starting points, the multi-start
  selection rule, the convergence settings, what each interval does and
  does not cover, the segmented model, and a list of what the package does
  not do. Each statement is held by a test in `test-contract.R`.

  `convert_offset_convention()` changes the sign of `a` between this
  package's `Q = C(H - a)^n` and the `Q = C(H + a)^n` some systems use. It
  round-trips in both directions and does not change a stage datum.

  Two limitations are written down and not hidden. A gauging exactly on a
  breakpoint is fitted into the lower limb but applied with the upper one.
  And `converged` in `@fit_starts` means an attempt passed the validity
  check, not that the optimiser reported convergence: when the iteration
  limit is reached `nlsLM` returns its last estimate with a warning that the
  package suppresses. The convergence columns planned for tranche A9 will
  expose it.

* Fixed: with age weighting, the multi-start ranked its attempts on the
  unweighted sum of squares although each attempt had minimised the
  weighted one, so a choice between local optima used a criterion nobody
  had optimised. It now ranks on the weighted sum on the objective's own
  scale, for `rate_optimise()` and `rate_optimise_segmented()`. Fits
  without age weighting are unchanged, because every weight is 1. The
  `rss` column of `@fit_starts` is now that weighted sum.

* Tranche A6 of the improvement plan. `validate_gaugings()` checks a set
  of gaugings (evidence, a plain table, or the output of
  `read_gaugings()`) and returns a `FlodeAssessment`: one row per check
  with `check_id`, `domain`, `severity`, `status`, `message`, the
  `evidence_id`s affected, the stage range affected and a recommendation.
  Six technical checks can fail (missing or non-finite stage or
  discharge, negative discharge, fewer than four usable rows, a repeated
  evidence id, a row that could not be read). Ten hydrometric checks can
  only warn (zero discharge, exact duplicates, stage-discharge inversion,
  an outlier, a gap in stage coverage, thin support at the top of the
  range, few gaugings, no recent gauging, rows already excluded, assumed
  times of day). A check that lacks what it needs is `not_assessed`, never
  `pass`. No row is ever removed or changed. The thresholds are arguments.

  `FlodeAssessment` does not know what was checked, so `assess_rating()`
  can reuse it unchanged. It holds each check to its domain: a technical
  check cannot warn and a hydrometric check cannot fail. `print()` lists
  what did not pass, worst first, and `plot()` draws every check by
  status with the status written in each tile. `assessment_checks()` and
  `assessment_status()` read it.

  The inversion check blames the gauging that sits in the most inverted
  pairs, so one high gauging is reported alone and not the gaugings above
  it. It is skipped beyond 10,000 usable rows; validate one station at a
  time. The outlier check compares each gauging with a cubic through its
  neighbours and scales by the prediction's own noise; in simulation it
  warned on 3 to 7 per cent of clean sets and found a doubled discharge
  nine times in ten.

* Fixed: `as_flode_evidence()` on an empty table gave an `exclusion_reason`
  column of the wrong class.

* Tranche A5 of the improvement plan: `read_gaugings()` is complete.
  It reads delimited text (comma, semicolon, tab, pipe, detected or set
  with `sep`), spreadsheets (`.xlsx`, `.xls`, through `readxl`, which is in
  Suggests; without it the function says to install it or save a CSV),
  and data.frames. New arguments: `datetime` for a single date-time column,
  `dec` for a decimal comma, `sheet`, `encoding`, and `keep_original`,
  which keeps each mapped column's text as written (`stage_original` and
  so on). A spreadsheet's Excel date and time cells are recognised. A
  repeated header is kept and made distinct. A file with only a header
  returns an empty table.

  `read_summary()` returns what a read found as a table: one row per kind
  of problem with the rows affected and their share, and the headline
  figures as attributes. It stops if rows have since been removed.
  `as_flode_evidence()` recognises a `read_gaugings()` table: `station_id`
  becomes `site_id`, the file name becomes `source_name`, and a row whose
  stage or discharge could not be read becomes `included = FALSE` with
  its `read_issue` as the reason. Nothing is dropped.

  Twenty fixtures under `tests/testthat/fixtures/gaugings/` each stand for
  a way real exports differ, with one test per file. The set is the
  package's own, not taken from an external specification.

* Fixed: `read_gaugings(tz = )` shifted the clock time by the zone's offset
  (12:00 in the file read as 13:00 in `Europe/London` during summer time).
  It now keeps the time as written, and a time that does not exist in the
  zone (the hour skipped when clocks go forward) is `NA`.

* Tranche A4 of the improvement plan, version 0.2.0. This changes what a
  rating stores. Ratings saved with 0.1.0 do not validate under 0.2.0
  (they carry no schema version); refit them.

  * `FlodeEvidence` is a new class: a `data.table` with fixed columns
    (`evidence_id`, `site_id`, `stage_m`, `discharge_cms`,
    `observation_time`, `source_type`, `source_name`, `source_version`,
    `quality_code`, `included`, `exclusion_reason`, `weight`, `notes`,
    `source_row` and a `metadata` list column) and a validator. Ordinary
    data.table use works on it unchanged. `source_type` is one of
    `evidence_source_types()`: `gauging`, `operational_rating`,
    `modelled`, `cross_section`, `structure_equation` or `other`. That
    vocabulary is this package's own default and is one line to extend.
  * A rating's `@gaugings` is now a `FlodeEvidence`. A plain table given
    to a rating, which is what every fitter does, is converted by
    `as_flode_evidence()`: ids `G001`, `G002` and so on in row order,
    `gauging_datetime` becoming `observation_time`, and a note on the
    table saying what was assumed. Evidence ids survive fitting,
    flagging, the diagnostics and `saveRDS()`/`readRDS()`.
    `rating_evidence()` now returns the canonical columns first.
    Subsetting rows keeps the result as evidence. Selecting columns or
    aggregating (`ev[, .(a, b)]`) returns an ordinary data.table, unless
    every canonical column is kept.
  * `@status` splits in two. `@fit_origin` keeps the old values
    (`independently_fitted`, `post_fit_aligned`, `constrained_refit`, and
    on a rating table also `extended_low` and `grafted`). `@lifecycle` is
    new: `draft`, `under_review`, `approved`, `superseded` or
    `withdrawn`. It starts at `draft`, an amendment returns to `draft`,
    and the package never sets `approved`. `@status` remains as a
    read-only alias for `@fit_origin`. `rating_history()` now reports
    `fit_origin` and `lifecycle` columns in place of `status`;
    `rating_provenance()` of a rating table reports the same two.
  * Every rating records a `schema_version` (`rating_schema_version()`),
    shown by `rating_provenance()`. A rating whose version is missing or
    newer than the installed package fails validation with a message that
    says so.
  * `tool_version` in a fit's provenance is now `reach.rate <version>`.

* Every exported function and class now has a runnable example, and the
  examples render on the reference site. They use one small simulated
  two-limb rating, so each runs in well under a second. A new test fails if
  an export is added without one. The interactive explorer's example is
  guarded by `interactive()`.

* A fit's provenance now records `reach.rate` and its version in
  `tool_version`. It recorded the package's old name, `rating_curves 1.0`,
  whatever the version.

* Tranche A3 of the improvement plan: eight accessors read a rating without
  touching its S7 properties. `rating_limbs()` gives the stage range and
  equation of each limb; `rating_coefficients()` every parameter in long
  form with its asymptotic and bootstrap uncertainty (`NA` where it was not
  computed, never zero); `rating_evidence()` the gaugings used;
  `rating_diagnostics()` the fit diagnostics; `rating_support()` how much of
  each limb rests on gaugings; `rating_bootstrap()` the bootstrap draws;
  `rating_history()` the whole chain of amended versions, oldest first; and
  `rating_provenance()` how the fit was made. Each is a generic with
  methods for `FlodeRating`, `FlodeSegmentedRating` and `FlodeRatingTable`
  where the class holds the information, and an error that names the class
  and says what to use instead where it does not. Each returns a copy, so
  editing the result cannot change the rating. `rating_limbs(all_columns =
  TRUE)` returns everything a rating carries per limb, including the
  columns that `flag_extrapolated_limbs()`, `align_limb_equations()` and
  `align_limb_boundaries()` add.

* `bootstrap_to_table()` is deprecated in favour of `rating_bootstrap()`,
  which returns the same draws with `lower_stage_m` and `upper_stage_m` in
  place of `lower_level` and `upper_level`. `apply_rating_interval()` now
  accepts either naming, on a copy of the table it is given. The old
  function still works, with a warning, and will be removed in a later
  release.

* The README, every vignette and the walkthrough script now use the
  accessors in place of `@` property access; `grep '@[a-z]'` over them
  finds none. `vignette("s7_objects_guide")` is rewritten as a maintainer
  guide: how the classes are built, how to read properties with
  `S7::prop()`, and how to add an accessor. No mathematical changes.

* Two more pieces of the rating arithmetic moved into the C kernel
  (`src/reach_core.c`), so another language can share them: the stage where
  two limb equations cross, and the geometry of a surveyed cross-section.
  `reach_crossing()` finds `C1 (H - a1)^n1 = C2 (H - a2)^n2` by Brent's
  method to an absolute accuracy of the square root of machine epsilon, and
  reports no crossing when the curves do not change order in the range or a
  curve cannot be evaluated; `graft_rating()` and `align_limb_boundaries()`
  use it, replacing `uniroot()` with the same tolerance. `reach_xs_geometry()`
  gives wetted area and perimeter at each stage from the survey points (the
  free surface is not part of the perimeter, a segment crossing the water
  line is clipped, and the section is not extended above its highest
  point), and `reach_manning()` turns them into Manning's discharge;
  `rate_from_cross_section()` uses both. Results are unchanged: the previous
  R code, including `uniroot()`, is kept in the tests as an oracle and the
  kernel is compared against it on random equations and random surveys,
  exactly at every survey point and just either side. A cross-section's
  geometry for 4,000 survey points at 346 stages takes 0.009 s instead of
  0.59 s. One small difference: a survey with a non-finite elevation or
  distance is now refused with a clear message, where before it failed
  with an unrelated condition. No mathematical changes.

* The rating arithmetic now lives in a small C library, `src/reach_core.c`
  and `src/reach_core.h`, so that other languages can use exactly the same
  code. It covers stage to discharge, discharge to stage, which limb a stage
  falls on and whether it was extrapolated, the discharge on each side of
  each junction, and the tangent limb used by `extend_rating_low()`. It
  uses the C standard library only, allocates nothing, keeps no global state
  and is thread safe. The header is the specification: it fixes how the
  edges of a limb, missing values, extrapolation and errors behave. R calls
  it through a thin binding (`src/reach_r.c`); a binding for another
  language would load the same source, so the two could not drift apart. `apply_rating()`,
  `apply_rating_inverse()` and `extend_rating_low()` use it. Results are
  unchanged: the old R arithmetic is kept in the tests as an oracle, and the
  kernel is compared against it on random ratings, on every limb edge and
  offset, and on missing and infinite values. The arithmetic is about 4.7
  times faster; `apply_rating()` end to end about 1.5 times, since most of
  the remaining time is R's own overhead. Two small differences: a rating
  with a non-finite value, a limb whose upper level is not above its lower
  level, or (for the inverse) a non-positive `C` or `n` is now refused with a
  clear message, where before it gave `NaN` or a meaningless answer; and a
  `NaN` at a limb junction is reported as a discharge gap by
  `apply_rating_inverse()`. Standalone C tests run on Linux and macOS with
  gcc and clang, and under the address and undefined-behaviour sanitizers
  (`.github/workflows/c-core.yaml`). The package now needs a C compiler to
  install from source. No mathematical changes.

* New `match_stations()` and `check_operational_ratings()`: the whole check of
  an operational ratings export against a gauging archive in two calls.
  `match_stations()` links each rating station to its gauging stations with
  a table you supply (rating station id and gauging reference), and by
  direct id match, ignoring case and spaces, for stations the table does not
  cover. It reports what did not match on each side, and any row of the
  table that could not be used and why. `check_operational_ratings()` builds
  each rating as a table, compares it with the gaugings of its matched
  station through `compare_gaugings_to_rating()`, and returns one row per
  rating and one row per limb (with the export's `flag` and `open_ended`
  carried alongside, so you can see whether `Flag` lines up with limbs that
  have no gaugings), plus the ratings that are not valid tables and the
  unmatched stations. Nothing is excluded for being odd. `use_dates = TRUE`
  restricts each rating to gaugings taken while it was in force. About 70
  seconds for 3,000 ratings against a million gaugings. No mathematical
  changes.

* New `read_gaugings()`, `read_operational_ratings()` and
  `operational_rating_tables()`: bring a spot-gauging archive and an
  operational power-law ratings export into R without cleaning them.
  Everything is read as text and parsed explicitly, placeholder text such
  as `---` becomes a missing value, and nothing is dropped: each row that
  did not parse cleanly carries a `read_issue` note saying why. Dates are
  detected (day-first ahead of month-first, with a warning only when the
  two readings genuinely differ) and the format used is reported.
  `read_operational_ratings()` renames the export's `A`, `B` and `C` to the
  package's `a`, `n` and `C` for `Q = C(H - a)^n`, marks open-ended top
  limbs, carries `Flag` through without interpreting it, and omits
  grid-to-grid model ratings (`G2G` is `TRUE`) unless asked.
  `operational_rating_tables()` builds one `FlodeRatingTable` per rating and
  lists any rating that cannot form a valid table (gap, overlap, missing
  value) with its reason, instead of failing the whole export. The defaults
  match the Environment Agency gauging and ratings export headers; every
  column can be remapped. A million-row archive reads in about 11 seconds.
  Reading, not yet the guided `read_gaugings()` of the improvement plan:
  no evidence class or station matching yet. No mathematical changes.

* New `compare_gaugings_to_rating()`: checks a rating against a set of spot
  gaugings that need not be the ones it was fitted to, such as an
  operational rating against a full gauging archive. It returns the
  residual of every gauging and a per-limb summary: how many gaugings sit
  on the limb, over what stage range, the median and interquartile range of
  the percentage residual, and the share within a tolerance. A limb with no
  gaugings is reported as such, which is what a limb modelled for high flows
  looks like. Gaugings outside the rating are flagged and kept out of each
  limb's statistics. Summaries are medians because a percentage residual is
  unstable where the rating predicts almost nothing; a single archive row
  with a measured flow at stage zero would otherwise dominate a mean. Rows
  with missing values are kept, never dropped. First step towards merging
  the gauging archive with the operational ratings. Accepts a `FlodeRating`,
  a `FlodeRatingTable` or a plain table. No mathematical changes.

* `apply_rating()` now accepts a `FlodeRating` directly, so a fit from
  `rate_optimise()` or `rate_optimise_constrained()` no longer needs
  `as_rating_table()` first. Before, `apply_rating(fit, stage_dt)` failed
  with "Can't find method for `apply_rating(<FlodeRating>)`", although the
  documentation listed `FlodeRating` as supported. The new method converts
  with `as_rating_table()` and uses the `FlodeRatingTable` method, so the
  two routes give identical results.

* `apply_rating()` also accepts a plain numeric vector of stage values for
  all three fit classes, e.g. `apply_rating(fit, dt$stage)`. It returns a
  table with the stage column (named by `stage_col`), `discharge` and
  `extrapolated`. A character vector, matrix or list is still refused.

* The `apply_rating()` reference page now documents what the function does:
  `stage_dt`, `stage_col`, `out_col`, the return value, and how the
  `FlodeRatingTable` and `FlodeSegmentedRating` methods differ in zero-flow
  handling and in which stages are flagged `extrapolated`. The method
  blocks in `apply_rating.R` and `rate_optimise_segmented.R` are marked
  `@noRd` because roxygen cannot name a `method(...) <-` call, which is why
  their documentation never reached the page.

* `apply_rating()` now has a worked, graphed example: a hand-typed four-limb
  rating applied to a two-day stage record, with the rating curve coloured
  by limb and the stage and flow hydrographs. The old two-limb example was
  never published: its roxygen block sat above a `method(...) <-` call,
  which roxygen cannot name, so it was dropped from the Rd. The example now
  lives on the generic's block in `R/flode_classes.R`. Documentation only;
  no mathematical changes.

* New `extend_rating_low()`: adds an explicit linear limb below the lowest
  limb of a rating, for stage records that fall below the lowest gauged
  stage or go negative. The limb is the tangent to the lowest power-law
  limb at its lower boundary, so discharge and gradient both match at the
  junction; it reaches zero discharge at `h - (h - a)/n`. It is stored as
  an ordinary `n = 1` row, so `apply_rating()`, `apply_rating_inverse()`,
  `apply_rating_interval()` and the gap checks need no changes. The
  extension is opt-in and never added automatically; the result carries
  `@status` `"extended_low"` and a `linear_extension` column.

* `suggest_breakpoints()` gains a `selected` column marking the candidate
  each round adopted. Extract the chosen stages with
  `sort(result[selected == TRUE, candidate_stage])`. The
  `"selected_breaks"` attribute is still set, but attributes can be lost
  under ordinary data.table operations. No mathematical changes.

* `suggested_breakpoints_vector()` is deprecated and warns; use the
  `selected` column instead. It will be removed in the release after next.

* The function reference is regrouped by job: using a rating, advanced
  modelling, diagnostics, uncertainty, plotting, specialist hydraulics,
  conversion, rating objects, teaching tools and deprecated. The README
  gains a workflow section showing the planned six-function route and
  today's equivalent. Tranche A2 of `IMPROVEMENT_PLAN.md` (#37).

* `R CMD check` no longer notes undefined globals: data.table column
  names are declared in `R/globals.R`, and `stats::uniroot` is imported.
  `utils` joins Imports for `globalVariables()`.

* Continuous integration now runs `R CMD check`, with vignettes built, on
  Windows and Ubuntu against R release and oldrel-1, plus a line-coverage
  job. The README states the supported environments; the `R (>= 4.1)`
  floor in `DESCRIPTION` is untested and says so. Tranche A1 of
  `IMPROVEMENT_PLAN.md` (#36). No mathematical changes.

* Plot labels no longer use characters outside Latin-1, which the default
  `pdf()` device cannot encode: saving `plot_rating_comparison()`,
  `plot_rc_gaps()`, `run_demo()` or `demo_cross_section_rating()` output
  to PDF failed or substituted dots. `ΔQ` becomes `dQ`, the
  y-axis `Δ Discharge` becomes `Discharge difference`, and minus
  signs, em dashes and `H₀` become `-`, `:` and `H0`. Plotting
  tests now render through `pdf(NULL)` and fail on any conversion
  warning. Label text only; no mathematical changes.

* The `data.table` properties of `FlodeRatingBase`, `FlodeRating`,
  `FlodeSegmentedRating` and `FlodeRatingTable` now default to an empty
  `data.table()`. The old implicit default deparsed differently between
  S7 releases, so the documented constructor usage drifted from the code
  and `R CMD check` warned. Omitting the table still fails: the validator
  rejects an empty one, now with its own message instead of S7's
  "doesn't have a constructor". No mathematical changes.

* New `vignette("rating_methods_overview")`: two flow diagrams tying the
  whole package together -- which of the five ways to build a rating
  (`rate_optimise()`, `rate_optimise_constrained()`,
  `rate_optimise_segmented()`, `rate_from_cross_section()`, or the
  standalone weir/flume equations) fits your data, and what happens
  downstream of a fit, including an honest accounting of what
  `FlodeSegmentedRating` doesn't have an equivalent of yet (the four
  diagnostic functions, `as_rating_table()`, and everything
  `FlodeRatingTable`-shaped that depends on it).

* `inst/examples/walkthrough.R` gains steps 22-26, covering functions
  that shipped after its last pass: `rate_from_cross_section()` (with
  the `plot_rating_cross_section()` overlay actually shown, not just the
  fitted coefficients), the weir/flume equations, `flag_influential_
  gaugings()`/`plot_rating_leverage()`, `age_halflife` recency weighting
  on a drifting-channel example, and `apply_rating_inverse()` round-
  tripped against `apply_rating()`.

* New `vignette("s7_objects_guide")`: the last gap from the same
  vignette-coverage audit. Covers the class hierarchy (`FlodeRatingBase`
  abstract, `FlodeRating`/`FlodeSegmentedRating` as children,
  `FlodeRatingTable` separate), `@`-access and `print()`, a validator
  catching a malformed construction, `S7_inherits()` for writing code
  that accepts either a fit or a table, walking the `@status`/`@previous`
  audit chain with real code, and the three shared generics
  (`rating_plot()`/`apply_rating()`/`as_rating_table()`). Previously the
  entire documentation set had exactly one sentence on any of this.

* `rate_optimise()` and `rate_optimise_segmented()` gain opt-in recency
  weighting: `age_halflife`, `age_min_weight`, `reference_datetime`.
  Each gauging's residual is weighted by exponential decay from its age
  (relative to `reference_datetime`, defaulting to the dataset's own
  most recent gauging) down to a floor (`age_min_weight`) that stops any
  gauging -- including a limb's one high-flow flood -- ever being
  weighted to near-zero purely for being old; not magnitude-aware (an
  old extreme and an old ordinary gauging decay identically), so this is
  a partial answer to issue #9, not the full one. `age_halflife = NULL`
  (default) fits unweighted, exactly as before -- supplying
  `gauging_datetime` alone still changes nothing about the fit.
  `rate_optimise_constrained()` forwards the new arguments through `...`,
  same as `gauging_datetime` itself already does. `@gaugings` gains an
  `age_weight` column when `age_halflife` is used. New
  `vignette("recency_weighting_guide")` covers the full formula and a
  worked example on a station whose channel has genuinely drifted.

* New `vignette("objective_guide")`: absolute vs. relative fitting
  objectives, with a diagram of the implied per-gauging weight each one
  uses (flat for absolute; approximately `1/Q^2` for relative, via the
  standard first-order log-residual approximation) -- the mechanism
  behind `non_standard_optimisation.Rmd`'s existing `objective =
  "relative"` coverage, not previously diagrammed.

* New `vignette("segmented_model_guide")`: how
  `rate_optimise_segmented()`'s multiplicative segments actually compose,
  with each factor plotted separately to show the "inert until its own
  breakpoint" property the formula states but didn't previously
  illustrate, and a side-by-side comparison against independently-fitted
  limbs showing why the segmented model has no junction gap to reconcile.

* New functions `flag_influential_gaugings()` and `plot_rating_leverage()`:
  per-gauging leverage and Cook's distance, adapted to `rate_optimise()`'s
  nonlinear fit via the standard local-linearisation trick (the fitted
  model's Jacobian w.r.t. `C`/`a`/`n`, evaluated at each gauging, in place
  of a design matrix). Answers a question `plot_rating_residuals()`
  can't: not how far off a gauging ends up after fitting, but how much
  it shaped the fit to begin with -- a gauging isolated at the sparse end
  of a limb can have high leverage regardless of how small its residual
  looks. `flag_influential_gaugings()` returns a new `FlodeRating` with
  `@gaugings` columns added (`leverage`, `cooks_distance`, `influential`,
  using standard rule-of-thumb cutoffs); `plot_rating_leverage()` plots
  both quantities per limb. New `vignette("leverage_influence_guide")`
  explains the two diagnostics in plain language, with a worked example
  showing how much a single flagged gauging can move a fitted
  coefficient.

* New module `R/weir_equations.R`: four standard weir/flume discharge
  functions -- `weir_discharge_rectangular()` (Rehbock, full-width
  sharp-crested; ISO 1438:2017), `weir_discharge_vnotch()`
  (Kindsvater-Shen triangular notch), `weir_discharge_cipoletti()`
  (trapezoidal, USBR), and `flume_discharge_parshall()` (standard 1-8 ft
  throat widths). Physically-derived from structure geometry, not fitted
  to gaugings -- deliberately outside `FlodeRating`/`FlodeRatingTable`.
  Each propagates a GUM-style (JCGM 100:2008) uncertainty from a
  required `u_cd` (discharge coefficient's relative standard
  uncertainty) and `u_head_m` (head measurement's absolute standard
  uncertainty) -- both required, not defaulted, since a fabricated
  default would look authoritative without being traceable to anything.
  `flume_discharge_parshall()` also checks the standard free-flow
  submergence limit when a downstream head is supplied, erroring rather
  than silently applying the free-flow equation to submerged conditions.
  New `vignette("weir_flume_guide")` covers the four structures (with
  diagrams), the equations and their sourcing, and the GUM propagation
  in detail.

* New function `rate_from_cross_section()`: derives a theoretical rating
  from a surveyed channel cross-section via Manning's equation, with no
  gaugings required. Wetted area and perimeter are found by trapezoidal
  integration of the surveyed points at a dense sequence of stages, and
  the resulting synthetic `(stage, discharge)` series is fitted through
  `rate_optimise()`'s own pipeline, so the result is an ordinary
  `FlodeRating` -- distinguished from a gauged fit only by
  `provenance$source == "cross_section_theoretical"`. A standalone
  diagnostic for now (a first-cut rating at an ungauged site, or a
  physically-grounded check on a surveyed section's implied shape);
  composes directly with `plot_rating_cross_section()`, since both take
  the same `cross_section` object.

* New function `apply_rating_inverse()`: the other direction from
  `apply_rating()` -- given a discharge series, finds the stage that
  produced it. Requires a gap-free `FlodeRatingTable` (checked directly
  from the equations at each junction, erroring and naming the junction
  otherwise, rather than guessing at an ambiguous inverse); discharge
  `<= 0` returns `NA` with a warning, since it has no unique inverse
  stage. Not valid for tidal/backwater stations where stage-discharge
  isn't single-valued -- a documented limitation.

* `rate_optimise()`'s `@limbs` gains `rmse_pct` (a relative/percentage
  RMSE alongside the existing absolute `rmse_cms`, always computed
  regardless of `objective`) and `C_se_asymp`/`a_se_asymp`/`n_se_asymp`
  (closed-form asymptotic parameter standard errors from the fit's own
  NLS covariance matrix, always computed -- a free fallback when
  `n_boot = 0`, distinct from the bootstrap-only `C_se`/`a_se`/`n_se`).
  `rate_optimise_constrained()` recomputes all four for any limb it
  actually refits (via the delta method for the SEs, since that refit's
  own model has only `a`/`n` as free parameters) and leaves
  `anchor_limb`'s untouched; `align_limb_equations()`/
  `align_limb_boundaries()` recompute `rmse_pct` and NA out the three
  `*_se_asymp` columns, the same discipline already applied to
  `near_bound`.

* New function `plot_rating_cross_section()`: overlays a real surveyed
  channel cross-section on a real fitted rating's own plot, rescaling
  the survey's distance onto the discharge axis (with a secondary axis
  giving the true distance scale back) so the channel's shape and the
  rating's shape sit on one figure. Complements
  `demo_cross_section_rating()`, which stays a fixed synthetic
  illustration.

* New function `graft_rating()`: joins a freshly-fitted rating onto a
  pre-existing one used above the newly gauged range, finding the stage
  where the two curves actually cross (reusing the same crossing search
  `align_limb_boundaries()` uses for a junction inside one table) and
  combining them into one contiguous `FlodeRatingTable`. Distinct from
  `align_limb_equations()`/`align_limb_boundaries()`, which reconcile a
  junction within one already-built table rather than joining two
  independently-sourced ratings.

* New vignette `n_bounds_guide`: a visual companion to
  `non_standard_optimisation`'s `n_bounds` demonstration, with idealised
  cross-section diagrams for the rectangular/V-notch/wide-channel control
  families, a log-log plot showing why the control's shape sets the
  exponent, a compound-channel diagram illustrating why distinct regimes
  need separate `n_bounds` calls, and a practical starting-bounds table.

* New bundled example dataset `station_gaugings`: a real spot-gauging
  record for a UK gauging station, 1974-2024 (223 gaugings), included to
  demonstrate `rate_optimise()` against actual station messiness rather
  than only synthetic data -- irregular gauging intervals, decades-long
  gaps, and one gauging recorded at zero stage. See `?station_gaugings`.

* **Breaking change**: `align_limb_equations()` and
  `align_limb_boundaries()`, given a `FlodeRating` (the bridge added in a
  previous release this same development cycle), now return a new
  `FlodeRating` instead of downgrading to a `FlodeRatingTable`. This
  keeps the amendment inside `FlodeRating` -- gaugings, an audit chain,
  and diagnostics -- rather than losing all of that the moment a rating
  gets aligned.
  - `@gaugings` is carried forward (`limb` membership **reclassified**
    against relocated boundaries for `align_limb_boundaries()`, since a
    moved junction can shift which limb a gauging belongs to; unchanged
    for `align_limb_equations()`, which never moves boundaries).
  - `@limbs` diagnostics (`rmse_cms`, `r_squared`, `n_obs`, and friends)
    are recomputed against the amended equations, never left describing
    the pre-amendment fit.
  - `@bootstrap` and `@fit_starts` are dropped (with a warning if either
    was present) -- they describe a fit that no longer applies, the same
    discipline `rate_optimise_constrained()` already applies to its own
    refit.
  - `@previous` references the exact original `FlodeRating` (a new
    `previous` property added to `FlodeRatingBase`, so `FlodeRating` and
    `FlodeSegmentedRating` both now carry this).
  - A plain data.frame/data.table or an already-constructed
    `FlodeRatingTable` input is unaffected -- still returns a
    `FlodeRatingTable`, exactly as before.
  - Direct payoff: `rating_plot()` and `plot_rating_residuals()` (both
    written for `FlodeRating`) now work immediately on an aligned result,
    with no new arguments or functions needed.
* `expand_rating_table()` now accepts a `FlodeRating` directly (bridged
  via `as_rating_table()`), matching `align_limb_equations()`/
  `align_limb_boundaries()`'s existing bridge.

* **Breaking change**: `rate_optimise()` and `rate_optimise_constrained()`
  now fit `Q = C(H - a)^n` instead of `Q = C(H + a)^n`. This unifies the
  fitting engine's convention with `FlodeRatingTable`'s equation-table
  representation (`gap_check`, `apply_rating`), which already used
  `Q = C(H - a)^n` -- the two sides of the toolkit previously used
  opposite-signed offsets, bridged by an explicit (and easy to get
  backwards) sign flip inside `as_rating_table()`/`bootstrap_to_table()`.
  That bridge is now a straight, unflipped copy.
  - Every `a` coefficient a fit reports (`fit@limbs$a`, bootstrap draws,
    `@fit_starts`) is the negative of what the same data would have
    produced before this change. `C` and `n` are unaffected.
  - If you have saved `FlodeRating` objects, re-fit them rather than
    reusing the stored coefficients under the new convention.
  - `FlodeRatingTable`'s own coefficients, `apply_rating()`,
    `expand_rating_table()`, `align_limb_equations()`, and
    `align_limb_boundaries()` are unaffected -- they already used this
    convention.

# reach.rate 0.1.0

* Initial release: the `rating_curves` toolkit, converted from a set of
  standalone `box` modules into the `reach.rate` package.
  - `rate_optimise()` / `rate_optimise_constrained()`: multi-limb
    power-law rating fitting by nonlinear least squares, with
    multi-start fitting and bootstrap coefficient uncertainty.
  - `rate_optimise_segmented()`: a joint segmented parameterisation
    after Hodson et al. (2024), with no junction gap to reconcile.
  - `expand_rating_table()`, `detect_rc_gaps()`, `resolve_rc_gaps()`,
    `align_limb_equations()`, `plot_rc_gaps()`: junction-gap detection
    and resolution between independently-fitted limbs.
  - `apply_rating()`, `apply_rating_interval()`,
    `apply_rating_versioned()`: convert a fitted rating (or a bootstrap
    of one, or a rating history) into a discharge time series.
  - `compare_ratings()` / `plot_rating_comparison()`: document a rating
    amendment.
  - `FlodeRating`, `FlodeSegmentedRating`, `FlodeRatingTable`: S7
    classes carrying gaugings, fitting bookkeeping, and provenance
    alongside every fitted rating.
  - `demo_cross_section_rating()`, `rating_curve_explorer()`: worked
    examples and an interactive Shiny explorer of the rating equation.
  - `vignette("rating_curves_guide")`: the full theory-and-usage guide.
