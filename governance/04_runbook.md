# 04 Runbook

| | |
|---|---|
| Status | DRAFT for review. Nothing in this document has been agreed. |
| Version | 0.1 |
| Date | 22 November 2026 |
| Asset | `reach.rate` 0.2.0 |
| Reader | Custodians and analysts |

## Summary

`reach.rate` is a library, not a service. Nothing runs, so nothing needs
monitoring or restarting. What needs a procedure is the work done with it: producing
a rating, reviewing it, approving it, archiving it, and keeping the installation
trustworthy as R and its packages change.

This runbook gives those procedures. Every command in it was run end to end on the
shipped example file before it was written down.

**Do not follow it for live forecasting yet.** The package is Tier 1 until the Owner
promotes it (document 01). Until then, follow it for analysis and evaluation.

## Preconditions for any operational use

All of these MUST hold. If one does not, stop.

| # | Precondition | Where it is settled |
|---|---|---|
| 1 | The Owner has promoted the package to Tier 3 | Document 01 |
| 2 | The target-environment test has passed on this machine, for this package version | Document 07 |
| 3 | The gaugings are Gold-tier data | Limitation L14; decision D5 |
| 4 | A named rating approver exists for the station | Document 01 |
| 5 | The previous rating is archived and retrievable | Document 05 |
| 6 | The package version and its dependencies are recorded | Section 6 below |

## 1 Produce a rating

The decision gates are marked **STOP** and **CONTINUE**. A gate is not advice.

```r
library(reach.rate)
library(data.table)

# 1. Read. Never edit the source file.
gaugings <- read_gaugings("site_gaugings.csv")
read_summary(gaugings)

# 2. Validate.
checks <- validate_gaugings(gaugings)
assessment_checks(checks)[status %in% c("fail", "warning")]

# 3. Fit.
fit <- fit_rating(gaugings, seed = 1)

# 4. Look.
autoplot(fit)

# 5. State the range of use, and why.
fit <- set_operational_limits(fit, 0.25, 3.6, basis = "Control confirmed by site visit, 12 March 2026")

# 6. Assess.
assessment <- assess_rating(fit)
assessment_checks(assessment)[status != "pass"]

# 7. Test the dependence on the evidence.
rating_sensitivity(fit)

# 8. Submit for review.
fit <- set_lifecycle(fit, "under_review", by = "A. Analyst", reason = "Fitted from the 2026 gaugings")
export_rating(fit, assessment, path = "site_rating_review")
rating_report("site_rating_review", path = "site_rating_review_report.html")
```

| Step | Read | STOP if |
|---|---|---|
| 1 | `read_summary()`: the rows read, and every row with a note | The row count is not what the source file holds, or a station is missing |
| 2 | Every `fail`, then every `warning` | Any `fail`. A fail means the data cannot be used as it stands. Fix the source and read again |
| 3 | The message: rows used, rows not used, with reasons | Rows were dropped that should not have been. Each exclusion has a reason; read them |
| 4 | The plot: grey points are excluded rows, never hidden | The curve is plainly wrong for the data |
| 5 | The basis, written so a reviewer can check it | You cannot state a basis. A range without a reason is a guess |
| 6 | Every non-pass, with its recommendation | Any `fail`. A `warning` needs a written reason to accept it |
| 7 | How far discharge moves when the highest gaugings leave | The top of the curve rests on a few gaugings the reviewer has not seen |
| 8 | The report: a second person reads it | |

**Record the assessment limits.** The assessment does not store the thresholds it
used. If any default was changed, write down which and why, and archive it with the
rating (limitation L02).

**A reviewer who is also the analyst is not a review.** Step 9 is by a different
person unless the Steward has said otherwise.

```r
# 9. The approver, after reading the report and the assessment.
fit <- set_lifecycle(fit, "approved", by = "B. Reviewer",
                     reason = "Assessment and sensitivity read; limits confirmed",
                     allow_self_approval = FALSE)

# 10. Archive.
export_rating(fit, assessment, path = "site_rating_approved")
writeLines(capture.output(sessionInfo()), "site_rating_approved/sessionInfo.txt")
```

`allow_self_approval = FALSE` makes the package refuse the approval if the same
person put it under review. It is the default to allow it, by the maintainer's
decision. A Steward may set the opposite as policy (document 01).

## 2 What to archive

Keep these together, for the life of the rating plus `[TO CONFIRM]` years.

| Item | Why |
|---|---|
| The export folder (`rating.rds`, `assessment.rds`, the CSV tables, `README.txt`, `manifest.csv`) | The record, and a copy a person can read without R |
| `sessionInfo.txt` | The R and package versions that made it |
| The source gauging file, unaltered, with its checksum | The evidence the rating rests on |
| The assessment limits used, if any default was changed | Limitation L02 |
| The review report, and who read it | The review |

`manifest.csv` lists a checksum for each file in the export. It detects damage and
accidental edits. It does not stop someone who edits the manifest as well, so store
the checksums somewhere else if tampering matters (limitation L12).

## 3 Reading the package's messages

| Message, or its start | Meaning | Do |
|---|---|---|
| `N of M stage value(s) lie beyond the gauged range ... are extrapolated` (warning) | A stage outside the gauged range. The value is returned and flagged `extrapolation` in the `support` column. No operational limits are set | Set limits with a basis (step 5), or treat the value as an extrapolation |
| `N of M stage value(s) fall outside this rating's operational limits` (error) | A stage outside limits a person stated | Check the stage values for a unit or datum error. Widen the limits only if you can state why |
| `this rating fails N post-fit check(s) and will not be applied` (error) | The equations fail a validity check | `rating_invariants(x)` lists them. Refit or correct. Do not work round it |
| `lie beyond the numerical range of this rating ... a discharge computed there would not be a number` (error) | A stage so large the equation overflows | Check the stage values for a unit or datum error |
| `limb N did not converge from its single start` (warning) | The optimiser did not settle | Use `multi_start = TRUE`, or treat that limb with caution |
| `age_halflife needs an observation_time for every gauging used` (error) | Recency weighting needs a time on every row | Supply the times, or drop the weighting |
| `does not match its checksum in the manifest` (error) | A file in an export was changed or damaged | Do not use that export. Restore from the archive (document 05) |
| `has no manifest.csv` (error) | Not an export folder, or its manifest was removed | Locate the original export |
| `schema_version N is newer than this reach.rate understands` (error) | The object was saved by a newer package | Update the package. Do not edit the object |
| `No migration from N exists, so it cannot be read` (error) | The object is from an older layout with no migration | Refit from its evidence, or use the package version that saved it |
| `a rating that is X cannot go to Y` (error) | A lifecycle move the rules do not allow | The message lists the moves that are allowed |
| `cannot also approve it` (error) | `allow_self_approval = FALSE` and the same person reviewed it | A second person approves |
| `fails its own validity checks cannot be approved` (error) | Approval refused for an invalid rating | `rating_invariants(x)` |

A message not on this list is not an emergency. Read it. If the cause is not clear,
record it and raise it with the maintainer.

## 4 Periodic and event-driven tasks

| Task | When | Who | Evidence |
|---|---|---|---|
| Run `check_reference_cases()` | After any change to R, a dependency, or the package on the machine | Custodian | The result table, saved |
| Run the target-environment script | Before first use on a machine, and after a major change | Custodian | Document 07 record |
| Review the limitations register | At each release, and each quarter `[TO CONFIRM]` | Maintainer, Steward | Updated register |
| Review a station's rating | At an interval the Steward sets `[TO CONFIRM]`, and after any event that may have moved the control | Rating approver | A new assessment, and the old one archived |
| Check the manifest of an archived export | Annually `[TO CONFIRM]` | Custodian | `import_rating()` succeeds |

## 5 Upgrade R, a dependency or the package

The reference cases exist for this. A change that moves a fit shows in them.

1. Read `NEWS.md` for the versions between. Look for **Breaking** and
   **mathematical change**.
2. Keep the current installation for rollback (document 05).
3. Install the new version on a test machine first, or a separate library.
4. Run `check_reference_cases()`. All ten MUST pass.
5. Re-run the routine on two or three stations whose approved ratings you hold, and
   compare:

   ```r
   old <- import_rating("site_rating_approved")$rating
   new <- fit_rating(gaugings, seed = 1)
   compare_ratings(old, new)$discharge
   ```

6. Differences MUST be understood. A difference that is not understood blocks the
   upgrade.
7. Record the upgrade: what, when, who, and the result of step 4.

## 6 Record the installation

```r
sessionInfo()
packageVersion("reach.rate")
```

Save the output where the target-environment record is kept. An installation that
cannot say what it is cannot be reproduced.

## 7 Incident handling

An incident is a rating that is wrong, a package that fails, or a result nobody can
explain. The package cannot detect the first. A person finds it.

| Step | Action |
|---|---|
| 1 | **Contain.** Fall back to the previous rating (document 05). Do this first |
| 2 | **Record.** Date, station, what was seen, who saw it |
| 3 | **Classify.** A rating problem (the evidence or the judgement), a package problem (a defect), or an environment problem (R, a dependency, the machine) |
| 4 | **Fix.** A rating problem: a new rating, through the routine. A package problem: a change through review. An environment problem: the machine, then document 07 again |
| 5 | **Review.** What would have caught it earlier? Update the limitations register |

**An urgent code change** is a Route D hotfix under the framework. It needs verbal
authorisation from the Steward before the work. A rapid record follows within 24
hours, a standard record and a post-incident review within ten working days. No more
than two hotfixes in twelve months for the same tool area. A third means the area
needs redesign, not a third patch.

## 8 Reproduce a rating from an archive

A competent analyst MUST be able to do this without asking the author.

```r
library(reach.rate)
imported <- import_rating("site_rating_approved")   # checks every file first
imported$rating                                     # the rating, with who approved it
imported$assessment                                 # the assessment
rating_lifecycle(imported$rating)                   # who, when and why
rating_history(imported$rating)                     # what was done to it
rating_provenance(imported$rating)$fit_rating$call  # how it was fitted
autoplot(imported$rating)
rating_report(imported$rating, imported$assessment, path = "report.html")
```

A rating made under a different package version may not read. The archived
`sessionInfo.txt` says which version to install (document 05).

## 9 Do not

- Edit a rating object, an export, or a manifest by hand.
- Approve a rating you have not read the report for.
- Use a rating beyond its operational limits by widening them to make an error
  disappear.
- Use `rate_optimise()` for an operational rating. It has no operational gate and no
  guided record. It is for experts.
- Use the teaching tools (`rating_curve_explorer()`, `run_demo()`, `station_gaugings`)
  for anything operational.
- Treat a passing assessment as an approval. It is a prompt to look.

## Decisions this document needs

D1, D3, D5, D11. The intervals marked `[TO CONFIRM]` belong to the Steward.

## Version history

| Version | Date | Change |
|---|---|---|
| 0.1 | 22 November 2026 | First draft |
