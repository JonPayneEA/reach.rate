# ---------------------------------------------------------------------------
# FlodeAssessment -- the outcome of a set of checks on some subject.
#
# validate_gaugings() makes one for evidence; assess_rating() will make one
# for a fitted rating. The class does not know what was checked. It holds a
# table of checks with a fixed schema, and holds each check to the rules
# for its domain:
#
#   technical    can pass, fail or be not_assessed. A failure means the
#                data cannot be used as it stands.
#   hydrometric  can pass, warn or be not_assessed. A warning is a
#                judgement call for a person. It never excludes anything.
# ---------------------------------------------------------------------------

.assessment_statuses <- c("pass", "warning", "fail", "not_assessed")
.assessment_domains <- c("technical", "hydrometric")

# The columns of a check table, in order, with the class each must have.
.assessment_columns <- c(
  check_id = "character", domain = "character", severity = "character",
  status = "character", message = "character", affected_evidence = "list",
  affected_stage_min_m = "numeric", affected_stage_max_m = "numeric",
  recommendation = "character"
)

# An empty check table with the right classes.
.empty_checks <- function() {
  data.table(
    check_id = character(0), domain = character(0), severity = character(0),
    status = character(0), message = character(0), affected_evidence = list(),
    affected_stage_min_m = numeric(0), affected_stage_max_m = numeric(0),
    recommendation = character(0)
  )
}

.assessment_dt_class <- new_S3_class(
  c("data.table", "data.frame"),
  constructor = function(.data = data.table()) as.data.table(.data)
)

#' The outcome of a set of checks (S7)
#'
#' @description
#' What [validate_gaugings()] returns, and what `assess_rating()` will. It
#' holds one row per check, and does not know what was checked: the same
#' class serves evidence now and a fitted rating later.
#'
#' Each check belongs to one of two domains, and the class holds it to that
#' domain's rules.
#'
#' * **technical** checks can `pass`, `fail` or be `not_assessed`. A
#'   failure means the data cannot be used as it stands.
#' * **hydrometric** checks can `pass`, raise a `warning` or be
#'   `not_assessed`. A warning is a judgement for a person to make. No check
#'   ever removes or changes a row.
#'
#' A check that could not run (the information it needs is absent) is
#' `not_assessed`, never `pass`.
#'
#' The check table has these columns:
#'
#' | column | meaning |
#' |---|---|
#' | `check_id` | a stable short name, unique within the assessment |
#' | `domain` | `technical` or `hydrometric` |
#' | `severity` | what a non-pass raises: `error` for technical, `warning` for hydrometric |
#' | `status` | `pass`, `warning`, `fail` or `not_assessed` |
#' | `message` | what was found, in a sentence |
#' | `affected_evidence` | list column; the `evidence_id`s concerned, empty when none |
#' | `affected_stage_min_m`, `affected_stage_max_m` | the stage range concerned, `NA` when none |
#' | `recommendation` | what to look at next |
#'
#' Read it with [assessment_checks()] and summarise it with
#' [assessment_status()]. `print()` lists what did not pass, and `plot()`
#' draws every check by status.
#'
#' @param checks A data.table with the columns above.
#' @param subject Character. What was assessed, for example `"gaugings"`.
#' @param assessed_rows Integer. How many rows (or other units) the checks
#'   looked at.
#'
#' @return A `FlodeAssessment`.
#'
#' @seealso [validate_gaugings()], [assessment_checks()],
#'   [assessment_status()]
#'
#' @examples
#' gaugings <- data.frame(
#'   stage_m = c(0.5, 0.9, 1.4, 2.0, 2.6, 3.1),
#'   discharge_cms = c(1.1, 3.0, 7.6, 16, 27, 40)
#' )
#' assessment <- validate_gaugings(gaugings)
#' assessment
#' plot(assessment)
#'
#' @export
FlodeAssessment <- new_class(
  "FlodeAssessment",
  properties = list(
    checks = new_property(.assessment_dt_class, default = quote(.empty_checks())),
    subject = new_property(class_character, default = "gaugings"),
    assessed_rows = new_property(class_integer, default = 0L)
  ),
  validator = function(self) {
    chk <- self@checks
    missing_cols <- setdiff(names(.assessment_columns), names(chk))
    if (length(missing_cols)) {
      return(paste0("checks is missing column(s): ", paste(missing_cols, collapse = ", ")))
    }
    for (col in names(.assessment_columns)) {
      v <- chk[[col]]
      ok <- switch(.assessment_columns[[col]],
        character = is.character(v), numeric = is.numeric(v), list = is.list(v)
      )
      if (!ok) return(sprintf("checks$%s must be of class %s", col, .assessment_columns[[col]]))
    }
    if (nrow(chk) == 0L) return(NULL)
    if (anyNA(chk$check_id) || anyDuplicated(chk$check_id)) {
      return("check_id must be unique and never missing")
    }
    if (!all(chk$domain %in% .assessment_domains)) {
      return(sprintf("domain must be one of: %s", paste(.assessment_domains, collapse = ", ")))
    }
    if (!all(chk$status %in% .assessment_statuses)) {
      return(sprintf("status must be one of: %s", paste(.assessment_statuses, collapse = ", ")))
    }
    if (any(chk$domain == "technical" & chk$status == "warning")) {
      return("a technical check can pass or fail but not warn; a warning belongs to a hydrometric check")
    }
    if (any(chk$domain == "hydrometric" & chk$status == "fail")) {
      return("a hydrometric check can warn but not fail; only a technical check fails")
    }
    expected_severity <- ifelse(chk$domain == "technical", "error", "warning")
    if (!identical(chk$severity, expected_severity)) {
      return("severity must be 'error' for a technical check and 'warning' for a hydrometric one")
    }
    if (!all(vapply(chk$affected_evidence, is.character, logical(1)))) {
      return("affected_evidence must hold a character vector of evidence ids for every check, empty if none")
    }
    NULL
  }
)

# One check row. The severity follows from the domain.
.check_row <- function(check_id, domain, status, message, recommendation = NA_character_,
                       affected = character(0), stage = numeric(0)) {
  stage <- stage[is.finite(stage)]
  data.table(
    check_id = check_id, domain = domain,
    severity = if (domain == "technical") "error" else "warning",
    status = status, message = message,
    affected_evidence = list(as.character(affected)),
    affected_stage_min_m = if (length(stage)) min(stage) else NA_real_,
    affected_stage_max_m = if (length(stage)) max(stage) else NA_real_,
    recommendation = recommendation
  )
}

# The worst status in a check table: fail, then warning, then pass; and
# not_assessed only when nothing was assessed at all.
.assessment_overall <- function(checks) {
  s <- checks$status
  if (any(s == "fail")) return("fail")
  if (any(s == "warning")) return("warning")
  if (any(s == "pass")) return("pass")
  "not_assessed"
}

#' Read the checks of an assessment
#'
#' @description
#' The check table of a [FlodeAssessment], as a copy. See
#' [FlodeAssessment] for the columns.
#'
#' @param x A [FlodeAssessment].
#'
#' @return A data.table, one row per check.
#'
#' @seealso [assessment_status()]
#'
#' @examples
#' assessment <- validate_gaugings(data.frame(
#'   stage_m = c(0.5, 0.9, 1.4, 2.0, 2.6, 3.1),
#'   discharge_cms = c(1.1, 3.0, 7.6, 16, 27, 40)
#' ))
#' assessment_checks(assessment)[, .(check_id, domain, status)]
#'
#' @export
assessment_checks <- function(x) {
  if (!S7_inherits(x, FlodeAssessment)) stop("x must be a FlodeAssessment", call. = FALSE)
  copy(x@checks)
}

#' The overall status of an assessment
#'
#' @description
#' One word for the whole assessment: `"fail"` if any technical check
#' failed, otherwise `"warning"` if any hydrometric check warned, otherwise
#' `"pass"`. It is `"not_assessed"` only when no check could be run.
#' `"pass"` means every check that could be run passed; read
#' [assessment_checks()] for any that were `not_assessed`.
#'
#' @param x A [FlodeAssessment].
#'
#' @return A single string.
#'
#' @seealso [assessment_checks()]
#'
#' @examples
#' assessment <- validate_gaugings(data.frame(
#'   stage_m = c(0.5, 0.9, 1.4, 2.0, 2.6, 3.1),
#'   discharge_cms = c(1.1, 3.0, 7.6, 16, 27, 40)
#' ))
#' assessment_status(assessment)
#'
#' @export
assessment_status <- function(x) {
  if (!S7_inherits(x, FlodeAssessment)) stop("x must be a FlodeAssessment", call. = FALSE)
  .assessment_overall(x@checks)
}

#' Print an assessment (S7 method)
#' @param x A [FlodeAssessment].
#' @param ... Unused.
#' @noRd
method(print, FlodeAssessment) <- function(x, ...) {
  chk <- x@checks
  counts <- vapply(.assessment_statuses, function(s) sum(chk$status == s), integer(1))
  cat(sprintf(
    "<FlodeAssessment> %s, %d row(s) assessed. Overall: %s\n",
    x@subject, x@assessed_rows, .assessment_overall(chk)
  ))
  cat(sprintf(
    "  %d pass, %d warning, %d fail, %d not assessed\n",
    counts[["pass"]], counts[["warning"]], counts[["fail"]], counts[["not_assessed"]]
  ))
  shown <- chk[chk$status != "pass"]
  if (nrow(shown)) {
    shown <- shown[order(match(shown$status, c("fail", "warning", "not_assessed")))]
    for (i in seq_len(nrow(shown))) {
      cat(sprintf("  [%s] %s: %s\n", shown$status[i], shown$check_id[i], shown$message[i]))
    }
  }
  invisible(x)
}

#' Plot an assessment (S7 method)
#'
#' Every check as a row, coloured by status, with the number of rows it
#' affected. The status is also written in each tile, so the chart does not
#' rely on colour alone.
#'
#' @param x A [FlodeAssessment].
#' @param y,... Unused.
#' @return A ggplot object.
#' @noRd
method(plot, FlodeAssessment) <- function(x, y, ...) {
  chk <- copy(x@checks)
  if (nrow(chk) == 0L) stop("there are no checks to plot", call. = FALSE)
  chk[, n_affected := vapply(affected_evidence, length, integer(1))]
  chk[, status := factor(status, levels = .assessment_statuses)]
  chk[, check_label := factor(check_id, levels = rev(check_id))]
  chk[, tile_label := ifelse(n_affected > 0L, sprintf("%s (%d)", status, n_affected), as.character(status))]
  fills <- c(pass = "#2E7D32", warning = "#B26A00", fail = "#B3261E", not_assessed = "#5F6368")
  p <- ggplot(chk, aes(x = domain, y = check_label, fill = status)) +
    geom_tile(colour = "white", linewidth = 1) +
    geom_text(aes(label = tile_label), colour = "white", size = 3.2) +
    scale_fill_manual(values = fills, drop = FALSE, name = "Status") +
    labs(
      x = NULL, y = NULL,
      title = sprintf("Checks on %s", x@subject),
      subtitle = sprintf("Overall: %s. Number of rows affected in brackets.", .assessment_overall(x@checks))
    ) +
    theme_minimal(base_size = 11) +
    theme(panel.grid = element_blank(), legend.position = "bottom")
  p
}
