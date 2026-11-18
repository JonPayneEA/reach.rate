# The pure-R rating arithmetic as it was before it moved into the C kernel
# (src/reach_core.c). Kept here, unchanged in substance, as the oracle the
# kernel is tested against: if the two ever disagree, one of them is wrong.
# Nothing in the package calls these.

reference_sort <- function(rating_dt) {
  rating_dt <- data.table::copy(data.table::as.data.table(rating_dt))
  rating_dt[order(rating_dt$lower_level)]
}

# Stage to discharge, as apply_rating() computed it.
reference_forward <- function(rating_dt, stage_vals) {
  rating_dt <- reference_sort(rating_dt)
  n_limbs <- nrow(rating_dt)
  breaks <- c(rating_dt$lower_level[1], rating_dt$upper_level)
  limb_idx_raw <- findInterval(stage_vals, breaks, rightmost.closed = TRUE)
  extrapolated <- limb_idx_raw == 0L | limb_idx_raw == (n_limbs + 1L)
  limb_idx <- pmin(pmax(limb_idx_raw, 1L), n_limbs)

  C <- rating_dt$C[limb_idx]
  a <- rating_dt$a[limb_idx]
  n <- rating_dt$n[limb_idx]
  discharge <- C * (stage_vals - a)^n
  discharge[!is.na(stage_vals) & stage_vals <= a] <- 0
  list(discharge = discharge, extrapolated = extrapolated, limb = limb_idx)
}

# Discharge to stage, as apply_rating_inverse() computed it, without the
# junction-gap check (that is tested separately).
reference_inverse <- function(rating_dt, discharge_vals) {
  rating_dt <- reference_sort(rating_dt)
  n_limbs <- nrow(rating_dt)
  eval_q <- function(C, a, n, H) C * (H - a)^n
  q_lo <- eval_q(rating_dt$C, rating_dt$a, rating_dt$n, rating_dt$lower_level)
  q_hi <- eval_q(rating_dt$C, rating_dt$a, rating_dt$n, rating_dt$upper_level)
  q_breaks <- c(q_lo[1], q_hi)

  stage <- rep(NA_real_, length(discharge_vals))
  extrapolated <- rep(NA, length(discharge_vals))
  valid_idx <- !is.na(discharge_vals) & discharge_vals > 0
  if (any(valid_idx)) {
    q_valid <- discharge_vals[valid_idx]
    limb_idx_raw <- findInterval(q_valid, q_breaks, rightmost.closed = TRUE)
    extrap_valid <- limb_idx_raw == 0L | limb_idx_raw == (n_limbs + 1L)
    limb_idx <- pmin(pmax(limb_idx_raw, 1L), n_limbs)
    stage[valid_idx] <- rating_dt$a[limb_idx] + (q_valid / rating_dt$C[limb_idx])^(1 / rating_dt$n[limb_idx])
    extrapolated[valid_idx] <- extrap_valid
  }
  list(stage = stage, extrapolated = extrapolated)
}

# Discharge on each side of each junction, as apply_rating_inverse() computed it.
reference_junctions <- function(rating_dt) {
  rating_dt <- reference_sort(rating_dt)
  n_limbs <- nrow(rating_dt)
  eval_q <- function(C, a, n, H) C * (H - a)^n
  j <- seq_len(n_limbs - 1L)
  list(
    below = eval_q(rating_dt$C[j], rating_dt$a[j], rating_dt$n[j], rating_dt$upper_level[j]),
    above = eval_q(rating_dt$C[j + 1L], rating_dt$a[j + 1L], rating_dt$n[j + 1L], rating_dt$upper_level[j])
  )
}

# The tangent limb, as extend_rating_low() computed it.
reference_tangent <- function(C, a, n, h) {
  depth <- h - a
  c(n * C * depth^(n - 1), h - depth / n)
}

# Wetted area and perimeter of a surveyed cross-section at one stage, as
# .xs_area_perimeter() computed them before they moved into the C kernel.
reference_xs_area_perimeter <- function(distance_m, elevation_m, stage) {
  area <- 0
  perimeter <- 0
  for (i in seq_len(length(distance_m) - 1L)) {
    x1 <- distance_m[i]; z1 <- elevation_m[i]
    x2 <- distance_m[i + 1L]; z2 <- elevation_m[i + 1L]
    d1 <- stage - z1
    d2 <- stage - z2
    if (d1 <= 0 && d2 <= 0) next
    if (d1 > 0 && d2 > 0) {
      area <- area + (d1 + d2) / 2 * (x2 - x1)
      perimeter <- perimeter + sqrt((x2 - x1)^2 + (z2 - z1)^2)
    } else {
      frac <- d1 / (d1 - d2)
      xc <- x1 + frac * (x2 - x1)
      if (d1 > 0) {
        area <- area + d1 / 2 * (xc - x1)
        perimeter <- perimeter + sqrt((xc - x1)^2 + d1^2)
      } else {
        area <- area + d2 / 2 * (x2 - xc)
        perimeter <- perimeter + sqrt((x2 - xc)^2 + d2^2)
      }
    }
  }
  c(area = area, perimeter = perimeter)
}

# Manning's discharge from area and perimeter, as rate_from_cross_section()
# computed it.
reference_manning <- function(area, perimeter, roughness, slope) {
  radius <- ifelse(perimeter > 0, area / perimeter, 0)
  (1 / roughness) * area * radius^(2 / 3) * sqrt(slope)
}

# The stage where two limb equations give the same discharge, as
# .find_intersection_stage() found it with uniroot(), or NA if they do not
# cross in the range.
reference_intersection <- function(C1, a1, n1, C2, a2, n2, search_lo, search_hi) {
  f <- function(H) C1 * (H - a1)^n1 - C2 * (H - a2)^n2
  f_lo <- tryCatch(f(search_lo), error = function(e) NA_real_)
  f_hi <- tryCatch(f(search_hi), error = function(e) NA_real_)
  if (!is.finite(f_lo) || !is.finite(f_hi) || sign(f_lo) == sign(f_hi)) return(NA_real_)
  tryCatch(
    uniroot(f, lower = search_lo, upper = search_hi, tol = .Machine$double.eps^0.5)$root,
    error = function(e) NA_real_
  )
}
