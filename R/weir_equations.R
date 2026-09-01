# ============================================================ #
# Tool:         weir_equations
# Description:  Discharge equations for standard weir and flume
#               structures -- rectangular (suppressed) sharp-crested,
#               V-notch/triangular sharp-crested, Cipoletti (trapezoidal)
#               sharp-crested, and Parshall flume -- each with GUM-style
#               (JCGM 100:2008) uncertainty propagation from a supplied
#               discharge-coefficient uncertainty and head-measurement
#               uncertainty. Physically-derived from structure geometry,
#               not fitted to gaugings -- deliberately separate from
#               rate_optimise()'s NLS machinery and FlodeRating, which
#               this module does not touch. See
#               vignette("weir_flume_guide") for the structures, the
#               equations, and worked examples.
# Author:       Jonathan Payne
# Created:      2026-09-01
# Tier:         3
# Inputs:       head_m (numeric vector) plus per-structure geometry
#               (width/crest length/notch angle/throat width, scalar),
#               and u_cd/u_head_m (scalar standard uncertainties) for
#               the GUM propagation.
# Outputs:      A data.table, one row per head_m value: discharge (m^3/s),
#               the combined and expanded relative uncertainties, and
#               discharge_lower/discharge_upper at the expanded
#               uncertainty.
# Dependencies: data.table
# ============================================================ #

# Standard gravity, m/s^2 (CGPM 1901 conventional value; used throughout
# this module's SI-form discharge constants).
.G <- 9.80665

# GUM (JCGM 100:2008) combination in quadrature of two independent
# relative standard uncertainty contributions -- the discharge
# coefficient's own relative uncertainty, and the head measurement's
# absolute uncertainty scaled by the equation's head exponent (the
# sensitivity coefficient for Q proportional to C * H^n is n/H, so its
# relative contribution is n * u(H)/H). Shared by every structure type
# below; only the exponent and the effective head differ.
.gum_combine <- function(u_cd, n_exponent, u_head_m, head_effective_m) {
  sqrt(u_cd^2 + (n_exponent * u_head_m / head_effective_m)^2)
}

# Shared validation for the two uncertainty inputs every structure
# function below takes. u_cd/u_head_m are required, not defaulted --
# see individual functions' @details for literature reference points,
# none of which substitute for a value appropriate to a specific
# installation and instrument.
.validate_gum_inputs <- function(u_cd, u_head_m, fn_name) {
  if (!is.numeric(u_cd) || length(u_cd) != 1L || !is.finite(u_cd) || u_cd < 0) {
    stop(fn_name, "(): u_cd must be a single non-negative finite number ",
         "(the discharge coefficient's relative standard uncertainty, e.g. 0.02 for 2%)")
  }
  if (!is.numeric(u_head_m) || length(u_head_m) != 1L || !is.finite(u_head_m) || u_head_m < 0) {
    stop(fn_name, "(): u_head_m must be a single non-negative finite number ",
         "(the head measurement's absolute standard uncertainty, in metres)")
  }
}

# Shared GUM output columns for a vector of discharges, effective heads,
# and a per-row combined relative uncertainty.
.gum_output <- function(head_m, discharge, u_c_rel, coverage_k) {
  U_rel <- coverage_k * u_c_rel
  data.table(
    head_m = head_m,
    discharge = discharge,
    u_c_rel = u_c_rel,
    U_rel = U_rel,
    discharge_lower = discharge * (1 - U_rel),
    discharge_upper = discharge * (1 + U_rel),
    coverage_k = coverage_k
  )
}

#' Discharge over a full-width (suppressed) rectangular sharp-crested weir
#'
#' @description
#' The Rehbock equation for a rectangular sharp-crested weir spanning the
#' full width of its approach channel (no end contractions), as specified
#' for this structure type by ISO 1438:2017:
#'
#' \deqn{Q = \frac{2}{3} C_d \sqrt{2g} \, B H^{3/2}, \qquad
#'       C_d = 0.602 + 0.083 \frac{H}{P}}
#'
#' where \eqn{H} is head over the crest, \eqn{B} is crest width, and
#' \eqn{P} is the weir's height above the channel bed. ISO 1438 restricts
#' this formula to \eqn{P < 1}\,m; `weir_height_m >= 1` is accepted but
#' warns, since the coefficient is unvalidated outside that range.
#'
#' Uncertainty is propagated by GUM (JCGM 100:2008) quadrature combination
#' of `u_cd` (the discharge coefficient's own relative standard
#' uncertainty) and `u_head_m` (the head measurement's absolute standard
#' uncertainty), using the equation's head exponent (`3/2`) as the head
#' term's sensitivity coefficient. Both are required, not defaulted: a
#' realistic starting point is a relative \eqn{u^*(C_d)} on the order of
#' 1-2\% for a well-maintained, correctly-installed weir plate (ISO 1438's
#' own worked uncertainty examples are in this range), rising for a
#' rougher field installation -- but this is illustrative context, not a
#' substitute for the actual value for a specific structure and
#' instrument.
#'
#' This assumes free (unsubmerged, non-drowned) flow, negligible approach
#' velocity, and a truly full-width crest -- side contractions (a weir
#' narrower than its channel) are not modelled; that is a different,
#' contracted-weir formula this function does not implement.
#'
#' @param head_m Numeric vector. Head over the weir crest, m. Must be positive.
#' @param width_m Single positive number. Crest width (= channel width,
#'   full-width/suppressed), m.
#' @param weir_height_m Single positive number. Weir crest height above
#'   the channel bed, m.
#' @param u_cd Single non-negative number. Relative standard uncertainty
#'   in the discharge coefficient (e.g. `0.02` for 2%). See Description.
#' @param u_head_m Single non-negative number. Absolute standard
#'   uncertainty in the measured head, m.
#' @param coverage_k Single positive number. GUM coverage factor for the
#'   expanded uncertainty `U = coverage_k * u_c`. Default `2`
#'   (approximately 95% for a normally-distributed measurand, the
#'   conventional GUM default -- JCGM 100:2008 §2.3.6).
#'
#' @return A data.table, one row per `head_m`: `head_m`, `discharge`
#'   (m^3/s), `u_c_rel` (combined relative standard uncertainty),
#'   `U_rel` (expanded relative uncertainty), `discharge_lower`/
#'   `discharge_upper` (discharge at `+/- U_rel`), `coverage_k`.
#'
#' @seealso [weir_discharge_vnotch()], [weir_discharge_cipoletti()],
#'   [flume_discharge_parshall()]; `vignette("weir_flume_guide")` for the
#'   structures, diagrams, and worked examples.
#'
#' @references ISO 1438:2017, *Hydrometry -- Open channel flow
#'   measurement using thin-plate weirs*. JCGM 100:2008, *Evaluation of
#'   measurement data -- Guide to the expression of uncertainty in
#'   measurement (GUM)*.
#'
#' @examples
#' weir_discharge_rectangular(
#'   head_m = c(0.1, 0.2, 0.3), width_m = 1.5, weir_height_m = 0.5,
#'   u_cd = 0.02, u_head_m = 0.003
#' )
#'
#' @export
weir_discharge_rectangular <- function(head_m, width_m, weir_height_m,
                                        u_cd, u_head_m, coverage_k = 2) {
  if (!is.numeric(head_m) || length(head_m) == 0L || any(!is.finite(head_m)) || any(head_m <= 0)) {
    stop("weir_discharge_rectangular(): head_m must be numeric, finite, and positive")
  }
  if (!is.numeric(width_m) || length(width_m) != 1L || !is.finite(width_m) || width_m <= 0) {
    stop("weir_discharge_rectangular(): width_m must be a single positive finite number")
  }
  if (!is.numeric(weir_height_m) || length(weir_height_m) != 1L || !is.finite(weir_height_m) || weir_height_m <= 0) {
    stop("weir_discharge_rectangular(): weir_height_m must be a single positive finite number")
  }
  .validate_gum_inputs(u_cd, u_head_m, "weir_discharge_rectangular")
  if (!is.numeric(coverage_k) || length(coverage_k) != 1L || !is.finite(coverage_k) || coverage_k <= 0) {
    stop("weir_discharge_rectangular(): coverage_k must be a single positive finite number")
  }
  if (weir_height_m >= 1) {
    warning(
      "weir_discharge_rectangular(): weir_height_m (", weir_height_m, " m) is outside ISO 1438's ",
      "validated range for the Rehbock coefficient (P < 1 m); treat the result as an extrapolation.",
      call. = FALSE
    )
  }

  cd <- 0.602 + 0.083 * (head_m / weir_height_m)
  discharge <- (2 / 3) * cd * sqrt(2 * .G) * width_m * head_m^1.5
  u_c_rel <- .gum_combine(u_cd, 1.5, u_head_m, head_m)
  .gum_output(head_m, discharge, u_c_rel, coverage_k)
}

#' Discharge over a V-notch (triangular) sharp-crested weir
#'
#' @description
#' The Kindsvater-Shen equation, the form ISO, ASTM, and USBR each adopt
#' for a sharp-crested triangular-notch weir:
#'
#' \deqn{Q = \frac{8}{15} \sqrt{2g} \, C_e \tan(\theta/2) \, H_e^{5/2},
#'       \qquad H_e = H + k_h}
#'
#' where \eqn{\theta} is the full notch angle and \eqn{H_e} is head over
#' the notch vertex corrected by a small empirical head offset
#' \eqn{k_h}. Both \eqn{C_e} (dimensionless) and \eqn{k_h} (originally
#' published in feet; converted to metres internally, with the polynomial
#' itself evaluated exactly as published) are fitted polynomials in
#' \eqn{\theta} (degrees), valid for notch angles from 25 to 100 degrees
#' -- outside that range this errors rather than extrapolating an
#' unvalidated fit.
#'
#' Uncertainty follows the same GUM quadrature as
#' [weir_discharge_rectangular()], with head exponent `5/2` (applied to
#' the corrected head \eqn{H_e}). A relative \eqn{u^*(C_e)} of roughly
#' 1-2\% is a common literature reference point for a well-installed
#' V-notch weir -- context, not a default; `u_cd` is still required.
#'
#' @inheritParams weir_discharge_rectangular
#' @param notch_angle_deg Single number, 25-100. Full notch angle, degrees.
#'
#' @return As [weir_discharge_rectangular()].
#'
#' @seealso [weir_discharge_rectangular()], [weir_discharge_cipoletti()],
#'   [flume_discharge_parshall()]; `vignette("weir_flume_guide")`.
#'
#' @references Kindsvater, C.E. & Carter, R.W. (1957); Shen, J. (1981),
#'   *Discharge Characteristics of Triangular-Notch Thin-Plate Weirs*,
#'   USGS Water-Supply Paper 1617-B. USBR *Water Measurement Manual*,
#'   ch. 7, §7. JCGM 100:2008 (GUM).
#'
#' @examples
#' weir_discharge_vnotch(
#'   head_m = c(0.05, 0.1, 0.15), notch_angle_deg = 90,
#'   u_cd = 0.02, u_head_m = 0.002
#' )
#'
#' @export
weir_discharge_vnotch <- function(head_m, notch_angle_deg, u_cd, u_head_m, coverage_k = 2) {
  if (!is.numeric(head_m) || length(head_m) == 0L || any(!is.finite(head_m)) || any(head_m <= 0)) {
    stop("weir_discharge_vnotch(): head_m must be numeric, finite, and positive")
  }
  if (!is.numeric(notch_angle_deg) || length(notch_angle_deg) != 1L || !is.finite(notch_angle_deg)) {
    stop("weir_discharge_vnotch(): notch_angle_deg must be a single finite number")
  }
  if (notch_angle_deg < 25 || notch_angle_deg > 100) {
    stop(
      "weir_discharge_vnotch(): notch_angle_deg (", notch_angle_deg, ") is outside the ",
      "Kindsvater-Shen equation's validated range (25-100 degrees)"
    )
  }
  .validate_gum_inputs(u_cd, u_head_m, "weir_discharge_vnotch")
  if (!is.numeric(coverage_k) || length(coverage_k) != 1L || !is.finite(coverage_k) || coverage_k <= 0) {
    stop("weir_discharge_vnotch(): coverage_k must be a single positive finite number")
  }

  theta <- notch_angle_deg
  ce <- 0.607165052 - 0.000874466963 * theta + 6.10393334e-6 * theta^2
  k_ft <- 0.0144902648 - 0.00033955535 * theta + 3.29819003e-6 * theta^2 - 1.06215442e-8 * theta^3
  k_m <- k_ft * 0.3048
  head_effective_m <- head_m + k_m

  discharge <- (8 / 15) * sqrt(2 * .G) * ce * tan((theta * pi / 180) / 2) * head_effective_m^2.5
  u_c_rel <- .gum_combine(u_cd, 2.5, u_head_m, head_effective_m)
  .gum_output(head_m, discharge, u_c_rel, coverage_k)
}

#' Discharge over a Cipoletti (trapezoidal) sharp-crested weir
#'
#' @description
#' The Cipoletti weir's trapezoidal notch (sides sloped 1 horizontal to 4
#' vertical) is designed so the side slopes' extra discharge compensates
#' for end-contraction losses, letting it use a single fixed coefficient
#' with no weir-height or approach-channel correction, unlike the
#' rectangular case:
#'
#' \deqn{Q = 1.859 \, L \, H^{3/2}}
#'
#' (SI form; \eqn{L} is crest length, \eqn{H} is head over the crest.
#' Derived here from the USBR *Water Measurement Manual*'s published US
#' customary form, \eqn{Q_{cfs} = 3.367 \, L_{ft} H_{ft}^{3/2}}, by direct
#' unit conversion.)
#'
#' That simplicity comes at a cost: the USBR manual describes overall
#' accuracy for a well-maintained Cipoletti installation as only around
#' \eqn{\pm 5\%} -- markedly worse than a rectangular or V-notch weir.
#' Uncertainty here still follows the same GUM quadrature as the other
#' structures (head exponent `3/2`); `u_cd` and `u_head_m` are required,
#' with that \eqn{\pm 5\%} figure as context for the scale of `u_cd` a
#' Cipoletti weir typically needs, not a substitute for it (it is an
#' aggregate accuracy figure, not already split into coefficient/head
#' components).
#'
#' @inheritParams weir_discharge_rectangular
#' @param crest_length_m Single positive number. Crest length, m (the
#'   longer, downstream edge of the trapezoidal notch).
#'
#' @return As [weir_discharge_rectangular()].
#'
#' @seealso [weir_discharge_rectangular()], [weir_discharge_vnotch()],
#'   [flume_discharge_parshall()]; `vignette("weir_flume_guide")`.
#'
#' @references USBR *Water Measurement Manual*, ch. 7, §12. JCGM 100:2008 (GUM).
#'
#' @examples
#' weir_discharge_cipoletti(
#'   head_m = c(0.1, 0.2, 0.3), crest_length_m = 1.0,
#'   u_cd = 0.05, u_head_m = 0.003
#' )
#'
#' @export
weir_discharge_cipoletti <- function(head_m, crest_length_m, u_cd, u_head_m, coverage_k = 2) {
  if (!is.numeric(head_m) || length(head_m) == 0L || any(!is.finite(head_m)) || any(head_m <= 0)) {
    stop("weir_discharge_cipoletti(): head_m must be numeric, finite, and positive")
  }
  if (!is.numeric(crest_length_m) || length(crest_length_m) != 1L || !is.finite(crest_length_m) || crest_length_m <= 0) {
    stop("weir_discharge_cipoletti(): crest_length_m must be a single positive finite number")
  }
  .validate_gum_inputs(u_cd, u_head_m, "weir_discharge_cipoletti")
  if (!is.numeric(coverage_k) || length(coverage_k) != 1L || !is.finite(coverage_k) || coverage_k <= 0) {
    stop("weir_discharge_cipoletti(): coverage_k must be a single positive finite number")
  }

  discharge <- 1.859 * crest_length_m * head_m^1.5
  u_c_rel <- .gum_combine(u_cd, 1.5, u_head_m, head_m)
  .gum_output(head_m, discharge, u_c_rel, coverage_k)
}

#' Discharge through a standard Parshall flume (free flow)
#'
#' @description
#' The general free-flow discharge equation for a standard Parshall
#' flume with throat width between 1 and 8 feet (0.3048-2.4384 m):
#'
#' \deqn{Q = 2.340 \, W^{1.026} \, H_a^{1.522}}
#'
#' (SI form; \eqn{W} is throat width, \eqn{H_a} is the upstream head
#' gauged at the standard measuring station. Derived here from the
#' equation's published US customary form,
#' \eqn{Q_{cfs} = 4 \, W_{ft}^{1.026} H_{a,ft}^{1.522}}, by direct unit
#' conversion.) `throat_width_m` outside 0.3048-2.4384 m warns, since
#' this general approximation is only confirmed within that range --
#' smaller and larger standard sizes have their own individually
#' tabulated `C`/`n` coefficients (USBR *Water Measurement Manual*, ch.
#' 8, §10; ISO 9826) not reproduced here.
#'
#' A Parshall flume only measures discharge correctly in free (unsubmerged)
#' flow. If `hb_head_m` (the downstream/submerged head) is supplied, this
#' checks the standard submergence limit for this throat-width range
#' (`hb_head_m / head_m <= 0.7`) and errors rather than applying an
#' uncorrected free-flow equation to submerged conditions -- submerged-flow
#' correction is not implemented.
#'
#' Uncertainty follows the same GUM quadrature as the other structures
#' (head exponent `1.522`). A 2021 Monte Carlo study (Ferreira et al.)
#' found roughly \eqn{\pm 2\%} for well-built laboratory flumes, rising to
#' \eqn{\pm 3\text{-}5\%} for realistic field installations -- context for
#' `u_cd`'s scale, not a default; both `u_cd` and `u_head_m` are required.
#'
#' @inheritParams weir_discharge_rectangular
#' @param throat_width_m Single positive number. Flume throat width, m.
#' @param hb_head_m Numeric vector matching `head_m` in length, or `NULL`
#'   (default). Downstream head, for the free-flow submergence check
#'   described above. `NULL` skips the check.
#'
#' @return As [weir_discharge_rectangular()].
#'
#' @seealso [weir_discharge_rectangular()], [weir_discharge_vnotch()],
#'   [weir_discharge_cipoletti()]; `vignette("weir_flume_guide")`.
#'
#' @references USBR *Water Measurement Manual*, ch. 8, §10. Ferreira,
#'   H.M. et al. (2021), Monte Carlo uncertainty analysis of Parshall
#'   flume discharge. JCGM 100:2008 (GUM).
#'
#' @examples
#' flume_discharge_parshall(
#'   head_m = c(0.15, 0.3, 0.45), throat_width_m = 0.3048,
#'   u_cd = 0.03, u_head_m = 0.005
#' )
#'
#' @export
flume_discharge_parshall <- function(head_m, throat_width_m, u_cd, u_head_m,
                                      coverage_k = 2, hb_head_m = NULL) {
  if (!is.numeric(head_m) || length(head_m) == 0L || any(!is.finite(head_m)) || any(head_m <= 0)) {
    stop("flume_discharge_parshall(): head_m must be numeric, finite, and positive")
  }
  if (!is.numeric(throat_width_m) || length(throat_width_m) != 1L || !is.finite(throat_width_m) || throat_width_m <= 0) {
    stop("flume_discharge_parshall(): throat_width_m must be a single positive finite number")
  }
  .validate_gum_inputs(u_cd, u_head_m, "flume_discharge_parshall")
  if (!is.numeric(coverage_k) || length(coverage_k) != 1L || !is.finite(coverage_k) || coverage_k <= 0) {
    stop("flume_discharge_parshall(): coverage_k must be a single positive finite number")
  }
  if (throat_width_m < 0.3048 || throat_width_m > 2.4384) {
    warning(
      "flume_discharge_parshall(): throat_width_m (", throat_width_m, " m) is outside the ",
      "general free-flow equation's confirmed range (0.3048-2.4384 m, i.e. 1-8 ft); standard ",
      "flumes outside this range use their own individually tabulated coefficients, not this formula.",
      call. = FALSE
    )
  }
  if (!is.null(hb_head_m)) {
    if (!is.numeric(hb_head_m) || length(hb_head_m) != length(head_m) || any(!is.finite(hb_head_m))) {
      stop("flume_discharge_parshall(): hb_head_m must be numeric, finite, and the same length as head_m")
    }
    submerged <- (hb_head_m / head_m) > 0.7
    if (any(submerged)) {
      stop(
        "flume_discharge_parshall(): submergence ratio hb_head_m/head_m exceeds the free-flow limit ",
        "(0.7) at ", sum(submerged), " head value(s) -- this is submerged flow, which this free-flow ",
        "equation does not correct for"
      )
    }
  }

  discharge <- 2.340 * throat_width_m^1.026 * head_m^1.522
  u_c_rel <- .gum_combine(u_cd, 1.522, u_head_m, head_m)
  .gum_output(head_m, discharge, u_c_rel, coverage_k)
}
