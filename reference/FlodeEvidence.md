# Evidence a rating rests on (S7)

A `data.table` with a fixed set of columns. Each row is one observation
(a spot gauging, a point read off an operational rating, a modelled
value, a cross-section computation or a structure equation) and keeps a
stable identifier, so that a diagnostic, a flag or an exclusion can name
the observation it concerns. Because it is a data.table, ordinary
subsetting and column access work unchanged.

The columns are:

|  |  |  |
|----|----|----|
| column | class | meaning |
| `evidence_id` | character | unique, never missing; the row's identity |
| `site_id` | character | station identifier, `NA` if unknown |
| `stage_m` | numeric | stage in metres |
| `discharge_cms` | numeric | discharge in cubic metres per second |
| `observation_time` | `Date` or `POSIXct` | when it was observed, `NA` if unknown |
| `source_type` | character | one of [`evidence_source_types()`](https://jonpayneea.github.io/reach.rate/reference/evidence_source_types.md) |
| `source_name` | character | the file, system or method it came from |
| `source_version` | character | the version or extract date of the source |
| `quality_code` | character | the source's own quality marker, carried uninterpreted |
| `included` | logical | whether a fit should use it |
| `exclusion_reason` | character | why not, when `included` is `FALSE` |
| `weight` | numeric | a prior weight, 1 unless set |
| `notes` | character | free text |
| `source_row` | integer | the row number in the source, for tracing back |
| `metadata` | list | anything source-specific, one entry per row |

Columns beyond these are allowed and kept, after the canonical ones.

## Usage

``` r
FlodeEvidence(.data = data.table(), conversion_note = character(0))
```

## Arguments

- .data:

  A `data.frame` or `data.table` holding every canonical column. To
  build one from a table that does not, use
  [`as_flode_evidence()`](https://jonpayneea.github.io/reach.rate/reference/as_flode_evidence.md),
  which fills the missing columns and says what it assumed.

- conversion_note:

  Character. What was assumed when the table was built from a plainer
  one; empty when none was.

## Value

A `FlodeEvidence`, which is also a `data.table`.

## See also

[`as_flode_evidence()`](https://jonpayneea.github.io/reach.rate/reference/as_flode_evidence.md),
[`evidence_source_types()`](https://jonpayneea.github.io/reach.rate/reference/evidence_source_types.md),
[`rating_evidence()`](https://jonpayneea.github.io/reach.rate/reference/rating_evidence.md)

## Examples

``` r
evidence <- as_flode_evidence(data.frame(
  stage_m = c(0.5, 1.1, 1.8), discharge_cms = c(1.2, 5.1, 12.4)
))
evidence
#> <FlodeEvidence> 3 row(s), 3 included, source type(s): gauging
#> Note: Converted from a plain table; filled evidence_id, site_id, observation_time, source_type, source_name, source_version, quality_code, notes, exclusion_reason, included, weight, source_row, metadata. source_type assumed 'gauging', weight assumed 1, included TRUE unless stage or discharge is missing. 
#>    evidence_id stage_m discharge_cms observation_time source_type included
#>         <char>   <num>         <num>           <POSc>      <char>   <lgcl>
#> 1:        G001     0.5           1.2             <NA>     gauging     TRUE
#> 2:        G002     1.1           5.1             <NA>     gauging     TRUE
#> 3:        G003     1.8          12.4             <NA>     gauging     TRUE
evidence$stage_m
#> [1] 0.5 1.1 1.8
nrow(evidence[stage_m > 1])
#> [1] 2
```
