# Discharge over a V-notch (triangular) sharp-crested weir

The Kindsvater-Shen equation, the form ISO, ASTM, and USBR each adopt
for a sharp-crested triangular-notch weir:

\$\$Q = \frac{8}{15} \sqrt{2g} \\ C_e \tan(\theta/2) \\ H_e^{5/2},
\qquad H_e = H + k_h\$\$

where \\\theta\\ is the full notch angle and \\H_e\\ is head over the
notch vertex corrected by a small empirical head offset \\k_h\\. Both
\\C_e\\ (dimensionless) and \\k_h\\ (originally published in feet;
converted to metres internally, with the polynomial itself evaluated
exactly as published) are fitted polynomials in \\\theta\\ (degrees),
valid for notch angles from 25 to 100 degrees – outside that range this
errors rather than extrapolating an unvalidated fit.

Uncertainty follows the same GUM quadrature as
[`weir_discharge_rectangular()`](https://jonpayneea.github.io/reach.rate/reference/weir_discharge_rectangular.md),
with head exponent `5/2` (applied to the corrected head \\H_e\\). A
relative \\u^\*(C_e)\\ of roughly 1-2\\ V-notch weir – context, not a
default; `u_cd` is still required.

## Usage

``` r
weir_discharge_vnotch(head_m, notch_angle_deg, u_cd, u_head_m, coverage_k = 2)
```

## Arguments

- head_m:

  Numeric vector. Head over the weir crest, m. Must be positive.

- notch_angle_deg:

  Single number, 25-100. Full notch angle, degrees.

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

Kindsvater, C.E. & Carter, R.W. (1957); Shen, J. (1981), *Discharge
Characteristics of Triangular-Notch Thin-Plate Weirs*, USGS Water-Supply
Paper 1617-B. USBR *Water Measurement Manual*, ch. 7, §7. JCGM 100:2008
(GUM).

## See also

[`weir_discharge_rectangular()`](https://jonpayneea.github.io/reach.rate/reference/weir_discharge_rectangular.md),
[`weir_discharge_cipoletti()`](https://jonpayneea.github.io/reach.rate/reference/weir_discharge_cipoletti.md),
[`flume_discharge_parshall()`](https://jonpayneea.github.io/reach.rate/reference/flume_discharge_parshall.md);
[`vignette("weir_flume_guide")`](https://jonpayneea.github.io/reach.rate/articles/weir_flume_guide.md).

## Examples

``` r
weir_discharge_vnotch(
  head_m = c(0.05, 0.1, 0.15), notch_angle_deg = 90,
  u_cd = 0.02, u_head_m = 0.002
)
#>    head_m    discharge    u_c_rel     U_rel discharge_lower discharge_upper
#>     <num>        <num>      <num>     <num>           <num>           <num>
#> 1:   0.05 0.0007972567 0.10027612 0.2005522    0.0006373651    0.0009571484
#> 2:   0.10 0.0044125898 0.05344479 0.1068896    0.0039409299    0.0048842497
#> 3:   0.15 0.0120710027 0.03870555 0.0774111    0.0111365731    0.0130054323
#>    coverage_k
#>         <num>
#> 1:          2
#> 2:          2
#> 3:          2
```
