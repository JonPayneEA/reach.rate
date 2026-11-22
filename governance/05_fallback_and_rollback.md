# 05 Fallback and rollback

| | |
|---|---|
| Status | DRAFT for review. Nothing in this document has been agreed. |
| Version | 0.1 |
| Date | 22 November 2026 |
| Asset | `reach.rate` 0.2.0 |
| Reader | Custodians |

## Summary

Two things can go wrong, and they have different remedies.

- **A rating is wrong.** Fall back to the previous rating. This is a decision about
  data, and it takes minutes.
- **The package is wrong.** Roll back to the previous version. This is a decision
  about software, and its speed depends on what was kept.

The first needs an archive. The second needs a version that can be named. **Today the
package has no release tags**, so a version can be named only by its commit. Decision
D9 fixes that.

## What is not known

The most important fallback is the forecasting service's own. This document cannot
say what the service uses when a rating is withdrawn, because the author has not been
told. Decision D11 needs the answer from FFM/LFS and Warning: `[TO CONFIRM: the
operational rating source, who controls it, and how a rating is replaced there]`.

## 1 Fall back to the previous rating

### When

Any of these `[TO CONFIRM thresholds]`:

| Trigger | Example |
|---|---|
| A forecaster, hydrometrician or reviewer judges the rating wrong | Discharge at a known stage disagrees with a fresh gauging |
| A new gauging falls well outside the rating's band | A gauging more than `[TO CONFIRM]`% from the curve |
| The assessment, re-run on new evidence, fails | A `fail` where there was none |
| An error is found in the evidence | A unit or datum mistake in the source file |
| The package version that made the rating is found defective | Section 2 below |

### How

1. **Decide.** The rating approver, or the Steward in their absence
   `[TO CONFIRM]`. Record the time and the reason.
2. **Retrieve the previous approved rating** from the archive (document 04, section
   2):

   ```r
   previous <- import_rating("site_rating_approved_2025")
   previous$rating@lifecycle     # should read "approved"
   rating_lifecycle(previous$rating)
   ```

   `import_rating()` checks every file against its manifest first. If it refuses, the
   archive copy is damaged: use the CSV tables, or the next older archive.
3. **Put it into service** by the forecasting service's own route
   `[TO CONFIRM: depends on D11]`. The package does not push ratings anywhere.
4. **Withdraw the faulty rating**, so nobody uses it again:

   ```r
   bad <- set_lifecycle(bad, "withdrawn", by = "B. Reviewer",
                        reason = "Gauging of 14 November 2026 disagrees by 18%; see incident record")
   export_rating(bad, path = "site_rating_withdrawn_2026-11-20")
   ```

   A rating that is `withdrawn` is final: the package refuses any further change.
5. **Record the incident** (document 04, section 7).

### Retention

Keep every approved rating, not only the current one. A fallback to a rating you
deleted is not a fallback. Retention period `[TO CONFIRM]`.

## 2 Roll back the package

### When

| Trigger | Example |
|---|---|
| `check_reference_cases()` fails after an upgrade | A case outside its envelope |
| A defect in the package is confirmed | A wrong number the tests did not catch |
| A dependency upgrade changes behaviour | As S7 1.0.0 did on 20 November 2026 |
| The target-environment test fails on a changed machine | Document 07 |

### What makes it possible

| Needed | State today | Action |
|---|---|---|
| A name for each released version | **None.** The package has no tags. The version is 0.2.0, development | Tag every release (D9). Until then, record the commit |
| The ability to install that version | `remotes::install_github("JonPayneEA/reach.rate@<tag or commit>")` works, if the machine can reach GitHub | Confirm the route on the target machines (D7) |
| The dependency versions it ran with | Not pinned | A lockfile for operational installs (`renv`), document 02 |
| A copy that does not need the network | Not held | Keep the previous version's source archive on a Custodian-controlled share `[TO CONFIRM]` |

### How

```r
# Install a named version into a separate library, test it, then switch.
remotes::install_github("JonPayneEA/reach.rate@<tag-or-commit>", lib = "<test-library>")
.libPaths(c("<test-library>", .libPaths()))
packageVersion("reach.rate")
check_reference_cases()         # all ten must pass
```

1. **Keep the faulty installation.** Rename it; do not delete it. It is evidence.
2. **Install the previous version** into a separate library and switch to it.
3. **Verify:** `check_reference_cases()` passes; `import_rating()` reads a current
   archive; a routine run on one station matches its approved rating
   (`compare_ratings(old, new)`).
4. **Re-run the target-environment script** (document 07).
5. **Record** the rollback and the reason.

### Exports and versions

An export records the package version and schema in its `README.txt`. This governs
what a rollback can read.

| Situation | Result |
|---|---|
| A newer package reads an older export | Works, or is refused with a reason if the layout changed and no migration exists |
| An older package reads a newer export | **Refused**: `schema_version N is newer than this reach.rate understands` |
| Exports made after the faulty upgrade | May not read under the rolled-back package. Keep their CSV tables, which anyone can read |

So a rollback after exports were made needs the CSV tables, or a roll-forward fix.
Plan for that before upgrading, not after.

## 3 Roll forward instead

Sometimes the faster remedy is a fix, not a reversion. A Route D hotfix is allowed for
this, with the framework's limits: verbal authorisation from the Steward first, a
rapid record within 24 hours, and no more than two in twelve months for the same tool
area.

| Choose | When |
|---|---|
| Roll back | The previous version is known good, the defect is wide, and exports made since can be spared or read |
| Roll forward | The defect is narrow, the fix is small and tested, and exports made since must still read |

## 4 What cannot be rolled back

- **A decision already acted on.** If a forecast used the wrong rating, withdrawing it
  now does not unissue the forecast.
- **An approval's record.** A lifecycle record cannot be deleted. A new record
  supersedes it. That is intended.
- **A deleted archive.** See retention.

## 5 Test it

A fallback that has not been tried is a hope. Before Tier 3 promotion, the Custodian
MUST rehearse both once and record it:

| Rehearsal | Pass when |
|---|---|
| Fall back one station from an approved rating to its archived predecessor | The predecessor is retrieved, verified and ready within `[TO CONFIRM]` minutes |
| Roll the package back one version on a test machine | `check_reference_cases()` passes and an archive reads |

## Decisions this document needs

D7, D9, D11. The thresholds, retention period and times marked `[TO CONFIRM]` belong
to the Steward and to FFM/LFS.

## Version history

| Version | Date | Change |
|---|---|---|
| 0.1 | 22 November 2026 | First draft |
