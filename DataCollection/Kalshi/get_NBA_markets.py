import json
import os
from datetime import datetime
import requests

# Configuration
OUTPUT_DIR = "data"
GAME_SERIES_FILE = "data/game_series.json"
KALSHI_API_BASE = "https://api.elections.kalshi.com/trade-api/v2"

# Ensure output directory exists
os.makedirs(OUTPUT_DIR, exist_ok=True)


def get_all_markets_for_series(series_ticker):
    """
    Get all markets for a specific series, handling pagination
    Uses direct API calls to avoid SDK validation issues
    """
    all_markets = []
    cursor = None
    page = 1
    
    while True:
        print(f"  Fetching page {page}...")
        
        params = {
            "series_ticker": series_ticker,
            "limit": 200  # Max 200 per page
        }
        
        if cursor:
            params["cursor"] = cursor
        
        try:
            response = requests.get(
                f"{KALSHI_API_BASE}/markets",
                params=params
            )
            response.raise_for_status()
            
            data = response.json()
            markets_list = data.get('markets', [])
            all_markets.extend(markets_list)
            
            print(f"    Retrieved {len(markets_list)} markets (Total: {len(all_markets)})")
            
            # Check if there are more pages
            cursor = data.get('cursor')
            if not cursor:
                break
            
            page += 1
            
        except Exception as e:
            print(f"    Error fetching markets: {e}")
            break
    
    return all_markets


def fetch_nba_series_markets():
    """
    Fetch all markets for each NBA series from game_series.json
    """
    print("\nLoading NBA series from game_series.json...")
    
    # Read the sports series file
    with open(GAME_SERIES_FILE, 'r') as f:
        sports_data = json.load(f)
    
    nba_series = sports_data.get('nba_series', [])
    print(f"Found {len(nba_series)} NBA series to process")
    
    # Dictionary to store all markets by series
    all_series_markets = {}
    total_markets = 0
    
    # Process each series
    for i, series in enumerate(nba_series, 1):
        ticker = series['ticker']
        title = series['title']
        
        print(f"\n[{i}/{len(nba_series)}] Processing {title} ({ticker})...")
        
        # Get all markets for this series
        markets = get_all_markets_for_series(ticker)
        
        # Store markets by series
        all_series_markets[ticker] = {
            'series_info': series,
            'total_markets': len(markets),
            'markets': markets
        }
        
        total_markets += len(markets)
        print(f"  ✓ Completed: {len(markets)} markets found")
    
    return all_series_markets, total_markets


def categorize_markets_by_status(all_series_markets):
    """
    Create statistics about market statuses across all series
    """
    stats = {
        'by_series': {},
        'overall': {}
    }
    
    for series_ticker, series_data in all_series_markets.items():
        series_stats = {}
        
        for market in series_data['markets']:
            status = market.get('status', 'unknown')
            
            # Track in series stats
            if status not in series_stats:
                series_stats[status] = 0
            series_stats[status] += 1
            
            # Track in overall stats
            if status not in stats['overall']:
                stats['overall'][status] = 0
            stats['overall'][status] += 1
        
        stats['by_series'][series_ticker] = series_stats
    
    return stats


def main():
    """
    Main execution function
    """
    print("=" * 60)
    print("NBA Series Markets Collection Script")
    print("=" * 60)
    
    try:
        # Fetch all markets for NBA series (no authentication needed for public endpoints)
        all_series_markets, total_markets = fetch_nba_series_markets()
        
        # Generate statistics
        print("\n" + "=" * 60)
        print("Generating statistics...")
        stats = categorize_markets_by_status(all_series_markets)
        
        # Prepare output data
        output_data = {
            "fetch_date": datetime.now().isoformat(),
            "total_series": len(all_series_markets),
            "total_markets": total_markets,
            "statistics": stats,
            "series_markets": all_series_markets
        }
        
        # Save to JSON file
        output_file = os.path.join(OUTPUT_DIR, "nba_series_markets.json")
        with open(output_file, 'w') as f:
            json.dump(output_data, f, indent=2)
        
        print("\n" + "=" * 60)
        print("Data collection completed successfully!")
        print("=" * 60)
        print(f"\nTotal NBA Series: {len(all_series_markets)}")
        print(f"Total Markets Collected: {total_markets}")
        print(f"\nMarkets by Status (Overall):")
        for status, count in sorted(stats['overall'].items()):
            print(f"  {status}: {count}")
        print(f"\nData saved to: {output_file}")
        
    except FileNotFoundError as e:
        print(f"\n❌ Error: Could not find {GAME_SERIES_FILE}")
        print("Please ensure the game_series.json file exists in the data directory.")
    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()


if __name__ == "__main__":
    main()

