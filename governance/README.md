# Release D: operational readiness pack

| | |
|---|---|
| Status | DRAFT for review. Nothing in this pack has been agreed. |
| Version | 0.1 |
| Date | 22 November 2026 |
| Asset | `reach.rate` 0.2.0, an R package for hydrometric rating curves |
| Drafted by | Claude, for Jonathan Payne |
| Framework | F&W Data and Digital Asset Governance Framework v2.0 (Draft for Review). **Endorsement is pending.** If the framework changes, these documents change with it. |

## What this pack is

The Release D gate in the improvement plan reads: agreed governance requirements
met; passing checks alone do not qualify. The package has passed its checks. It has
not met the governance requirements, because most of them are decisions and
documents that code cannot supply.

This pack drafts those documents. It states what is known, marks what is not, and
lists the decisions that belong to the Owner and the Stewards. It does not make
those decisions.

## The first finding

**The package describes itself as Tier 3. It has not been promoted to Tier 3.**

Every source file header carries the line `Tier: 3 (operational forecasting
support; see the project governance notes before live use)`. Under the framework, a
tool begins at Tier 1 and may not be used in live forecasting until the Owner
promotes it to Tier 3. The header states an intention, not a status.

Until the Owner promotes it, `reach.rate` is a Tier 1 asset and must not be used to
produce ratings for live forecasting or operational warning. This is decision D1
below. The headers should be corrected to read "Tier 1, proposed for Tier 3" when it
is taken.

## The documents

| # | Document | What it settles | Written for |
|---|---|---|---|
| 01 | [Ownership](01_ownership.md) | Who owns, stewards, maintains, releases and approves | Owner, Stewards |
| 02 | [Dependency inventory](02_dependency_inventory.md) | What the package rests on, and the Route C criteria for each | Custodians, Steward |
| 03 | [Limitations register](03_limitations_register.md) | What the package does not do, and what follows | Everyone who uses it |
| 04 | [Runbook](04_runbook.md) | How to produce, review, approve and archive a rating; how to upgrade | Custodians, analysts |
| 05 | [Fallback and rollback](05_fallback_and_rollback.md) | What to do when a rating or the package is wrong | Custodians |
| 06 | [Handover](06_handover.md) | What a new maintainer needs to know | Incoming maintainer |
| 07 | [Target-environment test](07_target_environment_test.md) and [script](target_environment_test.R) | How to test on an EA managed machine, and a script that does it | Custodians |
| 08 | [Independent review](08_independent_review.md) | Terms of reference and a checklist for the reviewer | Reviewer, Steward |

## Decisions needed

These are the decisions that stop the gate being met. Each belongs to someone other
than the author. Placeholders in the documents appear as `[TO CONFIRM]`.

| ID | Decision | Whose | Where it bites |
|---|---|---|---|
| D1 | Confirm the development route (A, new standalone tool) and the current tier (1), and correct the source headers | ST G7 confirms within five working days (framework, Route A) | 01 |
| D2 | Name the Owner, Steward, Delegated Steward and Custodians for this asset | Owner, ST G7 | 01 |
| D3 | Name who may release, and who reviews a change before release | ST G7 | 01, 06 |
| D4 | Replace the personal maintainer address in `DESCRIPTION` with a team address | Maintainer, ST G7 | 01, 06 |
| D5 | Decide how gauging evidence is certified Gold and recorded. The package has no field for it | Steward, Owner | 03 (L14) |
| D6 | Take licence advice: an MIT package imports GPL-3 and GPL-2+ packages | Steward | 02 |
| D7 | Name the target machines, their R version, and the install route | Custodians, IT | 07 |
| D8 | Name the independent reviewer, and where they come from | ST G7 | 08 |
| D9 | Decide whether to tag releases and pin dependencies for operational installs | Maintainer, Steward | 05, 06 |
| D10 | Accept or change the release and deprecation policy (`vignette("release_policy")`) | Steward | 06 |
| D11 | State the operational fallback for a rating: what the forecasting service uses today | FFM/LFS, Warning | 05 |
| D12 | State whether AI-assisted authorship needs disclosure or extra review under the framework | Owner, Steward | 03 (L21), 08 |

## What this pack cannot tell you

The author had no access to these. Each is a placeholder in the documents.

- Names, grades and contact details of any individual.
- The managed machines: operating system, R version, network rules, install rights.
- How the forecasting service works today, or what it would fall back to.
- The text of the framework beyond its tier, role, medallion and route summaries.
- EA policy on licences, open-source use, or AI-assisted code.
- Whether any real gauging file has been read by the package. None has.

## Reading order

| If you are | Read |
|---|---|
| The Owner or a Steward | This page, then 01, then 03 |
| A Custodian preparing to run it | 04, 05, then 07 and run the script |
| The independent reviewer | 08, then 03 and 07 |
| An incoming maintainer | 06, then 02 |

## Version history

| Version | Date | Change |
|---|---|---|
| 0.1 | 22 November 2026 | First draft |
