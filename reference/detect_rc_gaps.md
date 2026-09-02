# Detect discharge gaps between rating-curve limbs

Scans every junction between consecutive limbs and measures the absolute
and relative discharge gap. A gap arises when the last discharge value
of one limb does not match the first discharge value of the next limb at
the shared breakpoint stage.

A shared breakpoint stage isn't guaranteed for an arbitrary `rc_dt` –
only for one built by
[`expand_rating_table()`](https://jonpayneea.github.io/reach.rate/reference/expand_rating_table.md)
from contiguous limbs. This distinguishes three kinds of junction: a
genuine **shared- stage discontinuity** (the case above, where a
discharge gap is calculated), a **stage gap** (the upper limb's first
stage is beyond the lower limb's last stage – no stage-discharge
coverage in between), and a **stage overlap** (the reverse). A discharge
difference between two limbs that don't actually share a stage isn't
comparable to one that does, so `gap_abs`/`gap_rel` are `NA` for the
latter two cases rather than a number computed across mismatched stages.

## Usage

``` r
detect_rc_gaps(
  rc_dt,
  stage_col = "stage",
  discharge_col = "discharge",
  limb_col = "limb",
  tol_abs = 0.5,
  tol_rel = 0.02,
  stage_tol = 1e-06
)
```

## Arguments

- rc_dt:

  A data.frame or data.table containing the rating curve. Rows should be
  ordered by stage (ascending) within each limb.

- stage_col:

  Character. Name of the stage (water level) column. Default `"stage"`.

- discharge_col:

  Character. Name of the discharge column. Default `"discharge"`.

- limb_col:

  Character or `NULL`. Name of the column that identifies each limb
  (integer or character values). If `NULL` or not present in `rc_dt`,
  limbs are auto-detected from monotonicity breaks in discharge. Default
  `"limb"`.

- tol_abs:

  Numeric. Absolute discharge tolerance (same units as `discharge_col`)
  below which a shared-stage gap is not flagged. Default `0.5`.

- tol_rel:

  Numeric. Relative discharge tolerance (fraction of the lower limb's
  end discharge) below which a shared-stage gap is not flagged. Default
  `0.02` (2%).

- stage_tol:

  Numeric. Two stages within this tolerance of each other are treated as
  "the same stage" for classifying a junction as shared-stage vs a stage
  gap/overlap. Default `1e-6`.

## Value

A `data.table` with one row per limb junction containing:

- junction:

  Junction index (1 = between limbs 1 and 2, etc.)

- limb_lower:

  Limb ID of the lower limb.

- limb_upper:

  Limb ID of the upper limb.

- stage_break:

  The lower limb's last stage, kept for backward compatibility; see
  `stage_lower_end`/`stage_upper_start` for both endpoints explicitly,
  which differ for a stage gap or overlap.

- stage_lower_end:

  The lower limb's last stage.

- stage_upper_start:

  The upper limb's first stage.

- junction_type:

  One of `"shared_stage"`, `"stage_gap"`, or `"stage_overlap"`.

- q_lower_end:

  Discharge at the end of the lower limb.

- q_upper_start:

  Discharge at the start of the upper limb.

- gap_abs:

  Absolute gap: `q_upper_start - q_lower_end`. `NA` unless
  `junction_type == "shared_stage"`.

- gap_rel:

  Relative gap: `gap_abs / q_lower_end`. `NA` unless
  `junction_type == "shared_stage"`, or if `q_lower_end` is too close to
  zero to divide by.

- gap_flagged:

  Logical; `TRUE` if a shared-stage gap exceeds `tol_abs` or `tol_rel`,
  or if the junction is a stage gap or overlap at all (both are worth
  flagging regardless of tolerance).

Returns `NULL` invisibly when fewer than two limbs are detected.

## Examples

``` r
stage_seq1 <- seq(8.0, 10.0, by = 0.2)
limb1_dt <- data.table::data.table(
  stage = stage_seq1,
  discharge = 12 * (stage_seq1 - 8.0)^1.65,
  limb = 1L
)
stage_seq2 <- seq(10.0, 11.5, by = 0.2)
limb2_dt <- data.table::data.table(
  stage = stage_seq2,
  discharge = (tail(limb1_dt$discharge, 1) - 5) + 30 * (stage_seq2 - 10.0)^1.4,
  limb = 2L
)
rc_raw_dt <- data.table::rbindlist(list(limb1_dt, limb2_dt))
detect_rc_gaps(rc_raw_dt)
#> INFO [2026-09-02 08:18:26] Checked 1 junction(s): 1 gap(s) flagged.
#>    junction limb_lower limb_upper stage_break stage_lower_end stage_upper_start
#>       <int>     <char>     <char>       <num>           <num>             <num>
#> 1:        1          1          2          10              10                10
#>    junction_type q_lower_end q_upper_start gap_abs    gap_rel gap_flagged
#>           <char>       <num>         <num>   <num>      <num>      <lgcl>
#> 1:  shared_stage    37.66004      32.66004      -5 -0.1327667        TRUE
```
