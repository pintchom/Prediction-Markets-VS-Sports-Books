
# Statistical tests on Brier scores and volume (base R only)
suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})

input_path <- "data/processed/clean/all_volume_odds.csv"
output_path <- "data/processed/analysis/brier_stats.txt"

if (!file.exists(input_path)) stop("Missing all_volume_odds.csv; run cleaning first.")

raw <- read_csv(input_path, show_col_types = FALSE)

df <- raw %>%
  filter(!is.na(home_win), !is.na(total_volume), !is.na(brier_kalshi), !is.na(brier_sportsbook)) %>%
  mutate(
    log_vol = log(total_volume),
    brier_edge = brier_kalshi - brier_sportsbook
  )

summarise_t <- function(data, label) {
  if (nrow(data) < 3) return(NULL)
  t_res <- t.test(data$brier_kalshi, data$brier_sportsbook, paired = TRUE)
  data.frame(
    scope = label,
    n_games = nrow(data),
    mean_brier_kalshi = mean(data$brier_kalshi, na.rm = TRUE),
    mean_brier_sportsbook = mean(data$brier_sportsbook, na.rm = TRUE),
    mean_diff = mean(data$brier_edge, na.rm = TRUE),
    ci_lower = t_res$conf.int[1],
    ci_upper = t_res$conf.int[2],
    p_value = t_res$p.value
  )
}

overall_t <- summarise_t(df, "overall")
by_league_t <- do.call(rbind, lapply(split(df, df$league), summarise_t, label = names(split(df, df$league))))

reg_kalshi <- lm(brier_kalshi ~ log_vol + league, data = df)
reg_edge <- lm(brier_edge ~ log_vol + league, data = df)

capture_coeff <- function(model) {
  co <- summary(model)$coefficients
  out <- data.frame(term = rownames(co), co, row.names = NULL)
  names(out) <- c("term", "estimate", "std_error", "t_value", "p_value")
  out
}

coeff_kalshi <- capture_coeff(reg_kalshi)
coeff_edge <- capture_coeff(reg_edge)

sink(output_path)
cat("Brier comparisons (Kalshi vs Sportsbook)
")
cat("======================================

")
cat("Paired t-tests (mean difference = Kalshi - Sportsbook)
")
print(overall_t)
print(by_league_t)
cat("
Interpretation: negative mean_diff => Kalshi lower (better) Brier.
")

cat("
Regression: Kalshi Brier ~ log(volume) + league
")
print(coeff_kalshi)
cat("
Regression: Brier edge (Kalshi - Sportsbook) ~ log(volume) + league
")
print(coeff_edge)
cat("
Interpretation: negative log_vol coefficient => higher volume linked to better (lower) Brier. For edge model, negative log_vol => Kalshi edge improves with volume; negative intercept => Kalshi better at baseline.
")

sink()
cat("Wrote stats to", output_path, "
")
