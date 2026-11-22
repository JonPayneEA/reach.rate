# ============================================================ #
# Tool:         target_environment_test.R
# Description:  Tests that an installation of reach.rate works on THIS machine:
#               it loads, its dependencies are present, the ten reference
#               cases pass, the guided workflow runs end to end and round-trips
#               through an export, files can be written and read, dates are
#               read correctly under this locale, and a fit takes a sensible
#               time. It writes a plain-text record to keep.
# Document:     governance/07_target_environment_test.md (the procedure)
# Status:       DRAFT 0.1, 22 November 2026
# Dependencies: reach.rate (installed). Base R only otherwise. testthat and
#               rmarkdown are used if present and their absence is recorded.
#
# Usage, from a command line:
#   Rscript target_environment_test.R
#   Rscript target_environment_test.R --output-dir="D:/managed/path" \
#       --gauging-file="D:/data/station_gaugings.csv" --report="record.txt"
# Or from R:
#   source("target_environment_test.R"); res <- reach_rate_target_test()
#
# It never changes the installation, and it writes only inside output-dir.
# It exits with status 1 if any check FAILS. SKIPPED is not PASS: a skipped
# check is a check not done, and the record says so.
# ============================================================ #

reach_rate_target_test <- function(output_dir = tempdir(), gauging_file = NULL, report = NULL,
                                   expected_version = NULL, max_fit_seconds = 10, max_bootstrap_seconds = 60) {
  started <- Sys.time()
  results <- list()
  add <- function(id, check, status, detail = "") {
    results[[length(results) + 1L]] <<- data.frame(id = id, check = check, status = status,
                                                  detail = paste(detail, collapse = " "), stringsAsFactors = FALSE)
    invisible(NULL)
  }
  run <- function(id, check, code) {
    out <- tryCatch(code(), error = function(e) list(status = "FAIL", detail = paste("error:", conditionMessage(e))))
    add(id, check, out$status, out$detail)
  }
  work <- file.path(output_dir, paste0("reach_rate_target_test_", format(Sys.time(), "%Y%m%d_%H%M%S")))
  if (!dir.create(work, recursive = TRUE, showWarnings = FALSE)) stop("cannot create ", work)
  on.exit(unlink(work, recursive = TRUE), add = TRUE)

  # TE-01 the environment: recorded, never judged
  info <- Sys.info()
  have <- function(p) requireNamespace(p, quietly = TRUE)
  env <- c(
    sprintf("Date and time:   %s", format(started, "%Y-%m-%d %H:%M:%S %Z")),
    sprintf("Machine:         %s (%s %s, %s)", info[["nodename"]], info[["sysname"]], info[["release"]], info[["machine"]]),
    sprintf("R:               %s", R.version.string),
    sprintf("Platform:        %s", R.version$platform),
    sprintf("Locale:          %s", Sys.getlocale("LC_COLLATE")),
    sprintf("Time zone:       %s", Sys.timezone()),
    sprintf("Library paths:   %s", paste(.libPaths(), collapse = "; ")),
    sprintf("Output folder:   %s", normalizePath(output_dir, mustWork = FALSE)),
    sprintf("pandoc:          %s", if (have("rmarkdown") && rmarkdown::pandoc_available()) as.character(rmarkdown::pandoc_version()) else "not available"),
    sprintf("testthat:        %s", if (have("testthat")) as.character(utils::packageVersion("testthat")) else "not installed")
  )
  add("TE-01", "Environment recorded", "INFO", "see the record header")

  # TE-02 the package loads
  loaded <- have("reach.rate")
  if (!loaded) {
    add("TE-02", "reach.rate loads", "FAIL", "reach.rate is not installed, or does not load")
    return(.finish(results, env, started, report, output_dir))
  }
  suppressPackageStartupMessages(library(reach.rate))
  ver <- as.character(utils::packageVersion("reach.rate"))
  ok_ver <- is.null(expected_version) || identical(ver, expected_version)
  add("TE-02", "reach.rate loads, at the expected version", if (ok_ver) "PASS" else "FAIL",
      sprintf("version %s%s", ver, if (is.null(expected_version)) " (no expected version given)" else sprintf("; expected %s", expected_version)))
  env <- c(env, sprintf("reach.rate:      %s", ver))

  # TE-03 dependencies present
  run("TE-03", "Every imported package is installed", function() {
    imp <- utils::packageDescription("reach.rate")$Imports
    pk <- trimws(sub("\\s*\\(.*$", "", strsplit(gsub("\n", " ", imp), ",")[[1L]]))
    pk <- pk[nzchar(pk)]
    missing <- pk[!vapply(pk, have, logical(1))]
    vers <- vapply(pk[!pk %in% missing], function(p) paste0(p, " ", utils::packageVersion(p)), "")
    env <<- c(env, sprintf("Imports:         %s", paste(vers, collapse = ", ")))
    list(status = if (length(missing)) "FAIL" else "PASS",
         detail = if (length(missing)) paste("missing:", paste(missing, collapse = ", ")) else sprintf("%d imports present", length(pk)))
  })

  # TE-04 the ten reference cases
  run("TE-04", "The ten reference cases pass", function() {
    r <- reach.rate::check_reference_cases()
    bad <- r$id[!r$passed]
    list(status = if (length(bad)) "FAIL" else "PASS",
         detail = if (length(bad)) paste("failed:", paste(bad, collapse = ", ")) else
           sprintf("%d of %d passed; largest error %.3f", sum(r$passed), nrow(r), max(r$max_rel_error)))
  })

  # TE-05 the package's own tests, if they were installed with it
  tests_dir <- system.file("tests", package = "reach.rate")
  if (nzchar(tests_dir) && have("testthat")) {
    run("TE-05", "The package's test suite passes", function() {
      res <- as.data.frame(suppressWarnings(testthat::test_dir(file.path(tests_dir, "testthat"), reporter = "silent",
                                                                stop_on_failure = FALSE, package = "reach.rate")))
      list(status = if (sum(res$failed) + sum(res$error) == 0) "PASS" else "FAIL",
           detail = sprintf("%d passed, %d failed, %d errors, %d skipped", sum(res$passed), sum(res$failed), sum(res$error), sum(res$skipped)))
    })
  } else {
    add("TE-05", "The package's test suite passes", "SKIPPED",
        "tests are not installed with the package. Run R CMD check on the source, or install with --install-tests")
  }

  # TE-06 the guided workflow, end to end, with a round trip
  example <- system.file("extdata", "example_gaugings.csv", package = "reach.rate")
  workflow <- function(file, label) {
    run(label[1L], label[2L], function() {
      g <- suppressMessages(reach.rate::read_gaugings(file))
      v <- reach.rate::validate_gaugings(g)
      fit <- suppressMessages(reach.rate::fit_rating(g, seed = 1))
      fit <- reach.rate::set_lifecycle(fit, "under_review", by = "Target test A", reason = "environment test")
      a <- reach.rate::assess_rating(fit)
      fit <- reach.rate::set_lifecycle(fit, "approved", by = "Target test B", reason = "environment test",
                                       allow_self_approval = FALSE)
      dir <- file.path(work, gsub("[^A-Za-z0-9]", "_", label[1L]))
      reach.rate::export_rating(fit, a, path = dir)
      back <- reach.rate::import_rating(dir)
      equal <- isTRUE(all.equal(back$rating, fit, tolerance = 0)) && nrow(reach.rate::rating_lifecycle(back$rating)) == 2L
      ck <- reach.rate::assessment_checks(a)
      list(status = if (equal) "PASS" else "FAIL",
           detail = sprintf("%d rows read, %d assessment checks (%d warnings, %d fails), export and import %s",
                            nrow(g), nrow(ck), sum(ck$status == "warning"), sum(ck$status == "fail"),
                            if (equal) "round-trip equal" else "NOT equal"))
    })
  }
  if (nzchar(example)) workflow(example, c("TE-06", "Guided workflow on the shipped example, with export and import round trip"))
  else add("TE-06", "Guided workflow on the shipped example", "FAIL", "the example file is missing from the installation")
  if (!is.null(gauging_file)) {
    if (file.exists(gauging_file)) workflow(gauging_file, c("TE-06b", "Guided workflow on the supplied gauging file"))
    else add("TE-06b", "Guided workflow on the supplied gauging file", "FAIL", paste("file not found:", gauging_file))
  }

  # TE-07 the review report
  if (have("rmarkdown") && have("knitr") && rmarkdown::pandoc_available()) {
    run("TE-07", "The review report builds", function() {
      g <- suppressMessages(reach.rate::read_gaugings(example))
      fit <- suppressMessages(reach.rate::fit_rating(g, seed = 1))
      out <- reach.rate::rating_report(fit, reach.rate::assess_rating(fit), path = file.path(work, "report.html"))
      list(status = if (file.exists(out) && file.size(out) > 10000) "PASS" else "FAIL", detail = sprintf("%d bytes", file.size(out)))
    })
  } else {
    add("TE-07", "The review report builds", "SKIPPED", "rmarkdown, knitr or pandoc is not available. The core workflow does not need them")
  }

  # TE-08 files: spaces and length, then non-ASCII characters. Two checks, so a
  # failure says which, because a non-UTF-8 locale fails the second and not the first.
  roundtrip_in <- function(dir) {
    g <- suppressMessages(reach.rate::read_gaugings(example))
    fit <- suppressMessages(reach.rate::fit_rating(g, seed = 1))
    reach.rate::export_rating(fit, path = dir)
    back <- reach.rate::import_rating(dir)
    list(status = if (isTRUE(all.equal(back$rating, fit, tolerance = 0))) "PASS" else "FAIL",
         detail = sprintf("path of %d characters", nchar(normalizePath(dir, mustWork = FALSE))))
  }
  run("TE-08a", "Export and import work in a path with spaces and a long length", function() {
    roundtrip_in(file.path(work, "reach test folder", paste(rep("long_folder_name", 8L), collapse = "_")))
  })
  run("TE-08b", "Export and import work in a path with accented characters", function() {
    r <- roundtrip_in(file.path(work, "reach test caf\u00e9 \u00fc"))
    r$detail <- paste0(r$detail, "; locale ", Sys.getlocale("LC_CTYPE"))
    r
  })

  # TE-09 dates under this locale
  run("TE-09", "Day-first dates are read correctly under this locale", function() {
    g <- suppressMessages(reach.rate::read_gaugings(example))
    got <- format(g$observation_time[1L], "%Y-%m-%d %H:%M")
    list(status = if (identical(got, "2014-03-24 16:45")) "PASS" else "FAIL",
         detail = sprintf("first gauging read as %s (the file says 24/03/2014 16:45)", got))
  })

  # TE-10 speed, at a realistic size
  run("TE-10", "A 100-gauging fit and a 200-draw bootstrap finish in time", function() {
    set.seed(1); h <- seq(0.3, 3.4, length.out = 100)
    d <- data.frame(stage_m = h, discharge_cms = 3 * h^1.6 * exp(stats::rnorm(100, sd = 0.03)))
    t1 <- system.time(suppressMessages(reach.rate::fit_rating(d, quiet = TRUE)))[["elapsed"]]
    t2 <- system.time(suppressMessages(reach.rate::fit_rating(d, n_boot = 200, seed = 1, quiet = TRUE)))[["elapsed"]]
    list(status = if (t1 <= max_fit_seconds && t2 <= max_bootstrap_seconds) "PASS" else "FAIL",
         detail = sprintf("fit %.2f s (limit %g), bootstrap %.2f s (limit %g). Build machine: 0.02 s and 0.26 s", t1, max_fit_seconds, t2, max_bootstrap_seconds))
  })

  .finish(results, env, started, report, output_dir)
}

# Assemble, print and write the record. Returns the results invisibly.
.finish <- function(results, env, started, report, output_dir) {
  res <- do.call(rbind, results)
  fails <- sum(res$status == "FAIL")
  skipped <- sum(res$status == "SKIPPED")
  overall <- if (fails) "FAIL" else if (skipped) "PASS WITH SKIPPED CHECKS" else "PASS"
  lines <- c(
    "reach.rate target-environment test record",
    "Procedure: governance/07_target_environment_test.md (DRAFT 0.1)",
    strrep("-", 72), env, strrep("-", 72),
    sprintf("%-7s %-8s %s", res$id, res$status, res$check),
    "",
    unlist(lapply(seq_len(nrow(res)), function(i) if (nzchar(res$detail[i])) sprintf("  %s: %s", res$id[i], res$detail[i]))),
    strrep("-", 72),
    sprintf("Overall: %s (%d checks: %d PASS, %d FAIL, %d SKIPPED, %d INFO)", overall, nrow(res),
            sum(res$status == "PASS"), fails, skipped, sum(res$status == "INFO")),
    sprintf("Elapsed: %.1f s", as.numeric(difftime(Sys.time(), started, units = "secs"))),
    "A SKIPPED check is a check not done. It is not a pass.",
    "",
    "Run by:      ______________________   Date: ______________",
    "Checked by:  ______________________   Date: ______________"
  )
  if (is.null(report)) report <- file.path(output_dir, sprintf("reach_rate_target_test_%s_%s.txt",
                                                                 gsub("[^A-Za-z0-9]", "", Sys.info()[["nodename"]]), format(started, "%Y%m%d_%H%M")))
  writeLines(lines, report)
  cat(paste(lines, collapse = "\n"), "\n\nRecord written to: ", normalizePath(report, mustWork = FALSE), "\n", sep = "")
  invisible(res)
}

`%||%` <- function(a, b) if (is.null(a)) b else a

# Run from a command line.
if (!interactive() && sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  get <- function(name) { m <- grep(paste0("^--", name, "="), args, value = TRUE); if (length(m)) sub(paste0("^--", name, "="), "", m[1L]) else NULL }
  res <- reach_rate_target_test(output_dir = get("output-dir") %||% getwd(), gauging_file = get("gauging-file"),
                                report = get("report"), expected_version = get("expected-version"))
  quit(status = if (any(res$status == "FAIL")) 1L else 0L)
}
