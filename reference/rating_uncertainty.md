# A rating's uncertainty, source by source

A rating's uncertainty has several sources, and they behave differently.
`rating_uncertainty()` reports each on its own and the combination, so a
reviewer can see what a band is made of:

- **Sampling.** The rating would differ with a different set of
  gaugings. Each draw resamples the gaugings used, with replacement, and
  refits with the rating's own settings and breakpoints. Random error in
  each gauging is part of this source already: it is the scatter of the
  gaugings about the curve, and resampling carries it into the band.

- **Gauging.** Error shared between gaugings: a current meter, a method
  or a team reading high or low for all of them. It leaves no scatter,
  so sampling cannot see it. Each draw moves the discharge of every
  gauging in a group by one shared factor, `exp(e)` with
  `e ~ Normal(0, u^2)`. With `group_by`, each group (a method, a meter)
  has its own draw; without, every gauging shares one.

- **Combined.** Each draw resamples, then applies the shared error, then
  refits. The two sources are taken as independent, and are never added.

- **Structure.** Another reasonable choice would give another curve: the
  other objective, a limb fewer (each breakpoint dropped), a breakpoint
  moved. Reported as a **range** (the lowest and highest curve, with the
  variant giving each), never as an interval: structure has no
  probability, only a spread of defensible choices.

**The package does not invent `u`.** It comes from the evidence's
optional `discharge_uncertainty` column (a fraction per gauging; a
group's value is the median of its gaugings') or, failing that, from
`gauging_uncertainty`. With neither, the gauging and combined sources
are reported as not assessed, with the reason. They are never reported
as zero.

With one group and no magnitude protection set in discharge, a shared
factor `k` on every discharge scales the fitted `C` by exactly `k` and
leaves `a` and `n` as they were, under either objective, so the gauging
draws need no refit: the curve is multiplied by `k`. With groups, or
with `protect_above`, every draw is refitted.

The method, its failure behaviour and its limitations are set out in
`design/E2_separated_uncertainty.md`.

## Usage

``` r
rating_uncertainty(
  rating,
  stage = NULL,
  n_draws = 500,
  gauging_uncertainty = NULL,
  group_by = NULL,
  sources = c("sampling", "gauging", "structure"),
  level = 0.95,
  seed = NULL
)
```

## Arguments

- rating:

  A
  [FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md)
  or
  [FlodeSegmentedRating](https://jonpayneea.github.io/reach.rate/reference/FlodeSegmentedRating.md)
  fitted from evidence. A
  [FlodeRatingTable](https://jonpayneea.github.io/reach.rate/reference/FlodeRatingTable.md)
  holds no evidence to resample and is refused.

- stage:

  Stages to report at, metres. Default: 50 stages over the gauged range.

- n_draws:

  Draws per resampling source, 100 or more. Default 500.

- gauging_uncertainty:

  One fraction for all gaugings, such as `0.05`, in `(0, 0.5]`, used
  where the evidence has no `discharge_uncertainty`.

- group_by:

  Optional: the name of an evidence column (such as the method or the
  meter). Gaugings sharing a value share an error; groups are
  independent.

- sources:

  Which of `"sampling"`, `"gauging"` and `"structure"` to assess.
  `"combined"` is reported whenever sampling and gauging both are.

- level:

  Width of the intervals. Default 0.95.

- seed:

  Integer or `NULL`, recorded.

## Value

A
[FlodeUncertainty](https://jonpayneea.github.io/reach.rate/reference/FlodeUncertainty.md).

## See also

[FlodeUncertainty](https://jonpayneea.github.io/reach.rate/reference/FlodeUncertainty.md),
[`uncertainty_bands()`](https://jonpayneea.github.io/reach.rate/reference/uncertainty_bands.md),
[`rating_sensitivity()`](https://jonpayneea.github.io/reach.rate/reference/rating_sensitivity.md)

## Examples

``` r
set.seed(1)
stage_m <- sort(runif(25, 0.3, 3))
gaugings <- data.frame(stage_m = stage_m,
                       discharge_cms = 3 * (stage_m - 0.1)^1.6 * exp(rnorm(25, sd = 0.05)))
fit <- fit_rating(gaugings, quiet = TRUE)
u <- rating_uncertainty(fit, n_draws = 100, gauging_uncertainty = 0.03, seed = 1)
u
#> <FlodeUncertainty> 95% intervals, 100 draws per resampling source
#>   sampling:  -10.4% to +10.3% of the rating, widest, over the gauged range
#>   gauging:   -5.6% to +6.1% of the rating, widest, over the gauged range
#>   combined:  -9.5% to +8.7% of the rating, widest, over the gauged range
#>   structure: range -1.1% to +12.7% of the rating over the gauged range (1 variant(s); a range, not an interval)
#>   Not a complete budget: stage error is not modelled.
head(uncertainty_bands(u))
#>      stage_m   source     lower    median     upper   min   max variant_min
#>        <num>   <char>     <num>     <num>     <num> <num> <num>      <char>
#> 1: 0.4668229 sampling 0.5314107 0.5929582 0.6541052    NA    NA        <NA>
#> 2: 0.5180744 sampling 0.6740852 0.7309682 0.7855390    NA    NA        <NA>
#> 3: 0.5693259 sampling 0.8283169 0.8791232 0.9255101    NA    NA        <NA>
#> 4: 0.6205774 sampling 0.9934217 1.0378893 1.0751641    NA    NA        <NA>
#> 5: 0.6718289 sampling 1.1688305 1.2066763 1.2342911    NA    NA        <NA>
#> 6: 0.7230804 sampling 1.3533050 1.3857336 1.4108617    NA    NA        <NA>
#>    variant_max rating_cms  support
#>         <char>      <num>   <char>
#> 1:        <NA>  0.5927700 observed
#> 2:        <NA>  0.7315178 observed
#> 3:        <NA>  0.8810935 observed
#> 4:        <NA>  1.0410247 observed
#> 5:        <NA>  1.2109053 observed
#> 6:        <NA>  1.3903814 observed
```
