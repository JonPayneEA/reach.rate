# ============================================================ #
# Tool:         rating_curve_explorer
# Description:  Interactive Shiny app for exploring how C, a, and n
#               shape a power-law rating curve, and how independently-
#               fitted limbs meet (or fail to meet) at a junction. A
#               teaching/exploration tool, not a fitting tool -- it does
#               not touch gauging data or call rate_optimise().
# Author:       Jonathan Payne
# Created:      2026-08-18
# Modified:     2026-08-18 - JP: initial version. Rebuilt from a first
#               pass done as a standalone React artifact, moved into R
#               because that is where this toolkit actually lives.
# Modified:     2026-08-25 - JP: converted from a plain Shiny app script
#               (run directly, not a box module) into a package function,
#               rating_curve_explorer(). shiny is a Suggests dependency,
#               not an Imports one -- the rest of this toolkit's fitting
#               and diagnostic functions have nothing to do with it, so
#               every shiny call here is explicitly shiny::-qualified
#               (rather than @import'd package-wide) and the function
#               checks requireNamespace("shiny") itself before building
#               any UI, per CRAN's policy for optional dependencies.
# Tier:         1
# Inputs:       None -- purely interactive, no data loaded
# Outputs:      A shiny.appobj; auto-launches when printed (e.g. simply
#               calling rating_curve_explorer() at the console), or pass
#               it to shiny::runApp() explicitly.
# Dependencies: data.table, ggplot2 (Imports); shiny (Suggests)
# ============================================================ #

STAGE_MIN <- 0.2
STAGE_MAX <- 4.0
LIMB_COLOURS <- c("#2E7D6B", "#B5541A", "#5B3B7A")

# Same equation and zero-flow convention used throughout the rest of the
# toolkit (rate_optimise(), apply_rating()): Q = C(H + a)^n, discharge is
# zero rather than NaN/negative below the zero-flow datum.
#' @keywords internal
#' @noRd
.explorer_eval_q <- function(C, a, n, H) {
  depth <- H + a
  fifelse(depth <= 0, 0, C * depth^n)
}

#' Launch the interactive rating curve explorer
#'
#' @description
#' A teaching/exploration Shiny app: adjust `C` (scale), `a` (offset),
#' and `n` (exponent) per limb with sliders and watch the curve shape
#' change live. Add a second or third limb to see whether
#' independently-fitted segments meet cleanly at a junction, or don't --
#' the "Align" button rescales the upper limb's `C` to close the gap,
#' mirroring [align_limb_equations()]. This app does not touch gauging
#' data or call [rate_optimise()]; it is purely for building intuition
#' about the equation and the junction-gap problem.
#'
#' Requires the \pkg{shiny} package (Suggests, not a hard dependency of
#' this package).
#'
#' @return A `shiny.appobj`, invisibly. Auto-launches when printed (which
#'   happens automatically if you just call `rating_curve_explorer()` at
#'   the console); pass it to [shiny::runApp()] explicitly otherwise.
#'
#' @examples
#' \dontrun{
#' rating_curve_explorer()
#' }
#'
#' @export
rating_curve_explorer <- function() {
  if (!requireNamespace("shiny", quietly = TRUE)) {
    stop(
      "rating_curve_explorer() requires the 'shiny' package. ",
      "Install it with install.packages(\"shiny\")."
    )
  }

  eval_q <- .explorer_eval_q

  # -------------------------------------------------------------------- #
  # UI
  # -------------------------------------------------------------------- #

  limb_defaults <- list(
    C = c(4.0, 8.0, 14.0),
    a = c(0.10, 0.30, 0.50),
    n = c(1.60, 1.70, 1.90)
  )
  break_defaults <- c(1.6, 2.6)

  limb_panel <- function(i) {
    colour <- LIMB_COLOURS[i]
    shiny::wellPanel(
      style = sprintf("border-left: 4px solid %s;", colour),
      shiny::tags$div(
        style = "display:flex; justify-content:space-between; align-items:baseline;",
        shiny::tags$strong(sprintf("Limb %d", i)),
        shiny::tags$span(
          class = "rce-mono", style = "font-size:11px; color:#5B6B6E;",
          shiny::textOutput(sprintf("bounds%d", i), inline = TRUE)
        )
      ),
      shiny::sliderInput(sprintf("C%d", i), "C  (scale)", min = 0.5, max = 20, value = limb_defaults$C[i], step = 0.1),
      shiny::sliderInput(sprintf("a%d", i), "a  (offset, m)", min = -1, max = 1.5, value = limb_defaults$a[i], step = 0.01),
      shiny::sliderInput(sprintf("n%d", i), "n  (exponent)", min = 0.8, max = 3, value = limb_defaults$n[i], step = 0.01)
    )
  }

  ui <- shiny::fluidPage(
    shiny::tags$head(
      shiny::tags$style(shiny::HTML("
        @import url('https://fonts.googleapis.com/css2?family=IBM+Plex+Sans:wght@400;500;600&family=IBM+Plex+Mono:wght@400;500;600&display=swap');
        body {
          background-color: #F5F2E8;
          background-image:
            linear-gradient(#D9DED9 1px, transparent 1px),
            linear-gradient(90deg, #D9DED9 1px, transparent 1px);
          background-size: 24px 24px;
          font-family: 'IBM Plex Sans', sans-serif;
          color: #1C2B2E;
        }
        .rce-mono { font-family: 'IBM Plex Mono', monospace; }
        .well { background: #FFFFFF; border: 1px solid #D8D0BC; border-radius: 10px; }
        .rce-title { font-size: 26px; font-weight: 600; letter-spacing: -0.01em; margin: 4px 0 2px; }
        .rce-eyebrow {
          font-family: 'IBM Plex Mono', monospace; font-size: 11px; letter-spacing: 0.12em;
          color: #5B6B6E; text-transform: uppercase;
        }
        .rce-sub { color: #5B6B6E; font-size: 14px; max-width: 640px; line-height: 1.5; }
        .rce-gap-panel { background: #1C2B2E; border-radius: 10px; padding: 14px 16px; color: #D8E4E1; }
        .rce-gap-label {
          font-family: 'IBM Plex Mono', monospace; font-size: 10.5px; letter-spacing: 0.1em;
          color: #9FB0AE; text-transform: uppercase; margin-bottom: 6px;
        }
        .rce-gap-row { display:flex; align-items:center; justify-content:space-between; padding: 3px 0; }
        .rce-gap-value { font-family: 'IBM Plex Mono', monospace; font-weight: 600; font-size: 13.5px; }
        .btn-align {
          background-color: #1F4B4A; color: white; border-color: #1F4B4A; font-size: 12px; padding: 3px 10px;
        }
        .btn-align:hover { opacity: 0.88; color: white; }
      "))
    ),

    shiny::tags$div(class = "rce-eyebrow", "Q = C(H + a)^n \u00b7 segmented power-law rating"),
    shiny::tags$div(class = "rce-title", "Rating curve explorer"),
    shiny::tags$p(
      class = "rce-sub",
      "Adjust C (scale), a (offset) and n (exponent) per limb and watch the curve shape ",
      "change. Add a second or third limb to see whether independently-fitted segments ",
      "meet cleanly at a junction, or don't."
    ),

    shiny::fluidRow(
      shiny::column(4,
        shiny::wellPanel(
          shiny::tags$div(
            style = "display:flex; justify-content:space-between; align-items:center;",
            shiny::tags$strong("Limbs"),
            shiny::radioButtons("num_limbs", NULL, choices = c("1" = 1, "2" = 2, "3" = 3), selected = 2, inline = TRUE)
          )
        ),
        limb_panel(1),
        shiny::conditionalPanel("input.num_limbs >= 2", limb_panel(2)),
        shiny::conditionalPanel("input.num_limbs >= 3", limb_panel(3)),
        shiny::conditionalPanel("input.num_limbs >= 2",
          shiny::wellPanel(
            shiny::tags$strong("Breakpoints"),
            shiny::conditionalPanel("input.num_limbs >= 2",
              shiny::sliderInput("brk1", "Limb 1 / 2 boundary (m)", min = STAGE_MIN, max = STAGE_MAX, value = break_defaults[1], step = 0.02)
            ),
            shiny::conditionalPanel("input.num_limbs >= 3",
              shiny::sliderInput("brk2", "Limb 2 / 3 boundary (m)", min = STAGE_MIN, max = STAGE_MAX, value = break_defaults[2], step = 0.02)
            )
          )
        ),
        shiny::actionButton("reset", "Reset to defaults")
      ),

      shiny::column(8,
        shiny::wellPanel(
          shiny::plotOutput("rating_plot", height = "440px")
        ),
        shiny::uiOutput("gap_panel")
      )
    )
  )

  # -------------------------------------------------------------------- #
  # Server
  # -------------------------------------------------------------------- #

  server <- function(input, output, session) {

    # --- Bounds: stage range for each limb, from the breakpoint sliders --
    bounds_dt <- shiny::reactive({
      nl <- as.integer(input$num_limbs)
      breaks <- STAGE_MIN
      if (nl >= 2) breaks <- c(breaks, min(max(input$brk1, STAGE_MIN + 0.05), STAGE_MAX - 0.05))
      if (nl >= 3) {
        brk2 <- min(max(input$brk2, breaks[length(breaks)] + 0.05), STAGE_MAX - 0.05)
        breaks <- c(breaks, brk2)
      }
      breaks <- c(breaks, STAGE_MAX)
      data.table(limb = seq_len(nl), lower = breaks[-length(breaks)], upper = breaks[-1])
    })

    # --- Coefficients currently set on the sliders, one row per limb -----
    coefs_dt <- shiny::reactive({
      nl <- as.integer(input$num_limbs)
      Cs <- c(input$C1, input$C2, input$C3)[seq_len(nl)]
      As <- c(input$a1, input$a2, input$a3)[seq_len(nl)]
      Ns <- c(input$n1, input$n2, input$n3)[seq_len(nl)]
      data.table(limb = seq_len(nl), C = Cs, a = As, n = Ns)
    })

    for (i in 1:3) {
      local({
        ii <- i
        output[[sprintf("bounds%d", ii)]] <- shiny::renderText({
          bd <- bounds_dt()
          if (ii > nrow(bd)) return("")
          sprintf("%.2f-%.2f m", bd$lower[ii], bd$upper[ii])
        })
      })
    }

    # --- Curve points, one row per (limb, stage) sample -------------------
    curve_dt <- shiny::reactive({
      bd <- bounds_dt()
      cf <- coefs_dt()
      rbindlist(lapply(seq_len(nrow(bd)), function(i) {
        stage_seq <- seq(bd$lower[i], bd$upper[i], length.out = 150)
        data.table(
          limb = factor(i),
          stage = stage_seq,
          q = eval_q(cf$C[i], cf$a[i], cf$n[i], stage_seq)
        )
      }))
    })

    # --- Junction gaps: discharge mismatch at each breakpoint -------------
    gaps_dt <- shiny::reactive({
      bd <- bounds_dt()
      cf <- coefs_dt()
      nl <- nrow(bd)
      if (nl < 2) return(data.table())
      rbindlist(lapply(seq_len(nl - 1), function(i) {
        brk <- bd$upper[i]
        q_lower <- eval_q(cf$C[i], cf$a[i], cf$n[i], brk)
        q_upper <- eval_q(cf$C[i + 1], cf$a[i + 1], cf$n[i + 1], brk)
        diff <- q_upper - q_lower
        rel_pct <- if (abs(q_lower) > 1e-9) 100 * diff / q_lower else NA_real_
        data.table(
          junction = i, stage = brk, q_lower = q_lower, q_upper = q_upper,
          diff = diff, rel_pct = rel_pct,
          flagged = abs(diff) > 0.5 | (!is.na(rel_pct) & abs(rel_pct) > 2)
        )
      }))
    })

    # --- Plot ---------------------------------------------------------------
    output$rating_plot <- shiny::renderPlot({
      cd <- curve_dt()
      bd <- bounds_dt()
      nl <- nrow(bd)

      p <- ggplot(cd, aes(x = q, y = stage, colour = limb, group = limb)) +
        geom_path(linewidth = 1.1) +
        scale_colour_manual(values = LIMB_COLOURS[seq_len(nl)], guide = "none") +
        scale_y_continuous(limits = c(STAGE_MIN, STAGE_MAX), expand = c(0, 0)) +
        scale_x_continuous(limits = c(0, NA), expand = expansion(mult = c(0, 0.06))) +
        labs(x = "Discharge (m\u00b3/s)", y = "Stage (m)") +
        theme_minimal(base_size = 13) +
        theme(
          panel.grid.minor = element_blank(),
          panel.border = element_rect(colour = "#D8D0BC", fill = NA),
          text = element_text(colour = "#1C2B2E")
        )

      if (nl > 1) {
        p <- p + geom_hline(yintercept = bd$upper[-nl], colour = "#5B6B6E", linetype = "dashed", linewidth = 0.5)
      }

      p
    })

    # --- Gap readout panel ---------------------------------------------------
    output$gap_panel <- shiny::renderUI({
      gd <- gaps_dt()
      if (nrow(gd) == 0) return(NULL)

      rows <- lapply(seq_len(nrow(gd)), function(i) {
        g <- gd[i]
        value_colour <- if (g$flagged) "#F0A99E" else "#9AD9C4"
        sign_str <- if (g$diff >= 0) "+" else ""
        pct_str <- if (!is.na(g$rel_pct)) sprintf(" (%s%.1f%%)", if (g$rel_pct >= 0) "+" else "", g$rel_pct) else ""

        shiny::tags$div(class = "rce-gap-row",
          shiny::tags$span(sprintf("Limb %d / %d at %.2f m", g$junction, g$junction + 1, g$stage)),
          shiny::tags$span(class = "rce-gap-value", style = sprintf("color:%s;", value_colour),
            sprintf("%s%.2f m\u00b3/s%s", sign_str, g$diff, pct_str)
          ),
          if (g$flagged) shiny::actionButton(sprintf("align%d", g$junction), "Align \u2192", class = "btn-align") else NULL
        )
      })

      shiny::tags$div(class = "rce-gap-panel",
        shiny::tags$div(class = "rce-gap-label", "Junction gap"),
        rows
      )
    })

    # --- Align buttons: rescale the upper limb's C to close the gap --------
    # Mirrors align_limb_equations(): hold A and B fixed, rescale C so the
    # upper limb passes exactly through the lower limb's discharge at the
    # shared breakpoint.
    shiny::observeEvent(input$align1, {
      bd <- bounds_dt()
      cf <- coefs_dt()
      brk <- bd$upper[1]
      target <- eval_q(cf$C[1], cf$a[1], cf$n[1], brk)
      depth <- brk + cf$a[2]
      if (depth > 0) {
        new_c <- target / depth^cf$n[2]
        shiny::updateSliderInput(session, "C2", value = round(new_c, 3))
      }
    })

    shiny::observeEvent(input$align2, {
      bd <- bounds_dt()
      cf <- coefs_dt()
      if (nrow(bd) < 3) return(invisible(NULL))
      brk <- bd$upper[2]
      target <- eval_q(cf$C[2], cf$a[2], cf$n[2], brk)
      depth <- brk + cf$a[3]
      if (depth > 0) {
        new_c <- target / depth^cf$n[3]
        shiny::updateSliderInput(session, "C3", value = round(new_c, 3))
      }
    })

    # --- Reset ----------------------------------------------------------------
    shiny::observeEvent(input$reset, {
      shiny::updateRadioButtons(session, "num_limbs", selected = 2)
      for (i in 1:3) {
        shiny::updateSliderInput(session, sprintf("C%d", i), value = limb_defaults$C[i])
        shiny::updateSliderInput(session, sprintf("a%d", i), value = limb_defaults$a[i])
        shiny::updateSliderInput(session, sprintf("n%d", i), value = limb_defaults$n[i])
      }
      shiny::updateSliderInput(session, "brk1", value = break_defaults[1])
      shiny::updateSliderInput(session, "brk2", value = break_defaults[2])
    })
  }

  shiny::shinyApp(ui = ui, server = server)
}
