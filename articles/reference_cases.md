# Reference Cases: Ten Stations With a Known Answer

**Audience:** technical. You are checking that an installation of the
package behaves as its tests say it should, reviewing what those tests
cover, or adding a case of your own.

## Why synthetic stations

A real station never tells you the true rating, so a fit to real
gaugings can be checked for consistency but never for correctness. A
synthetic station can. Each case below generates gaugings from a rating
the package knows, with scatter, fits them with the guided workflow, and
asks whether the answer comes back.

## Read this first

**These ten cases were written by the package’s author.** They are not
the cases of any external specification: the brief that asked for a
reference suite never supplied its list, so these are my own choices,
covering the situations I think matter most. They are a starting point
for a reviewer to extend.

**Passing them is necessary, not sufficient.** Ten tidy synthetic
stations say nothing about a real one. They catch a package that has
broken, not a rating that is wrong.

**The tests are about envelopes, not coefficients.** A case does not
demand that `C`, `a` and `n` come back to three decimals. Several
triples describe nearly the same curve, and a platform’s arithmetic can
move them in the last places. What matters is the discharge a user would
read off. So each case states an **envelope**, the largest relative
error allowed between the fitted curve and the truth across the gauged
range. Each envelope is set with room to spare: no case uses more than
half of it.

## The cases

``` r

cases <- reference_cases()
knitr::kable(cases[, .(Case = id, `What it tests` = purpose, `What it does not` = not_tested)])
```

| Case | What it tests | What it does not |
|:---|:---|:---|
| single_limb | The ordinary case: one control, 30 well-spread gaugings, 2% scatter. The baseline everything else is read against. | Anything about real stations: no shifts, no outliers, no structure. |
| two_limbs | A control that changes (exponent 1.6 to 2.9). The fit uses the break as given. Independently fitted limbs rarely meet exactly, and the assessment says so. | Finding the break: suggest_breakpoints() is not used. A statistical search can miss a real break. |
| heavy_noise | Gauging error far above what a good station has. The curve is recovered only loosely, and the assessment must say the scatter is high. | That the loose envelope is acceptable for any use. It is the most the method promises at this noise. |
| sparse_top | Dense gaugings to 2 m and two above. The fit still tracks the truth, but the assessment must warn that the top is thinly supported. | Whether a different truth above the top gaugings would be caught: nothing can. |
| isolated_high | A single high gauging far from the rest drags the top of the curve. Judged only below 2 m, where the data are dense; the assessment must flag the influence. | The curve above 2 m, which this gauging controls. Whether the gauging is right is a question for a person. |
| rating_shift | Gaugings from 2008 follow C = 3 and from 2024 follow C = 4. With a three-year half-life the fit follows today’s channel. The flat fit must be clearly worse. | Detecting the shift. Recency weighting acts on a judgement that the channel moved; it does not make it. |
| zero_flow_offset | A datum far from zero, with gaugings only above it. The zero-flow stage a must be recovered, not assumed to be zero. | A zero-flow stage below the lowest gauging by a long way, which no data can pin down. |
| steep_exponent | A V-notch-like control. The exponent must be recovered near 3, inside the range the assessment treats as usual. | Exponents outside 1 to 3.5, which the assessment flags as hydraulically unusual. |
| wide_exponent | An exponent at the bottom of the usual range. The fit must not be pushed off it by the lower bound. | Exponents below 1. |
| few_gaugings | Barely enough to fit three parameters. The curve is still close, with a wider envelope, and the assessment must say the evidence is thin. | Whether six gaugings are enough for any use. The envelope is for this one realisation. |

A case passes when four things hold. The fitted curve stays inside its
envelope. The optimiser converged and the rating is valid. Any parameter
the case checks (the zero-flow stage, an exponent) is recovered. And the
assessment raises the one check the case was built to trigger, for the
five that have one.

``` r

knitr::kable(cases[!is.na(designed_check), .(Case = id, `Envelope` = envelope, `Check it must raise` = designed_check)])
```

| Case          | Envelope | Check it must raise  |
|:--------------|---------:|:---------------------|
| two_limbs     |     0.10 | limb_continuity      |
| heavy_noise   |     0.35 | residual_spread      |
| sparse_top    |     0.06 | upper_range_support  |
| isolated_high |     0.08 | influential_gaugings |
| few_gaugings  |     0.12 | few_gaugings         |

## Running them

``` r

res <- check_reference_cases()
knitr::kable(res[, .(Case = id, `Largest error` = round(max_rel_error, 3), Envelope = envelope,
                     Converged = converged, Valid = valid, `Check raised` = check_raised, Passed = passed)])
```

| Case             | Largest error | Envelope | Converged | Valid | Check raised | Passed |
|:-----------------|--------------:|---------:|:----------|:------|:-------------|:-------|
| single_limb      |         0.007 |     0.03 | TRUE      | TRUE  | NA           | TRUE   |
| two_limbs        |         0.037 |     0.10 | TRUE      | TRUE  | TRUE         | TRUE   |
| heavy_noise      |         0.165 |     0.35 | TRUE      | TRUE  | TRUE         | TRUE   |
| sparse_top       |         0.016 |     0.06 | TRUE      | TRUE  | TRUE         | TRUE   |
| isolated_high    |         0.030 |     0.08 | TRUE      | TRUE  | TRUE         | TRUE   |
| rating_shift     |         0.038 |     0.10 | TRUE      | TRUE  | NA           | TRUE   |
| zero_flow_offset |         0.005 |     0.03 | TRUE      | TRUE  | NA           | TRUE   |
| steep_exponent   |         0.004 |     0.03 | TRUE      | TRUE  | NA           | TRUE   |
| wide_exponent    |         0.019 |     0.06 | TRUE      | TRUE  | NA           | TRUE   |
| few_gaugings     |         0.037 |     0.12 | TRUE      | TRUE  | TRUE         | TRUE   |

[`check_reference_cases()`](https://jonpayneea.github.io/reach.rate/reference/check_reference_cases.md)
is exported so that the same run can be made on any machine the package
is installed on, such as one it is about to be used on. It takes a few
seconds and changes nothing: it leaves your random seed as it found it
and moves no rating’s lifecycle.

``` r

cat(sprintf("%d of %d cases passed.\n", sum(res$passed), nrow(res)))
#> 10 of 10 cases passed.
```

## Looking at one case

``` r

case <- reference_case("two_limbs")
fit <- do.call(fit_rating, c(list(case$data, quiet = TRUE), case$fit_args))
stage <- c(0.5, 1.0, 1.5, 2.0, 3.0)
data.table(stage = stage,
           truth = round(case$truth(stage), 2),
           fitted = round(apply_rating(fit, stage)$discharge, 2),
           relative_error = round(apply_rating(fit, stage)$discharge / case$truth(stage) - 1, 3))
#>    stage truth fitted relative_error
#>    <num> <num>  <num>          <num>
#> 1:   0.5  1.06   1.08          0.024
#> 2:   1.0  3.20   3.24          0.011
#> 3:   1.5  6.12   6.07         -0.009
#> 4:   2.0 12.97  13.11          0.011
#> 5:   3.0 42.02  42.47          0.011
```

Each case is `reference_case(id)`: its `data`, identical on every call,
the `truth` as a function of stage, the arguments it is fitted with, and
the range and envelope it is judged over.

## What a failure would mean

A failing case is a finding about the installation, not a verdict on any
rating. Which part failed says where to look:

| Fails | Look at |
|----|----|
| The envelope | The fitting code or a dependency: the optimiser, `minpack.lm`, a platform’s arithmetic |
| Converged or valid | The same, and [`vignette("mathematical_contract")`](https://jonpayneea.github.io/reach.rate/articles/mathematical_contract.md) for what valid means |
| A parameter | Bounds on the exponent, or the starting values |
| The designed check | The assessment’s limits: [`vignette("thresholds")`](https://jonpayneea.github.io/reach.rate/articles/thresholds.md) |
| The channel-shift contrast | Age weighting: [`vignette("recency_weighting_guide")`](https://jonpayneea.github.io/reach.rate/articles/recency_weighting_guide.md) |

## Adding a case

A case is one entry in the package’s list of specifications: a title, a
seed, a true rating, a way to generate the data, an envelope, and the
check it should raise if any. The package’s tests loop over every case,
so a new one is tested without further work. Choose the envelope by
running the case and leaving at least double the error you see, then say
plainly in `not_tested` what the case cannot show.
