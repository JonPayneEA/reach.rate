# 02 Dependency inventory

| | |
|---|---|
| Status | DRAFT for review. Nothing in this document has been agreed. |
| Version | 0.1 |
| Date | 22 November 2026 |
| Asset | `reach.rate` 0.2.0 |
| Framework | Route C criteria apply to each external package: maintenance, licence, performance, dependencies, necessity, community adoption |

## Summary

`reach.rate` imports twelve packages, nine of them outside base R, and compiles one
C library. Four things need a decision or a check.

1. **Licences.** The package is MIT. It imports `minpack.lm` (GPL-3) and `gridExtra`
   (GPL 2 or later). A Steward should take licence advice (decision D6). This
   document records the facts and does not give legal advice.
2. **No minimum versions.** `DESCRIPTION` states a minimum version for `testthat`
   and for no other package. A change in a dependency can change behaviour
   silently. That happened on 20 November 2026: S7 1.0.0 stopped `autoplot()`
   working, and the continuous integration run did not catch it because it ran an
   older S7. The fix is in the package; the exposure remains.
3. **No lockfile.** Nothing pins what an operational installation uses.
4. **Two Route C criteria could not be assessed** from the build environment, which
   had no access to package metadata online: maintenance and community adoption. A
   Custodian with network access needs to complete them.

## How it was assessed

Versions and licences below come from the packages installed on the build machine
(R 4.3.3) on 22 November 2026. The continuous integration workflows install the
current releases at the time they run, on R release and R oldrel-1. Neither is a
statement about a target machine, which document 07 tests.

## Runtime dependencies (Imports)

| Package | Version tested | Licence | What `reach.rate` uses it for | What fails without it |
|---|---|---|---|---|
| `data.table` | 1.18.6.1 | MPL-2.0 or file LICENSE | The table type behind evidence, limbs and every result | Everything |
| `minpack.lm` | 1.2-4 | GPL-3 | `nlsLM`, the nonlinear least-squares optimiser behind every fit | Fitting |
| `S7` | 1.0.0 | MIT | The class system: `FlodeRating`, `FlodeRatingTable`, `FlodeAssessment` and the rest | Everything |
| `ggplot2` | 4.0.4 | MIT | `autoplot()`, the diagnostic plots, the report's figure | Plotting; `autoplot` is re-exported |
| `gridExtra` | 2.3.1 | GPL (>= 2) | Arranging multi-panel figures (`plot_rating_comparison()` and others) | Those figures |
| `grid` | base R | Part of R | Graphical objects for combined figures | Those figures |
| `logger` | 0.4.3 | MIT | The INFO messages the functions emit (15 call sites) | Messages |
| `scales` | 1.4.0 | MIT | One axis label in one plot. `ggplot2` already requires it, so removing it would save nothing | One plot's axis |
| `graphics`, `stats`, `utils` | base R | Part of R | Base plotting, statistics, utilities | Everything |
| `tools` | base R | Part of R | `md5sum`, for the export manifest checksums | `export_rating()`, `import_rating()` |

## Optional dependencies (Suggests)

| Package | Version tested | Licence | Needed for |
|---|---|---|---|
| `rmarkdown`, `knitr` | 2.25, 1.45 | GPL-3, GPL | Building vignettes and `rating_report()`. `rating_report()` also needs pandoc and says so if it is absent |
| `readxl` | 1.4.3 | MIT | Reading Excel input in one reader |
| `shiny` | 1.8.0 | GPL-3 | The teaching app `rating_curve_explorer()`. Not for operational use |
| `pkgdown` | 2.0.7 | MIT | The documentation website |
| `testthat` | 3.2.1 | MIT | Running the test suite |

Not installing a suggested package never stops the core workflow: read, validate,
fit, assess, apply and export.

## Transitive dependencies

The twelve imports pull in sixteen further non-base packages: `R6`, `RColorBrewer`,
`S7`, `cli`, `cpp11`, `farver`, `glue`, `gtable`, `isoband`, `labeling`, `lifecycle`,
`rlang`, `scales`, `vctrs`, `viridisLite` and `withr`. A Custodian installing from
source needs all of them, and a compiler for those with compiled code (`cpp11`,
`farver`, `isoband`, `vctrs` and others). On Windows that means Rtools.

## Compiled code

| | |
|---|---|
| What | A C99 evaluation kernel, `src/reach_core.c`, using the standard library only |
| Why | One implementation of the stage-to-discharge arithmetic, evaluated identically wherever it runs |
| Tested | On its own, with no R, on gcc and clang on Linux and clang on macOS (`c-core.yaml`); inside the package on Linux and Windows (`R-CMD-check.yaml`) |
| Shared with | A Python package outside this repository, which uses the same kernel. An incompatible change to the kernel affects both. The ABI version is 1 |
| Finding | The kernel reports its own version string, `0.1.0`, which does not match the package version, `0.2.0`. Cosmetic, and worth aligning before a release |

## System requirements

| Requirement | Detail |
|---|---|
| R | 4.1 or later is declared. **CI tests R release and oldrel-1 only.** 4.1 to 4.3 are not tested by CI; the build machine (4.3.3) passes the full suite |
| Compiler | Needed to install from source: Rtools on Windows, a C toolchain elsewhere |
| pandoc | Only for `rating_report()` and building vignettes |
| Network | **The computation makes no network calls.** Installing the package and its dependencies does. The teaching app's page asks Google Fonts for a typeface when opened; offline it uses a default face, and nothing else changes |
| Install route | GitHub only (`remotes::install_github`). The package is not on CRAN |

## Route C criteria

Six criteria apply to a package adopted from outside. The table gives what could be
assessed. A cell reading **Custodian** needs a person with network access.

| Package | Maintenance | Licence | Performance | Dependencies | Necessity | Community adoption |
|---|---|---|---|---|---|---|
| `data.table` | Custodian | MPL-2.0: file-level copyleft, compatible with use | Not a concern here | Few | Essential | Custodian |
| `minpack.lm` | Custodian | **GPL-3: see D6** | A 100-gauging fit took 0.02 s on the build machine | None beyond base | Essential: the fitting engine | Custodian |
| `S7` | Custodian. **Pre-1.0 until recently, and a 1.0.0 release changed behaviour** | MIT | Not a concern | None beyond base | Essential: the class system | Custodian |
| `ggplot2` | Custodian | MIT | Not a concern | Several | Plotting only | Custodian |
| `gridExtra` | Custodian | **GPL 2 or later: see D6** | Not a concern | Few | Some figures | Custodian |
| `logger` | Custodian | MIT | Not a concern | None | Messages only | Custodian |
| `scales` | Custodian | MIT | Not a concern | Several | One label; required by `ggplot2` anyway | Custodian |

Base R packages (`graphics`, `grid`, `stats`, `tools`, `utils`) are part of R and
follow its release process.

## Licences

| | |
|---|---|
| This package | MIT |
| Permissive | `ggplot2`, `S7`, `logger`, `scales`, `readxl`, `pkgdown`, `testthat` |
| Weak copyleft | `data.table` (MPL-2.0) |
| GPL | `minpack.lm` (3), `gridExtra` (2 or later); suggested: `rmarkdown` (3), `knitr`, `shiny` (3) |

R packages are loaded, not copied into the package, and mixing MIT code with GPL
imports is common practice in R. Whether it is acceptable for an EA asset, and whether
the package should be released under a different licence, is a question for the
people who give licence advice (decision D6). The shipped dataset `station_gaugings`
has no stated licence or station name in its documentation, only "Environment Agency
spot-gauging records". That needs a statement before the package leaves the EA
(limitation L22).

## Versions and pinning

- **Declared minimums:** `R (>= 4.1)` and `testthat (>= 3.0.0)`. Nothing else.
- **Recommendation:** for an operational installation, record the exact versions in
  a lockfile (`renv`) and install from it, so the packages in use are the packages
  tested. Decision D9.
- **Recommendation:** declare a minimum version for `S7` and `data.table`, after
  testing at that minimum, since a behaviour change in either breaks the package.

## Review

| Item | Value |
|---|---|
| Next review | At each release, and whenever R or a dependency is upgraded on a target machine |
| Owner of this inventory | Custodian `[TO CONFIRM]` |
| Trigger for an extra review | A dependency changes its licence, its maintainer, or its major version |

## Decisions this document needs

D6 (licence advice), D7 (target machines and install route), D9 (pinning).

## Version history

| Version | Date | Change |
|---|---|---|
| 0.1 | 22 November 2026 | First draft |
