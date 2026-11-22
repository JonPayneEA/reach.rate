# The reference cases

Ten synthetic stations, each with a rating that is **known**, so that a
fit can be judged against the truth, which real gaugings never allow.
Each case says what it tests and, as importantly, what it does not.

**These ten were written by the package's author.** They are not the ten
cases of any external brief, which was never supplied. They are a
starting point for a reviewer to extend, and passing them is necessary,
not sufficient: ten tidy synthetic stations say nothing about a real
one.

A case passes when the fitted curve stays inside a stated **envelope**
of the truth over its gauged range (a maximum relative error, not exact
coefficients), the fit converged and is valid, and the assessment raises
the one check the case was built to trigger. Run them with
[`check_reference_cases()`](https://jonpayneea.github.io/reach.rate/reference/check_reference_cases.md).

## Usage

``` r
reference_cases()
```

## Value

`reference_cases()`: a `data.table`, one row per case, with `id`,
`title`, `purpose`, `not_tested`, `envelope` and `designed_check` (the
assessment check the case should raise, `NA` where none).

## See also

[`reference_case()`](https://jonpayneea.github.io/reach.rate/reference/reference_case.md)
for one case's data and truth,
[`check_reference_cases()`](https://jonpayneea.github.io/reach.rate/reference/check_reference_cases.md)
to run them,
[`assess_rating()`](https://jonpayneea.github.io/reach.rate/reference/assess_rating.md).

## Examples

``` r
reference_cases()[, c("id", "title", "envelope")]
#>                   id                                  title envelope
#>               <char>                                 <char>    <num>
#>  1:      single_limb                   One limb, clean data     0.03
#>  2:        two_limbs   Two limbs with a real break at 1.6 m     0.10
#>  3:      heavy_noise                     Heavy scatter, 20%     0.35
#>  4:       sparse_top     Only two gaugings in the top fifth     0.06
#>  5:    isolated_high One isolated gauging 22% high at 3.4 m     0.08
#>  6:     rating_shift Channel shift, old and recent gaugings     0.10
#>  7: zero_flow_offset               Zero-flow stage at 0.8 m     0.03
#>  8:   steep_exponent              Steep control, exponent 3     0.03
#>  9:    wide_exponent            Wide control, exponent 1.05     0.06
#> 10:     few_gaugings                           Six gaugings     0.12
```
