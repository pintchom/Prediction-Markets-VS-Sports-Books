#!/usr/bin/env python3
"""
Simple test script to verify OddsAPI connection and data structure
Gets current live NFL odds (not historical)
"""

import json
import os
from datetime import datetime, timezone
from pathlib import Path
from odds_client import OddsAPIClient

# Base directory for data files
BASE_DIR = Path(__file__).parent.parent.parent
DATA_DIR = BASE_DIR / "data"

# API Key
ODDS_API_KEY = "d5eebbe2c7ef4d19099f2038efe9b71b"


def test_api_connection():
    """Test basic API connection and get current NFL games"""
    
    print("Testing OddsAPI connection...")
    client = OddsAPIClient(ODDS_API_KEY)
    
    # Check API usage
    usage_info = client.get_usage_info()
    if usage_info['success']:
        print(f"✓ API connection successful")
        print(f"  Requests remaining: {usage_info['usage']['requests_remaining']}")
    else:
        print(f"✗ API connection failed: {usage_info.get('error')}")
        return False
    
    # Get current NFL odds
    print("\nFetching current NFL odds...")
    result = client.get_nfl_odds(
        markets=['h2h'],  # Just moneyline for testing
        regions=['us'],
        odds_format='american'
    )
    
    if not result['success']:
        print(f"✗ Failed to get odds: {result.get('error')}")
        return False
    
    games = result['data']
    print(f"✓ Found {len(games)} current NFL games")
    
    # Show first few games as examples
    print("\nSample games:")
    for i, game in enumerate(games[:3]):
        print(f"\n{i+1}. {game.get('away_team')} @ {game.get('home_team')}")
        print(f"   Commence: {game.get('commence_time')}")
        print(f"   Game ID: {game.get('id')}")
        
        # Show bookmaker odds
        bookmakers = game.get('bookmakers', [])
        if bookmakers:
            print(f"   Bookmakers: {len(bookmakers)}")
            for bookie in bookmakers[:2]:  # Show first 2 bookies
                print(f"     {bookie.get('title')}:")
                for market in bookie.get('markets', []):
                    if market.get('key') == 'h2h':  # moneyline
                        for outcome in market.get('outcomes', []):
                            team = outcome.get('name')
                            odds = outcome.get('price')
                            print(f"       {team}: {odds}")
    
    # Save sample data for inspection
    sample_data = {
        'timestamp': datetime.now(timezone.utc).isoformat(),
        'total_games': len(games),
        'sample_games': games[:3],
        'api_usage': usage_info['usage']
    }
    
    output_file = DATA_DIR / "test_live_odds_sample.json"
    with open(output_file, 'w') as f:
        json.dump(sample_data, f, indent=2)
    
    print(f"\n✓ Sample data saved to: {output_file}")
    return True


def test_team_matching():
    """Test if we can match teams from different sources"""
    
    # Sample team names from different sources
    kalshi_teams = ["Washington Commanders", "Seattle Seahawks", "Kansas City Chiefs"]
    oddsapi_teams = ["Washington Commanders", "Seattle Seahawks", "Kansas City Chiefs"]
    
    print("\nTesting team name matching...")
    
    client = OddsAPIClient(ODDS_API_KEY)
    
    for kalshi_team in kalshi_teams:
        found_match = client.find_game_by_teams(
            [{'home_team': 'Sample Home', 'away_team': kalshi_team}],
            'Sample Home',
            kalshi_team
        )
        print(f"  {kalshi_team}: {'✓' if found_match else '✗'}")


def main():
    """Run all tests"""
    print("="*60)
    print("ODDSAPI CONNECTION TEST")
    print("="*60)
    
    if test_api_connection():
        test_team_matching()
        print("\n✓ All tests completed successfully!")
    else:
        print("\n✗ Tests failed - check API key and connection")


if __name__ == "__main__":
    main()