
# Kalshi trading volume + sportsbook odds cleaner
suppressPackageStartupMessages({
  library(dplyr)
  library(jsonlite)
  library(lubridate)
  library(purrr)
  library(readr)
  library(stringr)
  library(tidyr)
})

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x
american_to_prob <- function(odds) {
  ifelse(is.na(odds), NA_real_, ifelse(odds < 0, -odds / (-odds + 100), 100 / (odds + 100)))
}
first_non_na <- function(x) {
  out <- x[which(!is.na(x))[1]]
  ifelse(length(out) == 0, NA_real_, out)
}
safe_mean <- function(x) if (all(is.na(x))) NA_real_ else mean(x, na.rm = TRUE)

nba_map <- tibble(
  code = c("ATL","BOS","BKN","CHA","CHI","CLE","DAL","DEN","DET","GSW","HOU","IND","LAC","LAL","MEM","MIA","MIL","MIN","NOP","NYK","OKC","ORL","PHI","PHX","POR","SAC","SAS","TOR","UTA","WAS"),
  team = c("Atlanta Hawks","Boston Celtics","Brooklyn Nets","Charlotte Hornets","Chicago Bulls","Cleveland Cavaliers","Dallas Mavericks","Denver Nuggets","Detroit Pistons","Golden State Warriors","Houston Rockets","Indiana Pacers","Los Angeles Clippers","Los Angeles Lakers","Memphis Grizzlies","Miami Heat","Milwaukee Bucks","Minnesota Timberwolves","New Orleans Pelicans","New York Knicks","Oklahoma City Thunder","Orlando Magic","Philadelphia 76ers","Phoenix Suns","Portland Trail Blazers","Sacramento Kings","San Antonio Spurs","Toronto Raptors","Utah Jazz","Washington Wizards")
)

nfl_map <- tibble(
  code = c("ARI","ATL","BAL","BUF","CAR","CHI","CIN","CLE","DAL","DEN","DET","GB","HOU","IND","JAX","KC","LA","LAC","LV","MIA","MIN","NE","NO","NYG","NYJ","PHI","PIT","SEA","SF","TB","TEN","WAS"),
  team = c("Arizona Cardinals","Atlanta Falcons","Baltimore Ravens","Buffalo Bills","Carolina Panthers","Chicago Bears","Cincinnati Bengals","Cleveland Browns","Dallas Cowboys","Denver Broncos","Detroit Lions","Green Bay Packers","Houston Texans","Indianapolis Colts","Jacksonville Jaguars","Kansas City Chiefs","Los Angeles Rams","Los Angeles Chargers","Las Vegas Raiders","Miami Dolphins","Minnesota Vikings","New England Patriots","New Orleans Saints","New York Giants","New York Jets","Philadelphia Eagles","Pittsburgh Steelers","Seattle Seahawks","San Francisco 49ers","Tampa Bay Buccaneers","Tennessee Titans","Washington Commanders")
)

dir.create("data/processed/clean", recursive = TRUE, showWarnings = FALSE)
dir.create("data/processed/analysis", recursive = TRUE, showWarnings = FALSE)

prepare_clean_frame <- function(path, league) {
  df <- read_csv(path, show_col_types = FALSE)
  df$league <- league
  df$event_ticker <- str_remove(df$kalshi_ticker, "-[A-Z0-9]+$")
  df$game_start <- suppressWarnings(ymd_hms(df$game_start))
  game_date_col <- if ("game_date" %in% names(df)) as_date(df$game_date) else as_date(NA)
  game_date_et_col <- if ("game_date_et" %in% names(df)) as_date(df$game_date_et) else as_date(NA)
  df$game_date <- game_date_col
  df$game_date_et <- game_date_et_col
  df$game_date_clean <- dplyr::coalesce(game_date_col, game_date_et_col, as_date(df$game_start))
  df$home_score <- suppressWarnings(as.numeric(df$home_score))
  df$away_score <- suppressWarnings(as.numeric(df$away_score))
  df
}

compute_sportsbook_probs <- function(clean_df) {
  clean_df %>%
    filter(market_type == "h2h", value_type == "price") %>%
    group_by(game_id, bookmaker) %>%
    summarise(
      event_ticker = first(event_ticker),
      league = first(league),
      home_team = first(home_team),
      away_team = first(away_team),
      game_start = first(game_start),
      game_date = first(game_date_clean),
      home_score = first(home_score),
      away_score = first(away_score),
      home_price = first(value[team_or_side == first(home_team)]),
      away_price = first(value[team_or_side == first(away_team)]),
      .groups = "drop"
    ) %>%
    mutate(
      home_prob_raw = american_to_prob(home_price),
      away_prob_raw = american_to_prob(away_price),
      vig = home_prob_raw + away_prob_raw,
      prob_home = home_prob_raw / vig,
      prob_away = away_prob_raw / vig
    ) %>%
    group_by(game_id, event_ticker, league, home_team, away_team, game_start, game_date, home_score, away_score) %>%
    summarise(
      bookmakers_used = sum(!is.na(prob_home)),
      sportsbook_prob_home = safe_mean(prob_home),
      sportsbook_prob_away = safe_mean(prob_away),
      .groups = "drop"
    ) %>%
    mutate(home_win = ifelse(!is.na(home_score) & !is.na(away_score), as.integer(home_score > away_score), NA_integer_))
}

prepare_closing_lines <- function(path, league, team_map) {
  raw <- fromJSON(path)$closing_lines
  if (length(raw) == 0) return(tibble())
  tibble::as_tibble(raw) %>%
    mutate(
      event_ticker = str_remove(ticker, "-[A-Z0-9]+$"),
      team_code = str_extract(ticker, "[A-Z0-9]+$"),
      league = league
    ) %>%
    unnest_wider(price, names_sep = "_") %>%
    unnest_wider(yes_bid, names_sep = "_") %>%
    unnest_wider(yes_ask, names_sep = "_") %>%
    rename(price_close = price_close, yes_bid_close = yes_bid_close, yes_ask_close = yes_ask_close) %>%
    mutate(prob_close = price_close / 100) %>%
    left_join(team_map, by = c("team_code" = "code"))
}

attach_volume <- function(consensus_df, closing_df) {
  if (nrow(consensus_df) == 0) return(consensus_df)
  if (nrow(closing_df) == 0) {
    return(consensus_df %>% mutate(volume_home = NA_real_, volume_away = NA_real_, total_volume = NA_real_, kalshi_prob_home = NA_real_, kalshi_prob_away = NA_real_))
  }
  lookup <- consensus_df %>% select(event_ticker, league, home_team, away_team)
  closing_with_side <- closing_df %>%
    inner_join(lookup, by = c("event_ticker", "league")) %>%
    mutate(side = case_when(team == home_team ~ "home", team == away_team ~ "away", TRUE ~ NA_character_))

  summary <- closing_with_side %>%
    group_by(event_ticker, league) %>%
    summarise(
      volume_home = sum(volume[side == "home"], na.rm = TRUE),
      volume_away = sum(volume[side == "away"], na.rm = TRUE),
      kalshi_prob_home = first_non_na(prob_close[side == "home"]),
      kalshi_prob_away = first_non_na(prob_close[side == "away"]),
      .groups = "drop"
    ) %>%
    mutate(total_volume = ifelse(is.na(volume_home) & is.na(volume_away), NA_real_, volume_home + volume_away))

  consensus_df %>%
    left_join(summary, by = c("event_ticker", "league")) %>%
    mutate(
      total_prob = ifelse(!is.na(kalshi_prob_home) & !is.na(kalshi_prob_away), kalshi_prob_home + kalshi_prob_away, NA_real_),
      kalshi_prob_home = ifelse(!is.na(total_prob), kalshi_prob_home / total_prob, kalshi_prob_home),
      kalshi_prob_away = ifelse(!is.na(total_prob), kalshi_prob_away / total_prob, kalshi_prob_away),
      total_prob = NULL
    )
}

add_scoring <- function(df) {
  df %>%
    mutate(
      home_win = ifelse(!is.na(home_score) & !is.na(away_score), as.integer(home_score > away_score), home_win),
      prob_home_kalshi_clipped = pmin(pmax(kalshi_prob_home, 1e-6), 1 - 1e-6),
      prob_home_sportsbook_clipped = pmin(pmax(sportsbook_prob_home, 1e-6), 1 - 1e-6),
      brier_kalshi = ifelse(is.na(home_win), NA_real_, (prob_home_kalshi_clipped - home_win)^2),
      logloss_kalshi = ifelse(is.na(home_win), NA_real_, -(home_win * log(prob_home_kalshi_clipped) + (1 - home_win) * log(1 - prob_home_kalshi_clipped))),
      brier_sportsbook = ifelse(is.na(home_win), NA_real_, (prob_home_sportsbook_clipped - home_win)^2),
      logloss_sportsbook = ifelse(is.na(home_win), NA_real_, -(home_win * log(prob_home_sportsbook_clipped) + (1 - home_win) * log(1 - prob_home_sportsbook_clipped)))
    ) %>%
    select(-prob_home_kalshi_clipped, -prob_home_sportsbook_clipped)
}

build_league <- function(league, clean_path, closing_path, team_map) {
  clean_df <- prepare_clean_frame(clean_path, league)
  consensus <- compute_sportsbook_probs(clean_df)
  closing <- prepare_closing_lines(closing_path, league, team_map)
  final <- consensus %>% attach_volume(closing) %>% mutate(market_type = "h2h")
  add_scoring(final)
}

nba_input <- file.path("Odds API Data", "NBA Data", "NBA_clean_odd.csv")
nfl_input <- file.path("Odds API Data", "NFL Data", "NFL_clean_odd.csv")

nba <- build_league("NBA", nba_input, "data/nba_closing_lines.json", nba_map)
nfl <- build_league("NFL", nfl_input, "data/nfl_closing_lines.json", nfl_map)
combined <- bind_rows(nba, nfl)

write_csv(nba, "data/processed/clean/nba_volume_odds.csv")
write_csv(nfl, "data/processed/clean/nfl_volume_odds.csv")
write_csv(combined, "data/processed/clean/all_volume_odds.csv")

cat("Saved league volume+odds files to data/processed/clean
")
