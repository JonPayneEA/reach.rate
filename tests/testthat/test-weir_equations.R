test_that("weir_discharge_rectangular matches a hand-computed Rehbock value", {
  H <- 0.2; B <- 1.5; P <- 0.5
  cd <- 0.602 + 0.083 * (H / P)
  q_expected <- (2 / 3) * cd * sqrt(2 * 9.80665) * B * H^1.5

  out <- weir_discharge_rectangular(head_m = H, width_m = B, weir_height_m = P, u_cd = 0.02, u_head_m = 0.003)
  expect_equal(out$discharge, q_expected, tolerance = 1e-10)
  expect_equal(out$U_rel, 2 * out$u_c_rel, tolerance = 1e-10)
  expect_true(out$discharge_lower < out$discharge && out$discharge < out$discharge_upper)
})

test_that("weir_discharge_rectangular warns outside ISO 1438's P < 1 m range", {
  expect_warning(
    weir_discharge_rectangular(head_m = 0.1, width_m = 1, weir_height_m = 1.2, u_cd = 0.02, u_head_m = 0.003),
    "ISO 1438"
  )
})

test_that("weir_discharge_rectangular validates its inputs", {
  expect_error(weir_discharge_rectangular(head_m = -1, width_m = 1, weir_height_m = 1, u_cd = 0.02, u_head_m = 0.003), "head_m")
  expect_error(weir_discharge_rectangular(head_m = 0.1, width_m = 0, weir_height_m = 1, u_cd = 0.02, u_head_m = 0.003), "width_m")
  expect_error(weir_discharge_rectangular(head_m = 0.1, width_m = 1, weir_height_m = -1, u_cd = 0.02, u_head_m = 0.003), "weir_height_m")
  expect_error(weir_discharge_rectangular(head_m = 0.1, width_m = 1, weir_height_m = 1, u_cd = -0.1, u_head_m = 0.003), "u_cd")
  expect_error(weir_discharge_rectangular(head_m = 0.1, width_m = 1, weir_height_m = 1, u_cd = 0.02, u_head_m = -1), "u_head_m")
})

test_that("weir_discharge_vnotch matches a hand-computed Kindsvater-Shen value at 90 degrees", {
  theta <- 90; H <- 0.1
  ce <- 0.607165052 - 0.000874466963 * theta + 6.10393334e-6 * theta^2
  k_ft <- 0.0144902648 - 0.00033955535 * theta + 3.29819003e-6 * theta^2 - 1.06215442e-8 * theta^3
  He <- H + k_ft * 0.3048
  q_expected <- (8 / 15) * sqrt(2 * 9.80665) * ce * tan((theta * pi / 180) / 2) * He^2.5

  out <- weir_discharge_vnotch(head_m = H, notch_angle_deg = theta, u_cd = 0.02, u_head_m = 0.002)
  expect_equal(out$discharge, q_expected, tolerance = 1e-10)
})

test_that("weir_discharge_vnotch rejects notch angles outside 25-100 degrees", {
  expect_error(weir_discharge_vnotch(head_m = 0.1, notch_angle_deg = 10, u_cd = 0.02, u_head_m = 0.002), "25-100")
  expect_error(weir_discharge_vnotch(head_m = 0.1, notch_angle_deg = 110, u_cd = 0.02, u_head_m = 0.002), "25-100")
})

test_that("weir_discharge_cipoletti matches its USBR US-customary form after unit conversion", {
  H_m <- 0.2; L_m <- 1.0
  H_ft <- H_m / 0.3048; L_ft <- L_m / 0.3048
  q_cfs <- 3.367 * L_ft * H_ft^1.5
  q_expected_cms <- q_cfs * 0.0283168

  out <- weir_discharge_cipoletti(head_m = H_m, crest_length_m = L_m, u_cd = 0.05, u_head_m = 0.003)
  expect_equal(out$discharge, q_expected_cms, tolerance = 1e-4)
})

test_that("flume_discharge_parshall matches its general US-customary form after unit conversion", {
  H_m <- 0.3; W_m <- 0.3048
  H_ft <- H_m / 0.3048; W_ft <- W_m / 0.3048
  q_cfs <- 4 * W_ft^1.026 * H_ft^1.522
  q_expected_cms <- q_cfs * 0.0283168

  out <- flume_discharge_parshall(head_m = H_m, throat_width_m = W_m, u_cd = 0.03, u_head_m = 0.005)
  # The published US-customary constant (4) is only given to 1 significant
  # figure, so this converted cross-check agrees to ~0.1%, not machine precision.
  expect_equal(out$discharge, q_expected_cms, tolerance = 1e-3)
})

test_that("flume_discharge_parshall warns outside its confirmed throat-width range", {
  expect_warning(
    flume_discharge_parshall(head_m = 0.3, throat_width_m = 0.1, u_cd = 0.03, u_head_m = 0.005),
    "1-8 ft"
  )
})

test_that("flume_discharge_parshall errors on submerged flow rather than silently applying the free-flow equation", {
  expect_error(
    flume_discharge_parshall(
      head_m = 0.3, throat_width_m = 0.3048, u_cd = 0.03, u_head_m = 0.005,
      hb_head_m = 0.25
    ),
    "submerged"
  )
  expect_silent(
    flume_discharge_parshall(
      head_m = 0.3, throat_width_m = 0.3048, u_cd = 0.03, u_head_m = 0.005,
      hb_head_m = 0.1
    )
  )
})

test_that("GUM uncertainty combination increases with head-measurement uncertainty and decreases with head", {
  low_u <- weir_discharge_cipoletti(head_m = 0.3, crest_length_m = 1, u_cd = 0.05, u_head_m = 0.001)
  high_u <- weir_discharge_cipoletti(head_m = 0.3, crest_length_m = 1, u_cd = 0.05, u_head_m = 0.05)
  expect_true(high_u$u_c_rel > low_u$u_c_rel)

  small_head <- weir_discharge_cipoletti(head_m = 0.05, crest_length_m = 1, u_cd = 0.05, u_head_m = 0.005)
  large_head <- weir_discharge_cipoletti(head_m = 0.5, crest_length_m = 1, u_cd = 0.05, u_head_m = 0.005)
  expect_true(small_head$u_c_rel > large_head$u_c_rel)
})

test_that("all four structure functions vectorise over head_m and expose a consistent output shape", {
  expected_cols <- c("head_m", "discharge", "u_c_rel", "U_rel", "discharge_lower", "discharge_upper", "coverage_k")

  r1 <- weir_discharge_rectangular(head_m = c(0.1, 0.2), width_m = 1, weir_height_m = 0.5, u_cd = 0.02, u_head_m = 0.003)
  r2 <- weir_discharge_vnotch(head_m = c(0.1, 0.2), notch_angle_deg = 90, u_cd = 0.02, u_head_m = 0.002)
  r3 <- weir_discharge_cipoletti(head_m = c(0.1, 0.2), crest_length_m = 1, u_cd = 0.05, u_head_m = 0.003)
  r4 <- flume_discharge_parshall(head_m = c(0.1, 0.2), throat_width_m = 0.6, u_cd = 0.03, u_head_m = 0.005)

  for (out in list(r1, r2, r3, r4)) {
    expect_equal(names(out), expected_cols)
    expect_equal(nrow(out), 2L)
    expect_true(all(out$discharge > 0))
  }
})
