import requests

# Extract event ticker from market
event_ticker = "KXNFLGAME-25SEP25SEAARI"

# Get event details
url = f"https://api.elections.kalshi.com/trade-api/v2/events/{event_ticker}"
response = requests.get(url)
event = response.json()

# Event should contain the scheduled start time
print(event)