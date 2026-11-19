# ============================================================ #
# Tool:         assess_rating
# Description:  Assess a fitted rating across six domains: data, numerical,
#               statistical, hydraulic, operational and provenance. Returns
#               a FlodeAssessment (tranche B2), built on validate_gaugings()
#               (A6) and rating_invariants() (A8). There is no summary
#               score: each check says what it found and what to do.
# Author:       Jonathan Payne
# Created:      2026-11-18
# Tier:         3
# Inputs:       A FlodeRating, FlodeSegmentedRating or FlodeRatingTable.
# Outputs:      A FlodeAssessment.
# Dependencies: data.table, stats
# ============================================================ #

#' @include flode_assessment.R validate_gaugings.R invariants.R fit_rating.R
NULL

# One row per gauging used, with the fitted discharge and the relative
# residual, for either kind of fit. `limb` is the limb the fitter assigned
# (independent fit) or the segment the stage falls in (segmented fit).
# NULL when the rating holds no gaugings.
.rating_frame <- function(x) {
  if (S7_inherits(x, FlodeRatingTable)) return(NULL)
  g <- as.data.table(x@gaugings)
  g <- g[is.finite(stage_m) & is.finite(discharge_cms)]
  if (!nrow(g)) return(NULL)
  if (S7_inherits(x, FlodeRating)) {
    limbs <- x@limbs
    idx <- match(g$limb, limbs$limb)
    if (anyNA(idx)) idx <- findInterval(g$stage_m, c(limbs$lower_stage_m, max(limbs$upper_stage_m)), rightmost.closed = TRUE)
    pred <- .eval_limb(limbs$C[idx], limbs$a[idx], limbs$n[idx], g$stage_m)
    limb <- as.integer(limbs$limb[idx])
  } else {
    co <- as.list(x@coefficients)
    k <- as.integer(x@n_segments)
    pred <- .segmented_predict_cms(co, k, g$stage_m)
    bp <- unlist(co[sprintf("bp%d", seq_len(k))])
    limb <- if (k == 1L) rep(1L, nrow(g)) else pmax(1L, findInterval(g$stage_m, bp[-1L], left.open = TRUE) + 1L)
  }
  data.table(
    evidence_id = g$evidence_id, stage_m = g$stage_m, observed = g$discharge_cms, fitted = pred,
    relative_residual = ifelse(pred > 0, g$discharge_cms / pred - 1, NA_real_), limb = limb
  )
}

.pct <- function(x) sprintf("%.1f%%", 100 * x)

# Leverage and Cook's distance for each gauging of an independent fit, on the
# scale the fit minimised: log discharge for the relative objective,
# discharge for the absolute one, with any age weights applied. (The
# diagnostic flag_influential_gaugings() works on absolute residuals, which
# grow with flow, so it always flags the highest gauging of a relative-error
# fit.) A limb with no more gaugings than parameters has no influence to
# compute. Returns NULL if it cannot be computed.
.fit_scale_influence <- function(x, frame) {
  objective <- if (is.null(x@provenance$objective)) "absolute" else x@provenance$objective
  g <- as.data.table(x@gaugings)
  w_all <- if ("age_weight" %in% names(g)) g$age_weight[match(frame$evidence_id, g$evidence_id)] else rep(1, nrow(frame))
  out <- data.table(evidence_id = frame$evidence_id, stage_m = frame$stage_m,
                    leverage = NA_real_, cooks_distance = NA_real_)
  for (lb in unique(frame$limb)) {
    li <- match(lb, x@limbs$limb)
    C <- x@limbs$C[li]; a <- x@limbs$a[li]; n <- x@limbs$n[li]
    rows <- which(frame$limb == lb)
    d <- frame$stage_m[rows] - a
    keep <- d > 0 & frame$observed[rows] > 0 & frame$fitted[rows] > 0
    rows <- rows[keep]; d <- d[keep]
    p <- 3L
    if (length(rows) <= p) next
    if (objective == "relative") {
      J <- cbind(1 / C, -n / d, log(d))
      e <- log(frame$observed[rows] / frame$fitted[rows])
    } else {
      J <- cbind(d^n, -C * n * d^(n - 1), C * d^n * log(d))
      e <- frame$observed[rows] - frame$fitted[rows]
    }
    sw <- sqrt(w_all[rows])
    J <- J * sw
    e <- e * sw
    inv <- tryCatch(solve(crossprod(J)), error = function(err) NULL)
    if (is.null(inv)) next
    hat <- rowSums((J %*% inv) * J)
    s2 <- sum(e^2) / (length(rows) - p)
    cooks <- if (s2 > 0) (hat / (p * (1 - hat)^2)) * (e^2 / s2) else rep(0, length(rows))
    set(out, rows, "leverage", hat)
    set(out, rows, "cooks_distance", cooks)
  }
  out
}

#' Assess a fitted rating
#'
#' @description
#' Looks at a rating from six sides and returns what it found as a
#' [FlodeAssessment]. It does not give a score, a grade or a verdict. Each
#' check states what it measured, whether that passed, and what to look at
#' next, so that a reviewer can see the reasons and not only an answer. A
#' rating that passes every check is not thereby approved: approval is a
#' decision for a person.
#'
#' The six domains, and the checks in each:
#'
#' * **data**: the checks of [validate_gaugings()] run on the evidence the
#'   rating used (missing or non-finite values, negative or zero discharge,
#'   duplicates, inversions, outliers, gaps in stage coverage, thin support at
#'   the top, few gaugings, no recent gauging, excluded rows, assumed times);
#' * **numerical**: the technical checks of [rating_invariants()] (finite
#'   coefficients, ordered limbs, monotonic discharge, a consistent inverse,
#'   interval order, bounds), and `convergence`;
#' * **statistical**: `residual_bias`, `residual_spread` and `residual_trend`
#'   per limb, `limb_support`, `parameter_identifiability`,
#'   `multi_start_agreement`, `bound_hits` and `influential_gaugings`;
#' * **hydraulic**: whether the exponents and zero-flow stage are physically
#'   plausible, and the hydrometric checks of [rating_invariants()] (gaps,
#'   steps at junctions, a limb that starts below its zero-flow stage);
#' * **operational**: whether the range it may be applied over has been
#'   stated, how far that goes beyond the gauged range, and whether the rating
#'   has been changed since it was fitted;
#' * **provenance**: whether the evidence has a recorded source and ids, how
#'   the fit was made and by what version, and whether its assumptions are
#'   written down.
#'
#' Independent and segmented fits are assessed with the same checks. A check
#' that cannot be computed for one of them, or for a rating that holds only
#' equations, is `not_assessed` and says why, never `pass`.
#'
#' @param x A [FlodeRating], [FlodeSegmentedRating] or [FlodeRatingTable].
#' @param bias_tol Number. A limb whose median relative residual is further
#'   from zero than this is reported. Default 0.05 (5%).
#' @param spread_tol Number. A limb whose relative residual spread (the
#'   interquartile range divided by 1.349) exceeds this is reported. Default
#'   0.15.
#' @param trend_rho Number. A limb whose relative residuals have a rank
#'   correlation with stage larger than this in absolute value, over at least
#'   8 gaugings, is reported as misfitting systematically. Default 0.6.
#' @param min_limb_gaugings Integer. A limb with fewer gaugings is reported.
#'   Default 5.
#' @param n_range Numeric `c(lower, upper)`. A limb exponent outside this
#'   range is reported as hydraulically unusual. Default `c(1, 3.5)`: roughly
#'   from a wide channel control to a steep V-notch or compound section.
#' @param zero_flow_margin Number. A zero-flow stage `a` further below the
#'   lowest gauging than this multiple of the gauged stage range is reported.
#'   Default 1.
#' @param extrapolation_tol Number. Operational limits that extend beyond the
#'   gauged range by more than this fraction of that range are reported.
#'   Default 0.2.
#' @param cooks_warn Number. A gauging whose Cook's distance exceeds this is
#'   reported as strongly influential. Default 1. The diagnostic
#'   [flag_influential_gaugings()] uses the lower, usual 4/n rule.
#' @param continuity_tol Number. Passed to [rating_invariants()]. Default
#'   0.01.
#' @param reference_time The time recency of gaugings is measured from, as in
#'   [validate_gaugings()]. Default `Sys.time()`; set it to make a result
#'   reproducible.
#' @param ... Further thresholds for [validate_gaugings()].
#'
#' @return A [FlodeAssessment] with subject `"rating"`. Its overall status
#'   (see [assessment_status()]) is a status, never a score. `print()` lists
#'   what did not pass and `plot()` draws every check.
#'
#' @seealso [validate_gaugings()], [rating_invariants()], [FlodeAssessment],
#'   [fit_rating()]
#'
#' @examples
#' set.seed(1)
#' gaugings <- data.frame(stage_m = round(seq(0.4, 3, length.out = 24), 3))
#' gaugings$discharge_cms <- round(3.2 * gaugings$stage_m^1.6 * exp(rnorm(24, sd = 0.03)), 3)
#' fit <- fit_rating(gaugings, quiet = TRUE)
#' assessment <- assess_rating(fit, reference_time = as.POSIXct("2026-01-01", tz = "UTC"))
#' assessment
#' assessment_checks(assessment)[status != "pass", .(domain, check_id, status)]
#' plot(assessment)
#'
#' @export
assess_rating <- function(x, bias_tol = 0.05, spread_tol = 0.15, trend_rho = 0.6, min_limb_gaugings = 5L,
                          n_range = c(1, 3.5), zero_flow_margin = 1, extrapolation_tol = 0.2,
                          cooks_warn = 1, continuity_tol = 0.01, reference_time = Sys.time(), ...) {
  if (!(S7_inherits(x, FlodeRatingBase) || S7_inherits(x, FlodeRatingTable))) {
    stop("assess_rating(): x must be a FlodeRating, FlodeSegmentedRating or FlodeRatingTable, not ",
         class(x)[1L], call. = FALSE)
  }
  num <- function(v, name, lo = 0) {
    if (!is.numeric(v) || length(v) != 1L || is.na(v) || v < lo) {
      stop(sprintf("assess_rating(): %s must be a single number of at least %s", name, lo), call. = FALSE)
    }
  }
  num(bias_tol, "bias_tol"); num(spread_tol, "spread_tol"); num(trend_rho, "trend_rho")
  num(min_limb_gaugings, "min_limb_gaugings"); num(zero_flow_margin, "zero_flow_margin")
  num(extrapolation_tol, "extrapolation_tol"); num(continuity_tol, "continuity_tol"); num(cooks_warn, "cooks_warn")
  if (!is.numeric(n_range) || length(n_range) != 2L || any(!is.finite(n_range)) || n_range[1L] >= n_range[2L]) {
    stop("assess_rating(): n_range must be c(lower, upper) with lower below upper", call. = FALSE)
  }

  rows <- list()
  add <- function(check_id, domain, status, message, recommendation = NA_character_,
                  affected = character(0), stage = numeric(0), severity = "warning") {
    rows[[length(rows) + 1L]] <<- .check_row(check_id, domain, status, message, recommendation,
                                              affected, stage, severity = severity)
  }
  ok <- function(bad) if (length(bad)) "warning" else "pass"
  na_check <- function(check_id, domain, message, severity = "warning") {
    add(check_id, domain, "not_assessed", message, severity = severity)
  }

  is_fit <- !S7_inherits(x, FlodeRatingTable)
  is_independent <- S7_inherits(x, FlodeRating)
  frame <- .rating_frame(x)
  no_data_msg <- "A rating that holds only equations has no gaugings to assess."

  # ---- data: validate_gaugings() on the evidence the rating used ------------------------
  if (is_fit) {
    v <- assessment_checks(validate_gaugings(x@gaugings, reference_time = reference_time, ...))
    v[, domain := "data"]
    rows <- c(rows, lapply(seq_len(nrow(v)), function(i) {
      .check_row(v$check_id[i], "data", v$status[i], v$message[i], v$recommendation[i],
                 v$affected_evidence[[i]], c(v$affected_stage_min_m[i], v$affected_stage_max_m[i]),
                 severity = v$severity[i])
    }))
  } else {
    na_check("evidence_available", "data", no_data_msg)
  }

  # ---- numerical and hydraulic: the invariants, and convergence ---------------------------
  inv <- assessment_checks(rating_invariants(x, continuity_tol = continuity_tol))
  for (i in seq_len(nrow(inv))) {
    technical <- inv$domain[i] == "technical"
    add(inv$check_id[i], if (technical) "numerical" else "hydraulic", inv$status[i], inv$message[i],
        inv$recommendation[i], severity = inv$severity[i])
  }
  conv_col <- if (is_independent) x@limbs else if (is_fit) x@coefficients else NULL
  if (!is.null(conv_col) && "converged" %in% names(conv_col) && !all(is.na(conv_col$converged))) {
    # Only a recorded failure counts. A limb with no record (amended since it
    # was fitted) is not known to have failed.
    bad <- which(conv_col$converged %in% FALSE)
    unknown <- which(is.na(conv_col$converged))
    add("convergence", "numerical", if (length(bad)) "warning" else if (length(unknown)) "not_assessed" else "pass",
        if (length(bad)) sprintf("%s: the optimiser did not converge (%s).",
                                 if (is_independent) .limbs_text(bad) else "The fit",
                                 sub("\\s+$", "", conv_col$convergence_message[bad[1L]]))
        else if (length(unknown)) sprintf("%s: no optimiser record, because the limb was amended after it was fitted.", .limbs_text(unknown))
        else "The optimiser reported convergence.",
        "A fit that stopped at its limit may still be good, but check its residuals and try other starting values.")
  } else {
    na_check("convergence", "numerical",
             if (is_fit) "No optimiser record: the rating was amended after it was fitted."
             else "A rating that holds only equations has no optimiser record.")
  }

  # ---- statistical ------------------------------------------------------------------------------
  per_limb <- function(fun, min_n) {
    if (is.null(frame)) return(NULL)
    res <- frame[!is.na(relative_residual), .(value = fun(relative_residual, stage_m), n = .N), by = limb]
    res[n >= min_n]
  }
  if (is.null(frame)) {
    for (id in c("residual_bias", "residual_spread", "residual_trend", "limb_support")) na_check(id, "statistical", no_data_msg)
  } else {
    b <- per_limb(function(r, s) stats::median(r), 3L)
    bad <- b[abs(value) > bias_tol]
    add("residual_bias", "statistical", if (!nrow(b)) "not_assessed" else ok(bad$limb),
        if (!nrow(b)) "No limb has 3 gaugings, so bias cannot be judged."
        else if (nrow(bad)) sprintf("%s: the fit sits systematically %s (median relative residual %s).", .limbs_text(bad$limb),
                                    ifelse(bad$value[1L] > 0, "below the gaugings", "above the gaugings"),
                                    paste(.pct(bad$value), collapse = ", "))
        else sprintf("Median relative residual is within %s in every limb.", .pct(bias_tol)),
        "A bias means the curve does not pass through the middle of the gaugings. Look at the residual plot and the limb boundaries.",
        affected = frame[limb %in% bad$limb]$evidence_id, stage = frame[limb %in% bad$limb]$stage_m)
    sp <- per_limb(function(r, s) stats::IQR(r) / 1.349, 4L)
    bad <- sp[value > spread_tol]
    add("residual_spread", "statistical", if (!nrow(sp)) "not_assessed" else ok(bad$limb),
        if (!nrow(sp)) "No limb has 4 gaugings, so spread cannot be judged."
        else if (nrow(bad)) sprintf("%s: gaugings scatter by about %s around the fit.", .limbs_text(bad$limb), paste(.pct(bad$value), collapse = ", "))
        else sprintf("Relative scatter is within %s in every limb.", .pct(spread_tol)),
        "Large scatter widens every interval. Check the quality and method of the gaugings in the limb.")
    tr <- per_limb(function(r, s) suppressWarnings(stats::cor(s, r, method = "spearman")), 8L)
    bad <- tr[is.finite(value) & abs(value) > trend_rho]
    add("residual_trend", "statistical", if (!nrow(tr)) "not_assessed" else ok(bad$limb),
        if (!nrow(tr)) "No limb has 8 gaugings, so a trend in the residuals cannot be judged."
        else if (nrow(bad)) sprintf("%s: residuals change systematically with stage (rank correlation %s).", .limbs_text(bad$limb),
                                    paste(sprintf("%.2f", bad$value), collapse = ", "))
        else "Residuals show no strong trend with stage in any limb.",
        "A trend means the equation form does not suit the limb. Consider another breakpoint or a different control.")
    cnt <- frame[, .N, by = limb]
    thin <- cnt[N < min_limb_gaugings]
    add("limb_support", "statistical", ok(thin$limb),
        if (nrow(thin)) sprintf("%s has fewer than %d gaugings (%s).", .limbs_text(thin$limb), as.integer(min_limb_gaugings),
                                paste(thin$N, collapse = ", "))
        else sprintf("Every limb has at least %d gaugings.", as.integer(min_limb_gaugings)),
        "Parameters of a thinly gauged limb are poorly determined. Gauge in the limb or merge it with a neighbour.")
  }
  ident_col <- if (is_independent) x@limbs else if (is_fit) x@coefficients else NULL
  if (!is.null(ident_col) && "parameter_correlation" %in% names(ident_col) && !all(is.na(ident_col$parameter_correlation))) {
    bad <- which(ident_col$parameter_correlation > 0.995 | ident_col$condition_number > 1e4)
    add("parameter_identifiability", "statistical", ok(bad),
        if (length(bad)) sprintf("%s: parameters trade off almost exactly (largest correlation %.4f, condition number %.3g).",
                                 if (is_independent) .limbs_text(bad) else "The fit",
                                 max(ident_col$parameter_correlation[bad]), max(ident_col$condition_number[bad]))
        else "The data separate the parameters: correlations and condition numbers are moderate.",
        "The curve may be well determined though its coefficients are not. Do not read C, a and n separately.")
  } else {
    na_check("parameter_identifiability", "statistical",
             if (is_fit) "No optimiser record for this rating." else "A rating that holds only equations has no optimiser record.")
  }
  if (is_independent && "multi_start_spread" %in% names(x@limbs) && any(!is.na(x@limbs$multi_start_spread))) {
    bad <- which(x@limbs$multi_start_spread > 0.05)
    add("multi_start_agreement", "statistical", ok(bad),
        if (length(bad)) sprintf("%s: near-optimal starting points disagree by up to %s of peak discharge.", .limbs_text(bad),
                                 .pct(max(x@limbs$multi_start_spread[bad])))
        else "Near-optimal starting points give the same curve.",
        "Two almost equally good fits predict different discharges: the data do not choose between them.")
  } else {
    na_check("multi_start_agreement", "statistical",
             if (is_independent) "Only one starting point was valid, or the rating was amended after fitting."
             else if (is_fit) "The multi-start record does not store each attempt's curve for a segmented fit."
             else "A rating that holds only equations has no multi-start record.")
  }
  if (is_independent && "bound_hits" %in% names(x@limbs) && !all(is.na(x@limbs$bound_hits))) {
    bad <- which(nzchar(x@limbs$bound_hits) & !is.na(x@limbs$bound_hits))
    add("bound_hits", "statistical", ok(bad),
        if (length(bad)) sprintf("%s: a parameter is on a bound (%s).", .limbs_text(bad), paste(unique(x@limbs$bound_hits[bad]), collapse = "; "))
        else "No parameter is on a bound.",
        "A parameter on a bound was set by the bound, not the data.")
  } else {
    na_check("bound_hits", "statistical",
             if (is_independent) "The rating was amended after fitting."
             else if (is_fit) "A segmented fit has no box bounds to hit."
             else "A rating that holds only equations has no fitting bounds.")
  }
  if (is_independent && !is.null(frame)) {
    infl <- tryCatch(.fit_scale_influence(x, frame), error = function(e) NULL)
    if (!is.null(infl) && any(is.finite(infl$cooks_distance))) {
      # The usual 4/n rule flags a point or two in almost any healthy set, which
      # is right for a diagnostic but would make every assessment warn. The
      # warning is for a gauging whose Cook's distance exceeds `cooks_warn`.
      bad <- infl[is.finite(infl$cooks_distance) & infl$cooks_distance > cooks_warn]
      n_in_limb <- frame[, .N, by = limb]
      usual <- sum(infl$cooks_distance > 4 / n_in_limb$N[match(frame$limb, n_in_limb$limb)], na.rm = TRUE)
      add("influential_gaugings", "statistical", ok(bad$evidence_id),
          if (nrow(bad)) sprintf("%d gauging%s a Cook's distance above %g (the usual 4/n rule flags %d).", nrow(bad),
                                 if (nrow(bad) == 1L) " has" else "s have", cooks_warn, usual)
          else sprintf("No gauging has a Cook's distance above %g (the usual 4/n rule flags %d).", cooks_warn, usual),
          "Refit without each to see what it changes before relying on the curve there.",
          affected = bad$evidence_id, stage = bad$stage_m)
    } else {
      na_check("influential_gaugings", "statistical", "Influence could not be computed for this fit.")
    }
  } else {
    na_check("influential_gaugings", "statistical",
             if (is_fit) "Influence is computed per limb for independent fits; a segmented fit's comes with the sensitivity analysis."
             else no_data_msg)
  }

  # ---- hydraulic: plausibility ------------------------------------------------------------------
  if (is_independent || S7_inherits(x, FlodeRatingTable)) {
    tbl <- .invariant_table(x)
    bad <- which(is.finite(tbl$n) & (tbl$n < n_range[1L] | tbl$n > n_range[2L]))
    add("exponent_plausible", "hydraulic", ok(bad),
        if (length(bad)) sprintf("%s: exponent %s lies outside %g to %g, unusual for an open-channel control.", .limbs_text(bad),
                                 paste(format(tbl$n[bad], digits = 3), collapse = ", "), n_range[1L], n_range[2L])
        else sprintf("Every limb exponent lies within %g to %g.", n_range[1L], n_range[2L]),
        "An implausible exponent may be absorbing something else: a shift, a backwater, or a missing breakpoint.")
  } else {
    na_check("exponent_plausible", "hydraulic",
             "A segmented fit's exponents are factors of one joint equation, not the exponents of separate limbs.")
  }
  if (is_independent && !is.null(frame)) {
    gmin <- min(frame$stage_m); span <- diff(range(frame$stage_m))
    a1 <- x@limbs$a[which.min(x@limbs$lower_stage_m)]
    far <- is.finite(a1) && span > 0 && (gmin - a1) > zero_flow_margin * span
    add("zero_flow_stage", "hydraulic", if (far) "warning" else "pass",
        if (far) sprintf("The zero-flow stage (%.3g m) lies %.3g m below the lowest gauging, more than %g times the gauged range.", a1, gmin - a1, zero_flow_margin)
        else "The zero-flow stage is within reach of the lowest gauging.",
        "Low flows are an extrapolation from the gaugings. Confirm the zero-flow stage from a survey or a low-flow gauging.")
  } else {
    na_check("zero_flow_stage", "hydraulic", if (is_fit) "Only assessed for independent fits." else no_data_msg)
  }

  # ---- operational ----------------------------------------------------------------------------------
  if (is_fit) {
    lim <- x@provenance$operational_limits
    guided <- !is.null(x@provenance$fit_rating)
    add("operational_limits_stated", "operational", if (is.null(lim)) "warning" else "pass",
        if (is.null(lim)) "No operational limits are stated for this rating." else
          sprintf("Operational limits are %.4g to %.4g m%s.", lim$lower_stage_m, lim$upper_stage_m,
                  if (is.na(lim$basis)) " (no basis recorded)" else paste0(" (", lim$basis, ")")),
        if (guided) "Until limits are stated, stages beyond the gauged range are flagged as extrapolation but not bounded. Use set_operational_limits()."
        else "State the stage range this rating may be used over, and why, with set_operational_limits().")
    if (!is.null(lim) && !is.null(frame)) {
      gmin <- min(frame$stage_m); gmax <- max(frame$stage_m); span <- diff(c(gmin, gmax))
      above <- max(lim$upper_stage_m - gmax, 0); below <- max(gmin - lim$lower_stage_m, 0)
      far <- span > 0 && (above > extrapolation_tol * span || below > extrapolation_tol * span)
      add("extrapolation_extent", "operational", if (far) "warning" else "pass",
          if (far) sprintf("The limits extend %.3g m above and %.3g m below the gauged range (%.3g to %.3g m), more than %s of its width.",
                           above, below, gmin, gmax, .pct(extrapolation_tol))
          else sprintf("The limits stay within %s of the gauged range.", .pct(extrapolation_tol)),
          "Discharge outside the gauged range is an extrapolation. The basis for the limits should say why it can be trusted.")
    } else {
      na_check("extrapolation_extent", "operational",
               if (is.null(lim)) "No limits are stated, so their extent cannot be judged." else "No gaugings to compare the limits with.")
    }
    amended <- !identical(x@fit_origin, "independently_fitted")
    add("fit_unchanged", "operational", if (amended) "warning" else "pass",
        if (amended) sprintf("The rating has been changed since it was fitted (origin: %s), so some checks of the fit itself are not assessed.", x@fit_origin)
        else "The rating is as the optimiser produced it.",
        "Check the amended coefficients against the gaugings: the optimiser did not produce them.")
  } else {
    na_check("operational_limits_stated", "operational", "A table has no provenance in which to record limits.")
  }

  # ---- provenance ---------------------------------------------------------------------------------------
  if (is_fit) {
    ev <- x@gaugings
    n_src <- sum(!is.na(ev$source_name))
    add("evidence_sources", "provenance", if (n_src == 0L) "warning" else "pass",
        if (n_src == 0L) "No row of evidence records where it came from."
        else sprintf("%d of %d evidence rows record their source.", n_src, nrow(ev)),
        "Without a source, a gauging cannot be traced back or weighed. Read the data with read_gaugings() or fill source_name.")
    note <- ev@conversion_note
    add("evidence_assumptions", "provenance", if (length(note)) "warning" else "pass",
        if (length(note)) note
        else "No assumptions were made in building the evidence.",
        "Read the conversion note and check each assumption holds for your data.")
    guided <- x@provenance$fit_rating
    add("fit_recorded", "provenance", if (is.null(guided)) "warning" else "pass",
        if (is.null(guided)) "The rating was not made by fit_rating(), so the call, exclusions and breakpoint origin are not recorded."
        else sprintf("Made by fit_rating(): call, seed, %d exclusion%s and breakpoint origin recorded.", nrow(guided$excluded),
                     if (nrow(guided$excluded) == 1L) "" else "s"),
        "Fit with fit_rating() to record how the rating was made.")
    add("tool_version", "provenance", if (is.null(x@provenance$tool_version)) "warning" else "pass",
        if (is.null(x@provenance$tool_version)) "No tool version is recorded."
        else sprintf("Made with %s, schema version %d.", x@provenance$tool_version, x@schema_version),
        "A rating without a tool version cannot be reproduced.")
    boot <- is_independent && "C_se" %in% names(x@limbs) && any(!is.na(x@limbs$C_se))
    seed_missing <- boot && is.null(guided$seed)
    add("seed_recorded", "provenance", if (seed_missing) "warning" else "pass",
        if (seed_missing) "Bootstrap draws were made but no seed is recorded, so they cannot be repeated."
        else if (boot) sprintf("The bootstrap seed (%s) is recorded.", guided$seed)
        else "No bootstrap was run, so no seed is needed.",
        "Rerun the bootstrap with a seed.")
  } else {
    na_check("evidence_sources", "provenance", no_data_msg)
  }

  n_units <- if (is_fit && !is.null(frame)) nrow(frame) else if (is_independent) nrow(x@limbs) else 0L
  FlodeAssessment(checks = rbindlist(rows), subject = "rating", assessed_rows = as.integer(n_units))
}
