# A fitted segmented rating curve, Hodson et al. (2024) parameterisation (S7)

The result of
[`rate_optimise_segmented()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise_segmented.md):
a single joint model rather than independent limbs, so `@coefficients`
is one row (`C`, `bp1..bpk`, `n1..nk`, diagnostics), not one row per
segment.

## Usage

``` r
FlodeSegmentedRating(
  gaugings = (structure(function (.data) 

    stop2(sprintf("S3 class <%s> doesn't have a constructor.", "data.table"), call =
    NULL), class = "S7_constructor"))(),
  fit_starts = NULL,
  status = "independently_fitted",
  provenance = list(),
  previous = NULL,
  coefficients = (structure(function (.data) 

    stop2(sprintf("S3 class <%s> doesn't have a constructor.", "data.table"), call =
    NULL), class = "S7_constructor"))(),
  n_segments = integer(0),
  estimate_breakpoints = logical(0)
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

  The exact pre-amendment `FlodeSegmentedRating` this was built from, or
  `NULL` (default) for an independently-fitted result. Nothing in the
  package currently produces an amended `FlodeSegmentedRating` – this
  exists for parity with
  [FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md).

- coefficients:

  Single-row data.table: `C`, `bp1..bpk`, `n1..nk`, and fit diagnostics.

- n_segments:

  Integer. Number of segments `k`.

- estimate_breakpoints:

  Logical. Whether the interior breakpoints were refit as free
  parameters (`TRUE`) or held fixed at `control` (`FALSE`).
