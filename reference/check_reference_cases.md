# Run the reference cases

Fits each case with
[`fit_rating()`](https://jonpayneea.github.io/reach.rate/reference/fit_rating.md),
assesses it with
[`assess_rating()`](https://jonpayneea.github.io/reach.rate/reference/assess_rating.md),
and judges it against the known truth. Use it to check that an
installation behaves as the package's own tests say it should, for
example on a machine the package is about to be used on. It takes a few
seconds.

For each case it reports the largest relative error of the fitted curve
against the truth over the case's range, whether that is inside the
envelope, whether the optimiser converged and the rating is valid, any
parameters the case checks, whether the assessment raised the designed
check, and, for the channel-shift case, whether the flat fit is clearly
worse than the weighted one.

## Usage

``` r
check_reference_cases(ids = NULL)
```

## Arguments

- ids:

  Which cases to run: a character vector of `reference_cases()$id`, or
  `NULL` (default) for all ten.

## Value

A `data.table`, one row per case: `id`, `title`, `max_rel_error`,
`envelope`, `within_envelope`, `converged`, `valid`, `parameters_ok`,
`designed_check`, `check_raised`, `contrast_ok` and `passed`.

## See also

[`reference_cases()`](https://jonpayneea.github.io/reach.rate/reference/reference_cases.md),
[`reference_case()`](https://jonpayneea.github.io/reach.rate/reference/reference_case.md).

## Examples

``` r
res <- check_reference_cases(c("single_limb", "few_gaugings"))
res[, c("id", "max_rel_error", "envelope", "passed")]
#>              id max_rel_error envelope passed
#>          <char>         <num>    <num> <lgcl>
#> 1:  single_limb   0.007402939     0.03   TRUE
#> 2: few_gaugings   0.036921850     0.12   TRUE
```
