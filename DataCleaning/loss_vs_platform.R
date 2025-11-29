# Compare expected bettor loss (log loss) between Sportsbooks and Kalshi
suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})

input_path <- "data/processed/clean/all_volume_odds.csv"
viz_dir <- "data/processed/visualizations"
out_csv <- "data/processed/analysis/platform_loss_summary.csv"
out_png <- file.path(viz_dir, "platform_expected_loss.png")
out_png_diff <- file.path(viz_dir, "platform_expected_loss_diff.png")
house_value <- 500000  # scenario: bettor stakes their house value per game

if (!file.exists(input_path)) {
  stop("Missing data/processed/clean/all_volume_odds.csv. Run kalshi_cleaning.R first.")
}
if (!dir.exists(viz_dir)) dir.create(viz_dir, recursive = TRUE, showWarnings = FALSE)
if (!dir.exists(dirname(out_csv))) dir.create(dirname(out_csv), recursive = TRUE, showWarnings = FALSE)

# Palette
kalshi_col <- "#2ca25f"
book_col <- "#1f78b4"

df <- read_csv(input_path, show_col_types = FALSE)

complete <- df %>%
  filter(!is.na(home_win), !is.na(logloss_kalshi), !is.na(logloss_sportsbook))

summary_loss <- complete %>%
  group_by(league) %>%
  summarise(
    games = n(),
    logloss_kalshi = mean(logloss_kalshi, na.rm = TRUE),
    logloss_sportsbook = mean(logloss_sportsbook, na.rm = TRUE),
    logloss_diff = logloss_kalshi - logloss_sportsbook,
    exp_loss_kalshi_house = logloss_kalshi * house_value,
    exp_loss_sportsbook_house = logloss_sportsbook * house_value,
    exp_loss_diff_house = logloss_diff * house_value,
    .groups = "drop"
  )

# Overall
overall <- data.frame(
  league = "ALL",
  games = nrow(complete),
  logloss_kalshi = mean(complete$logloss_kalshi, na.rm = TRUE),
  logloss_sportsbook = mean(complete$logloss_sportsbook, na.rm = TRUE),
  logloss_diff = mean(complete$logloss_kalshi - complete$logloss_sportsbook, na.rm = TRUE)
)
overall$exp_loss_kalshi_house <- overall$logloss_kalshi * house_value
overall$exp_loss_sportsbook_house <- overall$logloss_sportsbook * house_value
overall$exp_loss_diff_house <- overall$logloss_diff * house_value

write_csv(bind_rows(summary_loss, overall), out_csv)

# Visualization: lower logloss => better for bettor (less expected loss)
fmt_dollars <- function(x) {
  paste0("$", format(round(x, 0), big.mark = ",", trim = TRUE))
}

save_png <- function(path, expr) {
  png(path, width = 900, height = 560, res = 120)
  op <- par(
    mar = c(8.5, 6.8, 3.5, 1) + 0.1,  # extra left margin keeps y-axis label visible
    bg = "#f8f9fb",
    col.lab = "#1f1f1f",
    col.axis = "#3a3a3a",
    col.main = "#111111",
    family = "sans",
    mgp = c(3.8, 0.7, 0)  # move axis title outward to avoid overlap
  )
  on.exit({par(op); dev.off()}, add = TRUE)
  expr()
}

save_png(out_png, function() {
  leagues <- summary_loss$league
  mat <- rbind(summary_loss$exp_loss_sportsbook_house, summary_loss$exp_loss_kalshi_house)
  rownames(mat) <- c("Sportsbook", "Kalshi")
  yr <- range(mat, na.rm = TRUE)
  sp <- diff(yr)
  pad <- if (is.finite(sp) && sp > 0) max(sp * 0.25, 1500) else 1500
  y_min <- max(0, yr[1] - pad * 0.3)
  y_max <- yr[2] + pad * 1.8  # extra headroom for legend and labels
  bp <- barplot(mat, beside = TRUE, names.arg = leagues, las = 2,
          col = c(book_col, kalshi_col), border = NA, ylim = c(y_min, y_max),
          ylab = "Loss per game", main = "House Bet: Expected Loss",
          cex.names = 0.6)
  abline(h = pretty(mat), col = "grey90", lty = 3)
  text(x = bp, y = mat, labels = fmt_dollars(mat), pos = 3, cex = 0.58, col = "#2c2c2c", offset = 0.5)
  legend("top", inset = c(0, -0.05), xpd = NA, legend = c("Sportsbook", "Kalshi"),
         fill = c(book_col, kalshi_col), bty = "n", cex = 0.9, horiz = TRUE)
})

# Visual 2: difference (Sportsbook - Kalshi) expected loss; positive => sportsbook worse for bettor
save_png(out_png_diff, function() {
  leagues <- summary_loss$league
  diff_vals <- summary_loss$exp_loss_sportsbook_house - summary_loss$exp_loss_kalshi_house
  cols <- ifelse(diff_vals >= 0, book_col, kalshi_col)
  yr <- range(diff_vals, na.rm = TRUE)
  sp <- diff(yr)
  pad <- if (is.finite(sp) && sp > 0) max(sp * 0.4, 1200) else 1200
  y_min <- min(0, yr[1] - pad * 0.2)
  y_max <- yr[2] + pad * 2.0  # extra headroom for legend and labels
  bp <- barplot(diff_vals, names.arg = leagues, las = 2, col = cols, border = NA,
                ylim = c(y_min, y_max),
                ylab = "Loss gap (SB - Kalshi)",
                main = "Which Platform Costs More?",
                cex.names = 0.6)
  abline(h = 0, col = "#555555", lty = 2)
  abline(h = pretty(diff_vals), col = "grey90", lty = 3)
  text(x = bp, y = diff_vals, labels = fmt_dollars(diff_vals), pos = ifelse(diff_vals >= 0, 3, 1),
       cex = 0.58, col = "#2c2c2c", offset = 0.6)
  legend("top", inset = c(0, -0.05), xpd = NA, legend = c("Sportsbook higher loss", "Kalshi higher loss"),
         fill = c(book_col, kalshi_col), bty = "n", cex = 0.9, horiz = TRUE)
})

# Brief console readout
overall_cmp <- if (overall$logloss_diff > 0) "Sportsbooks cost bettors more on average" else "Kalshi costs bettors more on average"
league_lines <- summary_loss %>%
  transmute(line = sprintf("%s: Sportsbook loss %s vs Kalshi %s (diff %s)", league,
                           fmt_dollars(exp_loss_sportsbook_house),
                           fmt_dollars(exp_loss_kalshi_house),
                           fmt_dollars(exp_loss_diff_house)))

cat("Wrote platform loss summary to", out_csv, "and visualizations to", out_png, "and", out_png_diff, "\n")
cat("Overall comparison:", overall_cmp, " (logloss_diff =", round(overall$logloss_diff, 4), ")\n")
cat("Per league expected loss (house stake per game):\n")
cat(paste0(" - ", league_lines$line, collapse = "\n"), "\n")
