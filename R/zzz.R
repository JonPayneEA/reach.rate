# ============================================================ #
# File:         zzz.R
# Purpose:      Package load hook. S7's own "Packages" vignette
#               recommends calling S7::methods_register() from .onLoad():
#               it registers this package's S7 methods (rating_plot,
#               apply_rating, as_rating_table, and the three FlodeX print
#               methods) for S3-compatible dispatch, so print()/format()
#               and friends keep working correctly regardless of how the
#               package was loaded or in what order dependent packages
#               attach.
# ============================================================ #

.onLoad <- function(libname, pkgname) {
  S7::methods_register()
}
