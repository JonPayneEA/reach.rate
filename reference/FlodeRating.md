# A fitted multi-limb rating curve (S7)

The result of
[`rate_optimise()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise.md)
(or
[`rate_optimise_constrained()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise_constrained.md)):
one row per limb in `@limbs` (bounds, coefficients `C`/`a`/`n`, fit
diagnostics, and – when produced by
[`rate_optimise_constrained()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise_constrained.md)
– alignment provenance), the raw gaugings in `@gaugings`, and bootstrap
draws in `@bootstrap` when `rate_optimise(..., n_boot = )` was used.

## Usage

``` r
FlodeRating(
  gaugings = (structure(function (.data) 

    stop2(sprintf("S3 class <%s> doesn't have a constructor.", "data.table"), call =
    NULL), class = "S7_constructor"))(),
  fit_starts = NULL,
  status = "independently_fitted",
  provenance = list(),
  previous = NULL,
  limbs = (structure(function (.data) 

    stop2(sprintf("S3 class <%s> doesn't have a constructor.", "data.table"), call =
    NULL), class = "S7_constructor"))(),
  bootstrap = NULL
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

  The exact pre-amendment `FlodeRating` this was built from (e.g. by
  [`align_limb_equations()`](https://jonpayneea.github.io/reach.rate/reference/align_limb_equations.md)/[`align_limb_boundaries()`](https://jonpayneea.github.io/reach.rate/reference/align_limb_boundaries.md)),
  or `NULL` (default) for an independently-fitted result.

- limbs:

  Data.table, one row per limb: bounds, coefficients `C`/`a`/`n`, and
  fit diagnostics.

- bootstrap:

  Data.table of per-draw bootstrap coefficients, or `NULL` if the fit
  wasn't produced with `n_boot > 0`.
