# Compare sportsbook vig vs Kalshi fee drag
suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})

input_path <- "data/processed/clean/all_volume_odds.csv"
viz_dir <- "data/processed/visualizations"
out_csv <- "data/processed/analysis/platform_fee_vs_vig.csv"
out_png <- file.path(viz_dir, "platform_fee_vs_vig.png")

kalshi_fee <- list(entry = 0.01, profit = 0.05)  # adjust if fee schedule changes

if (!file.exists(input_path)) {
  stop("Missing data/processed/clean/all_volume_odds.csv. Run kalshi_cleaning.R first.")
}

if (!dir.exists(viz_dir)) dir.create(viz_dir, recursive = TRUE, showWarnings = FALSE)
if (!dir.exists(dirname(out_csv))) dir.create(dirname(out_csv), recursive = TRUE, showWarnings = FALSE)

df <- read_csv(input_path, show_col_types = FALSE)

if (!"vig_mean" %in% names(df)) {
  stop("Expected vig_mean column not found. Re-run kalshi_cleaning.R after pulling latest changes.")
}

# Expected % cost per $1 staked from sportsbook overround
vig_calc <- df %>%
  mutate(
    sportsbook_overround = vig_mean - 1,
    sportsbook_cost_pct = ifelse(!is.na(vig_mean) & vig_mean > 0, sportsbook_overround / vig_mean, NA_real_)
  )

# Expected % cost from Kalshi taker + profit fees (assumes closing price reflects true prob)
fee_calc <- vig_calc %>%
  mutate(
    price_home = kalshi_prob_home,
    price_away = kalshi_prob_away,
    fee_home = price_home * kalshi_fee$entry + price_home * (1 - price_home) * kalshi_fee$profit,
    fee_away = price_away * kalshi_fee$entry + price_away * (1 - price_away) * kalshi_fee$profit,
    kalshi_cost_pct = rowMeans(cbind(fee_home, fee_away), na.rm = TRUE)
  )

summary_costs <- fee_calc %>%
  group_by(league) %>%
  summarise(
    games = n(),
    avg_sportsbook_cost = mean(sportsbook_cost_pct, na.rm = TRUE),
    avg_kalshi_cost = mean(kalshi_cost_pct, na.rm = TRUE),
    cost_gap_sportsbook_minus_kalshi = avg_sportsbook_cost - avg_kalshi_cost,
    .groups = "drop"
  )

overall <- fee_calc %>%
  summarise(
    league = "ALL",
    games = n(),
    avg_sportsbook_cost = mean(sportsbook_cost_pct, na.rm = TRUE),
    avg_kalshi_cost = mean(kalshi_cost_pct, na.rm = TRUE),
    cost_gap_sportsbook_minus_kalshi = avg_sportsbook_cost - avg_kalshi_cost
  )

out_table <- bind_rows(summary_costs, overall)
write_csv(out_table, out_csv)

fmt_pct <- function(x) {
  paste0(round(x * 100, 2), "%")
}

save_png <- function(path, expr) {
  png(path, width = 900, height = 560, res = 120)
  op <- par(
    mar = c(8.5, 6.8, 3.5, 1) + 0.1,
    bg = "#f8f9fb",
    col.lab = "#1f1f1f",
    col.axis = "#3a3a3a",
    col.main = "#111111",
    family = "sans",
    mgp = c(3.8, 0.7, 0)
  )
  on.exit({par(op); dev.off()}, add = TRUE)
  expr()
}

save_png(out_png, function() {
  leagues <- summary_costs$league
  mat <- rbind(summary_costs$avg_sportsbook_cost, summary_costs$avg_kalshi_cost)
  rownames(mat) <- c("Sportsbook vig", "Kalshi fees")
  yr <- range(mat, na.rm = TRUE)
  sp <- diff(yr)
  pad <- if (is.finite(sp) && sp > 0) max(sp * 0.35, 0.02) else 0.02
  y_min <- max(0, yr[1] - pad * 0.2)
  y_max <- yr[2] + pad * 1.8
  bp <- barplot(mat, beside = TRUE, names.arg = leagues, las = 2,
                col = c("#1f78b4", "#2ca25f"), border = NA, ylim = c(y_min, y_max),
                ylab = "Expected cost per $1 staked",
                main = "Sportsbook Vig vs Kalshi Fees",
                cex.names = 0.65)
  abline(h = pretty(mat), col = "grey90", lty = 3)
  text(x = bp, y = mat, labels = fmt_pct(mat), pos = 3, cex = 0.6, col = "#2c2c2c", offset = 0.6)
  legend("top", inset = c(0, -0.05), xpd = NA,
         legend = c("Sportsbook vig", "Kalshi fees"),
         fill = c("#1f78b4", "#2ca25f"), bty = "n", cex = 0.9, horiz = TRUE)
})

cat("Wrote fee vs vig table to", out_csv, "and visualization to", out_png, "\n")
cat("Overall gap (Sportsbook - Kalshi):", fmt_pct(overall$cost_gap_sportsbook_minus_kalshi), "\n")
