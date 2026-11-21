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

- support:

  What each stage range rests on, old against new: how far the observed,
  fitted and numerical ranges moved, and how many observations lie in
  each. This answers "is the new rating better supported, or only
  different?"

- evidence:

  Only when both inputs are fits. The observations behind each, matched
  by `evidence_id` and checked against their values.

## Usage

``` r
compare_ratings(rating_old_dt, rating_new_dt, step = 0.01)
```

## Arguments

- rating_old_dt, rating_new_dt:

  A
  [FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md),
  a
  [FlodeRatingTable](https://jonpayneea.github.io/reach.rate/reference/FlodeRatingTable.md),
  or a plain data.frame/data.table with columns `lower_level`,
  `upper_level`, `C`, `a`, `n` – one row per limb. Need not have the
  same number of limbs. Pass fits, not tables, to compare their evidence
  as well. A
  [FlodeSegmentedRating](https://jonpayneea.github.io/reach.rate/reference/FlodeSegmentedRating.md)
  is not accepted: its joint equation has no per-limb coefficients to
  compare.

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

- support:

  A `data.table`, one row per stage range (`observed`, `modelled`,
  `fitted`, `operational`, `numerical`): `lower_stage_m_old`,
  `lower_stage_m_new`, `upper_stage_m_old`, `upper_stage_m_new`,
  `lower_moved_m`, `upper_moved_m` (new minus old; `NA` where either
  side is missing or has no practical limit), and `n_evidence_old`,
  `n_evidence_new`.

- evidence:

  `NULL` unless both inputs are fits. Otherwise a list with `summary`, a
  one-row `data.table` (`n_old`, `n_new`, `n_shared`, `n_changed`,
  `n_added`, `n_removed`, the gauged stage range of each and the latest
  observation of each), and `rows`, one row per observation in either,
  with `change` one of `"shared"`, `"changed"` (same id, different stage
  or discharge), `"added"` or `"removed"`. Ids made by converting a
  plain table are positional, so two different datasets can share ids:
  such rows show as `"changed"`, not `"shared"`.

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
cmp$support
#>          range lower_stage_m_old lower_stage_m_new upper_stage_m_old
#>         <char>             <num>             <num>             <num>
#> 1:    observed                NA                NA                NA
#> 2:    modelled                NA                NA                NA
#> 3:      fitted                 0                 0      3.000000e+00
#> 4: operational                NA                NA                NA
#> 5:   numerical              -Inf              -Inf     9.243622e+180
#>    upper_stage_m_new lower_moved_m upper_moved_m n_evidence_old n_evidence_new
#>                <num>         <num>         <num>          <int>          <int>
#> 1:                NA            NA            NA              0              0
#> 2:                NA            NA            NA              0              0
#> 3:      3.000000e+00             0             0             NA             NA
#> 4:                NA            NA            NA             NA             NA
#> 5:     9.378866e+180            NA            NA             NA             NA

# With fits, the evidence is compared too.
set.seed(1)
stage <- seq(0.3, 3, length.out = 25)
g <- data.frame(stage_m = stage, discharge_cms = 3 * stage^1.6 * exp(rnorm(25, sd = 0.03)))
old_fit <- fit_rating(g[1:20, ], quiet = TRUE)
new_fit <- fit_rating(g, quiet = TRUE)
cmp2 <- compare_ratings(old_fit, new_fit)
cmp2$evidence$summary
#>    n_old n_new n_shared n_changed n_added n_removed gauged_min_old_m
#>    <int> <int>    <int>     <int>   <int>     <int>            <num>
#> 1:    20    25       20         0       5         0              0.3
#>    gauged_max_old_m gauged_min_new_m gauged_max_new_m latest_old latest_new
#>               <num>            <num>            <num>     <POSc>     <POSc>
#> 1:           2.4375              0.3                3       <NA>       <NA>
```
