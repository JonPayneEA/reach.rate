# Column names used inside data.table's non-standard evaluation
# (`dt[, x := y]`, `dt[x > 0]`, `.()`) look like undefined globals to
# R CMD check's code analysis, which cannot see that they are resolved
# against the table's columns at run time. Declaring them here silences
# that NOTE without hiding genuine undefined names elsewhere: the list is
# exactly the set check reported, plus `selected` (suggest_breakpoints()).
# Add to it when new data.table code introduces a column name.
utils::globalVariables(c(
  ".", ".a", ".limb", ".row_id", ".stage_value", "C", "C_new", "C_old", "a",
  "a_new", "a_old", "above_bankfull", "age_weight", "aligned", "band",
  "cooks_distance", "depth", "discharge", "discharge_", "discharge_cms",
  "discharge_diff", "discharge_draw", "discharge_lower", "discharge_mean",
  "discharge_new", "discharge_old", "discharge_pct_diff", "discharge_scaled",
  "discharge_upper", "distance_m", "doubtful", "draw", "effective_from",
  "effective_to", "elevation_m", "elevation_maod", "extrapolated",
  "extrapolates_above_range", "extrapolates_below_range", "fit_status",
  "fitted_cms", "gap_flagged", "gauged_max_stage_m", "gauged_min_stage_m",
  "i.C", "i.a", "i.n", "i.n_obs", "improvement", "influential", "junction",
  "label", "leverage", "limb", "limb_", "limb_f", "limb_width_m",
  "lower_level", "lower_stage_m", "lower_unsupported_frac",
  "lower_unsupported_m", "n", "n_new", "n_obs", "n_old", "rating",
  "residual_cms", "score", "selected", "stage_", "stage_break", "stage_m",
  "stage_maod", "success", "upper_level", "upper_stage_m",
  "upper_unsupported_frac", "upper_unsupported_m", "x", "y", "y_junction"
))
