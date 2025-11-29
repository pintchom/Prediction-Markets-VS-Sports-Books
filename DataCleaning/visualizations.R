
# Visualizations using base R (no ggplot2 dependency)
# Generates PNGs into data/processed/visualizations

viz_dir <- "data/processed/visualizations"
if (!dir.exists(viz_dir)) dir.create(viz_dir, recursive = TRUE, showWarnings = FALSE)

# Palette
kalshi_col <- "#2ca25f"      # Kalshi green
book_col <- "#1f78b4"        # Sportsbook blue
accent_cols <- c(kalshi_col, book_col)

deciles_path <- "data/processed/analysis/volume_effects_by_decile.csv"
league_path <- "data/processed/analysis/volume_effects_by_league.csv"
full_path <- "data/processed/clean/all_volume_odds.csv"
nfl_book_summary_path <- file.path("Odds API Data", "NFL Data", "NFL_sportbook_summary_table.csv")
nfl_kalshi_summary_path <- file.path("Odds API Data", "NFL Data", "NFL_kalshi_summary_table.csv")
nba_book_summary_path <- file.path("Odds API Data", "NBA Data", "NBA_sportbook_summary_table.csv")
nba_kalshi_summary_path <- file.path("Odds API Data", "NBA Data", "NBA_kalshi_summary_table.csv")

stopifnot(file.exists(deciles_path), file.exists(league_path), file.exists(full_path))
stopifnot(file.exists(nfl_book_summary_path), file.exists(nfl_kalshi_summary_path),
          file.exists(nba_book_summary_path), file.exists(nba_kalshi_summary_path))

deciles <- read.csv(deciles_path, stringsAsFactors = FALSE)
league <- read.csv(league_path, stringsAsFactors = FALSE)
all_games <- read.csv(full_path, stringsAsFactors = FALSE)
nfl_book_summary <- read.csv(nfl_book_summary_path, stringsAsFactors = FALSE)
nfl_kalshi_summary <- read.csv(nfl_kalshi_summary_path, stringsAsFactors = FALSE)
nba_book_summary <- read.csv(nba_book_summary_path, stringsAsFactors = FALSE)
nba_kalshi_summary <- read.csv(nba_kalshi_summary_path, stringsAsFactors = FALSE)

# Helper to save PNG with consistent look
save_png <- function(path, expr) {
  png(path, width = 800, height = 520, res = 120)
  op <- par(
    mar = c(7, 5, 3.5, 1) + 0.1,
    bg = "#f8f9fb",
    col.lab = "#1f1f1f",
    col.axis = "#3a3a3a",
    col.main = "#111111",
    family = "sans"
  )
  on.exit({par(op); dev.off()}, add = TRUE)
  expr()
}

# Plot 1: Brier vs volume decile
save_png(file.path(viz_dir, "volume_decile_brier.png"), function() {
  plot(deciles$volume_bucket, deciles$brier_kalshi, type = "o", pch = 19, col = kalshi_col,
       ylim = range(deciles$brier_kalshi, deciles$brier_sportsbook, na.rm = TRUE),
       xlab = "Volume decile (low to high)", ylab = "Brier score",
       main = "Brier Score vs Kalshi Volume Decile")
  lines(deciles$volume_bucket, deciles$brier_sportsbook, type = "o", pch = 17, col = book_col)
  axis(1, at = deciles$volume_bucket)
  grid(col = "grey85")
  legend("topleft", legend = c("Kalshi", "Sportsbook"), col = c(kalshi_col, book_col),
         pch = c(19, 17), bty = "n")
})

# Plot 2: Log loss vs volume decile
save_png(file.path(viz_dir, "volume_decile_logloss.png"), function() {
  plot(deciles$volume_bucket, deciles$logloss_kalshi, type = "o", pch = 19, col = kalshi_col,
       ylim = range(deciles$logloss_kalshi, deciles$logloss_sportsbook, na.rm = TRUE),
       xlab = "Volume decile (low to high)", ylab = "Log loss",
       main = "Log Loss vs Kalshi Volume Decile")
  lines(deciles$volume_bucket, deciles$logloss_sportsbook, type = "o", pch = 17, col = book_col)
  axis(1, at = deciles$volume_bucket)
  grid(col = "grey85")
  legend("topleft", legend = c("Kalshi", "Sportsbook"), col = c(kalshi_col, book_col),
         pch = c(19, 17), bty = "n")
})

# Plot 3: Brier edge vs volume (log x-axis) with lowess per league
save_png(file.path(viz_dir, "volume_vs_brier_edge.png"), function() {
  df <- subset(all_games, !is.na(total_volume) & !is.na(brier_kalshi) & !is.na(brier_sportsbook))
  if (nrow(df) == 0) {
    plot.new(); title("No data available")
    return()
  }
  df$brier_diff <- df$brier_kalshi - df$brier_sportsbook
  leagues <- unique(df$league)
  cols <- setNames(c("#2ca25f", "#1f78b4", "#6a51a3", "#e6550d")[seq_along(leagues)], leagues)
  plot(df$total_volume, df$brier_diff, log = "x", pch = 16, cex = 0.6,
       col = cols[df$league], xlab = "Kalshi total volume (log scale)",
       ylab = "Brier: Kalshi - Sportsbook", main = "Brier Edge vs Kalshi Volume")
  abline(h = 0, col = "grey50", lty = 2)
  for (lg in leagues) {
    sub <- df[df$league == lg, c("total_volume", "brier_diff")]
    if (nrow(sub) > 5) {
      lw <- lowess(sub$total_volume, sub$brier_diff, f = 0.6)
      lines(lw, col = cols[lg], lwd = 2)
    }
  }
  grid(col = "grey85")
  legend("topright", legend = leagues, col = cols[leagues], pch = 16, lwd = 2, bty = "n")
})

# Plot 4: Average Brier by league (grouped bars)
save_png(file.path(viz_dir, "league_brier_comparison.png"), function() {
  mat <- rbind(league$brier_kalshi, league$brier_sportsbook)
  colnames(mat) <- league$league
  yr <- range(mat, na.rm = TRUE)
  sp <- diff(yr)
  pad <- if (is.finite(sp) && sp > 0) max(sp * 0.15, 0.005) else 0.01
  y_min <- max(0, yr[1] - pad)
  y_max <- yr[2] + pad
  barplot(mat, beside = TRUE, col = accent_cols, ylim = c(y_min, y_max),
          ylab = "Brier score", main = "Average Brier Score by League",
          border = NA, cex.names = 0.85)
  legend("topright", inset = c(0.02, 0.02), legend = c("Kalshi", "Sportsbook"), fill = accent_cols,
         bty = "n", horiz = FALSE, cex = 0.9, xpd = NA)
})

# Plot 5: Sportsbook vs Kalshi Brier (per league, bookmaker level)
make_brier_bar <- function(book_summary, kalshi_summary, league_label, filename) {
  # order sportsbooks by their Brier; pair each with Kalshi side-by-side
  books_ordered <- book_summary[order(book_summary$brier_mean), c("bookmaker", "brier_mean")]
  kalshi_val <- kalshi_summary$brier_mean[1]
  mat <- rbind(Sportsbook = books_ordered$brier_mean, Kalshi = rep(kalshi_val, nrow(books_ordered)))
  cols <- matrix(c(rep(book_col, nrow(books_ordered)), rep(kalshi_col, nrow(books_ordered))), nrow = 2, byrow = TRUE)
  yrng <- range(mat, na.rm = TRUE)
  spread <- diff(yrng)
  pad <- if (is.finite(spread) && spread > 0) max(spread * 0.15, 0.005) else 0.01
  y_min <- max(0, yrng[1] - pad)
  y_max <- yrng[2] + pad
  save_png(file.path(viz_dir, filename), function() {
    barplot(mat, beside = TRUE, names.arg = books_ordered$bookmaker, las = 2,
            col = cols, ylab = "Mean Brier score", border = NA,
            ylim = c(y_min, y_max), main = paste("Sportsbook vs Kalshi Brier -", league_label),
            cex.names = 0.75)
    abline(h = pretty(mat), col = "grey90", lty = 3)
    abline(h = kalshi_val, col = kalshi_col, lty = 2, lwd = 1.4)
    legend("top", inset = 0.02, legend = c("Kalshi", "Sportsbook"), fill = c(kalshi_col, book_col),
           bty = "n", horiz = TRUE, cex = 0.9)
  })
}

make_brier_bar(nfl_book_summary, nfl_kalshi_summary, "NFL", "nfl_sportsbook_vs_kalshi_brier.png")
make_brier_bar(nba_book_summary, nba_kalshi_summary, "NBA", "nba_sportsbook_vs_kalshi_brier.png")

cat("Saved visualizations to", viz_dir, "
")
