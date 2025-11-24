#!/usr/bin/env python3
"""
Script to collect Kalshi NBA market prices 5 minutes before game start (closing lines)
Uses the candlesticks endpoint to get historical price data
"""

import json
import requests
from datetime import datetime, timedelta
from pathlib import Path
import time

# Base directory for data files
BASE_DIR = Path(__file__).parent.parent.parent
DATA_DIR = BASE_DIR / "data"

def get_price_before_game_start(series_ticker, market_ticker, expected_expiration_time, minutes_before=5):
    """
    Get Kalshi market price X minutes before game start
    
    Args:
        series_ticker: Series ticker (e.g., 'KXNBAGAME')
        market_ticker: Market ticker (e.g., 'KXNBAGAME-25NOV25LACLAL-LAL')
        expected_expiration_time: ISO timestamp from Kalshi (e.g., '2025-11-26T07:00:00Z')
        minutes_before: How many minutes before tipoff (default 5)
    
    Returns:
        dict with price data at that timestamp, or None if no data available
    """
    try:
        # Calculate game start time (expiration - 2.5 hours for NBA games)
        game_end = datetime.fromisoformat(expected_expiration_time.replace('Z', '+00:00'))
        game_start = game_end - timedelta(hours=2, minutes=30)
        
        # Calculate target time (5 minutes before start)
        target_time = game_start - timedelta(minutes=minutes_before)
        
        # Convert to Unix timestamp (seconds)
        target_ts = int(target_time.timestamp())
        
        # Query a 10-minute window around target time to ensure we get data
        start_ts = target_ts - 300  # 5 minutes before
        end_ts = target_ts + 300    # 5 minutes after
        
        # Call Kalshi API - correct endpoint format includes series ticker
        url = f"https://api.elections.kalshi.com/trade-api/v2/series/KXNBAGAME/markets/{market_ticker}/candlesticks"
        
        params = {
            "start_ts": start_ts,
            "end_ts": end_ts,
            "period_interval": 1  # 1-minute intervals
        }
        
        response = requests.get(url, params=params)
        response.raise_for_status()
        
        candlesticks = response.json()
        
        # Find the candlestick closest to our target time
        if 'candlesticks' in candlesticks and len(candlesticks['candlesticks']) > 0:
            # Get the candlestick closest to target_ts
            closest = min(candlesticks['candlesticks'], 
                         key=lambda x: abs(x['end_period_ts'] - target_ts))
            
            return {
                'ticker': market_ticker,
                'game_start': game_start.isoformat(),
                'game_end': game_end.isoformat(),
                'price_time': datetime.fromtimestamp(closest['end_period_ts']).isoformat(),
                'price_time_unix': closest['end_period_ts'],
                'price': {
                    'close': closest['price']['close'],  # Closing trade price (in cents)
                    'open': closest['price']['open'],
                    'high': closest['price']['high'],
                    'low': closest['price']['low'],
                    'mean': closest['price'].get('mean'),
                },
                'yes_bid': {
                    'close': closest['yes_bid']['close'],
                    'open': closest['yes_bid']['open'],
                    'high': closest['yes_bid']['high'],
                    'low': closest['yes_bid']['low'],
                },
                'yes_ask': {
                    'close': closest['yes_ask']['close'],
                    'open': closest['yes_ask']['open'],
                    'high': closest['yes_ask']['high'],
                    'low': closest['yes_ask']['low'],
                },
                'volume': closest.get('volume', 0),
                'open_interest': closest.get('open_interest', 0)
            }
        else:
            return None
            
    except Exception as e:
        print(f"    Error processing {market_ticker}: {e}")
        return None


def collect_closing_lines_for_all_games(markets_file, output_file, delay=0.1):
    """
    Collect closing lines (5 min before start) for all NBA games
    
    Args:
        markets_file: Path to the input JSON file with markets
        output_file: Path to save the results
        delay: Delay between API calls to avoid rate limiting (seconds)
    """
    print(f"Reading markets from {markets_file}...")
    
    with open(markets_file, 'r') as f:
        data = json.load(f)
    
    closing_lines = []
    series_markets = data.get('series_markets', {})
    
    total_markets = 0
    for series in series_markets.values():
        total_markets += len(series.get('markets', []))
    
    print(f"Found {total_markets} total markets to process")
    print("Collecting closing line prices...\n")
    
    processed = 0
    successful = 0
    failed = 0
    skipped = 0
    
    for series_ticker, series_data in series_markets.items():
        markets = series_data.get('markets', [])
        
        for market in markets:
            processed += 1
            ticker = market.get('ticker')
            expected_expiration = market.get('expected_expiration_time')
            status = market.get('status')
            
            # Skip active/future markets - they don't have historical candlestick data yet
            if status != 'finalized':
                print(f"[{processed}/{total_markets}] ⊗ Skipping {ticker} - status: {status} (not finalized)")
                skipped += 1
                continue
            
            if not ticker or not expected_expiration:
                print(f"[{processed}/{total_markets}] ✗ Skipping market - missing ticker or expiration")
                failed += 1
                continue
            
            print(f"[{processed}/{total_markets}] Processing {ticker}...", end=" ")
            
            price_data = get_price_before_game_start(
                series_ticker,
                ticker,
                expected_expiration,
                minutes_before=5
            )
            
            if price_data:
                # Add additional market context
                price_data['event_ticker'] = market.get('event_ticker')
                price_data['subtitle'] = market.get('subtitle')
                price_data['no_sub_title'] = market.get('no_sub_title')
                price_data['yes_sub_title'] = market.get('yes_sub_title')
                price_data['market_type'] = market.get('market_type')
                
                closing_lines.append(price_data)
                successful += 1
                print(f"✓ Close price: {price_data['price']['close']}¢")
            else:
                failed += 1
                print("✗ No data available")
            
            # Delay to avoid rate limiting
            if delay > 0:
                time.sleep(delay)
    
    # Save results
    output_data = {
        'collection_date': datetime.utcnow().isoformat() + 'Z',
        'description': 'Market prices 5 minutes before game start (closing lines)',
        'total_markets_processed': processed,
        'successful': successful,
        'failed': failed,
        'skipped': skipped,
        'closing_lines': closing_lines
    }
    
    print(f"\nSaving results to {output_file}...")
    with open(output_file, 'w') as f:
        json.dump(output_data, f, indent=2)
    
    print(f"\n{'='*60}")
    print(f"SUMMARY")
    print(f"{'='*60}")
    print(f"Total markets processed: {processed}")
    print(f"Skipped (not finalized): {skipped}")
    print(f"Successful: {successful}")
    print(f"Failed: {failed}")
    if successful + failed > 0:
        print(f"Success rate: {(successful/(successful+failed)*100):.1f}%")
    print(f"\nResults saved to: {output_file}")


def main():
    """Main execution"""
    markets_file = DATA_DIR / "nba_series_markets.json"
    output_file = DATA_DIR / "nba_closing_lines.json"
    
    if not markets_file.exists():
        print(f"Error: Markets file not found at {markets_file}")
        return
    
    collect_closing_lines_for_all_games(
        markets_file=markets_file,
        output_file=output_file,
        delay=0.1  # 100ms delay between requests
    )


if __name__ == "__main__":
    main()

