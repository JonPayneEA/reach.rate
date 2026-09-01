# Abstract base class for a fitted rating (S7)

Properties and validation shared by
[FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md)
and
[FlodeSegmentedRating](https://jonpayneea.github.io/reach.rate/reference/FlodeSegmentedRating.md):
the gaugings a fit was built from, multi-start fitting bookkeeping (if
any), a status flag distinguishing an independently-fitted result from a
post-fit amendment, a provenance list for auditability (fitting method,
controls, bounds, tool version), and a `previous` chain for amendments
produced from an earlier fit of the same class. Never constructed
directly – see
[FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md)
and
[FlodeSegmentedRating](https://jonpayneea.github.io/reach.rate/reference/FlodeSegmentedRating.md).

## Usage

``` r
FlodeRatingBase(
  gaugings = (structure(function (.data) 

    stop2(sprintf("S3 class <%s> doesn't have a constructor.", "data.table"), call =
    NULL), class = "S7_constructor"))(),
  fit_starts = NULL,
  status = "independently_fitted",
  provenance = list(),
  previous = NULL
)
```

## Arguments

- gaugings:

  Data.table with `discharge_cms` and `stage_m` columns – the gaugings
  the fit was built from. May optionally include a `gauging_datetime`
  column (`Date` or `POSIXct`) recording when each spot gauging was
  taken. Nothing in the package currently reads this column – it's
  groundwork for a future age-aware fitting option (see issue \#9). A
  gauging's own measurement method (current- meter, ADCP, salt-dilution,
  index-velocity, ...) is not currently recorded either – every gauging
  is treated identically regardless of source.

- fit_starts:

  Data.table of multi-start fitting attempts, or `NULL` if the fit
  wasn't produced with `multi_start = TRUE`.

- status:

  Character. One of `"independently_fitted"`, `"post_fit_aligned"`, or
  `"constrained_refit"`.

- provenance:

  List recording how the fit was made (fitting method, controls, bounds,
  tool version).

- previous:

  The exact pre-amendment fit this was built from (same class as this
  instance), or `NULL` (default) for a fit with no such history – an
  independently-fitted result, for instance. Mirrors
  [FlodeRatingTable](https://jonpayneea.github.io/reach.rate/reference/FlodeRatingTable.md)'s
  own `@previous` audit chain.
