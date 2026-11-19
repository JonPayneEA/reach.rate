# Every exported function carries a runnable example, which pkgdown renders on
# the reference site. This fails when a new export is added without one.
test_that("every exported function has an example in its help page", {
  rd_dir <- file.path(testthat::test_path("..", ".."), "man")
  skip_if_not(dir.exists(rd_dir), "man/ is not available (installed package)")

  exports <- getNamespaceExports("reach.rate")
  rd_files <- list.files(rd_dir, pattern = "\\.Rd$", full.names = TRUE)
  has_example <- function(f) any(grepl("^\\\\examples\\{", readLines(f, warn = FALSE)))
  aliases <- function(f) {
    l <- readLines(f, warn = FALSE)
    sub("^\\\\alias\\{(.*)\\}$", "\\1", l[grepl("^\\\\alias\\{", l)])
  }
  covered <- unlist(lapply(rd_files[vapply(rd_files, has_example, logical(1))], aliases))
  # A re-export (autoplot, from ggplot2) is documented where it is defined.
  reexported <- unlist(lapply(rd_files[basename(rd_files) == "reexports.Rd"], aliases))
  missing <- setdiff(setdiff(exports, reexported), covered)
  expect_identical(sort(missing), character(0))
})
