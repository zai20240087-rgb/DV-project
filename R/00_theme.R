# 00_theme.R
# Shared figure style for all group figures. Every script sources this file.

library(ggplot2)

theme_group <- function(base_size = 12) {
  theme_minimal(base_size = base_size) +
    theme(
      plot.title       = element_text(face = "bold", size = base_size + 2),
      plot.subtitle    = element_text(colour = "grey30"),
      plot.caption     = element_text(colour = "grey45", size = base_size - 3, hjust = 0),
      panel.grid.minor = element_blank(),
      legend.position  = "bottom",
      strip.text       = element_text(face = "bold", hjust = 0)
    )
}

# Colour-blind-safe colours, fixed so the same category looks the same in every figure
pal_reason <- c(Weather = "#0072B2", Carrier = "#E69F00", NAS = "#009E73", Security = "#CC79A7")
pal_main   <- "#0072B2"

src_caption <- "Source: BTS Reporting Carrier On-Time Performance, 2025 (7,001,619 scheduled flights)."