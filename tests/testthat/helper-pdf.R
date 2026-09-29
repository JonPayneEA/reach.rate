# R's default pdf() device encodes text as Latin-1. A plot label outside
# that set (a Greek capital delta, a Unicode minus sign, a subscript
# digit) makes it warn "conversion failure ... dot substituted" or, on
# some platforms and R versions, error outright. R CMD check runs tests
# on that device, and users save plots through it, so every test that
# draws a plot renders through this helper: an error fails the test as
# usual, and a conversion warning now fails it too instead of passing
# with a mangled label.
expect_pdf_renders <- function(expr) {
  conversion_warnings <- character()
  grDevices::pdf(NULL)
  on.exit(grDevices::dev.off(), add = TRUE)
  value <- withCallingHandlers(
    expr,
    warning = function(w) {
      if (grepl("conversion failure", conditionMessage(w), fixed = TRUE)) {
        conversion_warnings <<- c(conversion_warnings, conditionMessage(w))
        invokeRestart("muffleWarning")
      }
    }
  )
  expect(
    length(conversion_warnings) == 0L,
    paste0(
      "Plot text the PDF device cannot encode:\n",
      paste(unique(conversion_warnings), collapse = "\n")
    )
  )
  invisible(value)
}
