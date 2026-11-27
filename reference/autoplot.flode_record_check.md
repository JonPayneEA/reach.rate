# Plot a flow record check

The record's stage and flow pairs, coloured by period, with each
period's curve read back, the steps off the curve, and the top and
bankfull stages where given.

## Usage

``` r
# S3 method for class 'flode_record_check'
autoplot(object, ...)

# S3 method for class 'flode_record_check'
plot(x, ...)
```

## Arguments

- object, x:

  What
  [`check_flow_record()`](https://jonpayneea.github.io/reach.rate/reference/check_flow_record.md)
  returns.

- ...:

  Unused.

## Value

A ggplot object;
[`plot()`](https://rdrr.io/r/graphics/plot.default.html) prints it.

## Examples

``` r
time <- seq(as.POSIXct("2024-01-01", tz = "UTC"), by = 900, length.out = 2880)
stage <- round(0.45 + 0.25 * sin(2 * pi * seq_along(time) / 672), 3)
out <- check_flow_record(data.frame(time = time, stage_m = stage,
                                    discharge_cms = round(5 * (stage - 0.1)^1.6, 3)))
autoplot(out)
```
