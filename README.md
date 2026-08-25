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

```r
library(reach.rate)

fit <- rate_optimise(discharge_cms, stage_m, control = c(1.6, 2.2))
fit@limbs[, .(limb, C, a, n, rmse_cms, r_squared)]

rating_plot(fit)
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
