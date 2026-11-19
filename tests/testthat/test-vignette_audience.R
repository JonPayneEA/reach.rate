test_that("every vignette declares its audience on its own line", {
  skip_if_not(dir.exists(testthat::test_path("..", "..", "vignettes")) ||
                dir.exists("vignettes"), "vignette sources not available")
  dir <- if (dir.exists(testthat::test_path("..", "..", "vignettes")))
    testthat::test_path("..", "..", "vignettes") else "vignettes"
  files <- list.files(dir, pattern = "\\.Rmd$", full.names = TRUE)
  expect_gt(length(files), 0)
  levels <- c("novice", "practitioner", "technical", "specialist")
  for (f in files) {
    lines <- readLines(f, warn = FALSE)
    hit <- grep("^\\*\\*Audience:\\*\\* ", lines, value = TRUE)
    expect_length(hit, 1)
    lvl <- sub("^\\*\\*Audience:\\*\\* ([a-z]+)\\..*$", "\\1", hit)
    expect_true(lvl %in% levels, info = basename(f))
  }
})

test_that("the example gaugings file ships and reads", {
  path <- system.file("extdata", "example_gaugings.csv", package = "reach.rate")
  skip_if(path == "")
  g <- read_gaugings(path)
  expect_gt(nrow(g), 30)
  expect_true(any(!is.na(g$read_issue)))
})
