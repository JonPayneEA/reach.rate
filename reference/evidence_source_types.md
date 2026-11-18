# The controlled vocabulary for where evidence came from

The values `source_type` may take in a
[FlodeEvidence](https://jonpayneea.github.io/reach.rate/reference/FlodeEvidence.md)
table. Anything else is refused, so that a rating's evidence can be
grouped and filtered by origin without guessing at spellings.

## Usage

``` r
evidence_source_types()
```

## Value

A character vector.

## See also

[`FlodeEvidence()`](https://jonpayneea.github.io/reach.rate/reference/FlodeEvidence.md),
[`as_flode_evidence()`](https://jonpayneea.github.io/reach.rate/reference/as_flode_evidence.md)

## Examples

``` r
evidence_source_types()
#> [1] "gauging"            "operational_rating" "modelled"          
#> [4] "cross_section"      "structure_equation" "other"             
```
