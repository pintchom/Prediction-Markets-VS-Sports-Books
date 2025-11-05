import json
import os
from datetime import datetime, timedelta
from kalshi_python import Configuration, KalshiClient

API_KEY = os.getenv("KALSHI_API_KEY")  # Replace with your actual API key
PEM_FILE = "kalshi.pem"  # Path to your PEM file
OUTPUT_DIR = "data"  # Directory to store JSON files

os.makedirs(OUTPUT_DIR, exist_ok=True)

def authenticate_client():
    """
    Authenticate with Kalshi API using PEM file and API key
    """
    print("Authenticating with Kalshi API...")
    
    with open(PEM_FILE, 'r') as f:
        private_key = f.read()
    

    config = Configuration(
        host="https://api.elections.kalshi.com/trade-api/v2"
    )
    config.api_key_id = API_KEY
    config.private_key_pem = private_key
    
    # Initialize the client
    client = KalshiClient(config)
    
    print("Authentication successful!")
    return client


def fetch_all_series(client):
    """
    Fetch all series from Kalshi
    """
    print("\nFetching all series...")
    
    # Fetch all series (no pagination needed - returns all in one call)
    response = client.get_series()
    
    # Convert response object to dict if needed
    if hasattr(response, 'to_dict'):
        response_dict = response.to_dict()
    else:
        response_dict = response
    
    series_list = response_dict.get('series', [])
    
    print(f"  Retrieved {len(series_list)} series")
    
    # Save series to JSON
    series_file = os.path.join(OUTPUT_DIR, "all_series.json")
    with open(series_file, 'w') as f:
        json.dump({
            "fetch_date": datetime.now().isoformat(),
            "total_series": len(series_list),
            "series": series_list
        }, f, indent=2)
    
    print(f"Series data saved to {series_file}")
    return series_list


def fetch_markets_last_year(client):
    """
    Fetch all markets from the last year
    """
    print("\nFetching markets from the last year...")
    
    # Calculate timestamp for one year ago
    one_year_ago = datetime.now() - timedelta(days=365)
    min_close_ts = int(one_year_ago.timestamp())
    
    all_markets = []
    cursor = None
    page = 1
    
    # Fetch markets with different statuses
    statuses = ['open', 'closed', 'settled']
    
    for status in statuses:
        print(f"\n--- Fetching {status} markets ---")
        cursor = None
        page = 1
        
        while True:
            print(f"Fetching {status} markets page {page}...")
            
            params = {
                "limit": 200,  # Max limit per page
                "status": status,
            }
            
            # Only apply time filter for closed/settled markets
            if status in ['closed', 'settled']:
                params["min_close_ts"] = min_close_ts
            
            if cursor:
                params["cursor"] = cursor
            
            try:
                response = client.get_markets(**params)
                
                markets_list = response.get('markets', [])
                all_markets.extend(markets_list)
                
                print(f"  Retrieved {len(markets_list)} {status} markets (Total so far: {len(all_markets)})")
                
                # Check if there are more pages
                cursor = response.get('cursor')
                if not cursor:
                    break
                
                page += 1
            except Exception as e:
                print(f"  Error fetching {status} markets: {e}")
                break
    
    print(f"\nTotal markets retrieved: {len(all_markets)}")
    
    # Save markets to JSON
    markets_file = os.path.join(OUTPUT_DIR, "markets_last_year.json")
    with open(markets_file, 'w') as f:
        json.dump({
            "fetch_date": datetime.now().isoformat(),
            "time_range": {
                "start": one_year_ago.isoformat(),
                "end": datetime.now().isoformat()
            },
            "total_markets": len(all_markets),
            "markets": all_markets
        }, f, indent=2)
    
    print(f"Markets data saved to {markets_file}")
    return all_markets


def fetch_market_details(client, markets):
    """
    Fetch detailed information for each market including orderbook and trades
    """
    print("\nFetching detailed market information...")
    
    detailed_markets = []
    
    for i, market in enumerate(markets[:100], 1):  # Limit to first 100 to avoid rate limits
        ticker = market.get('ticker')
        print(f"  [{i}/{min(100, len(markets))}] Fetching details for {ticker}...")
        
        try:
            # Get market details
            market_detail = client.get_market(ticker)
            
            # Try to get orderbook (may not be available for closed markets)
            try:
                orderbook = client.get_orderbook(ticker)
                market_detail['orderbook'] = orderbook
            except:
                market_detail['orderbook'] = None
            
            detailed_markets.append(market_detail)
        except Exception as e:
            print(f"    Error fetching details for {ticker}: {e}")
            detailed_markets.append(market)
    
    # Save detailed markets to JSON
    detailed_file = os.path.join(OUTPUT_DIR, "markets_detailed.json")
    with open(detailed_file, 'w') as f:
        json.dump({
            "fetch_date": datetime.now().isoformat(),
            "total_markets": len(detailed_markets),
            "markets": detailed_markets
        }, f, indent=2)
    
    print(f"Detailed market data saved to {detailed_file}")
    return detailed_markets


def generate_summary_statistics(series, markets):
    """
    Generate summary statistics about the fetched data
    """
    print("\nGenerating summary statistics...")
    
    # Count markets by status
    status_counts = {}
    for market in markets:
        status = market.get('status', 'unknown')
        status_counts[status] = status_counts.get(status, 0) + 1
    
    # Count markets by category
    category_counts = {}
    for market in markets:
        category = market.get('category', 'unknown')
        category_counts[category] = category_counts.get(category, 0) + 1
    
    # Count series by category
    series_category_counts = {}
    for s in series:
        category = s.get('category', 'unknown')
        series_category_counts[category] = series_category_counts.get(category, 0) + 1
    
    summary = {
        "fetch_date": datetime.now().isoformat(),
        "totals": {
            "series": len(series),
            "markets": len(markets)
        },
        "markets_by_status": status_counts,
        "markets_by_category": category_counts,
        "series_by_category": series_category_counts
    }
    
    # Save summary
    summary_file = os.path.join(OUTPUT_DIR, "summary_statistics.json")
    with open(summary_file, 'w') as f:
        json.dump(summary, f, indent=2)
    
    print(f"\nSummary Statistics:")
    print(f"  Total Series: {len(series)}")
    print(f"  Total Markets: {len(markets)}")
    print(f"\n  Markets by Status:")
    for status, count in status_counts.items():
        print(f"    {status}: {count}")
    print(f"\n  Top 5 Market Categories:")
    sorted_categories = sorted(category_counts.items(), key=lambda x: x[1], reverse=True)
    for category, count in sorted_categories[:5]:
        print(f"    {category}: {count}")
    
    print(f"\nSummary saved to {summary_file}")
    return summary


def main():
    """
    Main execution function
    """
    print("=" * 60)
    print("Kalshi Data Collection Script")
    print("=" * 60)
    
    try:
        # Authenticate
        client = authenticate_client()
        
        # Fetch all series
        series = fetch_all_series(client)
        
        # Fetch markets from last year
        markets = fetch_markets_last_year(client)
        
        # Generate summary statistics
        summary = generate_summary_statistics(series, markets)
        
        print("\n" + "=" * 60)
        print("Data collection completed successfully!")
        print("=" * 60)
        print(f"\nAll data saved to '{OUTPUT_DIR}/' directory:")
        print(f"  - all_series.json: All series information")
        print(f"  - markets_last_year.json: All markets from the last year")
        print(f"  - summary_statistics.json: Summary statistics")
        
    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()


if __name__ == "__main__":
    main()

