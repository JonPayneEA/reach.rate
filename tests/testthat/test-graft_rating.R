build_crossing_pair <- function() {
  # new_rating's top limb and existing_rating's first limb genuinely
  # cross within (3.41, 6): existing starts above new at H = 3.41 but
  # has a smaller exponent, so new overtakes it further up.
  new_table <- data.table::data.table(
    lower_level = c(0.0, 1.5), upper_level = c(1.5, 3.41),
    C = c(2.5, 2.831), a = c(0.0, -0.886), n = c(1.50, 1.935)
  )
  existing_table <- data.table::data.table(
    lower_level = 3.41, upper_level = 6.0,
    C = 0.3128, a = 0, n = 4.095
  )
  list(new = new_table, existing = existing_table)
}

test_that("graft_rating finds a genuine crossing and joins there", {
  pair <- build_crossing_pair()
  grafted <- graft_rating(pair$new, pair$existing)

  expect_true(S7::S7_inherits(grafted, FlodeRatingTable))
  expect_equal(grafted@status, "grafted")
  expect_equal(nrow(grafted@table), 3L)
  expect_equal(grafted@table$source, c("new", "new", "existing"))

  # Contiguous end to end
  tbl <- grafted@table
  n <- nrow(tbl)
  expect_true(all(abs(tbl$upper_level[-n] - tbl$lower_level[-1L]) < 1e-8))

  # Curves genuinely agree at the join
  join_h <- tbl$upper_level[2]
  q_new <- tbl$C[2] * (join_h - tbl$a[2])^tbl$n[2]
  q_existing <- tbl$C[3] * (join_h - tbl$a[3])^tbl$n[3]
  expect_equal(q_new, q_existing, tolerance = 1e-6)

  # The join actually moved the boundary (not left at the original 3.41)
  expect_false(isTRUE(all.equal(join_h, 3.41)))
})

test_that("graft_rating only retains existing limbs above new_rating's top", {
  pair <- build_crossing_pair()
  # Add a lower existing limb entirely below new_rating's top -- should be dropped
  existing_multi <- rbind(
    data.table::data.table(lower_level = 2.0, upper_level = 3.41, C = 1, a = 0, n = 1.2),
    pair$existing
  )
  grafted <- graft_rating(pair$new, existing_multi)
  expect_equal(nrow(grafted@table), 3L)
  expect_true(all(grafted@table[source == "existing"]$lower_level >= 3.41 - 1e-8))
})

test_that("graft_rating errors by default when no crossing exists", {
  new_table <- data.table::data.table(lower_level = 0, upper_level = 2, C = 1, a = 0, n = 1.5)
  existing_table <- data.table::data.table(lower_level = 2, upper_level = 5, C = 100, a = 0, n = 1.5)
  expect_error(graft_rating(new_table, existing_table), "no crossing found")
})

test_that("graft_rating on_no_crossing = 'join_at_top' hard-joins with a warning", {
  new_table <- data.table::data.table(lower_level = 0, upper_level = 2, C = 1, a = 0, n = 1.5)
  existing_table <- data.table::data.table(lower_level = 2, upper_level = 5, C = 100, a = 0, n = 1.5)

  expect_warning(
    grafted <- graft_rating(new_table, existing_table, on_no_crossing = "join_at_top"),
    "discharge jumps"
  )
  expect_equal(grafted@table$upper_level[1], 2)
  expect_equal(grafted@table$lower_level[2], 2)
})

test_that("graft_rating errors when no existing limb extends above new_rating's top", {
  new_table <- data.table::data.table(lower_level = 0, upper_level = 5, C = 1, a = 0, n = 1.5)
  existing_table <- data.table::data.table(lower_level = 0, upper_level = 3, C = 1, a = 0, n = 1.5)
  expect_error(graft_rating(new_table, existing_table), "nothing to graft onto")
})

test_that("graft_rating errors on a non-contiguous existing_rating", {
  new_table <- data.table::data.table(lower_level = 0, upper_level = 2, C = 1, a = 0, n = 1.5)
  existing_table <- data.table::data.table(
    lower_level = c(2.0, 3.5), upper_level = c(2.9, 6.0),
    C = c(1, 1), a = c(0, 0), n = c(1.5, 1.5)
  )
  expect_error(graft_rating(new_table, existing_table), "contiguous")
})

test_that("graft_rating accepts a FlodeRating for new_rating and a FlodeRatingTable for existing_rating, and previous references it", {
  set.seed(1)
  stage_m <- seq(0.3, 3, by = 0.05)
  discharge_cms <- 4 * stage_m^1.6 + rnorm(length(stage_m), sd = 0.05)
  fit <- rate_optimise(discharge_cms, stage_m)
  q_at_top <- fit@limbs$C * (3 - fit@limbs$a)^fit@limbs$n

  existing_table <- data.table::data.table(
    lower_level = 3.0, upper_level = 6.0,
    C = (q_at_top * 1.2) / 3^1.3, a = 0, n = 1.3
  )
  existing_rt <- FlodeRatingTable(table = existing_table)

  grafted <- graft_rating(fit, existing_rt, search_range = c(3.0, 6.0))

  expect_true(S7::S7_inherits(grafted, FlodeRatingTable))
  expect_true(identical(grafted@previous, fit))
  expect_equal(nrow(grafted@table), nrow(fit@limbs) + 1L)
})

test_that("graft_rating validates required columns and search_range", {
  pair <- build_crossing_pair()
  expect_error(graft_rating(data.frame(x = 1), pair$existing), "missing column")
  expect_error(
    graft_rating(pair$new, pair$existing, search_range = c(5, 1)),
    "lower < upper"
  )
})
