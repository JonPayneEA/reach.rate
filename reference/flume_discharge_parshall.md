# Discharge through a standard Parshall flume (free flow)

The general free-flow discharge equation for a standard Parshall flume
with throat width between 1 and 8 feet (0.3048-2.4384 m):

\$\$Q = 2.340 \\ W^{1.026} \\ H_a^{1.522}\$\$

(SI form; \\W\\ is throat width, \\H_a\\ is the upstream head gauged at
the standard measuring station. Derived here from the equation's
published US customary form, \\Q\_{cfs} = 4 \\ W\_{ft}^{1.026}
H\_{a,ft}^{1.522}\\, by direct unit conversion.) `throat_width_m`
outside 0.3048-2.4384 m warns, since this general approximation is only
confirmed within that range – smaller and larger standard sizes have
their own individually tabulated `C`/`n` coefficients (USBR *Water
Measurement Manual*, ch. 8, §10; ISO 9826) not reproduced here.

A Parshall flume only measures discharge correctly in free (unsubmerged)
flow. If `hb_head_m` (the downstream/submerged head) is supplied, this
checks the standard submergence limit for this throat-width range
(`hb_head_m / head_m <= 0.7`) and errors rather than applying an
uncorrected free-flow equation to submerged conditions – submerged-flow
correction is not implemented.

Uncertainty follows the same GUM quadrature as the other structures
(head exponent `1.522`). A 2021 Monte Carlo study (Ferreira et al.)
found roughly \\\pm 2\\\\ for well-built laboratory flumes, rising to
\\\pm 3\text{-}5\\\\ for realistic field installations – context for
`u_cd`'s scale, not a default; both `u_cd` and `u_head_m` are required.

## Usage

``` r
flume_discharge_parshall(
  head_m,
  throat_width_m,
  u_cd,
  u_head_m,
  coverage_k = 2,
  hb_head_m = NULL
)
```

## Arguments

- head_m:

  Numeric vector. Head over the weir crest, m. Must be positive.

- throat_width_m:

  Single positive number. Flume throat width, m.

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

- hb_head_m:

  Numeric vector matching `head_m` in length, or `NULL` (default).
  Downstream head, for the free-flow submergence check described above.
  `NULL` skips the check.

## Value

As
[`weir_discharge_rectangular()`](https://jonpayneea.github.io/reach.rate/reference/weir_discharge_rectangular.md).

## References

USBR *Water Measurement Manual*, ch. 8, §10. Ferreira, H.M. et al.
(2021), Monte Carlo uncertainty analysis of Parshall flume discharge.
JCGM 100:2008 (GUM).

## See also

[`weir_discharge_rectangular()`](https://jonpayneea.github.io/reach.rate/reference/weir_discharge_rectangular.md),
[`weir_discharge_vnotch()`](https://jonpayneea.github.io/reach.rate/reference/weir_discharge_vnotch.md),
[`weir_discharge_cipoletti()`](https://jonpayneea.github.io/reach.rate/reference/weir_discharge_cipoletti.md);
[`vignette("weir_flume_guide")`](https://jonpayneea.github.io/reach.rate/articles/weir_flume_guide.md).

## Examples

``` r
flume_discharge_parshall(
  head_m = c(0.15, 0.3, 0.45), throat_width_m = 0.3048,
  u_cd = 0.03, u_head_m = 0.005
)
#>    head_m discharge    u_c_rel      U_rel discharge_lower discharge_upper
#>     <num>     <num>      <num>      <num>           <num>           <num>
#> 1:   0.15 0.0385324 0.05893955 0.11787911      0.03399024      0.04307457
#> 2:   0.30 0.1106608 0.03928699 0.07857398      0.10196573      0.11935585
#> 3:   0.45 0.2051184 0.03443814 0.06887629      0.19099062      0.21924621
#>    coverage_k
#>         <num>
#> 1:          2
#> 2:          2
#> 3:          2
```
