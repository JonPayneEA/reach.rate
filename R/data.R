#' Teaching data: spot gaugings from a UK gauging station
#'
#' **Teaching data, for learning the package and for the examples. Do not
#' use it to build a rating for operational use.** It is a spot-gauging
#' record spanning 1974 to 2024, provided as an example of the messiness of an
#' actual station history: irregular gauging intervals, decades-long gaps, a
#' handful of high-flow gaugings among many low-flow ones, and one gauging
#' recorded at zero stage. For a file to read from disk, see the synthetic
#' `example_gaugings.csv` in `system.file("extdata", package = "reach.rate")`
#' and `vignette("start_here")`.
#'
#' @format A [data.table::data.table] with 223 rows and 3 columns:
#' \describe{
#'   \item{gauging_datetime}{POSIXct (UTC) date and time of the spot gauging.}
#'   \item{discharge_cms}{Measured discharge, in cubic metres per second.}
#'   \item{stage_m}{Measured stage, in metres, on the station's local datum.}
#' }
#'
#' @details
#' One gauging (17 November 1976) was recorded at `stage_m = 0` with a
#' nonzero discharge. Since the rating equation \eqn{Q = C(H-a)^n} requires
#' `stage_m > a` for every gauging in a limb, that row is excluded in the
#' example below rather than passed to [rate_optimise()] as-is.
#'
#' @examples
#' # A single-limb fit across the whole record (excluding the zero-stage
#' # gauging, which no C(H-a)^n curve with a finite `a` can pass through):
#' dt <- station_gaugings[station_gaugings$stage_m > 0, ]
#' fit <- rate_optimise(dt$discharge_cms, dt$stage_m)
#' fit@limbs[, .(limb, C, a, n, rmse_cms, r_squared, n_obs)]
#' autoplot(fit)
#'
#' @source Environment Agency spot-gauging records for a UK river gauging
#'   station.
"station_gaugings"
