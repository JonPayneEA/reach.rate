# ============================================================ #
# Tool:         s7_external
# Description:  Handles for the generics this package adds S7 methods to but
#               does not own: print(), plot() and ggplot2's autoplot().
#               Methods are registered against these handles, never against
#               the bare names. `method(f, Class) <- fn` is a replacement
#               call, so it assigns its result back to `f`; under S7 1.0.0
#               that result is a placeholder, which silently replaced the real
#               autoplot() (and print and plot) inside the package namespace
#               and broke the exported autoplot(). Registering against a
#               separately named handle leaves the real function untouched, on
#               every S7 version.
# ============================================================ #

.s7_print    <- S7::new_external_generic("base", "print", "x")
.s7_plot     <- S7::new_external_generic("base", "plot", "x")
.s7_autoplot <- S7::new_external_generic("ggplot2", "autoplot", "object")
