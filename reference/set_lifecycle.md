# Record a change to a rating's lifecycle

A rating starts as a `"draft"`. This is how a person moves it on, and it
is the only way: nothing in the package changes a lifecycle by itself,
and nothing sets `"approved"` except this function called by a named
person. Each change records **who** made it, **when** and **why**, in
the rating's provenance and as a step in
[`rating_history()`](https://jonpayneea.github.io/reach.rate/reference/rating_history.md).
The earlier version is kept, so the rating can be checked against what
it was.

The states and where each may go next:

|  |  |
|----|----|
| From | May go to |
| `draft` | `under_review`, `withdrawn` |
| `under_review` | `approved`, `draft` (returned for rework), `withdrawn` |
| `approved` | `under_review` (re-review), `superseded`, `withdrawn` |
| `superseded`, `withdrawn` | nowhere: make a new rating |

**Approval has its own conditions.** It must come from `under_review`,
so no rating is approved without having been put up for review. It is
refused for a rating that fails its own validity checks
([`rating_invariants()`](https://jonpayneea.github.io/reach.rate/reference/rating_invariants.md)).
The person who put a rating under review **may approve it too**, which
is the default, but that is written into the reason so that a reader of
the record can see it. Set `allow_self_approval = FALSE` to require a
second person.

Amending a rating (setting its operational limits, aligning its limbs)
makes a new draft, because what was reviewed is no longer what exists.
That shows in
[`rating_history()`](https://jonpayneea.github.io/reach.rate/reference/rating_history.md);
the records here stay.

## Usage

``` r
set_lifecycle(x, to, by, reason, at = Sys.time(), allow_self_approval = TRUE)
```

## Arguments

- x:

  A
  [FlodeRating](https://jonpayneea.github.io/reach.rate/reference/FlodeRating.md)
  or
  [FlodeSegmentedRating](https://jonpayneea.github.io/reach.rate/reference/FlodeSegmentedRating.md).
  A
  [FlodeRatingTable](https://jonpayneea.github.io/reach.rate/reference/FlodeRatingTable.md)
  has nowhere to keep who, when and why, and is refused.

- to:

  The lifecycle to move to: one of `"draft"`, `"under_review"`,
  `"approved"`, `"superseded"`, `"withdrawn"`.

- by:

  Character. Who is making the change. A name, not a role.

- reason:

  Character. Why. Required for every change.

- at:

  The time of the change. Default now.

- allow_self_approval:

  Logical. If `TRUE` (default), the person who put a rating under review
  may also approve it, and the record says so. If `FALSE`, a second
  person must approve. Names are compared ignoring case and surrounding
  spaces.

## Value

A new rating with its lifecycle changed. The original is not altered.

## See also

[`rating_lifecycle()`](https://jonpayneea.github.io/reach.rate/reference/rating_lifecycle.md)
for the record,
[`rating_history()`](https://jonpayneea.github.io/reach.rate/reference/rating_history.md),
[`rating_invariants()`](https://jonpayneea.github.io/reach.rate/reference/rating_invariants.md).

## Examples

``` r
set.seed(1)
stage <- seq(0.3, 3, length.out = 25)
gaugings <- data.frame(stage_m = stage,
                       discharge_cms = 3 * stage^1.6 * exp(rnorm(25, sd = 0.03)))
fit <- fit_rating(gaugings, quiet = TRUE)

reviewed <- set_lifecycle(fit, "under_review", by = "A. Analyst",
                          reason = "Fitted from the 2024 gaugings; ready for review")
approved <- set_lifecycle(reviewed, "approved", by = "B. Reviewer",
                          reason = "Checked the assessment and the sensitivity tests")
rating_lifecycle(approved)[, c("from", "to", "by")]
#>            from           to          by
#>          <char>       <char>      <char>
#> 1:        draft under_review  A. Analyst
#> 2: under_review     approved B. Reviewer
rating_history(approved)[, c("step", "lifecycle", "note")]
#>     step    lifecycle
#>    <int>       <char>
#> 1:     1        draft
#> 2:     2 under_review
#> 3:     3     approved
#>                                                                                                                   note
#>                                                                                                                 <char>
#> 1:                                                                                                                <NA>
#> 2:      lifecycle: draft to under_review by A. Analyst on 2026-11-27 (Fitted from the 2024 gaugings; ready for review)
#> 3: lifecycle: under_review to approved by B. Reviewer on 2026-11-27 (Checked the assessment and the sensitivity tests)
```
