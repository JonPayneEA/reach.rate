# The overall status of an assessment

One word for the whole assessment: `"fail"` if any technical check
failed, otherwise `"warning"` if any hydrometric check warned, otherwise
`"pass"`. It is `"not_assessed"` only when no check could be run.
`"pass"` means every check that could be run passed; read
[`assessment_checks()`](https://jonpayneea.github.io/reach.rate/reference/assessment_checks.md)
for any that were `not_assessed`.

## Usage

``` r
assessment_status(x)
```

## Arguments

- x:

  A
  [FlodeAssessment](https://jonpayneea.github.io/reach.rate/reference/FlodeAssessment.md).

## Value

A single string.

## See also

[`assessment_checks()`](https://jonpayneea.github.io/reach.rate/reference/assessment_checks.md)

## Examples

``` r
assessment <- validate_gaugings(data.frame(
  stage_m = c(0.5, 0.9, 1.4, 2.0, 2.6, 3.1),
  discharge_cms = c(1.1, 3.0, 7.6, 16, 27, 40)
))
assessment_status(assessment)
#> [1] "warning"
```
