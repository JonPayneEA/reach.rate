# Convert a fit's bootstrap draws into apply_rating_interval()'s input

Bridges `rate_optimise(..., n_boot = )`'s per-draw coefficient samples
(`fit@bootstrap`, which records every requested draw including failed or
rejected ones) to the shape
[`apply_rating_interval()`](https://jonpayneea.github.io/reach.rate/reference/apply_rating_interval.md)
expects: one row per successful (limb, draw), with `C`/`a`/`n` copied
through unchanged –
[`rate_optimise()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise.md)
and the equation-table representation now share the same
`Q = C(H - a)^n` convention. Failed or rejected draws
(`success == FALSE`) are dropped – they have no coefficients to bridge.

## Usage

``` r
bootstrap_to_table(fit)
```

## Arguments

- fit:

  A
  [FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md)
  instance from `rate_optimise(..., n_boot > 0)`.

## Value

A `data.table` with columns `limb`, `draw`, `lower_level`,
`upper_level`, `C`, `a`, `n` – one row per successful bootstrap draw.
Errors if no draws succeeded.

## See also

[`as_rating_table()`](https://jonpayneea.github.io/reach.rate/reference/as_rating_table.md)
(in `flode_classes`)

## Examples

``` r
set.seed(1)
stage_seq <- seq(0.5, 2.5, by = 0.05)
discharge_seq <- 5 * stage_seq^1.6 + rnorm(length(stage_seq), sd = 0.02)
fit <- rate_optimise(discharge_seq, stage_seq, n_boot = 50L, boot_seed = 1L)
bootstrap_to_table(fit)
#> Key: <limb>
#>      limb  draw        C             a        n lower_level upper_level
#>     <int> <int>    <num>         <num>    <num>       <num>       <num>
#>  1:     1     1 5.026513  3.269700e-03 1.596470         0.5         2.5
#>  2:     1     2 5.018405  2.894247e-03 1.598703         0.5         2.5
#>  3:     1     3 4.994483 -2.239655e-05 1.600898         0.5         2.5
#>  4:     1     4 4.987085 -1.923446e-03 1.601480         0.5         2.5
#>  5:     1     5 4.975609 -3.532487e-03 1.602636         0.5         2.5
#>  6:     1     6 4.931092 -8.918330e-03 1.609525         0.5         2.5
#>  7:     1     7 4.961128 -4.950396e-03 1.605232         0.5         2.5
#>  8:     1     8 4.985530 -2.743744e-03 1.600977         0.5         2.5
#>  9:     1     9 5.020520  2.272977e-03 1.597180         0.5         2.5
#> 10:     1    10 5.004060  3.394448e-04 1.599370         0.5         2.5
#> 11:     1    11 5.005222 -2.844379e-04 1.597811         0.5         2.5
#> 12:     1    12 5.021559  1.722625e-03 1.596621         0.5         2.5
#> 13:     1    13 5.043662  5.520735e-03 1.594308         0.5         2.5
#> 14:     1    14 4.975302 -3.144331e-03 1.603501         0.5         2.5
#> 15:     1    15 5.026410  2.535426e-03 1.595888         0.5         2.5
#> 16:     1    16 5.033559  5.419898e-03 1.597145         0.5         2.5
#> 17:     1    17 5.003053 -4.070598e-04 1.598597         0.5         2.5
#> 18:     1    18 4.995718 -1.331431e-03 1.599955         0.5         2.5
#> 19:     1    19 4.993689 -1.150768e-03 1.600095         0.5         2.5
#> 20:     1    20 4.987672 -1.660871e-03 1.601616         0.5         2.5
#> 21:     1    21 4.960420 -4.854675e-03 1.605415         0.5         2.5
#> 22:     1    22 5.018184  1.447138e-03 1.596923         0.5         2.5
#> 23:     1    23 4.944699 -7.291249e-03 1.607643         0.5         2.5
#> 24:     1    24 4.983996 -1.392959e-03 1.602441         0.5         2.5
#> 25:     1    25 5.005695 -9.247399e-05 1.598480         0.5         2.5
#> 26:     1    26 4.936479 -8.855609e-03 1.608151         0.5         2.5
#> 27:     1    27 5.000864 -1.038021e-04 1.600129         0.5         2.5
#> 28:     1    28 5.014992  1.269936e-03 1.597528         0.5         2.5
#> 29:     1    29 5.015020  1.399292e-03 1.597821         0.5         2.5
#> 30:     1    30 4.964669 -4.911642e-03 1.604783         0.5         2.5
#> 31:     1    31 4.980601 -3.425070e-03 1.602279         0.5         2.5
#> 32:     1    32 4.965614 -5.574003e-03 1.603635         0.5         2.5
#> 33:     1    33 4.945376 -7.615681e-03 1.606819         0.5         2.5
#> 34:     1    34 4.973085 -3.901097e-03 1.602960         0.5         2.5
#> 35:     1    35 4.974065 -4.193734e-03 1.602476         0.5         2.5
#> 36:     1    36 4.954926 -6.120894e-03 1.606114         0.5         2.5
#> 37:     1    37 5.021509  2.220524e-03 1.596663         0.5         2.5
#> 38:     1    38 4.987082 -3.070390e-03 1.600143         0.5         2.5
#> 39:     1    39 4.901535 -1.267574e-02 1.613393         0.5         2.5
#> 40:     1    40 5.005279  1.590238e-03 1.599729         0.5         2.5
#> 41:     1    41 4.965181 -4.332906e-03 1.604676         0.5         2.5
#> 42:     1    42 4.964077 -5.179447e-03 1.604717         0.5         2.5
#> 43:     1    43 4.998765 -3.408305e-04 1.599872         0.5         2.5
#> 44:     1    44 4.970068 -4.137990e-03 1.604025         0.5         2.5
#> 45:     1    45 4.968745 -4.180424e-03 1.603977         0.5         2.5
#> 46:     1    46 4.970448 -3.203786e-03 1.604401         0.5         2.5
#> 47:     1    47 5.007088  1.044510e-03 1.599231         0.5         2.5
#> 48:     1    48 4.973395 -4.041959e-03 1.603480         0.5         2.5
#> 49:     1    49 5.010830  6.441706e-04 1.597336         0.5         2.5
#> 50:     1    50 4.943903 -7.567450e-03 1.607257         0.5         2.5
#>      limb  draw        C             a        n lower_level upper_level
#>     <int> <int>    <num>         <num>    <num>       <num>       <num>
```
