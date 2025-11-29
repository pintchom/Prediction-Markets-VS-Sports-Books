
# Visualizations using base R (no ggplot2 dependency)
# Generates PNGs into data/processed/visualizations

viz_dir <- "data/processed/visualizations"
if (!dir.exists(viz_dir)) dir.create(viz_dir, recursive = TRUE, showWarnings = FALSE)

deciles_path <- "data/processed/analysis/volume_effects_by_decile.csv"
league_path <- "data/processed/analysis/volume_effects_by_league.csv"
full_path <- "data/processed/clean/all_volume_odds.csv"

stopifnot(file.exists(deciles_path), file.exists(league_path), file.exists(full_path))

deciles <- read.csv(deciles_path, stringsAsFactors = FALSE)
league <- read.csv(league_path, stringsAsFactors = FALSE)
all_games <- read.csv(full_path, stringsAsFactors = FALSE)

# Helper to save PNG with consistent look
save_png <- function(path, expr) {
  png(path, width = 800, height = 520, res = 120)
  op <- par(mar = c(4.5, 4.5, 3, 1) + 0.1)
  on.exit({par(op); dev.off()}, add = TRUE)
  expr()
}

# Plot 1: Brier vs volume decile
save_png(file.path(viz_dir, "volume_decile_brier.png"), function() {
  plot(deciles$volume_bucket, deciles$brier_kalshi, type = "o", pch = 19, col = "steelblue",
       ylim = range(deciles$brier_kalshi, deciles$brier_sportsbook, na.rm = TRUE),
       xlab = "Volume decile (low to high)", ylab = "Brier score",
       main = "Brier Score vs Kalshi Volume Decile")
  lines(deciles$volume_bucket, deciles$brier_sportsbook, type = "o", pch = 17, col = "darkorange")
  axis(1, at = deciles$volume_bucket)
  grid(col = "grey85")
  legend("topleft", legend = c("Kalshi", "Sportsbook"), col = c("steelblue", "darkorange"),
         pch = c(19, 17), bty = "n")
})

# Plot 2: Log loss vs volume decile
save_png(file.path(viz_dir, "volume_decile_logloss.png"), function() {
  plot(deciles$volume_bucket, deciles$logloss_kalshi, type = "o", pch = 19, col = "steelblue",
       ylim = range(deciles$logloss_kalshi, deciles$logloss_sportsbook, na.rm = TRUE),
       xlab = "Volume decile (low to high)", ylab = "Log loss",
       main = "Log Loss vs Kalshi Volume Decile")
  lines(deciles$volume_bucket, deciles$logloss_sportsbook, type = "o", pch = 17, col = "darkorange")
  axis(1, at = deciles$volume_bucket)
  grid(col = "grey85")
  legend("topleft", legend = c("Kalshi", "Sportsbook"), col = c("steelblue", "darkorange"),
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
  cols <- setNames(c("steelblue", "darkorange", "darkgreen", "purple"), leagues)
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
  barplot(mat, beside = TRUE, col = c("steelblue", "darkorange"), ylim = c(0, max(mat, na.rm = TRUE) * 1.1),
          ylab = "Brier score", main = "Average Brier Score by League")
  legend("topright", legend = c("Kalshi", "Sportsbook"), fill = c("steelblue", "darkorange"), bty = "n")
})

cat("Saved visualizations to", viz_dir, "
")
