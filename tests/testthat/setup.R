# Safety net for the test files carried over from this package's box-module
# days: package Imports (data.table among them) are visible unqualified
# from inside the package's own namespace, which is where testthat runs
# these files -- but attaching data.table directly here guarantees every
# bare data.table()/:=/.N/setorder() call in tests/testthat/*.R resolves
# the same way regardless of how a given testthat version sources them.
library(data.table)
