# Apply a fitted rating to a stage series (S7 generic)

Converts a stage record to discharge. Dispatches on the class of `fit`:
[FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md),
[FlodeRatingTable](https://jonpayneea.github.io/reach.rate/reference/FlodeRatingTable.md)
and
[FlodeSegmentedRating](https://jonpayneea.github.io/reach.rate/reference/FlodeSegmentedRating.md)
each provide a method. Replaces the previous separate
`apply_rating()`/`apply_segmented_rating()` pair – one name, dispatched
by what you're holding.

The stage record can be a table with a stage column, or simply a numeric
vector of stage values.

## Usage

``` r
apply_rating(fit, ...)
```

## Arguments

- fit:

  A
  [FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md),
  [FlodeRatingTable](https://jonpayneea.github.io/reach.rate/reference/FlodeRatingTable.md)
  or
  [FlodeSegmentedRating](https://jonpayneea.github.io/reach.rate/reference/FlodeSegmentedRating.md).

- ...:

  Arguments for the class-specific method, which are the same for all
  three:

  - `stage_dt`: a data.frame or data.table with a stage column, or a
    numeric vector of stage values. Any other columns, such as
    `datetime`, are carried through unchanged. A vector is wrapped in a
    one-column table named by `stage_col`.

  - `stage_col`: name of the stage column in `stage_dt`. Default
    `"stage"`. With a vector it names the stage column of the result.

  - `out_col`: name of the discharge column to add. Default
    `"discharge"`.

## Value

`stage_dt` as a data.table (or, for a vector input, a table holding the
stage values) with three columns added: `out_col` (the computed
discharge), `extrapolated` (logical; `TRUE` where the stage fell outside
the range the rating covers, as defined for each class above) and
`support`, which says how well supported that stage is:

- `"interpolation_observed"`: inside the stage range of the gaugings;

- `"interpolation_mixed"`: inside the range of all the evidence but
  outside the gaugings, so it rests on modelled evidence (a modelled
  value, a cross-section or structure computation, a point read off
  another rating);

- `"model_supported"`: inside the range the equations are declared over
  but with no evidence there, as after
  [`extend_rating_low()`](https://jonpayneea.github.io/reach.rate/reference/extend_rating_low.md)
  or
  [`graft_rating()`](https://jonpayneea.github.io/reach.rate/reference/graft_rating.md);
  also what a table, which holds equations only, gives within its range;

- `"extrapolation"`: beyond the range the equations are declared over;

- `"outside_operational_range"`: beyond the operational limits, if
  stated. It outranks the others.

`NA` where the stage is `NA`. A stage beyond the numerical range of the
rating (where its top limb's equation overflows) is an error, because
the result would not be a number. See
[`rating_support()`](https://jonpayneea.github.io/reach.rate/reference/rating_support.md)
for the ranges.

A rating made by
[`fit_rating()`](https://jonpayneea.github.io/reach.rate/reference/fit_rating.md)
also refuses stages outside its operational limits, when they have been
stated. With none stated, stages beyond the gauged range are returned,
flagged `extrapolation` in the `support` column, with one warning per
call.

## Details

**[FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md)
method.** What
[`rate_optimise()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise.md)
and
[`rate_optimise_constrained()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise_constrained.md)
return. It is converted with
[`as_rating_table()`](https://jonpayneea.github.io/reach.rate/reference/as_rating_table.md)
and then handled exactly as below, so the two give identical results.

**[FlodeRatingTable](https://jonpayneea.github.io/reach.rate/reference/FlodeRatingTable.md)
method.** Each stage value is assigned to the limb whose
`[lower_level, upper_level]` band contains it, and discharge is that
limb's `Q = C(H - a)^n`. Limbs must be contiguous
(`upper_level[i] == lower_level[i + 1]`), or the call stops. Stage at or
below a limb's `a` gives zero discharge. Stage below the lowest limb or
above the highest is evaluated by extrapolating the nearest limb's
equation, and flagged `extrapolated = TRUE`. Where stage may fall below
the lowest gauged stage,
[`extend_rating_low()`](https://jonpayneea.github.io/reach.rate/reference/extend_rating_low.md)
adds an explicit linear limb there instead.

**[FlodeSegmentedRating](https://jonpayneea.github.io/reach.rate/reference/FlodeSegmentedRating.md)
method.** Discharge comes from the joint segmented formula. Stage at or
below the zero-flow stage `bp1` gives zero discharge, which falls out of
the formula itself. Only stage above the highest gauged stage is flagged
`extrapolated = TRUE`.

## See also

[`apply_rating_interval()`](https://jonpayneea.github.io/reach.rate/reference/apply_rating_interval.md)
for a bootstrap prediction interval,
[`apply_rating_versioned()`](https://jonpayneea.github.io/reach.rate/reference/apply_rating_versioned.md)
for a rating that changed over time,
[`apply_rating_inverse()`](https://jonpayneea.github.io/reach.rate/reference/apply_rating_inverse.md)
for discharge back to stage, and
[`extend_rating_low()`](https://jonpayneea.github.io/reach.rate/reference/extend_rating_low.md)
for stage below the lowest limb.

## Examples

``` r
# A rating typed in by hand, e.g. from a station's published rating
# sheet: four limbs, one row each. C, a and n are the coefficients of
# Q = C * (H - a)^n on that limb (a is the stage at zero flow), and
# lower_level/upper_level are the stage range (m) the limb covers. Each
# limb starts where the previous one ends, and C is chosen so the limbs
# also meet in discharge there.
limb_names <- c("Low flow", "In channel", "Bankfull", "Floodplain")
rating_dt <- data.table::data.table(
  lower_level = c(0.30, 0.90, 1.70, 2.60),
  upper_level = c(0.90, 1.70, 2.60, 4.00),
  C           = c(1.80000, 2.85549, 4.72355, 2.36038),
  a           = c(0.10, 0.25, 0.55, 0.40),
  n           = c(1.60, 1.90, 1.45, 2.20)
)
my_fit <- FlodeRatingTable(table = rating_dt)

# A stage record to convert: a two-day event on a 15-minute step. Stage
# starts and ends below the lowest limb (0.30 m) and the peak goes above
# the highest (4.00 m), so both ends of the rating are extrapolated.
time_h <- seq(0, 48, by = 0.25)
stage_dt <- data.table::data.table(
  datetime = as.POSIXct("2026-01-10 00:00", tz = "UTC") + time_h * 3600,
  stage    = 0.25 + 3.9 * exp(-((time_h - 20) / 9)^2) + 0.10 * sin(time_h / 2)
)

flow_dt <- apply_rating(my_fit, stage_dt)
#> INFO [2026-11-20 15:16:32] apply_rating(): 35 of 193 stage value(s) fell outside the rating and were extrapolated.
head(flow_dt)
#>               datetime     stage discharge extrapolated         support
#>                 <POSc>     <num>     <num>       <lgcl>          <char>
#> 1: 2026-01-10 00:00:00 0.2779512 0.1136983         TRUE   extrapolation
#> 2: 2026-01-10 00:15:00 0.2940671 0.1306158         TRUE   extrapolation
#> 3: 2026-01-10 00:30:00 0.3104096 0.1486543        FALSE model_supported
#> 4: 2026-01-10 00:45:00 0.3268280 0.1676437        FALSE model_supported
#> 5: 2026-01-10 01:00:00 0.3431807 0.1873955        FALSE model_supported
#> 6: 2026-01-10 01:15:00 0.3593381 0.2077105        FALSE model_supported

# How much of the record fell outside the rating's range?
table(flow_dt$extrapolated)
#> 
#> FALSE  TRUE 
#>   158    35 

# Which limb each stage fell on (for colouring the plot)
breaks <- c(rating_dt$lower_level[1], rating_dt$upper_level)
limb_idx <- pmin(pmax(findInterval(flow_dt$stage, breaks, rightmost.closed = TRUE), 1L), 4L)
flow_dt$limb <- factor(limb_names[limb_idx], levels = limb_names)

library(ggplot2)

# The rating curve itself, with the stage values that were converted
curve_dt <- data.table::rbindlist(lapply(seq_len(nrow(rating_dt)), function(i) {
  s <- seq(rating_dt$lower_level[i], rating_dt$upper_level[i], length.out = 60)
  data.frame(stage = s, limb = limb_names[i],
             discharge = rating_dt$C[i] * (s - rating_dt$a[i])^rating_dt$n[i])
}))
curve_dt$limb <- factor(curve_dt$limb, levels = limb_names)

ggplot() +
  geom_line(data = curve_dt, aes(stage, discharge, colour = limb), linewidth = 1.1) +
  geom_point(data = flow_dt, aes(stage, discharge, shape = extrapolated),
             colour = "grey20", size = 1.6, alpha = 0.6) +
  geom_vline(xintercept = rating_dt$upper_level[-4], linetype = "22", colour = "grey60") +
  scale_shape_manual(values = c(`FALSE` = 16, `TRUE` = 4),
                     labels = c(`FALSE` = "Inside rating", `TRUE` = "Extrapolated")) +
  labs(x = "Stage (m)", y = "Discharge (cumecs)", colour = "Limb", shape = NULL,
       title = "A four-limb rating applied to a stage record",
       subtitle = "Dashed lines mark the limb boundaries. Crosses were outside the rating.") +
  theme_minimal() +
  theme(legend.position = "bottom")


# The same event as a flow hydrograph beneath its stage record
long_dt <- data.table::melt(flow_dt, id.vars = "datetime",
                            measure.vars = c("stage", "discharge"),
                            variable.name = "series", value.name = "value")
long_dt$series <- factor(long_dt$series, c("stage", "discharge"),
                         c("Stage (m)", "Discharge (cumecs)"))
ggplot(long_dt, aes(datetime, value)) +
  geom_line(colour = "#00A33B", linewidth = 0.8) +
  facet_grid(series ~ ., scales = "free_y", switch = "y") +
  labs(x = NULL, y = NULL, title = "Stage converted to flow") +
  theme_minimal() +
  theme(strip.placement = "outside")


# A plain vector of stage values works too, and a fit from
# rate_optimise() can be used directly
apply_rating(my_fit, c(0.5, 1.5, 3.0))
#>    stage  discharge extrapolated         support
#>    <num>      <num>       <lgcl>          <char>
#> 1:   0.5  0.4154976        FALSE model_supported
#> 2:   1.5  4.3632457        FALSE model_supported
#> 3:   3.0 19.3162711        FALSE model_supported
gaugings <- station_gaugings
fit <- rate_optimise(gaugings$discharge_cms, gaugings$stage_m)
apply_rating(fit, quantile(gaugings$stage_m, c(0.25, 0.5, 0.75)))
#>    stage discharge extrapolated                support
#>    <num>     <num>       <lgcl>                 <char>
#> 1: 0.179 0.4909471        FALSE interpolation_observed
#> 2: 0.211 0.6250359        FALSE interpolation_observed
#> 3: 0.289 0.9919259        FALSE interpolation_observed
```
