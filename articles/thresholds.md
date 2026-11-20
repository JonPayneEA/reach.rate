# Thresholds: What the Checks Flag, and Why

**Audience:** practitioner. You are reading the output of
[`validate_gaugings()`](https://jonpayneea.github.io/reach.rate/reference/validate_gaugings.md)
or
[`assess_rating()`](https://jonpayneea.github.io/reach.rate/reference/assess_rating.md)
and want to know where each limit came from, how firm it is, and how to
change it.

## Read this first

**There is no Environment Agency guidance for these limits.** Nobody has
published one for this package to follow, so none of the values below is
policy, a standard or a recommendation from the Agency. They are my best
endeavours: round numbers, set by judgement and by common statistical
practice, chosen so that the checks flag what an experienced
hydrometrician would want to look at, and not so much that every rating
is flagged.

Three things follow.

1.  A flag is a prompt to look, never a verdict. A warning does not say
    a rating is wrong, and a pass does not say it is right.
2.  The values are open to change, and every one is an argument. If your
    organisation, a standard or a reviewer sets a limit, use theirs and
    say so.
3.  If guidance appears, it replaces this page. The defaults in the
    package would then change once, with the source cited, and the page
    would be rewritten around it.

## What each limit rests on

Each limit has one of three kinds of basis. They carry different weight.

| Basis | What it means |
|----|----|
| **Arithmetic** | Follows from the equation. A different value would be wrong, not just different. |
| **Convention** | A widely used statistical rule of thumb. Reasonable people could pick another. |
| **Judgement** | A round number I chose. It marks where I would start to look. Nothing more. |

The tables below read the **default** from the functions themselves when
this page is built, so they cannot disagree with the code.

## Limits in `validate_gaugings()`

These look at the gaugings before any curve is fitted.

| Argument | Default | What it flags | Basis |
|:---|:---|:---|:---|
| `min_gaugings` | `10L` | Fewer usable gaugings than this. Fewer than 4 is a failure, not a warning, because one limb has three parameters. | Judgement (the floor of 4 is arithmetic) |
| `inversion_tolerance` | `0.2` | A gauging whose discharge is more than this fraction below that of a gauging at a lower stage. | Judgement |
| `outlier_mad` | `4` | A gauging this many robust standard deviations off the cubic through its neighbours in stage. | Convention (median absolute deviation rules of thumb run from 3 to 5) |
| `gap_fraction` | `0.25` | A gap between neighbouring stages wider than this fraction of the whole stage range. | Judgement |
| `upper_range_fraction` | `0.2` | The top fraction of the stage range, which should hold at least `upper_range_min` gaugings. | Judgement |
| `upper_range_min` | `3L` | The least number of gaugings wanted in that top fraction. | Judgement |
| `recent_years` | `10` | The latest gauging is older than this many years. | Judgement |

## Limits in `assess_rating()`

These look at a fitted rating. They also pass `...` to
[`validate_gaugings()`](https://jonpayneea.github.io/reach.rate/reference/validate_gaugings.md),
so everything above applies here too.

| Argument | Default | What it flags | Basis |
|:---|:---|:---|:---|
| `bias_tol` | `0.05` | A limb whose median relative residual is further from zero than this. The curve sits systematically high or low. | Judgement |
| `spread_tol` | `0.15` | A limb whose relative residual spread (interquartile range over 1.349, which estimates a standard deviation if the errors are roughly normal) exceeds this. | Judgement; the 1.349 is arithmetic |
| `trend_rho` | `0.6` | A rank correlation between residuals and stage larger than this, over at least 8 gaugings. The curve has the wrong shape. | Judgement (the 8 is also judgement) |
| `min_limb_gaugings` | `5L` | A limb with fewer gaugings than this. | Judgement |
| `n_range` | `c(1, 3.5)` | An exponent outside this range. Roughly from a wide channel control to a steep V-notch or compound section. | Judgement, informed by weir theory |
| `zero_flow_margin` | `1` | A zero-flow stage further below the lowest gauging than this multiple of the gauged range. | Judgement |
| `extrapolation_tol` | `0.2` | Operational limits that reach beyond the gauged range by more than this fraction of it. | Judgement |
| `cooks_warn` | `1` | A gauging whose Cook’s distance exceeds this. [`flag_influential_gaugings()`](https://jonpayneea.github.io/reach.rate/reference/flag_influential_gaugings.md) uses the lower, usual 4/n rule. | Convention |
| `continuity_tol` | `0.01` | A jump in discharge across a limb junction larger than this fraction. | Judgement |

## What I would not change without a reason

Some limits matter more than others.

- **`min_gaugings` and `min_limb_gaugings`.** These protect against
  fitting a curve to too little. Lowering them hides the most common
  real problem.
- **`n_range`.** It catches the case where the optimiser has found a
  number that fits the points and means nothing hydraulically. Widen it
  only if you know the control.
- **`cooks_warn`.** At 1 it flags only gaugings that move the fit a
  great deal. The 4/n rule in
  [`flag_influential_gaugings()`](https://jonpayneea.github.io/reach.rate/reference/flag_influential_gaugings.md)
  is the one to use for a first look.

The others can move with little harm. A tighter `bias_tol` makes more
ratings warn. It does not make any of them worse.

## Changing a limit

Every limit is an argument. Pass your own and the result is computed
against it. This example uses the file from
[`vignette("start_here")`](https://jonpayneea.github.io/reach.rate/articles/start_here.md).

``` r

path <- system.file("extdata", "example_gaugings.csv", package = "reach.rate")
fit <- fit_rating(read_gaugings(path), quiet = TRUE)
#> read_gaugings(): 43 rows, 1 stations, date format %d/%m/%Y.
#>   Rows with a note: 3. Most common: discharge missing (1), stage missing (1), stage not a number (1), time missing, midnight assumed (1).
now <- as.POSIXct("2025-01-01", tz = "UTC")

default <- assess_rating(fit, reference_time = now)
strict  <- assess_rating(fit, min_gaugings = 50, min_limb_gaugings = 45, spread_tol = 0.03, reference_time = now)

rbind(
  default = table(assessment_checks(default)$status),
  strict  = table(assessment_checks(strict)$status)
)
#>         not_assessed pass warning
#> default            2   38       6
#> strict             2   35       9
```

The example fit has 40 gaugings, so asking for 50 and for 45 per limb
moves those checks from pass to warning, and so does a tighter spread.
Nothing about the rating changed, only the question asked of it. The
bias limit, by contrast, would not have moved anything here: this fit
sits close to its gaugings.

**Write down what you used.** The assessment does not keep your limits
for you, so when you change one, say which and why wherever you record
the rating. A reviewer reading a pass needs to know what it was a pass
against.

## If you have a reason for a limit

If you know of guidance, a standard or an internal rule that sets any of
these, send it. Say which argument it sets, the value, and where it
comes from. The default then changes once, with the source named in the
documentation, and the “basis” column above says so.
