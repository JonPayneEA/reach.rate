# Run the fit -\> flag -\> expand -\> detect -\> resolve -\> plot pipeline

A worked example showing `rate_optimise` and `gap_check` operating as a
single pipeline: gaugings go in, a fitted multi-limb rating comes out,
limbs that extrapolate beyond their own gaugings are flagged doubtful,
the fit is bridged to a rating table and expanded to stage-discharge
rows, junction gaps between independently-fitted limbs are detected and
resolved, and both stages are plotted.

## Usage

``` r
run_demo(plot = TRUE)
```

## Arguments

- plot:

  Logical. Draw
  [`rating_plot()`](https://jonpayneea.github.io/reach.rate/reference/rating_plot.md)
  and
  [`plot_rc_gaps()`](https://jonpayneea.github.io/reach.rate/reference/plot_rc_gaps.md)
  as a side effect. Default `TRUE`.

## Value

A list with elements `fit` (the
[FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md)
instance, with `doubtful` flagged in `@limbs`), `gaps` (the junction gap
report), `rc_raw` (the expanded table before resolution), and `rc_fixed`
(after resolution).

## Examples

``` r
result <- run_demo(plot = FALSE)
#> INFO [2026-09-02 07:43:52] Checked 2 junction(s): 2 gap(s) flagged.
#> INFO [2026-09-02 07:43:52] Checked 2 junction(s): 2 gap(s) flagged.
#> INFO [2026-09-02 07:43:52] Junction 1 (limbs 1/2, stage 1.6): gap 5.73 -> 11.56 | agreed Q = 8.6452
#> INFO [2026-09-02 07:43:52] Junction 2 (limbs 2/3, stage 2.2): gap 19.7 -> 34.74 | agreed Q = 27.2196
result$gaps
#>    junction limb_lower limb_upper stage_break stage_lower_end stage_upper_start
#>       <int>     <char>     <char>       <num>           <num>             <num>
#> 1:        1          1          2         1.6             1.6               1.6
#> 2:        2          2          3         2.2             2.2               2.2
#>    junction_type q_lower_end q_upper_start   gap_abs   gap_rel gap_flagged
#>           <char>       <num>         <num>     <num>     <num>      <lgcl>
#> 1:  shared_stage    5.733855      11.55655  5.822696 1.0154940        TRUE
#> 2:  shared_stage   19.703773      34.73535 15.031579 0.7628782        TRUE
```
