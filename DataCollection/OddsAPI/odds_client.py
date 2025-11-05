#!/usr/bin/env python3
"""
OddsAPI client for collecting sportsbook odds data
"""

import requests
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any
import json


class OddsAPIClient:
    """Client for The Odds API to collect sportsbook odds data"""
    
    def __init__(self, api_key: str):
        self.api_key = api_key
        self.base_url = "https://api.the-odds-api.com/v4"
        self.session = requests.Session()
    
    def get_nfl_odds(
        self, 
        markets: List[str] = None, 
        regions: List[str] = None,
        bookmakers: List[str] = None,
        odds_format: str = "american",
        date_format: str = "iso"
    ) -> Dict[str, Any]:
        """
        Get current NFL odds from sportsbooks
        
        Args:
            markets: List of markets to include (e.g., ['h2h', 'spreads', 'totals'])
            regions: List of regions to include (e.g., ['us', 'us2'])
            bookmakers: Specific bookmakers to include
            odds_format: 'american' or 'decimal'
            date_format: 'iso' or 'unix'
        
        Returns:
            Dictionary containing odds data and metadata
        """
        if markets is None:
            markets = ['h2h', 'spreads', 'totals']  # moneyline, spread, over/under
        if regions is None:
            regions = ['us']  # US sportsbooks
            
        url = f"{self.base_url}/sports/americanfootball_nfl/odds"
        
        params = {
            'apiKey': self.api_key,
            'markets': ','.join(markets),
            'regions': ','.join(regions),
            'oddsFormat': odds_format,
            'dateFormat': date_format
        }
        
        if bookmakers:
            params['bookmakers'] = ','.join(bookmakers)
            
        try:
            response = self.session.get(url, params=params)
            response.raise_for_status()
            
            return {
                'success': True,
                'data': response.json(),
                'headers': dict(response.headers),
                'timestamp': datetime.utcnow().isoformat() + 'Z'
            }
            
        except requests.exceptions.RequestException as e:
            return {
                'success': False,
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat() + 'Z'
            }
    
    def get_historical_odds(
        self,
        date: str,
        markets: List[str] = None,
        regions: List[str] = None,
        bookmakers: List[str] = None,
        odds_format: str = "american",
        date_format: str = "iso"
    ) -> Dict[str, Any]:
        """
        Get historical NFL odds for a specific date
        
        Args:
            date: Date in ISO format (e.g., '2024-11-05T20:00:00Z')
            markets: List of markets to include
            regions: List of regions to include
            bookmakers: Specific bookmakers to include
            odds_format: 'american' or 'decimal'
            date_format: 'iso' or 'unix'
        
        Returns:
            Dictionary containing historical odds data and metadata
        """
        if markets is None:
            markets = ['h2h', 'spreads', 'totals']
        if regions is None:
            regions = ['us']
            
        url = f"{self.base_url}/historical/sports/americanfootball_nfl/odds"
        
        params = {
            'apiKey': self.api_key,
            'date': date,
            'markets': ','.join(markets),
            'regions': ','.join(regions),
            'oddsFormat': odds_format,
            'dateFormat': date_format
        }
        
        if bookmakers:
            params['bookmakers'] = ','.join(bookmakers)
            
        try:
            response = self.session.get(url, params=params)
            response.raise_for_status()
            
            return {
                'success': True,
                'data': response.json(),
                'headers': dict(response.headers),
                'timestamp': datetime.utcnow().isoformat() + 'Z'
            }
            
        except requests.exceptions.RequestException as e:
            return {
                'success': False,
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat() + 'Z'
            }
    
    def find_game_by_teams(self, odds_data: List[Dict], team1: str, team2: str) -> Optional[Dict]:
        """
        Find a specific game in odds data by team names
        
        Args:
            odds_data: List of game odds data
            team1: First team name (can be home or away)
            team2: Second team name (can be home or away)
        
        Returns:
            Game data if found, None otherwise
        """
        team1_lower = team1.lower()
        team2_lower = team2.lower()
        
        for game in odds_data:
            home_team = game.get('home_team', '').lower()
            away_team = game.get('away_team', '').lower()
            
            if ((team1_lower in home_team or home_team in team1_lower) and 
                (team2_lower in away_team or away_team in team2_lower)) or \
               ((team2_lower in home_team or home_team in team2_lower) and 
                (team1_lower in away_team or away_team in team1_lower)):
                return game
                
        return None
    
    def get_usage_info(self) -> Dict[str, Any]:
        """
        Get API usage information
        
        Returns:
            Dictionary containing usage stats
        """
        url = f"{self.base_url}/sports"
        
        params = {
            'apiKey': self.api_key
        }
        
        try:
            response = self.session.get(url, params=params)
            response.raise_for_status()
            
            return {
                'success': True,
                'usage': {
                    'requests_used': response.headers.get('x-requests-used', 'N/A'),
                    'requests_remaining': response.headers.get('x-requests-remaining', 'N/A')
                },
                'sports': response.json()
            }
            
        except requests.exceptions.RequestException as e:
            return {
                'success': False,
                'error': str(e)
            }