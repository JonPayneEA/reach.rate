# Read back a rating written by export_rating()

Reads a folder made by
[`export_rating()`](https://jonpayneea.github.io/reach.rate/reference/export_rating.md)
and returns the rating and, if one was exported, its assessment. Before
it reads anything, it checks every file against the folder's
`manifest.csv`, so a file that was damaged, truncated or edited
afterwards is reported by name and not trusted.

The rating that comes back is the one that went in: the same
coefficients, evidence, history, provenance and lifecycle, equal in
every value. (It is not
[`identical()`](https://rdrr.io/r/base/identical.html) in the
byte-for-byte sense, which no R object is after being written and read:
`data.table` keeps internal pointers that differ.) A rating saved under
an older schema version is migrated if a migration exists, and refused
with the reason if not. A rating saved under a newer one is refused:
update the package.

## Usage

``` r
import_rating(path, verify = TRUE)
```

## Arguments

- path:

  Character. A folder made by
  [`export_rating()`](https://jonpayneea.github.io/reach.rate/reference/export_rating.md).

- verify:

  Logical. If `TRUE` (default), check every file against the manifest
  first. Switching it off is for the case where you have already decided
  the folder is trusted and the manifest is lost.

## Value

A list with `rating`, `assessment` (`NULL` if none was exported) and
`manifest`, the checksum table.

## See also

[`export_rating()`](https://jonpayneea.github.io/reach.rate/reference/export_rating.md).

## Examples

``` r
set.seed(1)
stage <- seq(0.3, 3, length.out = 25)
gaugings <- data.frame(stage_m = stage,
                       discharge_cms = 3 * stage^1.6 * exp(rnorm(25, sd = 0.03)))
fit <- fit_rating(gaugings, quiet = TRUE)
folder <- file.path(tempdir(), "example_import")
export_rating(fit, path = folder)

back <- import_rating(folder)
rating_limbs(back$rating)
#>     limb lower_stage_m upper_stage_m       C          a        n
#>    <int>         <num>         <num>   <num>      <num>    <num>
#> 1:     1           0.3             3 3.08768 0.01234489 1.581943
```
