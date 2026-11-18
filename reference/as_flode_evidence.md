# Make evidence from a plain table

Turns a `data.frame` or `data.table` into a
[FlodeEvidence](https://jonpayneea.github.io/reach.rate/reference/FlodeEvidence.md),
keeping every column it already has and filling the rest. Only `stage_m`
and `discharge_cms` are required. The fill is deliberately plain, and
the result says what it assumed in its `conversion_note`:

- `evidence_id` is generated as `G001`, `G002` and so on, in row order.

- `observation_time` is taken from `gauging_datetime` when that column
  exists, and is otherwise `NA`.

- A table from
  [`read_gaugings()`](https://jonpayneea.github.io/reach.rate/reference/read_gaugings.md)
  is recognised: its `station_id` becomes `site_id`, the file name
  becomes `source_name`, and a row whose stage or discharge could not be
  read becomes `included = FALSE` with its `read_issue` as the
  `exclusion_reason`. Nothing is dropped.

- `source_type` is `"gauging"`, `weight` is 1 and `source_row` is the
  row position. `included` is `TRUE` unless the stage or discharge is
  missing, in which case it is `FALSE` and `exclusion_reason` says why.

- The remaining text columns are `NA`, and `metadata` is empty for each
  row.

A table that is already a `FlodeEvidence` is returned as it is.

## Usage

``` r
as_flode_evidence(x)
```

## Arguments

- x:

  A `data.frame`, `data.table` or
  [FlodeEvidence](https://jonpayneea.github.io/reach.rate/reference/FlodeEvidence.md).

## Value

A
[FlodeEvidence](https://jonpayneea.github.io/reach.rate/reference/FlodeEvidence.md).

## See also

[`FlodeEvidence()`](https://jonpayneea.github.io/reach.rate/reference/FlodeEvidence.md),
[`evidence_source_types()`](https://jonpayneea.github.io/reach.rate/reference/evidence_source_types.md)

## Examples

``` r
plain <- data.frame(stage_m = c(0.5, 1.1, 1.8), discharge_cms = c(1.2, 5.1, 12.4))
evidence <- as_flode_evidence(plain)
evidence$evidence_id
#> [1] "G001" "G002" "G003"
evidence@conversion_note
#> [1] "Converted from a plain table; filled evidence_id, site_id, observation_time, source_type, source_name, source_version, quality_code, notes, exclusion_reason, included, weight, source_row, metadata. source_type assumed 'gauging', weight assumed 1, included TRUE unless stage or discharge is missing."
```
