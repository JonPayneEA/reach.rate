# Write a rating and its assessment to a folder for review

Saves everything a reviewer needs to check a rating without asking its
author: the rating itself, its assessment if you give one, plain tables
of the same content, and a manifest that lets
[`import_rating()`](https://jonpayneea.github.io/reach.rate/reference/import_rating.md)
confirm that nothing has changed since.

The folder holds:

- `rating.rds` and, if given, `assessment.rds`. These are the record.
  [`import_rating()`](https://jonpayneea.github.io/reach.rate/reference/import_rating.md)
  reads them back exactly.

- `limbs.csv`, `coefficients.csv`, `evidence.csv`, `history.csv`,
  `support.csv`, `lifecycle.csv` (only if someone has recorded a
  lifecycle change with
  [`set_lifecycle()`](https://jonpayneea.github.io/reach.rate/reference/set_lifecycle.md))
  and, with an assessment, `assessment_checks.csv`. The same content as
  plain tables, for people, spreadsheets and other software. A column
  that holds a list (evidence `metadata`) is left out of the CSV and
  stays in the `.rds`. A table that does not apply to this class (a
  [FlodeRatingTable](https://jonpayneea.github.io/reach.rate/reference/FlodeRatingTable.md)
  holds no gaugings) is not written, and the README says so.

- `README.txt`, which says what the folder is, when and with what
  version it was made, and the rating's lifecycle.

- `manifest.csv`, which lists every other file with its size and MD5
  checksum. The checksum detects accidental damage and untracked edits.
  It is not a defence against someone who edits the manifest as well.

Exporting does not change the rating. In particular it never moves the
lifecycle on: a draft is exported as a draft. Approval is a decision for
a person.

## Usage

``` r
export_rating(rating, assessment = NULL, path, overwrite = FALSE)
```

## Arguments

- rating:

  A
  [FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md),
  [FlodeSegmentedRating](https://jonpayneea.github.io/reach.rate/reference/FlodeSegmentedRating.md)
  or
  [FlodeRatingTable](https://jonpayneea.github.io/reach.rate/reference/FlodeRatingTable.md).

- assessment:

  Optional. A
  [FlodeAssessment](https://jonpayneea.github.io/reach.rate/reference/FlodeAssessment.md)
  from
  [`assess_rating()`](https://jonpayneea.github.io/reach.rate/reference/assess_rating.md).

- path:

  Character. The folder to write. Created if absent.

- overwrite:

  Logical. If `FALSE` (default), a folder that already holds files from
  an earlier export is left alone and an error is raised. If `TRUE`,
  only the files this function writes are replaced; anything else in the
  folder is left where it is.

## Value

Invisibly, a list with `path` and `files`, a `data.table` with one row
per file written (`file`, `description`, `bytes`, `md5`).

## See also

[`import_rating()`](https://jonpayneea.github.io/reach.rate/reference/import_rating.md),
[`assess_rating()`](https://jonpayneea.github.io/reach.rate/reference/assess_rating.md),
[`fit_rating()`](https://jonpayneea.github.io/reach.rate/reference/fit_rating.md).

## Examples

``` r
set.seed(1)
stage <- seq(0.3, 3, length.out = 25)
gaugings <- data.frame(stage_m = stage,
                       discharge_cms = 3 * stage^1.6 * exp(rnorm(25, sd = 0.03)))
fit <- fit_rating(gaugings, quiet = TRUE)
assessment <- assess_rating(fit, reference_time = as.POSIXct("2025-01-01", tz = "UTC"))

folder <- file.path(tempdir(), "example_rating")
out <- export_rating(fit, assessment, path = folder)
out$files[, c("file", "bytes")]
#>                     file bytes
#>                   <char> <num>
#> 1:            rating.rds 12194
#> 2:        assessment.rds  6931
#> 3:             limbs.csv   100
#> 4:      coefficients.csv   220
#> 5:          evidence.csv  1531
#> 6:           history.csv    89
#> 7:           support.csv   460
#> 8: assessment_checks.csv  6516
#> 9:            README.txt  1549

# Read it back: the rating is the same object.
back <- import_rating(folder)
identical(apply_rating(back$rating, c(1, 2))$discharge,
          apply_rating(fit, c(1, 2))$discharge)
#> [1] TRUE
```
