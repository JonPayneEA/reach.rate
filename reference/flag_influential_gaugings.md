# Flag gaugings that disproportionately steer their limb's fit

[`plot_rating_residuals()`](https://jonpayneea.github.io/reach.rate/reference/plot_rating_residuals.md)
shows how far off each gauging ends up *after* fitting; this asks a
different question – how much each gauging *shaped* the fit to begin
with. A gauging can sit right on its own limb's curve (a small residual)
while still having pulled `C`/`a`/`n` a long way to get there, if
nothing else nearby held the curve in place – typically a single high or
low gauging isolated at the sparse end of a limb.

Leverage and Cook's distance are standard linear-regression diagnostics
(Cook 1977), adapted here to
[`rate_optimise()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise.md)'s
nonlinear fit by the usual local-linearisation trick (St. Laurent & Cook
1992): the model's Jacobian with respect to `C`/`a`/`n`, evaluated at
each gauging, stands in for a design matrix. Leverage measures how
extreme a gauging's position is, independent of fit quality; Cook's
distance combines that with its residual to estimate how much
`C`/`a`/`n` would shift if that one gauging were dropped and the limb
refit – without actually doing the refit.

A limb with `n_obs <= 3` (fewer gaugings than free parameters) has no
defined leverage – both columns are `NA` for its gaugings.

## Usage

``` r
flag_influential_gaugings(fit, cooks_mult = 4, leverage_mult = 2)
```

## Arguments

- fit:

  A
  [FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md)
  instance.

- cooks_mult, leverage_mult:

  Single positive numbers. A gauging is flagged `influential` if its
  Cook's distance exceeds `cooks_mult / n_obs` (limb-specific `n_obs`)
  or its leverage exceeds `leverage_mult * 3 / n_obs` – the standard
  rule-of-thumb cutoffs (Cook 1977; Belsley, Kuh & Welsch 1980),
  computed per limb since `n_obs` varies by limb. Defaults `4` and `2`
  respectively.

## Value

A new
[FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md)
instance with `@gaugings` columns added: `fitted_cms`, `residual_cms`,
`leverage`, `cooks_distance`, `influential`.

## References

Cook, R. D. (1977). Detection of influential observations in linear
regression. *Technometrics*, 19(1), 15-18. St. Laurent, R. T., & Cook,
R. D. (1992). Leverage and superleverage in nonlinear regression.
*Journal of the American Statistical Association*, 87(420), 985-990.
Belsley, D. A., Kuh, E., & Welsch, R. E. (1980). *Regression
Diagnostics*. Wiley.

## See also

[`plot_rating_residuals()`](https://jonpayneea.github.io/reach.rate/reference/plot_rating_residuals.md)
for the complementary after-the-fact view;
[`plot_rating_leverage()`](https://jonpayneea.github.io/reach.rate/reference/plot_rating_leverage.md)
to see this plotted;
[`vignette("leverage_influence_guide")`](https://jonpayneea.github.io/reach.rate/articles/leverage_influence_guide.md)
for a plain-English explanation with a worked example.

## Examples

``` r
set.seed(1)
stage_m <- seq(0.3, 3, by = 0.1)
discharge_cms <- 5 * stage_m^1.5 * exp(rnorm(length(stage_m), sd = 0.03))
# one isolated, high gauging at the sparse top end
stage_m <- c(stage_m, 3.5)
discharge_cms <- c(discharge_cms, 5 * 3.5^1.5 * 1.25)

fit <- rate_optimise(discharge_cms, stage_m, n_bounds = c(1.3, 1.7))
flagged <- flag_influential_gaugings(fit)
flagged@gaugings[order(-cooks_distance)][1:3]
#>    discharge_cms stage_m  limb fitted_cms residual_cms   leverage
#>            <num>   <num> <int>      <num>        <num>      <num>
#> 1:      40.92438     3.5     1   35.69908     5.225298 0.59697824
#> 2:      24.85935     3.0     1   27.63987    -2.780520 0.14927731
#> 3:      19.74745     2.6     1   21.81569    -2.068232 0.07708563
#>    cooks_distance influential
#>             <num>      <lgcl>
#> 1:     18.6986541        TRUE
#> 2:      0.2971369        TRUE
#> 3:      0.0721333       FALSE
```
