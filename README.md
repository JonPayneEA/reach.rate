# reach.rate

Tools for fitting, diagnosing, and applying hydrometric rating curves: multi-limb power-law fitting by nonlinear least squares, junction-gap detection and resolution between independently-fitted limbs, a segmented joint-model alternative (Hodson et al. 2024), bootstrap coefficient uncertainty, versioned ratings, and rating-amendment comparison.

Fitted ratings are represented as [S7](https://rconsortium.github.io/S7/) classes (`FlodeRating`, `FlodeSegmentedRating`, `FlodeRatingTable`) that carry their own gaugings, fitting bookkeeping, and provenance, so a rating is never separated from the data and assumptions that produced it.

## Installation

This package is not on CRAN. Install the development version from GitHub:

```r
# install.packages("remotes")
remotes::install_github("JonPayneEA/reach.rate", build_vignettes = TRUE)
```

## Getting started

A complete, runnable example on synthetic data -- a three-limb rating station, gauged independently limb by limb (as real stations usually are), which is exactly the situation that produces the junction gaps `detect_rc_gaps()` exists to catch:

```r
library(reach.rate)
library(data.table)

# Pseudo gaugings for a three-limb rating station
set.seed(42)
stage_m <- seq(0.5, 3.5, by = 0.03)
true_limb <- cut(
  stage_m,
  breaks = c(0.5, 1.6, 2.2, 3.5),
  labels = FALSE, include.lowest = TRUE
)
true_coefs <- data.frame(C = c(3, 6, 10), a = c(0, 0.1, 0.2), n = c(1.4, 1.6, 1.8))
discharge_cms <- true_coefs$C[true_limb] *
  (stage_m + true_coefs$a[true_limb])^true_coefs$n[true_limb] +
  rnorm(length(stage_m), sd = 0.05)

# Fit a multi-limb power-law rating curve: Q = C(H + a)^n per limb
fit <- rate_optimise(discharge_cms, stage_m, control = c(1.6, 2.2))
fit@limbs[, .(limb, C, a, n, rmse_cms, r_squared)]

rating_plot(fit)

# Independently-fitted limbs rarely meet exactly at their junctions --
# detect the resulting discharge gap
rating_table <- as_rating_table(fit)
rc_dt <- expand_rating_table(rating_table, step = 0.01)
detect_rc_gaps(rc_dt)

# ...and close it, either at the table level or in the equations themselves
rc_fixed_dt <- resolve_rc_gaps(rc_dt)
aligned_table <- align_limb_equations(rating_table)

# Apply the (aligned) rating to a stage record to get a discharge record
hydrograph <- data.frame(stage = seq(0.8, 3.2, length.out = 10))
apply_rating(aligned_table, hydrograph)
```

For the full walkthrough -- theory, every function, and the reasoning behind the toolkit's design choices -- see:

```r
vignette("rating_curves_guide", package = "reach.rate")
```

or run the linear, section-by-section script at:

```r
system.file("examples", "walkthrough.R", package = "reach.rate")
```

## Development

This package was assembled from a set of standalone box modules; see `NEWS.md` for a summary and each `R/` file's header comment for the file-by-file conversion notes. If you have R and roxygen2 available locally, regenerate `NAMESPACE` and `man/` from the roxygen comments already in `R/`:

```r
devtools::document()
devtools::test()
devtools::check()
```
