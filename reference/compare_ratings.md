# Compare two rating equation tables

Diffs two rating tables (e.g. before/after a limb-alignment or a gauging
review) two ways:

- coefficients:

  A limb-by-limb comparison of `C`/`a`/`n`, produced only when both
  tables have the same number of limbs in the same order.

- discharge:

  The actual discharge difference across a common stage sequence,
  computed by running both tables through
  [`apply_rating()`](https://jonpayneea.github.io/reach.rate/reference/apply_rating.md).
  This is the more useful comparison when limb counts differ, or when
  the question is "how much does this amendment actually change the
  flow", not just "how much did the coefficients move".

## Usage

``` r
compare_ratings(rating_old_dt, rating_new_dt, step = 0.01)
```

## Arguments

- rating_old_dt, rating_new_dt:

  A
  [FlodeRatingTable](https://jonpayneea.github.io/reach.rate/reference/FlodeRatingTable.md),
  or a plain data.frame/data.table with columns `lower_level`,
  `upper_level`, `C`, `a`, `n` – one row per limb. Need not have the
  same number of limbs.

- step:

  Numeric. Stage increment for the discharge comparison. Default `0.01`.

## Value

A list with elements:

- coefficients:

  A `data.table` comparing limb-by-limb C/a/n, or `NULL` if the limb
  counts differ.

- discharge:

  A `data.table` with `stage`, `discharge_old`, `discharge_new`,
  `discharge_diff`, `discharge_pct_diff`, and the `extrapolated` flag
  from each table, across the overlapping stage range of both ratings.

## See also

[`apply_rating()`](https://jonpayneea.github.io/reach.rate/reference/apply_rating.md),
[`plot_rating_comparison()`](https://jonpayneea.github.io/reach.rate/reference/plot_rating_comparison.md)

## Examples

``` r
rating_old_dt <- data.table::data.table(
  lower_level = c(0.0, 1.2), upper_level = c(1.2, 3.0),
  C = c(2.5, 4.1), a = c(0, 0), n = c(1.5, 1.7)
)
rating_new_dt <- data.table::data.table(
  lower_level = c(0.0, 1.2), upper_level = c(1.2, 3.0),
  C = c(2.6, 4.0), a = c(0, 0), n = c(1.5, 1.7)
)
cmp <- compare_ratings(rating_old_dt, rating_new_dt)
cmp$coefficients
#>     limb lower_level upper_level C_old C_new a_old a_new n_old n_new C_diff
#>    <int>       <num>       <num> <num> <num> <num> <num> <num> <num>  <num>
#> 1:     1         0.0         1.2   2.5   2.6     0     0   1.5   1.5    0.1
#> 2:     2         1.2         3.0   4.1   4.0     0     0   1.7   1.7   -0.1
#>    a_diff n_diff
#>     <num>  <num>
#> 1:      0      0
#> 2:      0      0
cmp$discharge
#>      stage discharge_old extrapolated_old discharge_new extrapolated_new
#>      <num>         <num>           <lgcl>         <num>           <lgcl>
#>   1:  0.00   0.000000000            FALSE   0.000000000            FALSE
#>   2:  0.01   0.002500000            FALSE   0.002600000            FALSE
#>   3:  0.02   0.007071068            FALSE   0.007353911            FALSE
#>   4:  0.03   0.012990381            FALSE   0.013509996            FALSE
#>   5:  0.04   0.020000000            FALSE   0.020800000            FALSE
#>  ---                                                                    
#> 297:  2.96  25.940584979            FALSE  25.307887785            FALSE
#> 298:  2.97  26.089744172            FALSE  25.453408948            FALSE
#> 299:  2.98  26.239255333            FALSE  25.599273495            FALSE
#> 300:  2.99  26.389118108            FALSE  25.745481081            FALSE
#> 301:  3.00  26.539332144            FALSE  25.892031360            FALSE
#>      discharge_diff discharge_pct_diff
#>               <num>              <num>
#>   1:   0.0000000000                 NA
#>   2:   0.0001000000           4.000000
#>   3:   0.0002828427           4.000000
#>   4:   0.0005196152           4.000000
#>   5:   0.0008000000           4.000000
#>  ---                                  
#> 297:  -0.6326971946          -2.439024
#> 298:  -0.6363352237          -2.439024
#> 299:  -0.6399818374          -2.439024
#> 300:  -0.6436370270          -2.439024
#> 301:  -0.6473007840          -2.439024
```
