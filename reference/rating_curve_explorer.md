# Launch the interactive rating curve explorer

A teaching/exploration Shiny app: adjust `C` (scale), `a` (offset), and
`n` (exponent) per limb with sliders and watch the curve shape change
live. Add a second or third limb to see whether independently-fitted
segments meet cleanly at a junction, or don't – the "Align" button
rescales the upper limb's `C` to close the gap, mirroring
[`align_limb_equations()`](https://jonpayneea.github.io/reach.rate/reference/align_limb_equations.md).
This app does not touch gauging data or call
[`rate_optimise()`](https://jonpayneea.github.io/reach.rate/reference/rate_optimise.md);
it is purely for building intuition about the equation and the
junction-gap problem.

Requires the shiny package (Suggests, not a hard dependency of this
package).

## Usage

``` r
rating_curve_explorer()
```

## Value

A `shiny.appobj`, invisibly. Auto-launches when printed (which happens
automatically if you just call `rating_curve_explorer()` at the
console); pass it to
[`shiny::runApp()`](https://rdrr.io/pkg/shiny/man/runApp.html)
explicitly otherwise.

## Examples

``` r
if (FALSE) { # \dontrun{
rating_curve_explorer()
} # }
```
