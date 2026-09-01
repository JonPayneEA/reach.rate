# Spot gaugings for a real UK gauging station

A real spot-gauging record spanning 1974 to 2024, provided as an example
of the messiness of an actual station history: irregular gauging
intervals, decades-long gaps, a handful of high-flow gaugings among many
low-flow ones, and one gauging recorded at zero stage.

## Usage

``` r
station_gaugings
```

## Format

A
[data.table::data.table](https://rdrr.io/pkg/data.table/man/data.table.html)
with 223 rows and 3 columns:

- gauging_datetime:

  POSIXct (UTC) date and time of the spot gauging.

- discharge_cms:

  Measured discharge, in cubic metres per second.

- stage_m:

  Measured stage, in metres, on the station's local datum.

## Source

Environment Agency spot-gauging records for a UK river gauging station.

## Details

One gauging (17 November 1976) was recorded at `stage_m = 0` with a
nonzero discharge. Since the rating equation \\Q = C(H-a)^n\\ requires
`stage_m > a` for every gauging in a limb, that row is excluded in the
example below rather than passed to
[`rate_optimise()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise.md)
as-is.

## Examples

``` r
# A single-limb fit across the whole record (excluding the zero-stage
# gauging, which no C(H-a)^n curve with a finite `a` can pass through):
dt <- station_gaugings[station_gaugings$stage_m > 0, ]
fit <- rate_optimise(dt$discharge_cms, dt$stage_m)
fit@limbs[, .(limb, C, a, n, rmse_cms, r_squared, n_obs)]
#>     limb        C        a        n  rmse_cms r_squared n_obs
#>    <int>    <num>    <num>    <num>     <num>     <num> <int>
#> 1:     1 7.687527 0.116999 1.184888 0.7285289  0.857763   222
rating_plot(fit)

```
