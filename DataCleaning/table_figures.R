# Render analysis tables as PNG figures for easy copy/paste
suppressPackageStartupMessages({
  library(readr)
})

viz_dir <- "data/processed/visualizations"
if (!dir.exists(viz_dir)) dir.create(viz_dir, recursive = TRUE, showWarnings = FALSE)

# Helper to write a text block into a PNG
render_text_png <- function(lines, path, width = 900, height = 700, cex = 0.9, family = "mono") {
  png(path, width = width, height = height, res = 120)
  op <- par(mar = c(1, 1, 1, 1), bg = "white")
  on.exit({par(op); dev.off()}, add = TRUE)
  plot.new()
  # compute y positions
  n <- length(lines)
  y <- seq(1, 0, length.out = n + 2)[-c(1, n + 2)]  # leave a little padding
  text(x = 0, y = rev(y), labels = lines, adj = c(0, 0.5), cex = cex, family = family)
}

# 1) Brier stats text file
brier_txt <- readLines("data/processed/analysis/brier_stats.txt", warn = FALSE)
render_text_png(brier_txt, file.path(viz_dir, "brier_stats_table.png"), height = 820, cex = 0.9)

# Helper to render a small data frame as text table
render_df <- function(df, title, path, width = 900, height = 600, cex = 0.9, family = "mono") {
  # format table
  fmt <- function(x) {
    if (is.numeric(x)) return(format(round(x, 6), trim = TRUE, scientific = FALSE))
    x
  }
  df_fmt <- as.data.frame(lapply(df, fmt), stringsAsFactors = FALSE)
  # build lines
  headers <- names(df_fmt)
  # compute column widths
  col_widths <- pmax(nchar(headers), sapply(df_fmt, function(col) max(nchar(col), na.rm = TRUE)))
  pad_cell <- function(x, width) sprintf(paste0("%-", width, "s"), x)
  header_line <- paste(mapply(pad_cell, headers, col_widths), collapse = "  ")
  sep_line <- paste(mapply(function(w) paste(rep("-", w), collapse = ""), col_widths), collapse = "  ")
  body_lines <- apply(df_fmt, 1, function(row) paste(mapply(pad_cell, row, col_widths), collapse = "  "))
  lines <- c(title, sep_line, header_line, sep_line, body_lines)
  render_text_png(lines, path, width = width, height = height, cex = cex, family = family)
}

# 2) Volume by league table
vol_league <- read_csv("data/processed/analysis/volume_effects_by_league.csv", show_col_types = FALSE)
render_df(vol_league, "Volume effects by league", file.path(viz_dir, "volume_by_league_table.png"), height = 500, cex = 0.9)

# 3) Platform fee vs vig
fee_vig <- read_csv("data/processed/analysis/platform_fee_vs_vig.csv", show_col_types = FALSE)
render_df(fee_vig, "Sportsbook vig vs Kalshi fee", file.path(viz_dir, "fee_vs_vig_table.png"), height = 400, cex = 0.9)

# 4) Platform loss summary
loss_summary <- read_csv("data/processed/analysis/platform_loss_summary.csv", show_col_types = FALSE)
render_df(loss_summary, "Expected loss per $1 (log loss) and $500k stake", file.path(viz_dir, "platform_loss_table.png"), height = 500, cex = 0.9)

# 5) Volume deciles (accuracy)
vol_deciles <- read_csv("data/processed/analysis/volume_effects_by_decile.csv", show_col_types = FALSE)
render_df(vol_deciles, "Accuracy by Kalshi volume decile", file.path(viz_dir, "volume_deciles_table.png"), height = 700, cex = 0.85)

cat("Wrote table figures to", viz_dir, "\n")
