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
