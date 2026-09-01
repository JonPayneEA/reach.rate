# Demonstrate a river cross-section against its rating curve

A self-contained, synthetic worked example pairing a river cross-section
(with annotated stage levels: low flow, bankfull, flood) against its
Manning-style power-law rating curve \\Q = a(H - H_0)^b\\, drawn side by
side so the shape of the channel and the shape of the rating are
directly comparable. Not a fitting tool – it builds a synthetic bed
profile and rating curve from fixed constants, for illustration.

## Usage

``` r
demo_cross_section_rating(plot = TRUE)
```

## Arguments

- plot:

  Logical. Print the combined two-panel figure as a side effect. Default
  `TRUE`.

## Value

Invisibly, a list with elements `cross_section` (the bed profile
data.table), `rating_curve` (the stage-discharge data.table), `gauged`
(the synthetic gauged points), `p_xs`/`p_rc` (the two individual
`ggplot` objects), and `combined` (the combined grob from
[`gridExtra::grid.arrange()`](https://rdrr.io/pkg/gridExtra/man/arrangeGrob.html)).

## See also

[`plot_rating_cross_section()`](https://jonpayneea.github.io/reach.rate/reference/plot_rating_cross_section.md)
for the same pairing built from a real fit and a real surveyed
cross-section, on one shared axis, rather than this function's fixed
synthetic illustration.

## Examples

``` r
result <- demo_cross_section_rating(plot = FALSE)
#> Warning: Removed 2 rows containing missing values or values outside the scale range
#> (`geom_point()`).
result$cross_section
#>     distance_m elevation_maod
#>          <num>          <num>
#>  1:          0           12.0
#>  2:          2           11.8
#>  3:          5           10.5
#>  4:          8            9.2
#>  5:         10            8.6
#>  6:         12            8.3
#>  7:         15            8.0
#>  8:         18            8.1
#>  9:         22            8.4
#> 10:         26            9.0
#> 11:         30            9.8
#> 12:         34           10.6
#> 13:         38           11.5
#> 14:         40           11.9
#> 15:         42           12.1
#> 16:         45           12.3
result$rating_curve
#> Index: <above_bankfull>
#>     stage_maod discharge_cms above_bankfull
#>          <num>         <num>         <lgcl>
#>  1:       8.05    0.08560157          FALSE
#>  2:       8.10    0.26864654          FALSE
#>  3:       8.15    0.52448349          FALSE
#>  4:       8.20    0.84310320          FALSE
#>  5:       8.25    1.21837859          FALSE
#>  6:       8.30    1.64600563          FALSE
#>  7:       8.35    2.12272395          FALSE
#>  8:       8.40    2.64594146          FALSE
#>  9:       8.45    3.21352656          FALSE
#> 10:       8.50    3.82368188          FALSE
#> 11:       8.55    4.47486238          FALSE
#> 12:       8.60    5.16571937          FALSE
#> 13:       8.65    5.89506074          FALSE
#> 14:       8.70    6.66182181          FALSE
#> 15:       8.75    7.46504329          FALSE
#> 16:       8.80    8.30385438          FALSE
#> 17:       8.85    9.17745943          FALSE
#> 18:       8.90   10.08512735          FALSE
#> 19:       8.95   11.02618297          FALSE
#> 20:       9.00   12.00000000          FALSE
#> 21:       9.05   13.00599520          FALSE
#> 22:       9.10   14.04362346          FALSE
#> 23:       9.15   15.11237364          FALSE
#> 24:       9.20   16.21176509          FALSE
#> 25:       9.25   17.34134456          FALSE
#> 26:       9.30   18.50068366          FALSE
#> 27:       9.35   19.68937652          FALSE
#> 28:       9.40   20.90703782          FALSE
#> 29:       9.45   22.15330107          FALSE
#> 30:       9.50   23.42781703          FALSE
#> 31:       9.55   24.73025235          FALSE
#> 32:       9.60   26.06028839          FALSE
#> 33:       9.65   27.41762007          FALSE
#> 34:       9.70   28.80195492          FALSE
#> 35:       9.75   30.21301222          FALSE
#> 36:       9.80   31.65052218          FALSE
#> 37:       9.85   33.11422520          FALSE
#> 38:       9.90   34.60387126          FALSE
#> 39:       9.95   36.11921931          FALSE
#> 40:      10.00   37.66003670          FALSE
#> 41:      10.05   39.22609870          FALSE
#> 42:      10.10   40.81718806          FALSE
#> 43:      10.15   42.43309454          FALSE
#> 44:      10.20   44.07361457           TRUE
#> 45:      10.25   45.73855089           TRUE
#> 46:      10.30   47.42771216           TRUE
#> 47:      10.35   49.14091274           TRUE
#> 48:      10.40   50.87797234           TRUE
#> 49:      10.45   52.63871577           TRUE
#> 50:      10.50   54.42297272           TRUE
#> 51:      10.55   56.23057749           TRUE
#> 52:      10.60   58.06136881           TRUE
#> 53:      10.65   59.91518961           TRUE
#> 54:      10.70   61.79188686           TRUE
#> 55:      10.75   63.69131137           TRUE
#> 56:      10.80   65.61331764           TRUE
#> 57:      10.85   67.55776369           TRUE
#> 58:      10.90   69.52451094           TRUE
#> 59:      10.95   71.51342404           TRUE
#> 60:      11.00   73.52437075           TRUE
#> 61:      11.05   75.55722184           TRUE
#> 62:      11.10   77.61185093           TRUE
#> 63:      11.15   79.68813444           TRUE
#> 64:      11.20   81.78595143           TRUE
#> 65:      11.25   83.90518353           TRUE
#> 66:      11.30   86.04571483           TRUE
#> 67:      11.35   88.20743182           TRUE
#> 68:      11.40   90.39022328           TRUE
#> 69:      11.45   92.59398021           TRUE
#> 70:      11.50   94.81859576           TRUE
#> 71:      11.55   97.06396513           TRUE
#> 72:      11.60   99.32998555           TRUE
#> 73:      11.65  101.61655617           TRUE
#> 74:      11.70  103.92357801           TRUE
#> 75:      11.75  106.25095391           TRUE
#> 76:      11.80  108.59858847           TRUE
#>     stage_maod discharge_cms above_bankfull
#>          <num>         <num>         <lgcl>
```
