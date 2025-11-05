#!/usr/bin/env python3
"""
Live odds collection script for NFL games
Monitors upcoming games and collects odds 5 minutes before start time
"""

import json
import schedule
import time
from datetime import datetime, timedelta
from pathlib import Path
from typing import List, Dict, Any

from odds_client import OddsAPIClient

# Base directory for data files
BASE_DIR = Path(__file__).parent.parent.parent
DATA_DIR = BASE_DIR / "data"

# API Key
ODDS_API_KEY = "d5eebbe2c7ef4d19099f2038efe9b71b"


class LiveOddsCollector:
    """Collects sportsbook odds at specific times before NFL games start"""
    
    def __init__(self, api_key: str):
        self.client = OddsAPIClient(api_key)
        self.collected_games = set()  # Track games we've already collected
        
    def get_upcoming_games(self) -> List[Dict[str, Any]]:
        """Get list of upcoming NFL games"""
        result = self.client.get_nfl_odds(
            markets=['h2h'],  # Just need basic info for scheduling
            regions=['us']
        )
        
        if not result['success']:
            print(f"Error fetching upcoming games: {result.get('error')}")
            return []
            
        games = result['data']
        upcoming = []
        
        now = datetime.utcnow()
        
        for game in games:
            commence_time_str = game.get('commence_time')
            if not commence_time_str:
                continue
                
            # Parse commence time
            commence_time = datetime.fromisoformat(commence_time_str.replace('Z', '+00:00'))
            
            # Only include games that haven't started yet
            if commence_time > now:
                upcoming.append({
                    'id': game.get('id'),
                    'home_team': game.get('home_team'),
                    'away_team': game.get('away_team'),
                    'commence_time': commence_time,
                    'commence_time_str': commence_time_str
                })
        
        return upcoming
    
    def collect_odds_for_game(self, game: Dict[str, Any]) -> Dict[str, Any]:
        """Collect comprehensive odds for a specific game"""
        result = self.client.get_nfl_odds(
            markets=['h2h', 'spreads', 'totals'],
            regions=['us', 'us2'],  # Include more US books
            odds_format='american'
        )
        
        if not result['success']:
            return {
                'success': False,
                'error': result.get('error'),
                'game_id': game.get('id')
            }
        
        # Find this specific game in the odds data
        game_odds = None
        for odds_game in result['data']:
            if odds_game.get('id') == game.get('id'):
                game_odds = odds_game
                break
        
        if not game_odds:
            return {
                'success': False,
                'error': 'Game not found in current odds data',
                'game_id': game.get('id')
            }
        
        # Process bookmaker odds
        processed_odds = self._process_bookmaker_odds(game_odds)
        
        return {
            'success': True,
            'game_id': game_odds.get('id'),
            'home_team': game_odds.get('home_team'),
            'away_team': game_odds.get('away_team'),
            'commence_time': game_odds.get('commence_time'),
            'collection_time': datetime.utcnow().isoformat() + 'Z',
            'bookmaker_odds': processed_odds,
            'total_bookmakers': len(processed_odds),
            'raw_data': game_odds  # Keep full data for debugging
        }
    
    def _process_bookmaker_odds(self, game_data: Dict[str, Any]) -> Dict[str, Any]:
        """Process and structure bookmaker odds data"""
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
                    point = outcome.get('point')
                    
                    bookmaker_odds[bookie_name][market_key][outcome_name] = {
                        'price': odds_value,
                        'point': point
                    }
        
        return bookmaker_odds
    
    def schedule_collection_for_game(self, game: Dict[str, Any]):
        """Schedule odds collection 5 minutes before a game starts"""
        commence_time = game['commence_time']
        collection_time = commence_time - timedelta(minutes=5)
        
        game_key = f"{game['home_team']}-{game['away_team']}-{commence_time.isoformat()}"
        
        if game_key in self.collected_games:
            return  # Already scheduled or collected
            
        # Check if collection time is in the future
        now = datetime.utcnow().replace(tzinfo=commence_time.tzinfo)
        if collection_time <= now:
            print(f"Collection time has passed for {game['home_team']} vs {game['away_team']}")
            return
        
        def collect_job():
            print(f"Collecting odds for {game['home_team']} vs {game['away_team']}...")
            odds_data = self.collect_odds_for_game(game)
            
            if odds_data['success']:
                # Save individual game data
                filename = f"odds_{game['home_team']}_{game['away_team']}_{commence_time.strftime('%Y%m%d_%H%M')}.json"
                filepath = DATA_DIR / "live_odds" / filename
                filepath.parent.mkdir(exist_ok=True)
                
                with open(filepath, 'w') as f:
                    json.dump(odds_data, f, indent=2)
                
                print(f"  ✓ Saved odds data with {odds_data['total_bookmakers']} bookmakers to {filepath}")
                
                # Also append to master file
                self._append_to_master_file(odds_data)
                
            else:
                print(f"  ✗ Failed to collect odds: {odds_data.get('error')}")
            
            # Mark as collected
            self.collected_games.add(game_key)
        
        # Schedule the job
        schedule.every().day.at(collection_time.strftime('%H:%M')).do(collect_job).tag(game_key)
        self.collected_games.add(game_key)
        
        print(f"Scheduled collection for {game['home_team']} vs {game['away_team']} at {collection_time}")
    
    def _append_to_master_file(self, odds_data: Dict[str, Any]):
        """Append odds data to master file"""
        master_file = DATA_DIR / "live_nfl_odds.json"
        
        # Load existing data
        if master_file.exists():
            with open(master_file, 'r') as f:
                master_data = json.load(f)
        else:
            master_data = {
                'description': 'Live NFL sportsbook odds collected 5 minutes before game start',
                'games': []
            }
        
        # Add new game data
        master_data['games'].append(odds_data)
        master_data['last_updated'] = datetime.utcnow().isoformat() + 'Z'
        master_data['total_games'] = len(master_data['games'])
        
        # Save back to file
        with open(master_file, 'w') as f:
            json.dump(master_data, f, indent=2)
    
    def run_scheduler(self):
        """Main loop to monitor and schedule game collections"""
        print("Starting live odds collection scheduler...")
        
        while True:
            try:
                # Get upcoming games and schedule collections
                upcoming_games = self.get_upcoming_games()
                print(f"\nFound {len(upcoming_games)} upcoming NFL games")
                
                for game in upcoming_games:
                    self.schedule_collection_for_game(game)
                
                # Run any pending scheduled jobs
                schedule.run_pending()
                
                # Wait before next check (check every 10 minutes)
                time.sleep(600)
                
            except KeyboardInterrupt:
                print("\nShutting down scheduler...")
                break
            except Exception as e:
                print(f"Error in scheduler: {e}")
                time.sleep(60)  # Wait 1 minute before retrying


def main():
    """Main execution"""
    collector = LiveOddsCollector(ODDS_API_KEY)
    
    # Check API status
    usage_info = collector.client.get_usage_info()
    if usage_info['success']:
        print(f"API requests remaining: {usage_info['usage']['requests_remaining']}")
    else:
        print("Warning: Could not check API usage")
    
    # Start the scheduler
    collector.run_scheduler()


if __name__ == "__main__":
    main()