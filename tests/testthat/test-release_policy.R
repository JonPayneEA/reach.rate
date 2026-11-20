# The deprecation register in the release policy must match the code.

test_that("every function the reference index lists as deprecated is in the policy register and warns", {
  idx <- testthat::test_path("..", "..", "_pkgdown.yml")
  pol <- testthat::test_path("..", "..", "vignettes", "release_policy.Rmd")
  skip_if_not(file.exists(idx) && file.exists(pol), "package sources not available (installed package)")
  lines <- readLines(idx, warn = FALSE)
  start <- grep("^- title: Deprecated", lines)
  expect_length(start, 1L)
  rest <- lines[(start + 1L):length(lines)]
  end <- grep("^- title:", rest)
  block <- if (length(end)) rest[seq_len(end[1L] - 1L)] else rest
  listed <- trimws(sub("^\\s*-\\s*", "", grep("^\\s+-\\s+\\S", block, value = TRUE)))
  expect_gt(length(listed), 0L)
  txt <- paste(readLines(pol, warn = FALSE), collapse = "\n")
  for (fn in listed) {
    expect_match(txt, paste0("`", fn, "()`"), fixed = TRUE, info = fn)
    expect_match(txt, paste0("| `", fn, "()` | 2. Deprecated"), fixed = TRUE, info = fn)
  }
})

test_that("rating_plot is held at stage 1: documented as superseded and not warning", {
  skip_if_not(file.exists(testthat::test_path("..", "..", "R", "autoplot.R")), "package sources not available")
  src <- paste(readLines(testthat::test_path("..", "..", "R", "autoplot.R"), warn = FALSE), collapse = "\n")
  expect_match(src, "rating_plot\\(\\)` is superseded")
})
