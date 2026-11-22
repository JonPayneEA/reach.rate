# 06 Handover

| | |
|---|---|
| Status | DRAFT for review. Nothing in this document has been agreed. |
| Version | 0.1 |
| Date | 22 November 2026 |
| Asset | `reach.rate` 0.2.0 |
| Reader | An incoming maintainer |

## Summary

One person holds the knowledge of this package, and most of Releases A to C was
written in AI-assisted sessions under that person's direction. This document exists
so that a competent R developer who has never seen the code can maintain it. It is a
mitigation for a single point of failure, not a substitute for a second maintainer
(limitation L21).

## Read first

| Order | Read | Why |
|---|---|---|
| 1 | `governance/README.md` and `03_limitations_register.md` | What it is, and what it is not |
| 2 | `vignette("start_here")` | The workflow, from a file to a rating |
| 3 | `vignette("mathematical_contract")` | Exactly what is computed. The authority for the mathematics |
| 4 | `vignette("s7_objects_guide")` | How the classes are built |
| 5 | `vignette("release_policy")` | How a change is released. A proposal until accepted |
| 6 | `IMPROVEMENT_PLAN.md` | The plan the work followed, and what is left |

## What it is

An R package that fits, checks, applies and documents hydrometric rating curves of the
form `Q = C (H - a)^n`, one equation per limb of the stage range. A rating is an
object that records its evidence, how it was fitted, and what has been done to it.

| Part | Where | Notes |
|---|---|---|
| Guided workflow | `read_gaugings`, `validate_gaugings`, `fit_rating`, `assess_rating`, `apply_rating`, `export_rating` | The route for most users |
| Expert fitting | `rate_optimise`, `rate_optimise_segmented`, and the alignment functions | No operational gate and no guided record |
| Classes | `R/flode_classes.R`, `flode_evidence.R`, `flode_assessment.R`, `sensitivity.R` | S7. `FlodeRating`, `FlodeSegmentedRating`, `FlodeRatingTable`, `FlodeEvidence`, `FlodeAssessment`, `FlodeSensitivity` |
| C kernel | `src/reach_core.c`, called from `R/kernel.R` | One implementation of the stage-to-discharge arithmetic. Standard library only |
| Records | `R/export_rating.R`, `lifecycle.R`, `rating_report.R`, `inst/templates/` | Export, import, lifecycle, the review report |
| Assurance | `R/reference_cases.R`, `tests/testthat/` | Ten reference cases; about 4,000 expectations in 51 test files |
| Documentation | `vignettes/` (17), `man/`, `_pkgdown.yml`, `NEWS.md` | Every vignette states its audience on its first line, and a test enforces it |

The package has 43 R source files and 84 exports.

## Build and test

```r
devtools::document()        # regenerates man/, NAMESPACE and the Collate field
devtools::test()            # the full suite
devtools::check()           # or R CMD check --no-manual
pkgdown::check_pkgdown()    # every export must be in the reference index
check_reference_cases()     # the ten cases
```

| Workflow | Runs | Fails on |
|---|---|---|
| `R-CMD-check.yaml` | R CMD check on Windows and Ubuntu, R release and oldrel-1 | Errors **and warnings**. Notes do not fail it |
| `c-core.yaml` | The C kernel alone, on gcc, clang, and macOS clang | Any kernel test failure |
| `test-coverage.yaml` | The suite with coverage | A failing test |
| `pkgdown.yaml` | Builds the site; **deploys it on a push to `main`** | A build error |

**Never run `pkgdown.yaml` by hand from a branch.** It deploys to the live site.

## Things that will catch you

Each of these cost real time. They are written down so they cost none again.

| # | Trap | What to do |
|---|---|---|
| 1 | `method(print, Class) <- fn` rebinds `print` in the package namespace under S7 1.0.0, which broke the exported `autoplot()` | Register against the handles in `R/s7_external.R` (`.s7_print`, `.s7_plot`, `.s7_autoplot`), never the bare name |
| 2 | Column names used inside `data.table` code look like undefined globals to R CMD check | Add them to `R/globals.R` |
| 3 | Any `pkg::fn` needs `pkg` in `DESCRIPTION`, or R CMD check warns and CI fails. A test using `rlang::as_label` did exactly that | Declare it, or use a function from a package already declared |
| 4 | `devtools::install()` upgrades dependencies without asking. It moved S7 to 1.0.0 mid-project | Use `quick = TRUE` and check `packageVersion()` after |
| 5 | A test that reads `../../R/...` fails inside R CMD check, where the source is not there | Guard it with `skip_if_not(file.exists(...))` |
| 6 | New R files need `@include` tags or the `Collate` order breaks | Run `devtools::document()` and commit `DESCRIPTION` |
| 7 | `identical()` on a rating is `FALSE` after a write and read, because `data.table` keeps internal pointers | Use `all.equal(..., tolerance = 0)` |
| 8 | An S7 property validator runs on assignment, so a test cannot build an invalid object by assigning | `S7::prop<-` with `check = FALSE`, in tests only |
| 9 | Retargeting a pull request does not always start CI | Dispatch the three workflows by hand on the branch, but not `pkgdown.yaml` |
| 10 | Squash merges rewrite history, which breaks every branch stacked on the merged one | `git rebase --onto origin/main <old base> <branch>`, then `--force-with-lease` with the full old SHA, on your own branches only |
| 11 | A new file outside the package (documents, data-raw, tests/c) ships in the built package unless excluded | Add it to `.Rbuildignore`. `governance/` needs this (see below) |
| 12 | The sandbox this was built in prints a locale warning in `R CMD check`. CI does not | Ignore it there |

## Housekeeping this pack found

| Item | Action |
|---|---|
| `governance/` is not in `.Rbuildignore` | Add `^governance$`. The pull request that adds this pack does |
| The kernel reports `0.1.0`, the package is `0.2.0` | Align before a release |
| `.o` and `.so` files appear in `src/` and are not in `.gitignore` | Add `src/*.o` and `src/*.so` |
| `scales` is used once, for an axis label | Optional; no saving, since `ggplot2` requires it |
| The `selected` column of `suggest_breakpoints()` is superseded by `preferred` | Warn in a later release, then remove (policy, stage 1) |

## Releasing

`vignette("release_policy")` is the proposal: versions, what counts as breaking, the
three deprecation stages, schema versions, and a checklist whose last item is a person
who did not write the change. It has not been accepted (decision D10). There are no
release tags yet (decision D9).

## Open work

| Item | State |
|---|---|
| Release D (this pack) | Drafted. Decisions D1 to D12 outstanding |
| Release E: evidence weighting, temporal ratings, hysteresis, separated uncertainty, rating inventory | Not started. Needs approval. Issues #9, #10 and #11 |
| Magnitude-aware recency weighting | Issue #9 |
| `rating_plot()` deprecation | Held at stage 1. Move the vignettes to `autoplot()`, then warn |
| Real gauging files through the readers | **Never done.** The largest unknown |
| Minimum versions for `S7` and `data.table` | Declare, after testing at the minimum |
| Kernel shared with a Python package | Coordinate any kernel change with it |

## How the work was done

Releases A to C followed `IMPROVEMENT_PLAN.md` in tranches, each a pull request with
its own tests, documentation and NEWS entry, merged only when continuous integration
was green. Most of the code in those tranches was written in AI-assisted sessions
(Claude Code), under the maintainer's direction and review. At least 11 commits carry
an AI co-author trailer; squash merges do not keep trailers, so the figure is higher.

Two consequences follow for an incoming maintainer. The tests are the reliable
record of intent, because they were written with each change. And a reviewer who is
neither the maintainer nor the tool is worth more here than usual (document 08).
Whether the framework requires disclosure of AI-assisted authorship is decision D12.

## People

| Role | Name | Contact |
|---|---|---|
| Maintainer | `[TO CONFIRM]` | `[TO CONFIRM: team address, decision D4]` |
| Deputy maintainer | `[TO CONFIRM]` | |
| Steward | `[TO CONFIRM]` | |
| Custodian | `[TO CONFIRM]` | |

## Handover session checklist

Each takes about `[TO CONFIRM]` minutes with the outgoing maintainer.

- [ ] Walk `vignette("start_here")` on a real gauging file.
- [ ] Add a change end to end: a branch, a test that fails, the fix, `NEWS.md`, a pull
      request, a green CI run.
- [ ] Add a reference case, and see it picked up by the tests without further work.
- [ ] Read the table of traps above, and trigger one deliberately.
- [ ] Make a release: tag, checklist, `check_reference_cases()`.
- [ ] Roll the package back one version (document 05).
- [ ] Read the limitations register and add one entry.

## Decisions this document needs

D3 (release authority), D4 (team address), D9 (tags and pinning), D10 (the policy),
D12 (AI-assisted authorship).

## Version history

| Version | Date | Change |
|---|---|---|
| 0.1 | 22 November 2026 | First draft |
