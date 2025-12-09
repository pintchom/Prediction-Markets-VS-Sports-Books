# Calibration plot: Kalshi vs Sportsbook
suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})

input_path <- "data/processed/clean/all_volume_odds.csv"
viz_dir <- "data/processed/visualizations"
out_png <- file.path(viz_dir, "calibration_plot.png")

if (!file.exists(input_path)) stop("Missing data/processed/clean/all_volume_odds.csv. Run kalshi_cleaning.R first.")
if (!dir.exists(viz_dir)) dir.create(viz_dir, recursive = TRUE, showWarnings = FALSE)

bin_calibration <- function(df, prob_col, outcome_col, bins = 10) {
  df %>%
    filter(!is.na(.data[[prob_col]]), !is.na(.data[[outcome_col]])) %>%
    mutate(bin = ntile(.data[[prob_col]], bins)) %>%
    group_by(bin) %>%
    summarise(
      prob_avg = mean(.data[[prob_col]], na.rm = TRUE),
      outcome_rate = mean(.data[[outcome_col]], na.rm = TRUE),
      n = n(),
      .groups = "drop"
    ) %>%
    arrange(prob_avg)
}

# Load and prep data
raw <- read_csv(input_path, show_col_types = FALSE)
complete <- raw %>% filter(!is.na(home_win))

kalshi_bins <- bin_calibration(complete, "kalshi_prob_home", "home_win", bins = 10)
sb_bins     <- bin_calibration(complete, "sportsbook_prob_home", "home_win", bins = 10)

# Plot
png(out_png, width = 900, height = 560, res = 120)
op <- par(
  mar = c(6, 6, 4, 2) + 0.1,
  bg = "#f8f9fb",
  col.lab = "#1f1f1f",
  col.axis = "#3a3a3a",
  col.main = "#111111",
  family = "sans"
)
on.exit({par(op); dev.off()}, add = TRUE)

plot(kalshi_bins$prob_avg, kalshi_bins$outcome_rate,
     type = "o", pch = 19, col = "#2ca25f",
     xlim = c(0, 1), ylim = c(0, 1),
     xlab = "Forecasted home win probability",
     ylab = "Empirical win rate",
     main = "Calibration: Kalshi vs Sportsbook (moneylines)")
lines(sb_bins$prob_avg, sb_bins$outcome_rate, type = "o", pch = 17, col = "#1f78b4")
abline(0, 1, col = "#777777", lty = 2)
grid(col = "grey85")
legend("topleft",
       legend = c("Kalshi", "Sportsbook", "Perfect calibration"),
       col = c("#2ca25f", "#1f78b4", "#777777"),
       pch = c(19, 17, NA), lty = c(1, 1, 2), bty = "n")

cat("Wrote calibration plot to", out_png, "\n")
