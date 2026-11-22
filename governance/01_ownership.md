# 01 Ownership

| | |
|---|---|
| Status | DRAFT for review. Nothing in this document has been agreed. |
| Version | 0.1 |
| Date | 22 November 2026 |
| Asset | `reach.rate` 0.2.0 |
| Framework | F&W Data and Digital Asset Governance Framework v2.0 (Draft for Review; endorsement pending) |

## Summary

`reach.rate` has an author and no owner. This document proposes who should hold
each role under the framework, names the decisions that make it real, and
separates two things that are easily confused: ownership of the tool, and
ownership of a rating the tool produces.

Roles below are proposals. Individuals are marked `[TO CONFIRM]`. The author has not
been told who they are.

## Classification

| Item | Position | Basis |
|---|---|---|
| Asset category | Code and tools | Framework asset categories |
| Development route | A: new standalone tool | Framework tool routes. Needs ST G7 confirmation within five working days of the Git issue (decision D1) |
| Current tier | **Tier 1: Experimental** | A tool begins at Tier 1 and is promoted by the Owner |
| Intended tier | Tier 3: Operational | The source headers state it. It is an intention, not a status |
| Input data | Must be Gold for any Tier 3 run | Framework medallion rules. The package cannot check this (limitation L14) |
| Asset register entry | `[TO CONFIRM]` | Record the version, tier, route and roles below |

**Consequence.** Until the Owner promotes it, the package may be used for analysis,
teaching and evaluation. It may not produce ratings that drive live forecasting or
operational warning.

## Roles

| Role | Framework definition | Proposed holder |
|---|---|---|
| Owner | Deputy Director. Ultimate accountability. Approves promotion to Tier 3 | `[TO CONFIRM: Deputy Director]` |
| Steward | G7. Standards, registers, quality, escalation | ST G7 `[TO CONFIRM: name]` |
| Delegated Steward | G6. Operational decisions for the Steward. Cannot approve a tier promotion without Steward sign-off | The author `[TO CONFIRM: name]` |
| Custodian | Any grade. Hands-on installation, running and maintenance | `[TO CONFIRM: named people and a deputy]` |

Why ST G7 as Steward: Service Transformation owns the change programme that produced
the package. Service Management is the likely long-term home for enforcing standards.
Whether stewardship moves there, and when, is a decision for the Owner. This document
does not make it.

## Roles specific to this package

| Role | What it covers | Proposed holder |
|---|---|---|
| Maintainer | Changes the code, keeps the tests passing, writes NEWS | `[TO CONFIRM]`. Today one person (decision D3) |
| Release authority | Decides a version is fit to release, against `vignette("release_policy")` | `[TO CONFIRM]`. Not the author of the change |
| Change reviewer | Reads a change before it merges. The policy requires someone who did not write it | `[TO CONFIRM]` |
| Independent reviewer | Judges the package for Tier 3 consideration. See document 08 | `[TO CONFIRM]` (decision D8) |
| Rating approver | Approves a station's rating. See below | The station's rating owner |

## The tool is not the rating

Two assets are in play, with different owners.

| | The tool (`reach.rate`) | A rating made with it |
|---|---|---|
| What it is | Code | A record for one station, with its evidence |
| Category | Code and tools | `[TO CONFIRM: for example Model outputs]` |
| Owned by | The roles above | The station's rating owner `[TO CONFIRM]` |
| Approved by | The Owner, for tier promotion | The rating approver, by `set_lifecycle(x, "approved", ...)` |
| Changed by | The maintainer, through review | An analyst, through the workflow in document 04 |

Promoting the tool to Tier 3 does not approve any rating. A rating starts as a draft
and the package never moves it on by itself.

## What approval means in the software

`set_lifecycle()` records a name, a reason and a time. It does not check who the
person is. Anyone with R and the object can type any name. **The control is
procedural, not technical.** The framework's approval rules, not the software, make
an approval genuine.

Self-approval is allowed by default, by decision of the maintainer on 20 November
2026. `allow_self_approval = FALSE` requires a second person. A Steward may wish to
require it for Tier 3 ratings. The package records either way, and annotates a
self-approval in the reason (limitation L11).

## Who decides what

| Decision | Decides | Consulted | Evidence needed |
|---|---|---|---|
| Promote the tool to Tier 3 | Owner, on Steward sign-off | Independent reviewer, Custodians | Documents 01 to 08 complete; independent review accepted; target-environment test passed |
| Merge a change | Maintainer, after a change reviewer | Steward for a breaking change | Tests pass; NEWS entry; policy followed |
| Release a version | Release authority | Steward | Release checklist in `vignette("release_policy")` |
| Accept a new dependency | Steward | Custodians | The six Route C criteria, document 02 |
| Emergency hotfix (Route D) | Steward, verbally, before the work | Owner informed | Rapid record within 24 hours; review within ten working days; no more than two per twelve months in a tool area |
| Approve a station's rating | Rating approver | Reviewer of the rating | Assessment read; sensitivity read; lifecycle recorded |
| Withdraw a rating | Rating approver or Steward | Forecasting users | A reason, recorded with `set_lifecycle()` |
| Change an assessment threshold | Steward | Maintainer | The change recorded where the rating is archived: the assessment does not record the limits it used |

## Continuity

Three facts need attention before the package carries operational weight.

1. **One maintainer.** One person holds the knowledge of how it works. Document 06
   is the mitigation, and it is a mitigation, not a cure. A named deputy is needed
   `[TO CONFIRM]`.
2. **Personal contact details.** The maintainer address in `DESCRIPTION` is a
   personal address. An operational asset needs a team address (decision D4).
3. **Personal repository.** The code lives in a repository under a personal GitHub
   account. If that account is lost, so is the asset. Transfer to an
   EA-controlled organisation `[TO CONFIRM]`, or mirror it.

## Proposed asset register entry

| Field | Value |
|---|---|
| Name | `reach.rate` |
| Category | Code and tools |
| Version | 0.2.0 (development) |
| Route | A `[TO CONFIRM]` |
| Tier | 1 now; 3 proposed |
| Owner | `[TO CONFIRM]` |
| Steward | `[TO CONFIRM]` |
| Delegated Steward | `[TO CONFIRM]` |
| Custodians | `[TO CONFIRM]` |
| Repository | `[TO CONFIRM: EA-controlled location]` |
| Specification | `IMPROVEMENT_PLAN.md`, and `vignette("mathematical_contract")` for the mathematics |
| Dependencies | Document 02 |
| Limitations | Document 03 |
| Review due | `[TO CONFIRM]` |

## Decisions this document needs

D1 (route and tier), D2 (roles), D3 (release authority and reviewer), D4 (team
address), D8 (independent reviewer), D12 (AI-assisted authorship). See the
[index](README.md#decisions-needed).

## Version history

| Version | Date | Change |
|---|---|---|
| 0.1 | 22 November 2026 | First draft |
