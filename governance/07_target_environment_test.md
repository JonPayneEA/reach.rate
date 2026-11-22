# 07 Target-environment test

| | |
|---|---|
| Status | DRAFT for review. Nothing in this document has been agreed. |
| Version | 0.1 |
| Date | 22 November 2026 |
| Asset | `reach.rate` 0.2.0 |
| Reader | Custodians |
| Script | [`target_environment_test.R`](target_environment_test.R) |

## Summary

Continuous integration tests the package on GitHub's machines. It says nothing about
an EA managed machine, which has its own R version, locale, network rules and file
permissions. The Release D gate requires a test on those machines.

This document specifies that test. The script does the work and writes a record. A
Custodian runs it, reads the record, and signs it.

**It has been run on the build machine, not on a managed machine.** No managed machine
has been tested (limitation L16).

## Governance context

| Item | Position |
|---|---|
| Asset | `reach.rate`, code and tools. Tier 1 now; Tier 3 proposed (document 01) |
| Gate | Release D: agreed governance requirements met; passing checks alone do not qualify |
| This test | Necessary for Tier 3 promotion on a machine. It is not sufficient, and it is not a review (document 08) |
| Result | A signed record per machine and per package version, kept with the asset register entry |

## Scope

In scope: that an installation of `reach.rate` loads, computes correctly, reads and
writes files, handles dates and paths on this machine, and runs in a reasonable
time.

Out of scope: whether a rating for a real station is right; the machine's security
posture; the managed machine build itself; anything about the forecasting service.

## Assumptions

Each is a risk if wrong.

| # | Assumption | If wrong |
|---|---|---|
| A1 | The Custodian can install R packages on the machine, or has them installed | The test cannot run. Record it, and raise it with IT (D7) |
| A2 | R 4.1 or later is available | Below 4.1 the package is unsupported. Record the version |
| A3 | A UTF-8 locale | TE-08b fails and some file names may not work. This is a finding, not a script fault |
| A4 | The installed package includes its tests | TE-05 is SKIPPED. The reference cases (TE-04) still run |
| A5 | Write access to the output folder | The test cannot run. Choose another folder, and record it |
| A6 | No network is needed to run. Installing needs it | If the machine is offline, install from a source archive held by the Custodian |

## Requirements

Each requirement is checked by the script. MUST and SHOULD follow RFC 2119.

| ID | Requirement | Pass when |
|---|---|---|
| TE-01 | The test MUST record the environment | Date, machine, OS, R version, locale, time zone, library paths, package versions, pandoc and testthat are in the record |
| TE-02 | `reach.rate` MUST load, at the version under test | `library(reach.rate)` succeeds; the version equals `--expected-version` if given |
| TE-03 | Every imported package MUST be installed | All twelve imports present, with versions recorded |
| TE-04 | The ten reference cases MUST pass | `check_reference_cases()` returns `passed` for all ten |
| TE-05 | The package's own test suite SHOULD pass | Zero failures and zero errors. SKIPPED if tests are not installed |
| TE-06 | The guided workflow MUST run end to end and round-trip | Read, validate, fit, lifecycle, assess, export and import on the shipped example give an equal rating and a two-entry lifecycle record |
| TE-06b | The same MUST hold for a real gauging file, if one is supplied | As TE-06, on `--gauging-file` |
| TE-07 | The review report SHOULD build | A report file is written. SKIPPED if pandoc or rmarkdown is absent |
| TE-08a | Export and import MUST work in a path with spaces and a long length | A round trip in a path of about 280 characters |
| TE-08b | Export and import SHOULD work in a path with accented characters | A round trip in a UTF-8 path |
| TE-09 | Day-first dates MUST be read correctly | The first gauging reads as 2014-03-24 16:45 |
| TE-10 | A 100-gauging fit and a 200-draw bootstrap MUST finish in time | Within 10 s and 60 s unless the Steward sets other limits `[TO CONFIRM]` |

A SKIPPED check is a check not done. The record says so, and a Steward decides
whether a skipped SHOULD is acceptable.

## Procedure

1. **Install** the package version under test, by the route chosen in decision D7. Note
   the commit or tag.
2. **Open a new R session** as the user who will use it, not as an administrator.
3. **Run the script**, with the output folder set to the managed path where exports
   will be written:

   ```
   Rscript target_environment_test.R --output-dir="<managed path>" --expected-version="<version>"
   ```

   Add `--gauging-file="<a real file>"` to include TE-06b. Use a file from an
   intended station. This is the only way a real file is ever tested (limitation L01).
4. **Read the record**, which the script prints and saves.
5. **Resolve** any FAIL, or record why it is accepted (Failure handling below).
6. **Sign** the record and file it with the asset register entry.

The script changes nothing in the installation. It writes only inside the output
folder, and removes its working files afterwards. It exits with status 1 if any check
FAILS, so a deployment pipeline can use it.

## Acceptance criteria

A machine passes when all of these hold.

1. No check is FAIL.
2. TE-02, TE-03, TE-04, TE-06, TE-08a, TE-09 and TE-10 are PASS. These are MUST.
3. Every SKIPPED or failed SHOULD has a written reason accepted by the Steward.
4. At least one real gauging file has been run (TE-06b), and its assessment warnings
   have been read by a person.
5. The record is signed by the person who ran it and a second person.

A pass applies to one machine, one package version and one R version. Repeat after a
change to any of them (document 04, section 5).

## Failure handling

| Failure | Likely cause | Action |
|---|---|---|
| TE-02 | Not installed, wrong version | Reinstall the right version |
| TE-03 | A dependency is missing or blocked | Install it; record the blocker for IT |
| TE-04 | A fit differs on this platform or dependency version | **Do not use the machine.** Record which case and the error. This is the finding the reference cases exist to give |
| TE-05 | A test fails on this platform | As TE-04 |
| TE-06 | The workflow breaks, or the round trip is not equal | Do not use the machine. Record the error message in full |
| TE-08a | A path-length or permission limit | Use a shorter or permitted output folder, and record the limit |
| TE-08b | A non-UTF-8 locale | Set a UTF-8 locale, or avoid accented names. Record it |
| TE-09 | A locale changes how dates are read | Record the locale. Do not use the machine until understood |
| TE-10 | A slow or constrained machine | Record the time. The Steward decides whether it is acceptable |

A FAIL that is not understood blocks the machine. Raise it with the maintainer.

## Record

The script writes this. A Custodian completes the last block.

| Field | Value |
|---|---|
| Machine | (from the record) |
| Package version and commit | `[TO FILL]` |
| R version | (from the record) |
| Locale | (from the record) |
| Install route | `[TO FILL]` |
| Result per check | (from the record) |
| Real file used | `[TO FILL: station and date, or "none"]` |
| Skipped checks and the Steward's decision | `[TO FILL]` |
| Run by, date | `[TO FILL]` |
| Checked by, date | `[TO FILL]` |

## Reference run

The script was run on the build machine on 22 November 2026: Linux, R 4.3.3, a UTF-8
locale (`C.UTF-8`). Eleven checks: ten PASS, one INFO, none FAIL, none SKIPPED, in 99
seconds, most of it the test suite. The 100-gauging fit took 0.02 s and the 200-draw
bootstrap 0.26 s.

Under the sandbox's default C locale, TE-08b failed: R could not translate an
accented path to the native encoding. That is the check working. It found a machine
fact, not a package defect (assumption A3).

This run proves the script. It does not test any managed machine.

## Decisions this document needs

D7 (machines, R version, install route). The time limits in TE-10 belong to the
Steward.

## Version history

| Version | Date | Change |
|---|---|---|
| 0.1 | 22 November 2026 | First draft, with the script |
