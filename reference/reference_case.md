# One reference case: its data and its truth

One reference case: its data and its truth

## Usage

``` r
reference_case(id)
```

## Arguments

- id:

  The case, one of `reference_cases()$id`.

## Value

A list: `id`, `title`, `purpose`, `not_tested`; `data`, a `data.frame`
of `stage_m` and `discharge_cms` (with an `observation_time` column
where the case needs one), identical on every call; `truth`, a function
from stage to the true discharge; `fit_args`, the extra arguments the
case is fitted with; `range`, the stage range it is judged over;
`envelope`, the largest relative error allowed there; and
`designed_check`.

## See also

[`reference_cases()`](https://jonpayneea.github.io/reach.rate/reference/reference_cases.md),
[`check_reference_cases()`](https://jonpayneea.github.io/reach.rate/reference/check_reference_cases.md).

## Examples

``` r
case <- reference_case("two_limbs")
fit <- do.call(fit_rating, c(list(case$data, quiet = TRUE), case$fit_args))
stage <- seq(case$range[1], case$range[2], length.out = 5)
round(apply_rating(fit, stage)$discharge / case$truth(stage), 3)
#> [1] 1.001 1.008 0.998 1.021 0.994
```
