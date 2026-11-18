# A fitted multi-limb rating curve (S7)

The result of
[`rate_optimise()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise.md)
(or
[`rate_optimise_constrained()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise_constrained.md)):
one row per limb in `@limbs` (bounds, coefficients `C`/`a`/`n`, fit
diagnostics, and – when produced by
[`rate_optimise_constrained()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise_constrained.md)
– alignment provenance), the raw gaugings in `@gaugings`, and bootstrap
draws in `@bootstrap` when `rate_optimise(..., n_boot = )` was used.

## Usage

``` r
FlodeRating(
  gaugings = FlodeEvidence(),
  fit_starts = NULL,
  fit_origin = "independently_fitted",
  lifecycle = "draft",
  schema_version = 2L,
  provenance = list(),
  previous = NULL,
  limbs = data.table(),
  bootstrap = NULL
)
```

## Arguments

- gaugings:

  A
  [FlodeEvidence](https://jonpayneea.github.io/reach.rate/reference/FlodeEvidence.md)
  table of the observations the fit was built from. A plain `data.table`
  with `discharge_cms` and `stage_m` columns is accepted and converted
  by
  [`as_flode_evidence()`](https://jonpayneea.github.io/reach.rate/reference/as_flode_evidence.md),
  which generates evidence IDs and records what it assumed. A
  `gauging_datetime` column (`Date` or `POSIXct`) becomes
  `observation_time` and is used for age weighting.

- fit_starts:

  Data.table of multi-start fitting attempts, or `NULL` if the fit
  wasn't produced with `multi_start = TRUE`.

- fit_origin:

  Character. How the fit came to be: one of `"independently_fitted"`,
  `"post_fit_aligned"` or `"constrained_refit"`. Read-only `@status`
  returns the same value.

- lifecycle:

  Character. Where the rating stands in review: `"draft"` (default),
  `"under_review"`, `"approved"`, `"superseded"` or `"withdrawn"`. The
  package never sets `"approved"`; that is a decision for a person.

- schema_version:

  Integer. The layout version the object was made under; see
  [`rating_schema_version()`](https://jonpayneea.github.io/reach.rate/reference/rating_schema_version.md).
  Leave at the default.

- provenance:

  List recording how the fit was made (fitting method, controls, bounds,
  tool version).

- previous:

  The exact pre-amendment `FlodeRating` this was built from (e.g. by
  [`align_limb_equations()`](https://jonpayneea.github.io/reach.rate/reference/align_limb_equations.md)/[`align_limb_boundaries()`](https://jonpayneea.github.io/reach.rate/reference/align_limb_boundaries.md)),
  or `NULL` (default) for an independently-fitted result.

- limbs:

  Data.table, one row per limb: bounds, coefficients `C`/`a`/`n`, and
  fit diagnostics.

- bootstrap:

  Data.table of per-draw bootstrap coefficients, or `NULL` if the fit
  wasn't produced with `n_boot > 0`.

## Examples

``` r
# A FlodeRating normally comes from rate_optimise(); read it through
# the accessors.
set.seed(1)
stage_m <- seq(0.5, 3, by = 0.1)
discharge_cms <- 3.2 * stage_m^1.6 * exp(rnorm(length(stage_m), sd = 0.03))
fit <- rate_optimise(discharge_cms, stage_m)
fit
#> <FlodeRating> 1 limb(s), origin: independently_fitted, lifecycle: draft
#>   converged: yes (1 of 1 limb)
#>   valid: yes
#>     limb lower_stage_m upper_stage_m        C          a        n  rmse_cms
#>    <int>         <num>         <num>    <num>      <num>    <num>     <num>
#> 1:     1           0.5             3 3.520861 0.05580791 1.538393 0.2765406
#>    r_squared
#>        <num>
#> 1: 0.9973271
rating_limbs(fit)
#>     limb lower_stage_m upper_stage_m        C          a        n
#>    <int>         <num>         <num>    <num>      <num>    <num>
#> 1:     1           0.5             3 3.520861 0.05580791 1.538393
head(rating_evidence(fit))
#> <FlodeEvidence> 6 row(s), 6 included, source type(s): gauging
#> Note: Converted from a plain table; filled evidence_id, site_id, observation_time, source_type, source_name, source_version, quality_code, notes, exclusion_reason, included, weight, source_row, metadata. source_type assumed 'gauging', weight assumed 1, included TRUE unless stage or discharge is missing. 
#>    evidence_id stage_m discharge_cms observation_time source_type included
#>         <char>   <num>         <num>           <POSc>      <char>   <lgcl>
#> 1:        G001     0.5      1.035953             <NA>     gauging     TRUE
#> 2:        G002     0.6      1.420969             <NA>     gauging     TRUE
#> 3:        G003     0.7      1.763679             <NA>     gauging     TRUE
#> 4:        G004     0.8      2.348976             <NA>     gauging     TRUE
#> 5:        G005     0.9      2.730430             <NA>     gauging     TRUE
#> 6:        G006     1.0      3.122196             <NA>     gauging     TRUE

# The constructor checks its input, so a malformed object cannot exist:
# here the limb table is missing its stage bounds.
try(FlodeRating(
  limbs = data.table::data.table(limb = 1, C = 1, a = 0, n = 1),
  gaugings = data.table::data.table(discharge_cms = 1, stage_m = 1)
))
#> Warning: Tried to assign NULL to column 'metadata', but this column does not exist to remove
#> Error in colnamesInt(x, neworder, check_dups = FALSE, skip_absent = skip_absent) : 
#>   argument specifying columns received non-existing column(s): cols[15]='metadata'
```
