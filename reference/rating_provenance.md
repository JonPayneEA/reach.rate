# How a rating was made

The settings and versions recorded when a fit was made: the equation,
the fitting method and objective, bounds on the exponent, whether
multi-start and bootstrap were used, any recency weighting, and the
package version. Use it to say exactly how a rating was produced.

## Usage

``` r
rating_provenance(x)
```

## Arguments

- x:

  A
  [FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md),
  [FlodeSegmentedRating](https://jonpayneea.github.io/reach.rate/reference/FlodeSegmentedRating.md)
  or
  [FlodeRatingTable](https://jonpayneea.github.io/reach.rate/reference/FlodeRatingTable.md).

## Value

A list. For a fit, its recorded provenance, a copy. A
[FlodeRatingTable](https://jonpayneea.github.io/reach.rate/reference/FlodeRatingTable.md)
was not fitted by this package, so it records only `status` and
`has_previous` (whether an earlier version is kept; see
[`rating_history()`](https://jonpayneea.github.io/reach.rate/reference/rating_history.md)).

## See also

[`rating_history()`](https://jonpayneea.github.io/reach.rate/reference/rating_history.md)

## Examples

``` r
set.seed(1)
stage_m <- seq(0.5, 2.5, by = 0.05)
discharge_cms <- 5 * stage_m^1.6 + rnorm(length(stage_m), sd = 0.02)
fit <- rate_optimise(discharge_cms, stage_m)
str(rating_provenance(fit)[c("fitting_equation", "objective", "tool_version")])
#> List of 3
#>  $ fitting_equation: chr "Q = C(H - a)^n"
#>  $ objective       : chr "absolute"
#>  $ tool_version    : chr "reach.rate 0.1.0"
```
