# The Mathematical Contract: What reach.rate Computes, Exactly

This is the document to check a rating against. It states every equation
the package fits and applies, the units, the rules for awkward values,
how a fit is chosen, what “converged” means, and what each interval does
and does not cover. Where the package does something a reader might not
expect, this says so plainly, in a section called what the package does
not do.

Each statement here is held by a test in
`tests/testthat/test-contract.R`, which fails if the code and this
document disagree.

## The equation

A rating limb is

\\Q = C\\(H - a)^{n}, \qquad H \> a,\\

and zero for \\H \le a\\.

| symbol | meaning                        | unit          |
|--------|--------------------------------|---------------|
| \\Q\\  | discharge                      | m\\^3\\/s     |
| \\H\\  | stage                          | m             |
| \\a\\  | the stage at which flow ceases | m             |
| \\n\\  | the exponent                   | none          |
| \\C\\  | the coefficient                | m\\^{3-n}\\/s |

\\C\\ carries units that depend on \\n\\, so a \\C\\ is only comparable
with another \\C\\ when the exponents are close.

The offset is **subtracted**: \\(H - a)\\. Some systems write \\(H +
a)\\, in which the same offset has the opposite sign. Using one system’s
value in the other’s equation moves the curve by twice the offset and
gives no error.
[`convert_offset_convention()`](https://jonpayneea.github.io/reach.rate/reference/convert_offset_convention.md)
changes the sign of `a` and nothing else, because \\C(H + a')^n = C(H -
a)^n\\ exactly when \\a' = -a\\. Converting there and back returns the
original values. It does not change a stage datum.

``` r

external <- data.frame(lower_level = 0.5, upper_level = 3, C = 4.1, a = -0.35, n = 1.6)
internal <- convert_offset_convention(external)   # from "add" to "subtract"
internal$a
#> [1] 0.35
# Both tables describe one curve:
external$C * (1.8 + external$a)^external$n
#> [1] 7.429724
internal$C * (1.8 - internal$a)^internal$n
#> [1] 7.429724
```

## Limbs

A rating is a set of limbs, each with its own \\C\\, \\a\\ and \\n\\ and
a stage range.
[`rate_optimise()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise.md)
fits each limb independently to the gaugings that fall in its range. It
does not impose continuity at a breakpoint, and
[`detect_rc_gaps()`](https://jonpayneea.github.io/reach.rate/reference/detect_rc_gaps.md)
and
[`align_limb_equations()`](https://jonpayneea.github.io/reach.rate/reference/align_limb_equations.md)
exist to find and close any gap.
[`rate_optimise_segmented()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise_segmented.md)
fits one joint model in which continuity is automatic (see the section
on the segmented model).

**Which limb a gauging belongs to.** When fitting, a gauging is assigned
to the limb whose range contains it, with the range closed on the
*upper* side: limb 1 is \\\[h_0, h_1\]\\ and later limbs are
\\(h\_{j-1}, h_j\]\\. A gauging exactly on a breakpoint is fitted into
the lower limb.

When applying a rating the rule is the other way round. A stage is
assigned by the half-open ranges \\\[h\_{j-1}, h_j)\\, with the last
limb closed, so a stage exactly on a breakpoint is applied with the
upper limb. For a continuous rating the discharge is the same either
way. For a rating with a gap at the breakpoint it is not, and the gap
check is what reveals it.

**Outside the range.** A stage below the first limb or above the last is
computed with the nearest limb and flagged `extrapolated`. The equation
is continued, not bounded.

## Applying a rating

For a stage \\H\\ in limb \\j\\,

\\Q = \begin{cases} C_j\\(H - a_j)^{n_j} & H \> a_j \\ 0 & H \le a_j
\end{cases}\\

A stage of `NA` gives `NA`. The inverse, from discharge to stage, is

\\H = a_j + (Q / C_j)^{1/n_j},\\

for \\Q \> 0\\, with the limb chosen by comparing \\Q\\ with the
discharge at each limb’s bounds. A discharge of zero, a negative
discharge or `NA` gives `NA` stage, because zero discharge corresponds
to every stage at or below \\a\\ and has no single answer. The inverse
is only defined where discharge rises across the limbs; it refuses a
rating where it does not.

## The two objectives

Each limb is fitted by minimising a weighted sum of squares over its
\\m\\ gaugings \\(H_i, Q_i)\\ with weights \\w_i\\ (all 1 unless age
weighting is on).

**Absolute** (`objective = "absolute"`, the default of
[`rate_optimise()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise.md)
and of the other fitters today):

\\\min\_{C,a,n}\\ \sum\_{i=1}^{m} w_i\\\big(Q_i - C\\(H_i -
a)^{n}\big)^2 .\\

**Relative** (`objective = "relative"`; the planned guided workflow will
make this its default):

\\\min\_{C,a,n}\\ \sum\_{i=1}^{m} w_i\\\big(\ln Q_i - \ln C -
n\\\ln(H_i - a)\big)^2 .\\

The relative objective is a fit in log space. It needs every \\Q_i \>
0\\ and every \\H_i \> a\\. For small relative errors it is close to
minimising \\\sum w_i\\\big((Q_i - \hat Q_i)/\hat Q_i\big)^2\\, which is
why it suits gaugings whose error scales with the reading.

The two give the same answer when the data lie exactly on a curve and
different answers otherwise. Neither is “right”. The choice is a
statement about how gauging error behaves, and the objectives vignette
([`vignette("objective_guide")`](https://jonpayneea.github.io/reach.rate/articles/objective_guide.md))
works through when they diverge.

**Diagnostics are always on the discharge scale**, whichever objective
was used: `rmse_cms`, `r_squared`, `rmse_pct` and the error columns are
recomputed from the fitted coefficients as \\Q_i - C(H_i - a)^n\\, so
the two objectives’ results can be compared directly. `rmse_cms` is the
unweighted root mean square, \\\sqrt{\tfrac1m \sum (Q_i - \hat
Q_i)^2}\\.

Here is the absolute objective for three gaugings, worked by hand and
then by the package’s own equation.

``` r

H <- c(1.5, 2.5, 3.5)
Q <- c(2.1, 5.5, 10.6)
C <- 2; a <- 0.5; n <- 1.5
modelled <- C * (H - a)^n
modelled
#> [1]  2.000000  5.656854 10.392305
residual <- Q - modelled
round(residual, 4)
#> [1]  0.1000 -0.1569  0.2077
sum(residual^2)                       # the absolute objective, weights 1
#> [1] 0.07774053
sum((log(Q) - log(C) - n * log(H - a))^2)   # the relative objective
#> [1] 0.003562787
```

## Weighting by age

Age weighting is opt-in. With `age_halflife` set, a gauging of age \\t\\
days has weight

\\w = w\_{\min} + (1 - w\_{\min})\\0.5^{\\t / t\_{1/2}},\\

where \\t\_{1/2}\\ is `age_halflife`, \\w\_{\min}\\ is `age_min_weight`
(default 0.1) and age is measured back from `reference_datetime`
(default: the most recent gauging in the data). Age is clamped at zero,
so a gauging dated after the reference has weight 1, not more. Weights
are not normalised.

The floor exists so that an old gauging is never weighted to nothing. It
is not magnitude-aware: an old extreme flood and an old ordinary gauging
decay identically.

``` r

age_days <- c(0, 365, 730, 3650)
0.1 + 0.9 * 0.5^(age_days / 365)      # half-life one year, floor 0.1
#> [1] 1.0000000 0.5500000 0.3250000 0.1008789
```

Without `age_halflife` every weight is 1 and a supplied
`gauging_datetime` changes nothing about the fit.

## Zero and negative values

| input | absolute objective | relative objective |
|----|----|----|
| negative discharge | refused | refused |
| zero discharge | accepted | refused (log of zero) |
| `NA`, `NaN`, infinite stage or discharge | refused | refused |
| negative stage | accepted (stage is relative to a datum) | accepted |
| stage with no spread | refused | refused |

A limb needs at least 3 gaugings, because it has three parameters. The
check that returns advice and not an error,
[`validate_gaugings()`](https://jonpayneea.github.io/reach.rate/reference/validate_gaugings.md),
warns about zero discharge and treats a negative discharge as a
technical failure.

## Bounds on the parameters

For each limb the three parameters are box-constrained:

\\C \ge 10^{-6}, \qquad a \le h\_{\min} - 10^{-6}, \qquad n \ge
10^{-6},\\

where \\h\_{\min}\\ is the lowest stage among that limb’s gaugings. The
bound on \\a\\ keeps every gauging above the zero-flow stage, so
\\(H_i - a) \> 0\\ for all of them. `n_bounds = c(lower, upper)`
replaces the bounds on \\n\\, and `lower == upper` fixes it. A limb is
flagged `near_bound` when \\n\\ is within 0.01 of either bound, or \\a\\
is within 1% of the limb’s stage width of its upper bound.

A fit that sits on a bound is a fit the data did not decide. The flag
exists so that this is visible.

## Starting values and the multi-start rule

With `multi_start = TRUE` (the default) each limb is fitted from six
starting points, then the best valid result is kept. With \\a_0 = 0\\
unless the upper bound of \\a\\ is negative, in which case \$a_0 = \$
that bound \\- 0.01\\, the starts are:

1.  \\C = 1,\\ a = a_0,\\ n = 1\\
2.  \\C = 1,\\ a = a_0,\\ n = 1.5\\
3.  \\C = 1,\\ a = a_0,\\ n = 2\\
4.  \\C = \operatorname{median}(Q)/(\operatorname{median}(H) -
    a_0)^{1.5},\\ a = a_0,\\ n = 1.5\\
5.  \\C = 1,\\ a = a_0 - 0.25\\(h\_{\max} - h\_{\min}),\\ n = 1\\
6.  a log-log estimate: regress \\\ln Q\\ on \\\ln(H - h\_{\min} +
    0.1)\\ for the exponent and coefficient, with \\a = h\_{\min} -
    0.1\\, the coefficient floored at 0.01 and the exponent at 0.1. This
    is omitted if the regression fails.

Each start is clipped into the bounds. An attempt is **valid** if the
fitted equation is finite and does not decrease across a grid of 20
stages spanning the limb (30 across the range for the segmented model);
a decrease of more than \\10^{-9}\\ fails. Among the valid attempts the
one with the smallest **weighted sum of squares on the objective’s own
scale** is kept, whether or not the optimiser reported convergence (see
the next section): the weighted absolute sum for the absolute objective,
the weighted log-scale sum for the relative one. If no attempt is valid
the fit stops with an error. Every attempt, selected or not, is recorded
in `@fit_starts`.

This ranks attempts on the quantity each one minimised. Earlier versions
ranked them on the unweighted sum of squares even when age weights were
used, which chose between local optima by a criterion nobody had
optimised. The two agree when there are no weights.

## Convergence and identifiability

Each fit is a Levenberg-Marquardt least-squares fit
([`minpack.lm::nlsLM`](https://rdrr.io/pkg/minpack.lm/man/nlsLM.html))
with at most 100 iterations (300 for the segmented model) and the
optimiser’s default tolerances. It stops when the relative change in the
sum of squares, or in the parameters, falls below \\\sqrt{\epsilon}
\approx 1.5 \times 10^{-8}\\, with \\\epsilon\\ the machine epsilon. The
optimiser’s default limit of 400 function calls would stop a fit at
about 94 iterations, before the iteration limit, so the call limit is
raised to twenty times the iteration limit and the documented limit is
the one in force.

Every limb of a fit records what happened, in stable columns of `@limbs`
(and of `@coefficients` for the segmented model). Where the optimiser
does not supply a value the column is `NA`, meaning not assessed, never
a guess.

| column | meaning |
|----|----|
| `converged` | the optimiser reports convergence (stop codes 1 to 4) |
| `convergence_code`, `convergence_message` | its own stop code and message; `-1` is the iteration limit |
| `iterations` | iterations used by the fit that was kept |
| `objective_value` | the weighted objective of Section “The two objectives”, at the kept fit |
| `bound_hits` | parameters on a bound: `C_lower`, `a_upper`, `n_lower`, `n_upper`, comma separated; `""` for none |
| `multi_start_spread` | how far near-optimal starts disagree in discharge (see below) |
| `parameter_correlation` | the largest absolute correlation between two parameter estimates |
| `condition_number` | the condition number of the Jacobian with columns scaled to unit length |

In `@fit_starts`, an attempt has `converged` (the optimiser’s own
report) and `valid` (the domain and monotonicity check above) as
separate columns, together with its stop code, message and iteration
count.

**Converged does not mean good, and unconverged does not mean bad.**
Among the valid attempts the package keeps the one with the lowest
objective, whether or not it converged. A flat valley in the objective
lets the optimiser creep for the whole iteration limit while the fit is
already practically optimal, and a converged attempt can sit on a bound
with a much worse objective. Ranking on convergence would sometimes
choose the worse fit. So the choice is made on the objective, and the
report says whether the kept attempt converged. When it did not,
[`rate_optimise()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise.md)
and
[`rate_optimise_segmented()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise_segmented.md)
warn, and say how the optimiser stopped.

`multi_start_spread` makes the difference visible. It is the largest
difference in fitted discharge, across the limb, between the chosen
solution and any other valid attempt whose objective is within 5% of it,
as a fraction of the limb’s peak discharge. It is 0 when no other
attempt is that close and `NA` when fewer than two attempts were valid
or only one start was used. A large value means two almost equally good
fits predict different discharges: the data do not choose between them.
A small value alongside wandering parameters means the opposite: the
curve is well determined though its coefficients are not.

`parameter_correlation` near 1, or a `condition_number` in the
thousands, says two parameters trade off against each other. Neither is
a verdict; they say where to look first.

## Checks on the equations, and when a rating is refused

After a fit,
[`rating_invariants()`](https://jonpayneea.github.io/reach.rate/reference/rating_invariants.md)
checks the rating’s own equations, without reference to its gaugings,
and returns a `FlodeAssessment`. It answers whether the equations are
mathematically usable. It does not say whether the rating is a good one.

A **technical** check can fail:

- every \\C\\, \\a\\ and \\n\\ is finite, and \\C\\ and \\n\\ are
  positive;
- limb stage ranges are finite, ascending and contiguous;
- discharge is finite and not negative at 25 stages in each limb;
- discharge does not decrease as stage rises within a limb;
- the discharge at the top of each limb is no lower than at the top of
  the limb before, so each discharge belongs to one limb;
- discharge to stage and back reproduces the discharge to within
  \\10^{-6}\\ (relative);
- where bootstrap draws exist, each parameter’s lower, median and upper
  bounds are in order;
- for a fit made directly by the optimiser, each parameter is inside the
  bounds it was given.

A **hydrometric** check can only warn: no gap or overlap between
adjacent limbs’ stage ranges, discharge continuous across each junction
(within 1% by default), and each limb’s zero-flow stage at or below its
lower stage. That last one is a warning because discharge is zero at and
below \\a\\, so a limb that starts below it is a legitimate way to write
a table, but part of the limb then carries no flow.

**A failure stops the operation it makes meaningless.**
[`apply_rating()`](https://jonpayneea.github.io/reach.rate/reference/apply_rating.md)
refuses a rating that fails any technical check except the two that
concern the inverse, and says which check failed.
[`apply_rating_inverse()`](https://jonpayneea.github.io/reach.rate/reference/apply_rating_inverse.md)
refuses any failure. A drop in discharge at the top of a limb, for
example, leaves stage to discharge well defined, so forward application
proceeds, but makes the inverse ambiguous, so the inverse is refused. A
warning never blocks.

The checks are evaluated when asked for, not stored on the object, so
they always describe the rating as it now stands, including after a
change to it. The same two facts are on the printed rating, as separate
lines, because a fit can converge to an invalid equation and a valid
equation can come from a fit that did not converge:

``` r

set.seed(7)
h <- seq(0.4, 3, by = 0.05)
q <- 3.2 * h^1.6 * exp(rnorm(length(h), sd = 0.03))
print(rate_optimise(q, h, control = 1.5))
#> <FlodeRating> 2 limb(s), origin: independently_fitted, lifecycle: draft
#>   converged: yes (2 of 2 limbs)
#>   valid: yes, with 1 warning (limb_continuity)
#> 
#>     limb lower_stage_m upper_stage_m        C           a        n   rmse_cms
#>    <int>         <num>         <num>    <num>       <num>    <num>      <num>
#> 1:     1           0.4           1.5 3.452241  0.03394668 1.552369 0.09401666
#> 2:     2           1.5           3.0 1.942301 -0.35539746 1.872624 0.26140031
#>    r_squared
#>        <num>
#> 1: 0.9968900
#> 2: 0.9949382
```

## What the intervals mean

**Asymptotic standard errors** (`C_se_asymp`, `a_se_asymp`,
`n_se_asymp`) are the square roots of the diagonal of the fit’s
estimated covariance matrix under the usual linearised least-squares
theory. They are always computed, and are `NA` when that matrix is
singular. They assume the model is correct, errors are independent with
constant variance on the fitted scale, and the sample is large enough
for the linear approximation to hold. A limb with few gaugings, or whose
parameters sit on a bound, does not meet that.

**Bootstrap draws** (`n_boot > 0`). Within each limb, gaugings are
resampled with replacement, and the limb is refitted to the resample
with the same objective, weights and bounds, starting from the original
fitted values. A resample with fewer than 3 distinct stages or no stage
spread is rejected. A refit that errors is recorded as a failed draw
with its reason. Standard errors are the standard deviation of the
successful draws, and the 2.5%, 50% and 97.5% points are their
percentiles. A warning is issued when the successful fraction falls
below `min_boot_success` (default 0.8).

Limb boundaries are held fixed across draws. A draw is not checked for
the validity conditions that select the main fit, and because each
starts from the fitted values, draws tend to stay near the selected
solution and may understate how far another solution is.

**[`apply_rating_interval()`](https://jonpayneea.github.io/reach.rate/reference/apply_rating_interval.md)**
applies every successful bootstrap draw to a stage, using that draw’s
coefficients and the original limb boundaries, and reports for each
stage the mean, the median, a geometric standard error and the lower and
upper percentiles at `conf_level`.

``` r

set.seed(3)
stage_m <- seq(0.5, 3, length.out = 25)
discharge_cms <- 3 * (stage_m - 0.2)^1.6 * exp(rnorm(25, sd = 0.04))
fit <- rate_optimise(discharge_cms, stage_m, n_boot = 100, boot_seed = 1)
draws <- rating_bootstrap(fit)
at <- data.frame(stage = 2)
by_package <- apply_rating_interval(at, draws)
by_hand <- draws$C * (2 - draws$a)^draws$n
c(package = by_package$discharge_lower, by_hand = quantile(by_hand, 0.025, names = FALSE))
#>  package  by_hand 
#> 7.520575 7.520575
```

What this interval covers is **uncertainty in the fitted coefficients
that comes from the finite set of gaugings**. It does not cover:

- error in the stage measurement, or in the gaugings’ own discharge
  beyond what shows up as scatter;
- a shift in the rating over time;
- the choice of equation form, or of where the breakpoints are;
- the spread of a *new* gauging around the curve. It is an interval for
  the rating’s discharge at that stage, not a prediction interval for
  the next gauging.

Treat it as the width the data support, which is a lower bound on the
width a user should plan for.

## The segmented model

[`rate_optimise_segmented()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise_segmented.md)
fits one joint equation over the whole range, adapted from Hodson et
al. (2024):

\\Q = C\\\max(H - b_1,\\0)^{n_1}\\ \prod\_{j \ge 2} \big(\max(H -
b_j,\\0) + 1\big)^{n_j}.\\

\\b_1\\ is the stage of zero flow. Each later factor is exactly 1 at and
below its own breakpoint \\b_j\\, so continuity is automatic. Above
\\b_j\\ the local exponent of the curve changes. It is fitted by the
same least squares and objectives as above, not by the full Bayesian
inference of the original paper, so there are no priors and no
posterior. The interior breakpoints are held at `control` unless
`estimate_breakpoints = TRUE`, in which case the loss surface is not
convex and results can depend on the start. Multi-start selection and
the weighting are as for
[`rate_optimise()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise.md).

## What the package does not do

These are the places where the package is narrower than a reader might
assume. They are collected here so none is found by surprise.

- Limbs from
  [`rate_optimise()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise.md)
  are not forced to meet. A gap or overlap at a breakpoint is reported
  by the gap tools, not prevented.
- A gauging on a breakpoint is fitted with the lower limb and applied
  with the upper one.
- A fit that did not converge is still returned, with a warning and
  `converged = FALSE`, when it has the lowest objective. It is not an
  error.
- Bootstrap draws start from the fitted solution and are not validity
  checked.
- No interval includes stage error, rating shift or equation-form error.
- The offset convention is the only one handled. A stage datum shift is
  not.
- Breakpoints are supplied or suggested, not estimated, except in the
  segmented model with `estimate_breakpoints = TRUE`.

## Checking this against the package

The equations printed in a fit’s provenance are the ones in this
document.

``` r

absolute <- rate_optimise(discharge_cms, stage_m)
relative <- rate_optimise(discharge_cms, stage_m, objective = "relative")
rating_provenance(absolute)$fitting_equation
#> [1] "Q = C(H - a)^n"
rating_provenance(relative)$fitting_equation
#> [1] "log(Q) = log(C) + n*log(H - a)"
```

And the fitted coefficients minimise the objective written above. At a
minimum the objective cannot be reduced by moving any coefficient, so
every small step away gives a larger value.

``` r

limb <- rating_limbs(absolute)
objective <- function(par) sum((discharge_cms - par[1] * (stage_m - par[2])^par[3])^2)
here <- c(limb$C, limb$a, limb$n)
steps <- c(1e-3, 1e-3, 1e-3)
worse <- vapply(1:3, function(k) {
  up <- here; up[k] <- up[k] + steps[k]
  down <- here; down[k] <- down[k] - steps[k]
  min(objective(up), objective(down)) > objective(here)
}, logical(1))
worse
#> [1] TRUE TRUE TRUE
```
