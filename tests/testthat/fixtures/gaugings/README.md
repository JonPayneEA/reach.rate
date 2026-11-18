# Gauging input fixtures

Each file stands for a way real gauging exports differ. `make-fixtures.R`
rebuilds them; `test-read_gaugings_inputs.R` has one test per file. The
numbering is the test numbering. The set is the package's own: it was not
taken from an external specification.

| file | what it exercises |
|---|---|
| 01 | clean export with the default headers |
| 02 | semicolons and a decimal comma |
| 03, 04 | tab and pipe delimited |
| 05 | placeholder text (`---`, `NULL`, `N/A`, blank) |
| 06 | text that is not a number |
| 07 | blank station id |
| 08 | month-first dates |
| 09 | genuinely ambiguous dates |
| 10 | ISO dates |
| 11 | one date-time column |
| 12 | missing time of day |
| 13 | unreadable time of day |
| 14 | dates outside 1800 to next year |
| 15 | extra columns and a repeated header |
| 16 | other header names, mapped by the caller |
| 17 | a spreadsheet with Excel date cells and an unrelated first sheet |
| 18 | byte-order mark, CRLF, blank lines, a quoted comma |
| 19 | a header and nothing else |
| 20 | Latin-1 encoding |
