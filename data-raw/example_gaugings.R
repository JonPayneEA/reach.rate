# Builds inst/extdata/example_gaugings.csv, the file vignette("start_here")
# opens. It is synthetic: a made-up station ("TEST001", Example Weir) with a
# single-limb rating Q = 3.2 (H - 0.1)^1.6 and 4% multiplicative scatter, in
# the column layout of an Environment Agency gauging export. A handful of
# faults are put in on purpose, because a real archive has them and the
# vignette shows what the package does about each:
#   - a stage of "---" and a discharge of "---" (placeholders);
#   - a stage with a unit attached ("1.60m");
#   - a gauging entered twice;
#   - a zero discharge at a positive stage;
#   - one gauging 60% too high, with a remark;
#   - one gauging with no time of day.
# Run from the package root:  Rscript data-raw/example_gaugings.R
set.seed(2024)
n <- 42
stage <- sort(round(c(runif(n - 6, 0.3, 2.2), runif(6, 2.2, 2.9)), 3))
q <- 3.2 * (stage - 0.1)^1.6 * exp(rnorm(n, sd = 0.04))
dates <- sort(as.Date("2014-03-11") + sample(0:3600, n))
time <- sprintf("%02d:%02d:00", sample(8:16, n, replace = TRUE), sample(c(0, 15, 30, 45), n, replace = TRUE))
out <- data.frame(
  `Station number` = "TEST001", `Station name` = "Example Weir",
  Date = format(dates, "%d/%m/%Y"), Time = time,
  Stage = sprintf("%.3f", stage), Flow = sprintf("%.4f", q),
  Remark = "", check.names = FALSE, stringsAsFactors = FALSE
)
# Make sure at least one date cannot be read as month-first, so the format is detected, not guessed.
out$Date[1] <- format(as.Date("2014-03-24"), "%d/%m/%Y")
out$Stage[7] <- "---"; out$Flow[7] <- "---"; out$Remark[7] <- "dry bed"
out$Stage[15] <- paste0(trimws(out$Stage[15]), "m")
out <- rbind(out, out[22, ])                      # entered twice
out$Flow[30] <- "0.0000"; out$Remark[30] <- "pool, no flow"
out$Flow[35] <- sprintf("%.4f", as.numeric(out$Flow[35]) * 1.6); out$Remark[35] <- "wading, high wind"
out$Time[40] <- ""
write.csv(out, "inst/extdata/example_gaugings.csv", row.names = FALSE, quote = TRUE)
cat("wrote", nrow(out), "rows\n")
