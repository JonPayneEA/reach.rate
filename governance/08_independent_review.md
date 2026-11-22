# 08 Independent review

| | |
|---|---|
| Status | DRAFT for review. Nothing in this document has been agreed. |
| Version | 0.1 |
| Date | 22 November 2026 |
| Asset | `reach.rate` 0.2.0 |
| Reader | The independent reviewer, and the Steward who commissions the review |

## Summary

An independent review tells the Owner whether the package should be considered for
Tier 3. It is the one assurance step that checks the package against someone other
than its author.

That matters more than usual here. One person maintains the package, and most of
Releases A to C was written in AI-assisted sessions. The author's tests and
documentation are evidence. They are not independent evidence.

This document gives the reviewer terms of reference and a checklist. It does not
supply the reviewer: decision D8.

## Purpose and limits

The review MUST answer one question: **is there enough evidence that this package
does what it says, and says honestly where it does not, for the Owner to consider
promoting it to Tier 3?**

The review does **not**:

- approve any rating (a rating's approver does that);
- decide promotion (the Owner does that, on the Steward's sign-off);
- replace the target-environment test (document 07);
- judge a real station's hydrology.

## Independence

The reviewer MUST declare, before starting, that they:

| # | Declaration |
|---|---|
| 1 | Did not write or commit any code in the package, with or without AI assistance |
| 2 | Did not write any document in this pack |
| 3 | Will not approve ratings made with the package in the period under review |
| 4 | Has no reporting line to the maintainer that would make an adverse finding awkward `[TO CONFIRM how this is judged]` |
| 5 | Is competent in R and in hydrometry, or reviews with someone who is |

The commissioning Steward records the declaration. A reviewer who cannot make all five
is not independent, and the review is not accepted as one.

## What the reviewer is given

| Item | Where |
|---|---|
| The repository, at a named commit or tag | `[TO CONFIRM]` |
| This pack, documents 01 to 08 | `governance/` |
| The target-environment records | Document 07, for each machine |
| The reference cases | `reference_cases()`; `vignette("reference_cases")` |
| An export folder for the reproduction exercise | Made by the maintainer, as below |
| Read access to the issues and the plan | `IMPROVEMENT_PLAN.md`, the issue tracker |

The reviewer is **not** given the author's time during the reproduction exercise. That
is the point of it.

## Method

Suggested time: `[TO CONFIRM]` days. The reviewer chooses the order and may add checks.

### A The reproduction exercise (first, and alone)

The Release C gate states: a competent analyst reproduces and reviews a rating
without asking the author. This tests it.

The maintainer makes the exercise folder, then closes the session:

```r
library(reach.rate)
g <- read_gaugings(system.file("extdata", "example_gaugings.csv", package = "reach.rate"))
fit <- fit_rating(g, seed = 1)
fit <- set_operational_limits(fit, 0.25, 3.0, basis = "Exercise")
a <- assess_rating(fit)
fit <- set_lifecycle(fit, "under_review", by = "Exercise A", reason = "Exercise")
fit <- set_lifecycle(fit, "approved", by = "Exercise B", reason = "Exercise")
export_rating(fit, a, path = "exercise_rating")
```

The reviewer receives only `exercise_rating/`, a fresh R session and the installed
package. Without help they MUST answer:

1. What rating is this, for which evidence, and which equation does each limb use?
2. Who approved it, when, and why? Who put it under review?
3. How was it fitted: the objective, the model, the seed, the rows used and not used?
4. What did the assessment find? Which findings need a person's judgement?
5. What range may it be used over, and on what stated basis?
6. What does it rest on: which stage ranges are observed, and which are extrapolation?
7. Is the folder intact? (Alter one byte of one file in a copy and check the refusal.)
8. Can the rating be reproduced from its evidence, and does the reproduction agree?

The reviewer records how long each took and where they were stuck. **Anywhere they
needed the author is a finding**, because the next analyst will not have the author
either.

### B The mathematics

| Check | How |
|---|---|
| The equations are as stated | Read the implementation against `vignette("mathematical_contract")`. Each stated property should have a test |
| The fit is right | Refit two reference cases with a different tool, such as base `nls`, and compare discharge across the range |
| The weighting is right | Check the absolute and relative objectives, and the recency formula, by hand on a small example |
| The validity checks are right | Break a rating deliberately (negative `C`, an exponent out of range) and confirm `apply_rating()` refuses it |

### C The tests

Passing tests show the author's tests pass. The reviewer asks whether they would fail
if the code were wrong.

| Check | How |
|---|---|
| Behaviour, not implementation | Read twenty tests. Do they assert what the user sees? |
| Mutation spot checks | Change one coefficient, one comparison operator and one default in five places. A test SHOULD fail for each. Record those that do not |
| The reference cases | Review each of the ten. Are they realistic? What is missing? Suggested gaps: a hysteresis loop, weed growth through a season, an overbank control, tied stages, discharge near zero, a very large dataset, a clustered set of outliers |

### D Failure behaviour

Feed the readers and the fit bad input: an empty file, text in a numeric column,
duplicated rows, a wrong unit, negative discharge, `NA`, stage in centimetres. The
package MUST fail safe, and say why in words a Custodian can act on. Record each
result.

### E Records and the lifecycle

Try to defeat it, and compare with the limitations register (L11, L12).

| Attempt | Expected |
|---|---|
| Approve a draft | Refused |
| Approve a rating that fails its validity checks | Refused |
| Edit a file in an export, then import | Refused, naming the file |
| Edit a file and its manifest checksum | **Accepted.** The register says so. Confirm the register is honest |
| Put a table through `set_lifecycle()` | Refused, with the reason |
| Type another person's name as `by` | Accepted. The register says so |

### F Documentation honesty

Choose ten claims at random from the README, the vignettes and `NEWS.md`. Run each. A
claim that is false, overstated or untested is a finding. Then ask what the
limitations register leaves out.

**Check every literature citation.** The vignettes cite Hodson et al. (2024), Cook
(1977), St. Laurent and Cook (1992) and Belsley, Kuh and Welsch (1980). The reviewer
MUST confirm each exists and says what the vignette claims. AI-assisted drafting can
produce a plausible reference that is wrong.

### G Authorship

Because of the AI assistance (L21), read at least three modules without the tests, as a
reviewer reads code they will have to maintain. Look for code that is complex without
reason, patterns that look right and are not, comments that describe something else,
and duplication. Sample the commit history. State whether the code is something a
competent maintainer could own.

### H Dependencies and licences

Review document 02. Assess maintenance and community adoption for at least three
dependencies, which the document leaves to a person with network access.

### I Governance

Map the pack to the framework's Tier 3 requirements `[TO CONFIRM: the requirement
list is not held by the author]`. State which are met, which are partly met, and which
are not.

## Outcomes

| Outcome | Meaning |
|---|---|
| **Accept for Tier 3 consideration** | The evidence is sufficient. Findings, if any, are minor |
| **Accept with conditions** | Sufficient once named findings are closed. The conditions are listed and checkable |
| **Do not accept** | The evidence is not sufficient. The reasons and what would change them are stated |

The reviewer's outcome is advice to the Steward and the Owner. It is not a promotion.

## Findings

| ID | Severity | Finding | Evidence | Recommendation | Maintainer response | Status |
|---|---|---|---|---|---|---|
| R01 | | | | | | |

| Severity | Meaning |
|---|---|
| Blocker | Must close before promotion |
| Major | Should close before promotion; the Steward decides |
| Minor | Close in the normal course |
| Observation | No action required |

A finding is closed when the reviewer, not the maintainer, agrees the evidence shows it.

## Report

The reviewer writes a short report:

1. The declaration of independence.
2. What was reviewed, at which commit, over how many days.
3. The outcome, in the first paragraph.
4. The findings table.
5. The reproduction exercise: the eight answers, the time taken, and every point where
   help was needed.
6. What the review did not cover.
7. Signature and date.

## Sign-off

| | Name | Date |
|---|---|---|
| Reviewer | `[TO CONFIRM]` | |
| Commissioning Steward | `[TO CONFIRM]` | |
| Owner, on receipt | `[TO CONFIRM]` | |

## Decisions this document needs

D8 (the reviewer), D12 (a view on AI-assisted authorship). The time allowed, and how
independence from the maintainer is judged, belong to the Steward.

## Version history

| Version | Date | Change |
|---|---|---|
| 0.1 | 22 November 2026 | First draft |
