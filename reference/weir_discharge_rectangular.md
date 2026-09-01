# Discharge over a full-width (suppressed) rectangular sharp-crested weir

The Rehbock equation for a rectangular sharp-crested weir spanning the
full width of its approach channel (no end contractions), as specified
for this structure type by ISO 1438:2017:

\$\$Q = \frac{2}{3} C_d \sqrt{2g} \\ B H^{3/2}, \qquad C_d = 0.602 +
0.083 \frac{H}{P}\$\$

where \\H\\ is head over the crest, \\B\\ is crest width, and \\P\\ is
the weir's height above the channel bed. ISO 1438 restricts this formula
to \\P \< 1\\\\m; `weir_height_m >= 1` is accepted but warns, since the
coefficient is unvalidated outside that range.

Uncertainty is propagated by GUM (JCGM 100:2008) quadrature combination
of `u_cd` (the discharge coefficient's own relative standard
uncertainty) and `u_head_m` (the head measurement's absolute standard
uncertainty), using the equation's head exponent (`3/2`) as the head
term's sensitivity coefficient. Both are required, not defaulted: a
realistic starting point is a relative \\u^\*(C_d)\\ on the order of
1-2\\ own worked uncertainty examples are in this range), rising for a
rougher field installation – but this is illustrative context, not a
substitute for the actual value for a specific structure and instrument.

This assumes free (unsubmerged, non-drowned) flow, negligible approach
velocity, and a truly full-width crest – side contractions (a weir
narrower than its channel) are not modelled; that is a different,
contracted-weir formula this function does not implement.

## Usage

``` r
weir_discharge_rectangular(
  head_m,
  width_m,
  weir_height_m,
  u_cd,
  u_head_m,
  coverage_k = 2
)
```

## Arguments

- head_m:

  Numeric vector. Head over the weir crest, m. Must be positive.

- width_m:

  Single positive number. Crest width (= channel width,
  full-width/suppressed), m.

- weir_height_m:

  Single positive number. Weir crest height above the channel bed, m.

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

A data.table, one row per `head_m`: `head_m`, `discharge` (m^3/s),
`u_c_rel` (combined relative standard uncertainty), `U_rel` (expanded
relative uncertainty), `discharge_lower`/ `discharge_upper` (discharge
at `+/- U_rel`), `coverage_k`.

## References

ISO 1438:2017, *Hydrometry – Open channel flow measurement using
thin-plate weirs*. JCGM 100:2008, *Evaluation of measurement data –
Guide to the expression of uncertainty in measurement (GUM)*.

## See also

[`weir_discharge_vnotch()`](https://jonpayneea.github.io/reach.rate/reference/weir_discharge_vnotch.md),
[`weir_discharge_cipoletti()`](https://jonpayneea.github.io/reach.rate/reference/weir_discharge_cipoletti.md),
[`flume_discharge_parshall()`](https://jonpayneea.github.io/reach.rate/reference/flume_discharge_parshall.md);
[`vignette("weir_flume_guide")`](https://jonpayneea.github.io/reach.rate/articles/weir_flume_guide.md)
for the structures, diagrams, and worked examples.

## Examples

``` r
weir_discharge_rectangular(
  head_m = c(0.1, 0.2, 0.3), width_m = 1.5, weir_height_m = 0.5,
  u_cd = 0.02, u_head_m = 0.003
)
#>    head_m  discharge    u_c_rel      U_rel discharge_lower discharge_upper
#>     <num>      <num>      <num>      <num>           <num>           <num>
#> 1:    0.1 0.08663338 0.04924429 0.09848858      0.07810098      0.09516578
#> 2:    0.2 0.25161169 0.03010399 0.06020797      0.23646266      0.26676072
#> 3:    0.3 0.47432015 0.02500000 0.05000000      0.45060414      0.49803616
#>    coverage_k
#>         <num>
#> 1:          2
#> 2:          2
#> 3:          2
```
