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
