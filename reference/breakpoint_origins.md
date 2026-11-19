# Where a breakpoint can come from

The controlled vocabulary for the origin of a breakpoint, recorded by
[`fit_rating()`](https://jonpayneea.github.io/reach.rate/reference/fit_rating.md).
A breakpoint is a modelling decision, and what it rests on matters to
anyone who reviews the rating:

- `field_evidence`: observed at the site, for example a change of
  control seen during a gauging visit;

- `cross_section`: read from a surveyed cross-section (bankfull, a
  change in channel shape);

- `structure_geometry`: from the geometry of a structure (a weir crest,
  an overtopping level);

- `user_judgement`: the analyst's decision, without a recorded basis;

- `statistical_candidate`: put forward by
  [`suggest_breakpoints()`](https://jonpayneea.github.io/reach.rate/reference/suggest_breakpoints.md)
  and not otherwise supported;

- `existing_rating`: carried over from a rating already in use;

- `other`.

## Usage

``` r
breakpoint_origins()
```

## Value

A character vector.

## See also

[`fit_rating()`](https://jonpayneea.github.io/reach.rate/reference/fit_rating.md),
[`suggest_breakpoints()`](https://jonpayneea.github.io/reach.rate/reference/suggest_breakpoints.md)

## Examples

``` r
breakpoint_origins()
#> [1] "field_evidence"        "cross_section"         "structure_geometry"   
#> [4] "user_judgement"        "statistical_candidate" "existing_rating"      
#> [7] "other"                
```
