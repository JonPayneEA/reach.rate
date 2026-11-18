# Read the checks of an assessment

The check table of a
[FlodeAssessment](https://jonpayneea.github.io/reach.rate/reference/FlodeAssessment.md),
as a copy. See
[FlodeAssessment](https://jonpayneea.github.io/reach.rate/reference/FlodeAssessment.md)
for the columns.

## Usage

``` r
assessment_checks(x)
```

## Arguments

- x:

  A
  [FlodeAssessment](https://jonpayneea.github.io/reach.rate/reference/FlodeAssessment.md).

## Value

A data.table, one row per check.

## See also

[`assessment_status()`](https://jonpayneea.github.io/reach.rate/reference/assessment_status.md)

## Examples

``` r
assessment <- validate_gaugings(data.frame(
  stage_m = c(0.5, 0.9, 1.4, 2.0, 2.6, 3.1),
  discharge_cms = c(1.1, 3.0, 7.6, 16, 27, 40)
))
assessment_checks(assessment)[, .(check_id, domain, status)]
#>                      check_id      domain       status
#>                        <char>      <char>       <char>
#>  1:              stage_finite   technical         pass
#>  2:          discharge_finite   technical         pass
#>  3:    discharge_not_negative   technical         pass
#>  4:               enough_rows   technical         pass
#>  5:        evidence_id_unique   technical         pass
#>  6:               read_issues   technical not_assessed
#>  7:            zero_discharge hydrometric         pass
#>  8:        duplicate_gaugings hydrometric         pass
#>  9: stage_discharge_inversion hydrometric         pass
#> 10:                  outliers hydrometric not_assessed
#> 11:       stage_coverage_gaps hydrometric         pass
#> 12:       upper_range_support hydrometric      warning
#> 13:              few_gaugings hydrometric      warning
#> 14:         temporal_coverage hydrometric not_assessed
#> 15:             excluded_rows hydrometric         pass
#> 16:             times_assumed hydrometric not_assessed
```
