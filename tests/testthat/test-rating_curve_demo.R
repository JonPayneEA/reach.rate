test_that("as_rating_table flips the sign of the offset correctly", {
  set.seed(1)
  stage_seq <- seq(0.5, 2.5, by = 0.05)
  discharge_seq <- 5 * (stage_seq + 0.3)^1.6 + rnorm(length(stage_seq), sd = 0.01)

  fit <- rate_optimise(discharge_seq, stage_seq)
  rating_table <- as_rating_table(fit)

  expect_s3_class(rating_table, "reach.rate::FlodeRatingTable")
  rating_dt <- rating_table@table
  expect_true(is.data.table(rating_dt))
  expect_true(all(c("lower_level", "upper_level", "C", "A", "B") %in% names(rating_dt)))
  # A = -a: rate_optimise fit an 'a' close to +0.3, so A should be close to -0.3
  expect_equal(rating_dt$A[1], -fit@limbs$a[1])
  expect_equal(rating_dt$C[1], fit@limbs$C[1])
  expect_equal(rating_dt$B[1], fit@limbs$n[1])
})

test_that("as_rating_table carries the doubtful column through when present", {
  set.seed(1)
  stage_seq <- seq(0.5, 2.5, by = 0.05)
  discharge_seq <- 5 * stage_seq^1.6 + rnorm(length(stage_seq), sd = 0.01)

  fit <- rate_optimise(discharge_seq, stage_seq)
  fit <- flag_extrapolated_limbs(fit)
  rating_table <- as_rating_table(fit)

  expect_true("doubtful" %in% names(rating_table@table))
  expect_equal(rating_table@table$doubtful, fit@limbs$doubtful)
})

test_that("as_rating_table omits doubtful when absent from the fit", {
  set.seed(1)
  stage_seq <- seq(0.5, 2.5, by = 0.05)
  discharge_seq <- 5 * stage_seq^1.6 + rnorm(length(stage_seq), sd = 0.01)

  fit <- rate_optimise(discharge_seq, stage_seq)
  rating_table <- as_rating_table(fit)

  expect_false("doubtful" %in% names(rating_table@table))
})

test_that("as_rating_table rejects an object with no method", {
  # A plain data.table has no as_rating_table method -- S7 raises its
  # own no-applicable-method error. The exact wording is S7's, not ours.
  expect_error(as_rating_table(data.table(a = 1)))
})

test_that("run_demo wires rate_optimise and gap_check into a single pipeline", {
  pdf(NULL)
  on.exit(dev.off())

  result <- run_demo(plot = TRUE)

  expect_s3_class(result$fit, "reach.rate::FlodeRating")
  expect_true(is.data.table(result$fit@limbs))
  expect_equal(nrow(result$fit@limbs), 3L)
  expect_true("doubtful" %in% names(result$fit@limbs))
  expect_true(is.data.table(result$rc_raw))
  expect_true(is.data.table(result$rc_fixed))
  # The three independently-fitted limbs should produce at least one
  # junction gap before resolution
  expect_true(any(result$gaps$gap_flagged))
})

test_that("run_demo(plot = FALSE) does not require a graphics device", {
  result <- run_demo(plot = FALSE)
  expect_type(result, "list")
  expect_named(result, c("fit", "gaps", "rc_raw", "rc_fixed"))
})

test_that("bootstrap_to_table flips the sign of the offset per draw", {
  set.seed(1)
  stage_seq <- seq(0.5, 2.5, by = 0.05)
  discharge_seq <- 5 * (stage_seq + 0.3)^1.6 + rnorm(length(stage_seq), sd = 0.01)

  fit <- rate_optimise(discharge_seq, stage_seq, n_boot = 20L, boot_seed = 1L)
  boot_table_dt <- bootstrap_to_table(fit)
  boot_ok_dt <- fit@bootstrap[fit@bootstrap$success == TRUE]

  expect_true(is.data.table(boot_table_dt))
  expect_true(all(c("limb", "draw", "lower_level", "upper_level", "C", "A", "B") %in% names(boot_table_dt)))
  # bootstrap_to_table() only includes successful draws; boot_ok_dt above
  # is filtered the same way for a fair comparison
  expect_equal(nrow(boot_table_dt), nrow(boot_ok_dt))
  data.table::setorder(boot_ok_dt, limb, draw)
  expect_equal(boot_table_dt$A, -boot_ok_dt$a)
  expect_equal(boot_table_dt$B, boot_ok_dt$n)
  expect_true(all(boot_table_dt$lower_level == fit@limbs$lower_stage_m[1]))
})

test_that("bootstrap_to_table errors when fit has no bootstrap draws", {
  set.seed(1)
  stage_seq <- seq(0.5, 2.5, by = 0.05)
  discharge_seq <- 5 * stage_seq^1.6 + rnorm(length(stage_seq), sd = 0.01)
  fit <- rate_optimise(discharge_seq, stage_seq)

  expect_error(bootstrap_to_table(fit), "no bootstrap draws")
})

test_that("bootstrap_to_table rejects a non-FlodeRating object", {
  expect_error(bootstrap_to_table(data.table(a = 1)), "FlodeRating")
})

test_that("plot_rating_interval returns a ggplot object built from the interval band", {
  set.seed(1)
  stage_m <- seq(0.5, 3.5, by = 0.1)
  discharge_cms <- 5 * stage_m^1.6 + rnorm(length(stage_m), sd = 0.05)
  fit <- rate_optimise(discharge_cms, stage_m, n_boot = 100L, boot_seed = 1L)

  pdf(NULL)
  on.exit(dev.off())

  p <- plot_rating_interval(fit)

  expect_s3_class(p, "ggplot")
  expect_true(all(c("stage", "discharge_mean", "discharge_lower", "discharge_upper") %in% names(p$data)))
  expect_true(all(p$data$discharge_lower <= p$data$discharge_mean))
  expect_true(all(p$data$discharge_upper >= p$data$discharge_mean))
})

test_that("plot_rating_interval spans every limb for a multi-limb fit", {
  set.seed(2)
  stage_m <- seq(0.5, 3.5, by = 0.05)
  discharge_cms <- 5 * stage_m^1.6 + rnorm(length(stage_m), sd = 0.03)
  fit <- rate_optimise(discharge_cms, stage_m, control = c(1.5, 2.5), n_boot = 50L, boot_seed = 1L)

  pdf(NULL)
  on.exit(dev.off())

  p <- plot_rating_interval(fit)

  expect_equal(min(p$data$stage), fit@limbs$lower_stage_m[1])
  expect_equal(max(p$data$stage), fit@limbs$upper_stage_m[nrow(fit@limbs)])
})

test_that("plot_rating_interval errors when the fit has no bootstrap draws", {
  set.seed(1)
  stage_m <- seq(0.5, 2.5, by = 0.1)
  discharge_cms <- 5 * stage_m^1.6 + rnorm(length(stage_m), sd = 0.02)
  fit <- rate_optimise(discharge_cms, stage_m)

  expect_error(plot_rating_interval(fit), "no bootstrap draws")
})

test_that("plot_rating_interval rejects a non-FlodeRating object", {
  expect_error(plot_rating_interval(data.table(a = 1)), "FlodeRating")
})
