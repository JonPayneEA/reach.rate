# Extract the selected breakpoints from suggest_breakpoints() as a vector

Deprecated.
[`suggest_breakpoints()`](https://jonpayneea.github.io/reach.rate/reference/suggest_breakpoints.md)
now marks the adopted candidates in a `selected` column, which survives
data.table operations that can drop the attribute this function reads.
Use `sort(candidates_dt[selected == TRUE, candidate_stage])` instead.
This function will be removed in the release after next.

## Usage

``` r
suggested_breakpoints_vector(candidates_dt)
```

## Arguments

- candidates_dt:

  The data.table returned by
  [`suggest_breakpoints()`](https://jonpayneea.github.io/reach.rate/reference/suggest_breakpoints.md).

## Value

A numeric vector, sorted ascending.

## Examples

``` r
set.seed(7)
stage_m <- seq(0.3, 3.5, by = 0.05)
discharge_cms <- 4 * pmax(stage_m - 0.1, 0)^1.55 * (pmax(stage_m - 1.6, 0) + 1)^0.9 *
  (pmax(stage_m - 2.4, 0) + 1)^1.1 * exp(rnorm(length(stage_m), sd = 0.03))
candidates <- suggest_breakpoints(discharge_cms, stage_m, max_breaks = 1L)

# The replacement: read the `selected` column.
sort(candidates[selected == TRUE, candidate_stage])
#> [1] 2.45

# The deprecated function gives the same stages, with a warning.
suppressWarnings(suggested_breakpoints_vector(candidates))
#> [1] 2.45
```
