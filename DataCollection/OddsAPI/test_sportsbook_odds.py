#!/usr/bin/env python3
"""
Test script to collect sportsbook odds for just 3 games
Quick test version of get_sportsbook_odds.py
"""

import json
import os
from datetime import datetime, timedelta, timezone
from pathlib import Path
import time
from typing import Dict, List, Any, Optional
import os
from odds_client import OddsAPIClient

# Base directory for data files
BASE_DIR = Path(__file__).parent.parent.parent
DATA_DIR = BASE_DIR / "data"

# API Key
ODDS_API_KEY = "d5eebbe2c7ef4d19099f2038efe9b71b"


def get_sportsbook_odds_before_game_start(
    client: OddsAPIClient, 
    home_team: str, 
    away_team: str, 
    game_start_time: str,
    minutes_before: int = 5
) -> Optional[Dict[str, Any]]:
    """
    Get sportsbook odds X minutes before game start
    """
    try:
        # Parse game start time
        game_start = datetime.fromisoformat(game_start_time.replace('Z', '+00:00'))
        target_time = game_start - timedelta(minutes=minutes_before)
        
        print(f"    Target collection time: {target_time.isoformat()}")
        
        # For historical data, we need to call the historical endpoint
        historical_date = target_time.strftime('%Y-%m-%dT%H:%M:%SZ')
        
        # Get historical odds for that specific time
        result = client.get_historical_odds(
            date=historical_date,
            markets=['h2h', 'spreads', 'totals'],
            regions=['us'],
            odds_format='american'
        )
        
        if not result['success']:
            print(f"    Error fetching odds: {result.get('error', 'Unknown error')}")
            return None
            
        odds_data = result['data']
        
        if not odds_data:
            print("    No odds data available for this time")
            return None
            
        # Find the specific game in the odds data
        game_data = client.find_game_by_teams(odds_data.get('data', odds_data), home_team, away_team)
        
        if not game_data:
            print(f"    Game not found in odds data: {home_team} vs {away_team}")
            return None
            
        # Extract sportsbook odds
        bookmaker_odds = {}
        
        for bookmaker in game_data.get('bookmakers', []):
            bookie_name = bookmaker.get('title', bookmaker.get('key', 'unknown'))
            bookmaker_odds[bookie_name] = {}
            
            for market in bookmaker.get('markets', []):
                market_key = market.get('key')
                bookmaker_odds[bookie_name][market_key] = {}
                
                for outcome in market.get('outcomes', []):
                    outcome_name = outcome.get('name')
                    odds_value = outcome.get('price')
                    point = outcome.get('point')  # For spreads and totals
                    
                    bookmaker_odds[bookie_name][market_key][outcome_name] = {
                        'price': odds_value,
                        'point': point
                    }
        
        return {
            'game_id': game_data.get('id'),
            'home_team': game_data.get('home_team'),
            'away_team': game_data.get('away_team'),
            'commence_time': game_data.get('commence_time'),
            'game_start': game_start.isoformat(),
            'collection_time': target_time.isoformat(),
            'collection_time_actual': result['timestamp'],
            'bookmaker_odds': bookmaker_odds,
            'total_bookmakers': len(bookmaker_odds),
            'markets_collected': list(set([
                market_key 
                for bookie_data in bookmaker_odds.values() 
                for market_key in bookie_data.keys()
            ]))
        }
        
    except Exception as e:
        print(f"    Error processing {home_team} vs {away_team}: {e}")
        return None


def test_collect_sportsbook_odds(kalshi_data_file: str, output_file: str, max_games: int = 3):
    """
    Test version - collect sportsbook odds for just a few NFL games
    """
    print(f"Reading Kalshi data from {kalshi_data_file}...")
    
    with open(kalshi_data_file, 'r') as f:
        kalshi_data = json.load(f)
    
    # Initialize OddsAPI client
    client = OddsAPIClient(ODDS_API_KEY)
    
    # Check API usage before starting
    usage_info = client.get_usage_info()
    if usage_info['success']:
        print(f"API requests remaining: {usage_info['usage']['requests_remaining']}")
    
    sportsbook_odds = []
    closing_lines = kalshi_data.get('closing_lines', [])
    
    print(f"Found {len(closing_lines)} total games, testing with {max_games} games")
    print("Collecting sportsbook odds...\n")
    
    processed = 0
    successful = 0
    failed = 0
    
    # Team mapping for parsing tickers
    team_map = {
        'WAS': 'Washington Commanders', 'SEA': 'Seattle Seahawks',
        'DAL': 'Dallas Cowboys', 'ARI': 'Arizona Cardinals',
        'KC': 'Kansas City Chiefs', 'BUF': 'Buffalo Bills',
        'NO': 'New Orleans Saints', 'LA': 'Los Angeles Rams',
        'JAC': 'Jacksonville Jaguars', 'LV': 'Las Vegas Raiders',
        'CAR': 'Carolina Panthers', 'GB': 'Green Bay Packers',
        'DET': 'Detroit Lions', 'MIN': 'Minnesota Vikings',
        'CIN': 'Cincinnati Bengals', 'CHI': 'Chicago Bears',
        'NYJ': 'New York Jets', 'NE': 'New England Patriots',
        'MIA': 'Miami Dolphins', 'BAL': 'Baltimore Ravens',
        'PIT': 'Pittsburgh Steelers', 'CLE': 'Cleveland Browns',
        'HOU': 'Houston Texans', 'IND': 'Indianapolis Colts',
        'TEN': 'Tennessee Titans', 'DEN': 'Denver Broncos',
        'LAC': 'Los Angeles Chargers', 'NYG': 'New York Giants',
        'PHI': 'Philadelphia Eagles', 'SF': 'San Francisco 49ers',
        'TB': 'Tampa Bay Buccaneers', 'ATL': 'Atlanta Falcons'
    }
    
    for kalshi_game in closing_lines:
        if processed >= max_games:
            break
            
        processed += 1
        
        # Extract team names from Kalshi data
        subtitle = kalshi_game.get('subtitle', '').strip()
        ticker = kalshi_game.get('ticker', '')
        
        home_team = None
        away_team = None
        
        if subtitle and (' @ ' in subtitle or ' vs ' in subtitle):
            if ' @ ' in subtitle:
                away_team, home_team = subtitle.split(' @ ')
            elif ' vs ' in subtitle:
                teams = subtitle.split(' vs ')
                home_team, away_team = teams[0], teams[1]
        else:
            # Parse from ticker
            try:
                parts = ticker.split('-')
                if len(parts) >= 3:
                    team_part = parts[1][7:]  # Remove date part
                    winner = parts[2]
                    
                    # Find valid team combination
                    away_code = None
                    home_code = None
                    
                    for i in range(2, len(team_part)):
                        potential_team1 = team_part[:i]
                        potential_team2 = team_part[i:]
                        
                        if potential_team1 in team_map and potential_team2 in team_map:
                            if winner == potential_team1:
                                home_code = potential_team1
                                away_code = potential_team2
                            elif winner == potential_team2:
                                home_code = potential_team2
                                away_code = potential_team1
                            else:
                                away_code = potential_team1
                                home_code = potential_team2
                            break
                    
                    if away_code in team_map and home_code in team_map and away_code != home_code:
                        away_team = team_map[away_code]
                        home_team = team_map[home_code]
                        print(f"    Parsed: {away_code} @ {home_code} -> {away_team} @ {home_team}")
                        
            except Exception as e:
                print(f"    Error parsing ticker {ticker}: {e}")
        
        if not home_team or not away_team:
            print(f"[{processed}/{max_games}] ✗ Cannot parse teams from ticker: {ticker}")
            failed += 1
            continue
        
        game_start = kalshi_game.get('game_start')
        if not game_start:
            print(f"[{processed}/{max_games}] ✗ No game start time")
            failed += 1
            continue
        
        print(f"[{processed}/{max_games}] Processing {home_team} vs {away_team}...")
        
        odds_data = get_sportsbook_odds_before_game_start(
            client=client,
            home_team=home_team.strip(),
            away_team=away_team.strip(),
            game_start_time=game_start,
            minutes_before=5
        )
        
        if odds_data:
            # Add Kalshi context
            odds_data['kalshi_ticker'] = kalshi_game.get('ticker')
            odds_data['kalshi_price'] = kalshi_game.get('price', {}).get('close')
            odds_data['kalshi_yes_bid'] = kalshi_game.get('yes_bid', {}).get('close')
            odds_data['kalshi_yes_ask'] = kalshi_game.get('yes_ask', {}).get('close')
            
            sportsbook_odds.append(odds_data)
            successful += 1
            print(f"    ✓ Collected odds from {odds_data['total_bookmakers']} bookmakers")
            
            # Pretty print the first successful result for debugging
            if successful == 1:
                print("\n" + "="*60)
                print("SAMPLE ODDS DATA:")
                print("="*60)
                print(json.dumps(odds_data, indent=2)[:1000] + "...")
                print("="*60 + "\n")
                
        else:
            failed += 1
            print("    ✗ No sportsbook odds data available")
        
        # Small delay between requests
        time.sleep(0.3)
    
    # Save results
    output_data = {
        'collection_date': datetime.now(timezone.utc).isoformat(),
        'description': f'TEST: Sportsbook odds 5 minutes before NFL game start (first {max_games} games)',
        'source': 'The Odds API',
        'total_games_processed': processed,
        'successful': successful,
        'failed': failed,
        'sportsbook_odds': sportsbook_odds
    }
    
    print(f"Saving test results to {output_file}...")
    with open(output_file, 'w') as f:
        json.dump(output_data, f, indent=2)
    
    print(f"\n{'='*60}")
    print(f"TEST SUMMARY")
    print(f"{'='*60}")
    print(f"Games processed: {processed}")
    print(f"Successful: {successful}")
    print(f"Failed: {failed}")
    if successful + failed > 0:
        print(f"Success rate: {(successful/(successful+failed)*100):.1f}%")
    print(f"\nTest results saved to: {output_file}")
    
    # Check remaining API usage
    usage_info = client.get_usage_info()
    if usage_info['success']:
        print(f"API requests remaining: {usage_info['usage']['requests_remaining']}")


def main():
    """Main execution"""
    kalshi_data_file = DATA_DIR / "nfl_closing_lines.json"
    output_file = DATA_DIR / "test_nfl_sportsbook_odds.json"
    
    if not kalshi_data_file.exists():
        print(f"Error: Kalshi data file not found at {kalshi_data_file}")
        return
    
    test_collect_sportsbook_odds(
        kalshi_data_file=str(kalshi_data_file),
        output_file=str(output_file),
        max_games=3  # Only test with 3 games
    )


if __name__ == "__main__":
    main()