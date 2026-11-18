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
#>  1:     1     1 5.026513  3.269676e-03 1.596470         0.5         2.5
#>  2:     1     2 5.018405  2.894183e-03 1.598703         0.5         2.5
#>  3:     1     3 4.994507 -1.934379e-05 1.600895         0.5         2.5
#>  4:     1     4 4.987080 -1.924049e-03 1.601480         0.5         2.5
#>  5:     1     5 4.975609 -3.532390e-03 1.602635         0.5         2.5
#>  6:     1     6 4.931092 -8.918307e-03 1.609525         0.5         2.5
#>  7:     1     7 4.961129 -4.950192e-03 1.605232         0.5         2.5
#>  8:     1     8 4.985529 -2.743905e-03 1.600977         0.5         2.5
#>  9:     1     9 5.020521  2.273115e-03 1.597179         0.5         2.5
#> 10:     1    10 5.004065  3.401046e-04 1.599369         0.5         2.5
#> 11:     1    11 5.005244 -2.816888e-04 1.597808         0.5         2.5
#> 12:     1    12 5.021561  1.722782e-03 1.596620         0.5         2.5
#> 13:     1    13 5.043661  5.520666e-03 1.594308         0.5         2.5
#> 14:     1    14 4.975302 -3.144287e-03 1.603501         0.5         2.5
#> 15:     1    15 5.026409  2.535261e-03 1.595888         0.5         2.5
#> 16:     1    16 5.033559  5.419902e-03 1.597145         0.5         2.5
#> 17:     1    17 5.003060 -4.062317e-04 1.598596         0.5         2.5
#> 18:     1    18 4.995722 -1.331029e-03 1.599955         0.5         2.5
#> 19:     1    19 4.993686 -1.151140e-03 1.600096         0.5         2.5
#> 20:     1    20 4.987673 -1.660727e-03 1.601616         0.5         2.5
#> 21:     1    21 4.960419 -4.854770e-03 1.605415         0.5         2.5
#> 22:     1    22 5.018182  1.446883e-03 1.596923         0.5         2.5
#> 23:     1    23 4.944698 -7.291380e-03 1.607643         0.5         2.5
#> 24:     1    24 4.983995 -1.393056e-03 1.602441         0.5         2.5
#> 25:     1    25 5.005666 -9.636053e-05 1.598484         0.5         2.5
#> 26:     1    26 4.936479 -8.855669e-03 1.608151         0.5         2.5
#> 27:     1    27 5.000858 -1.046074e-04 1.600130         0.5         2.5
#> 28:     1    28 5.014993  1.269972e-03 1.597528         0.5         2.5
#> 29:     1    29 5.015022  1.399446e-03 1.597821         0.5         2.5
#> 30:     1    30 4.964668 -4.911652e-03 1.604783         0.5         2.5
#> 31:     1    31 4.980601 -3.425106e-03 1.602279         0.5         2.5
#> 32:     1    32 4.965613 -5.574073e-03 1.603635         0.5         2.5
#> 33:     1    33 4.945376 -7.615678e-03 1.606819         0.5         2.5
#> 34:     1    34 4.973085 -3.901093e-03 1.602960         0.5         2.5
#> 35:     1    35 4.974065 -4.193732e-03 1.602476         0.5         2.5
#> 36:     1    36 4.954927 -6.120829e-03 1.606114         0.5         2.5
#> 37:     1    37 5.021508  2.220387e-03 1.596663         0.5         2.5
#> 38:     1    38 4.987080 -3.070591e-03 1.600143         0.5         2.5
#> 39:     1    39 4.901534 -1.267592e-02 1.613393         0.5         2.5
#> 40:     1    40 5.005280  1.590332e-03 1.599729         0.5         2.5
#> 41:     1    41 4.965182 -4.332823e-03 1.604676         0.5         2.5
#> 42:     1    42 4.964077 -5.179462e-03 1.604717         0.5         2.5
#> 43:     1    43 4.998761 -3.413685e-04 1.599873         0.5         2.5
#> 44:     1    44 4.970069 -4.137865e-03 1.604025         0.5         2.5
#> 45:     1    45 4.968744 -4.180491e-03 1.603977         0.5         2.5
#> 46:     1    46 4.970447 -3.203928e-03 1.604401         0.5         2.5
#> 47:     1    47 5.007086  1.044312e-03 1.599232         0.5         2.5
#> 48:     1    48 4.973396 -4.041854e-03 1.603480         0.5         2.5
#> 49:     1    49 5.010830  6.442340e-04 1.597336         0.5         2.5
#> 50:     1    50 4.943903 -7.567427e-03 1.607257         0.5         2.5
#>      limb  draw        C             a        n lower_level upper_level
#>     <int> <int>    <num>         <num>    <num>       <num>       <num>
```
