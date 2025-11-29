
# Analyze how Kalshi volume relates to accuracy (Brier and log loss)
suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})

input_path <- "data/processed/clean/all_volume_odds.csv"
output_deciles <- "data/processed/analysis/volume_effects_by_decile.csv"
output_league <- "data/processed/analysis/volume_effects_by_league.csv"

if (!file.exists(input_path)) {
  stop("Combined volume + odds file not found. Run kalshi_cleaning.R first.")
}

df <- read_csv(input_path, show_col_types = FALSE)

usable <- df %>%
  filter(market_type == "h2h", !is.na(total_volume), !is.na(home_win)) %>%
  mutate(volume_bucket = ntile(total_volume, 10))

fmt_range <- function(lo, hi) {
  paste0(format(round(lo), big.mark = ",", trim = TRUE), " - ", format(round(hi), big.mark = ",", trim = TRUE))
}

volume_summary <- usable %>%
  group_by(volume_bucket) %>%
  summarise(
    n = n(),
    volume_min = min(total_volume, na.rm = TRUE),
    volume_max = max(total_volume, na.rm = TRUE),
    volume_median = median(total_volume, na.rm = TRUE),
    brier_kalshi = mean(brier_kalshi, na.rm = TRUE),
    logloss_kalshi = mean(logloss_kalshi, na.rm = TRUE),
    brier_sportsbook = mean(brier_sportsbook, na.rm = TRUE),
    logloss_sportsbook = mean(logloss_sportsbook, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(volume_range = fmt_range(volume_min, volume_max)) %>%
  select(volume_bucket, n, volume_range, volume_median, brier_kalshi, logloss_kalshi, brier_sportsbook, logloss_sportsbook)

league_summary <- usable %>%
  group_by(league) %>%
  summarise(
    games = n(),
    median_volume = median(total_volume, na.rm = TRUE),
    mean_volume = mean(total_volume, na.rm = TRUE),
    brier_kalshi = mean(brier_kalshi, na.rm = TRUE),
    logloss_kalshi = mean(logloss_kalshi, na.rm = TRUE),
    brier_sportsbook = mean(brier_sportsbook, na.rm = TRUE),
    logloss_sportsbook = mean(logloss_sportsbook, na.rm = TRUE),
    .groups = "drop"
  )

write_csv(volume_summary, output_deciles)
write_csv(league_summary, output_league)

cat("Wrote volume accuracy summaries to data/processed/analysis
")
