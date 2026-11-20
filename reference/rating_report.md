# Write a review report for a rating

Renders one self-contained HTML page that a reviewer can read without R:
the rating's status and lifecycle, its equations and plot, the evidence
and what was left out, every assessment check that did not pass with
what to look at, what each stage range rests on, how the rating was made
and what has been done to it since, and a short list of questions for
the reviewer.

The report is drawn from the stored objects and never refits anything,
so the same rating and assessment give the same report whether they come
from the live session or from a folder made by
[`export_rating()`](https://jonpayneea.github.io/reach.rate/reference/export_rating.md).
It does not approve a rating and never changes its lifecycle. It says so
on its first page.

Needs the `rmarkdown` and `knitr` packages and pandoc, which are
suggested and not required.

## Usage

``` r
rating_report(
  x,
  assessment = NULL,
  path = "rating_report.html",
  title = "Rating report",
  overwrite = FALSE
)
```

## Arguments

- x:

  A
  [FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md),
  [FlodeSegmentedRating](https://jonpayneea.github.io/reach.rate/reference/FlodeSegmentedRating.md)
  or
  [FlodeRatingTable](https://jonpayneea.github.io/reach.rate/reference/FlodeRatingTable.md),
  or the path to a folder made by
  [`export_rating()`](https://jonpayneea.github.io/reach.rate/reference/export_rating.md).

- assessment:

  Optional. A
  [FlodeAssessment](https://jonpayneea.github.io/reach.rate/reference/FlodeAssessment.md)
  from
  [`assess_rating()`](https://jonpayneea.github.io/reach.rate/reference/assess_rating.md).
  If `x` is a folder and this is `NULL`, the folder's own assessment is
  used.

- path:

  Character. The HTML file to write. Default `"rating_report.html"`.

- title:

  Character. The report's title.

- overwrite:

  Logical. If `FALSE` (default), an existing file is left alone and an
  error is raised.

## Value

Invisibly, the full path of the file written.

## See also

[`export_rating()`](https://jonpayneea.github.io/reach.rate/reference/export_rating.md),
[`import_rating()`](https://jonpayneea.github.io/reach.rate/reference/import_rating.md),
[`assess_rating()`](https://jonpayneea.github.io/reach.rate/reference/assess_rating.md).

## Examples

``` r
# \donttest{
if (requireNamespace("rmarkdown", quietly = TRUE) && rmarkdown::pandoc_available()) {
  set.seed(1)
  stage <- seq(0.3, 3, length.out = 25)
  gaugings <- data.frame(stage_m = stage,
                         discharge_cms = 3 * stage^1.6 * exp(rnorm(25, sd = 0.03)))
  fit <- fit_rating(gaugings, quiet = TRUE)
  assessment <- assess_rating(fit, reference_time = as.POSIXct("2025-01-01", tz = "UTC"))
  out <- rating_report(fit, assessment, path = file.path(tempdir(), "rating_report.html"))
  file.exists(out)
}
#> [1] TRUE
# }
```
