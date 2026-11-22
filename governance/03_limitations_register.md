# 03 Limitations register

| | |
|---|---|
| Status | DRAFT for review. Nothing in this document has been agreed. |
| Version | 0.1 |
| Date | 22 November 2026 |
| Asset | `reach.rate` 0.2.0 |

## Summary

This register lists what the package does not do and what follows from it. It is
written to be read by someone deciding whether to rely on the package, so it states
the consequence of each limitation, not only the fact.

Severity is judged for **Tier 3 use**, meaning a rating that drives live forecasting
or operational warning. A limitation that is trivial for analysis can be serious
there.

| Severity | Meaning |
|---|---|
| High | Resolve, or accept in writing, before Tier 3 promotion |
| Medium | Resolve or mitigate; the Steward should know |
| Low | Record and review |

Seven items are High. Five stand out: **L01** (no real gauging file has been read),
**L11** (an approval is a typed name), **L14** (nothing records whether evidence is
Gold), **L16** (no managed machine has been tested) and **L23** (the package claims a
tier it does not hold). Two more need a procedure or a person, not code: **L05**
(extrapolation is flagged, not blocked, without operational limits) and **L21** (one
maintainer, and AI-assisted authorship).

## Register

### Evidence and inputs

| ID | Limitation | Consequence | In place now | Needed | Severity |
|---|---|---|---|---|---|
| L01 | The readers were tested on synthetic files and one teaching dataset. **No real operational gauging or rating file has been read.** | A real export with a layout the readers did not anticipate may be misread. The readers keep every row and note each problem, so a misread is visible, not silent | Original text kept beside every converted value; `read_summary()`; the 16 `validate_gaugings()` checks | Run real files from the intended stations through the workflow and review each result (document 07, TE-06) | High |
| L14 | The evidence table has no field for medallion stage. The framework allows only Gold data as input to Tier 3 runs. | Nothing stops Bronze or Silver gaugings being fitted for an operational rating, and nothing records which stage was used | `quality_code`, `source_version` and `metadata` columns exist and could carry it; the report lists the sources | Decide how Gold is certified and recorded (D5). Then add a check that evidence carries it, or record it in the archive | High |
| L25 | A gauging with no time of day is given midnight. Dates are read in the format found, and time zones are not converted. | Recency weighting reads the wrong age by up to a day. A mixed-format file may misplace a date | The `times_assumed` warning; the date format found is reported | Confirm the time convention of the real files (document 07, TE-09) | Low |
| L22 | The shipped dataset `station_gaugings` has no stated licence or station name. | If the package leaves the EA, the dataset may not be redistributable | It is labelled teaching data, not for operational use | State the source and permission, or replace it with synthetic data | Medium |

### The model

| ID | Limitation | Consequence | In place now | Needed | Severity |
|---|---|---|---|---|---|
| L03 | Each limb is a power law, `Q = C (H - a)^n`, and the rating is stationary within itself. There is no hysteresis, backwater, weed growth or seasonal shift. | A station dominated by any of these gets a curve that is wrong in a way the package cannot see | Recency weighting for drift; the assessment's hydraulic checks; sensitivity tests | A hydrometrician judges each station. The package assists; it does not replace the judgement | Medium |
| L04 | Bootstrap bands, where requested, show the effect of having only these gaugings. They do not include each gauging's own measurement error. | A band narrower than the true uncertainty | The documentation states it; `rating_sensitivity()` shows dependence on evidence | Decide whether measurement error needs modelling (a Release E question) | Medium |
| L05 | A rating from `fit_rating()` with no operational limits returns a value beyond the gauged range, flagged `extrapolation` and warned, and does not refuse. A plain `rate_optimise()` fit has no such gate. | A forecast can use an extrapolated discharge without anyone reading the warning | The `support` column on every answer; one warning per call; limits can make it a hard boundary | Require operational limits for any Tier 3 rating (a procedure in document 04) | High |
| L06 | Operational limits are stated by a person, with a basis. The package does not test them against hydraulics. | Wrong limits are enforced faithfully | `extrapolation_extent` in the assessment, when limits are stated | A reviewer checks the stated basis | Medium |
| L07 | `suggest_breakpoints()` is a statistical search over the gaugings. | It can miss a real change of control and propose a spurious one. On a synthetic station with a known break at 1.6 m, the top candidate was 2.83 m and the real break ranked fifth | Output is called candidates; the origin of an adopted breakpoint is recorded | A person decides where a control changes, from the site | Medium |
| L08 | Limb snapping closes a discontinuity without saying which limb is right. | `align_limb_equations()` rescales an entire limb. A 10.9% gap closed that way changed discharge at 2.5 m by 9.8% | `check_limb_continuity()` before and after; the original coefficients kept | Investigate a gap before closing it | Medium |
| L09 | The segmented model is a harder fit. `compare_ratings()` does not accept it. | Possible local optima; fewer comparison tools | Multi-start by default; fixed breakpoints unless asked | Use independent limbs where comparison matters | Low |
| L10 | The recency floor protects every old gauging equally, not old floods in particular. The half-life is a judgement, in days. | An old extreme flood loses weight like an old routine gauging | Documented; the floor stops any weight reaching zero | A magnitude-aware version is tracked as an issue and not built | Medium |
| L26 | The largest set run through the workflow is 223 gaugings (the teaching dataset); timings were taken at 100. The pairwise inversion check is skipped above 10,000 usable gaugings, with a message. Many stations in one run were not tested. | Slower or less thorough checks on very large sets | The skip is reported; a 100-gauging fit took 0.02 s on the build machine | Test at the sizes the real stations have (document 07, TE-10) | Low |

### Approval and records

| ID | Limitation | Consequence | In place now | Needed | Severity |
|---|---|---|---|---|---|
| L11 | `set_lifecycle()` records the name it is given. It does not authenticate it. Self-approval is allowed by default. A `FlodeRatingTable` cannot hold a record. | An approval is as trustworthy as the process around it. A table has no record of who changed it | The record includes the time and reason; self-approval is annotated; `allow_self_approval = FALSE` requires a second person | A procedure that says who may approve and where the archive is kept (documents 01 and 04) | High |
| L27 | The export's CSV tables list the rows a rating used, not the rows left out. Those, with their reasons, are in `rating.rds` and the review report. | A reviewer without R cannot see which rows were excluded from the CSV tables alone | The report lists every exclusion with its reason; the reproduction from `evidence.csv` gives identical coefficients | Add an `excluded.csv` to the export (a small change, not made here) | Medium |
| L12 | The export manifest uses MD5 checksums. The `.rds` record depends on the package that wrote it. | A checksum detects damage and untracked edits, not someone who also edits the manifest. An `.rds` may not read under a different package version | `import_rating()` verifies every file; the README in each export names the version and schema | Archive the export with the package version; store checksums separately if tampering matters | Medium |
| L13 | The schema has one version with a layout. A migration mechanism exists and has nothing to run. | An object from a future layout is refused, not read. An object from an older layout is refused unless a migration exists | Refusals say why; the mechanism is tested | Write migrations when the layout changes | Low |
| L20 | The documentation site's diagrams use Mermaid, which could not be checked from the build environment. The live site was not reachable. | A diagram may show as source text | Each diagram's source is readable | Open the site and look | Low |

### Assurance

| ID | Limitation | Consequence | In place now | Needed | Severity |
|---|---|---|---|---|---|
| L15 | The ten reference cases are synthetic and were written by the package's author. | Passing them shows the package works as its author expects. It shows nothing about a real station | Each case states what it does not test; envelopes leave double the error seen | An independent reviewer extends them (document 08) | Medium |
| L16 | CI covers Windows and Linux on R release and oldrel-1; macOS builds the C core only. **No EA managed machine has been tested.** R 4.1, the declared minimum, is not in CI. | An environment-specific failure is possible and undetected | A full pass on the build machine (R 4.3.3); the target-environment script (document 07) | Run document 07 on each target machine | High |
| L17 | No minimum versions for dependencies, no lockfile. | A dependency update can change behaviour silently, as S7 1.0.0 did | The reference cases, which would show a change | Pin operational installs; declare minimums (document 02) | Medium |
| L18 | The C kernel reports version `0.1.0` against package `0.2.0`, and is shared with a Python package outside this repository. | A kernel change can affect the other package; a version mismatch confuses support | ABI version 1; the kernel is tested alone | Align the version string; coordinate kernel changes | Low |

### Governance

| ID | Limitation | Consequence | In place now | Needed | Severity |
|---|---|---|---|---|---|
| L23 | The source headers state Tier 3. The package is Tier 1 until the Owner promotes it. | A reader may take it as cleared for live use | This register and document 01 say otherwise | Decide D1, then correct the headers | High |
| L21 | One person maintains the package. Most changes in Releases A to C were written in AI-assisted sessions (Claude Code), under the maintainer's direction. At least 11 commits carry the AI co-author trailer; squash merges drop trailers, so the true number is higher. | Knowledge is concentrated. AI-assisted code needs a reader who is not the author and not the tool | Tests, CI, and a documented design; this pack | An independent reviewer, and a Steward view on disclosure (D12). A named deputy maintainer | High |
| L19 | The package has no release tags. Version 0.2.0 is a development version. The release policy is a proposal. | A rollback has to name a commit, not a version | Commits are identifiable | Tag releases once the policy is accepted (D9, D10) | Medium |
| L24 | `rating_plot()` is superseded but does not warn. The teaching tools (`rating_curve_explorer()`, `run_demo()`) are exported. | A user may reach for a tool that is not meant for operations | The reference index labels them; the policy register tracks `rating_plot()` | Move the vignettes to `autoplot()`, then warn | Low |
| L02 | Assessment limits are best-endeavours defaults, not EA policy. The assessment does not record which limits it used. | A pass can mean different things on different days | `vignette("thresholds")` states it; every limit is an argument | Record the limits used wherever a rating is archived (document 04) | Medium |

## Using this register

- **At promotion:** every High item is resolved or accepted in writing by the
  Owner.
- **At each release:** the maintainer reviews the register and updates it.
- **When a limitation bites:** add an entry, or raise its severity, and say what
  happened.

## Decisions this document needs

D1, D5, D9, D10, D12. See the [index](README.md#decisions-needed).

## Version history

| Version | Date | Change |
|---|---|---|
| 0.1 | 22 November 2026 | First draft: 27 entries |
