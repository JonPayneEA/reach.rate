# Discharge over a Cipoletti (trapezoidal) sharp-crested weir

The Cipoletti weir's trapezoidal notch (sides sloped 1 horizontal to 4
vertical) is designed so the side slopes' extra discharge compensates
for end-contraction losses, letting it use a single fixed coefficient
with no weir-height or approach-channel correction, unlike the
rectangular case:

\$\$Q = 1.859 \\ L \\ H^{3/2}\$\$

(SI form; \\L\\ is crest length, \\H\\ is head over the crest. Derived
here from the USBR *Water Measurement Manual*'s published US customary
form, \\Q\_{cfs} = 3.367 \\ L\_{ft} H\_{ft}^{3/2}\\, by direct unit
conversion.)

That simplicity comes at a cost: the USBR manual describes overall
accuracy for a well-maintained Cipoletti installation as only around
\\\pm 5\\\\ – markedly worse than a rectangular or V-notch weir.
Uncertainty here still follows the same GUM quadrature as the other
structures (head exponent `3/2`); `u_cd` and `u_head_m` are required,
with that \\\pm 5\\\\ figure as context for the scale of `u_cd` a
Cipoletti weir typically needs, not a substitute for it (it is an
aggregate accuracy figure, not already split into coefficient/head
components).

## Usage

``` r
weir_discharge_cipoletti(
  head_m,
  crest_length_m,
  u_cd,
  u_head_m,
  coverage_k = 2
)
```

## Arguments

- head_m:

  Numeric vector. Head over the weir crest, m. Must be positive.

- crest_length_m:

  Single positive number. Crest length, m (the longer, downstream edge
  of the trapezoidal notch).

- u_cd:

  Single non-negative number. Relative standard uncertainty in the
  discharge coefficient (e.g. `0.02` for 2%). See Description.

- u_head_m:

  Single non-negative number. Absolute standard uncertainty in the
  measured head, m.

- coverage_k:

  Single positive number. GUM coverage factor for the expanded
  uncertainty `U = coverage_k * u_c`. Default `2` (approximately 95% for
  a normally-distributed measurand, the conventional GUM default – JCGM
  100:2008 §2.3.6).

## Value

As
[`weir_discharge_rectangular()`](https://jonpayneea.github.io/reach.rate/reference/weir_discharge_rectangular.md).

## References

USBR *Water Measurement Manual*, ch. 7, §12. JCGM 100:2008 (GUM).

## See also

[`weir_discharge_rectangular()`](https://jonpayneea.github.io/reach.rate/reference/weir_discharge_rectangular.md),
[`weir_discharge_vnotch()`](https://jonpayneea.github.io/reach.rate/reference/weir_discharge_vnotch.md),
[`flume_discharge_parshall()`](https://jonpayneea.github.io/reach.rate/reference/flume_discharge_parshall.md);
[`vignette("weir_flume_guide")`](https://jonpayneea.github.io/reach.rate/articles/weir_flume_guide.md).

## Examples

``` r
weir_discharge_cipoletti(
  head_m = c(0.1, 0.2, 0.3), crest_length_m = 1.0,
  u_cd = 0.05, u_head_m = 0.003
)
#>    head_m  discharge    u_c_rel     U_rel discharge_lower discharge_upper
#>     <num>      <num>      <num>     <num>           <num>           <num>
#> 1:    0.1 0.05878674 0.06726812 0.1345362      0.05087779      0.06669569
#> 2:    0.2 0.16627401 0.05482928 0.1096586      0.14804065      0.18450738
#> 3:    0.3 0.30546487 0.05220153 0.1044031      0.27357340      0.33735634
#>    coverage_k
#>         <num>
#> 1:          2
#> 2:          2
#> 3:          2
```
