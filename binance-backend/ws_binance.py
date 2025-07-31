import json
import websocket
import threading
import time
from datetime import datetime
import os
import pytz
import requests

# Dictionnaire des symboles Binance → fichiers de sortie
SYMBOLS = {
    "btcusdt": "btc_usdt.ndjson",
    "ethusdt": "eth_usdt.ndjson",
    "solusdt": "sol_usdt.ndjson",
    "bnbusdt": "bnb_usdt.ndjson"
}

NDJSON_DIR = "/shared/data"
LOGS_DIR = "/shared/logs"

# Configuration Logstash (optionnel - pour envoyer directement à Logstash)
LOGSTASH_URL = os.getenv('LOGSTASH_URL', 'http://logstash:8080')

# Crée les dossiers si non existants
os.makedirs(NDJSON_DIR, exist_ok=True)
os.makedirs(LOGS_DIR, exist_ok=True)

def get_order_book(symbol):
    try:
        response = requests.get(
            f"https://api.binance.com/api/v3/depth?symbol={symbol.upper()}&limit=5",
            timeout=2
        )
        data = response.json()
        bids = [[float(price), float(qty)] for price, qty in data['bids']]
        asks = [[float(price), float(qty)] for price, qty in data['asks']]

        spread = round(asks[0][0] - bids[0][0], 8) if bids and asks else None
        spread_pct = round((spread / bids[0][0]) * 100, 6) if spread and bids[0][0] else None

        return bids, asks, spread, spread_pct
    except Exception as e:
        print(f"[ORDER BOOK ERROR] {symbol.upper()} - {e}")
        return [], [], None, None

def send_to_logstash(trade_data):
    """Envoie les données de trade directement à Logstash via HTTP"""
    try:
        response = requests.post(
            LOGSTASH_URL,
            json=trade_data,
            headers={'Content-Type': 'application/json'},
            timeout=5
        )
        if response.status_code != 200:
            print(f"[LOGSTASH ERROR] Status: {response.status_code}")
    except Exception as e:
        print(f"[LOGSTASH ERROR] {e}")

def on_message(symbol):
    def handler(ws, message):
        data = json.loads(message)
        timestamp_utc = datetime.utcfromtimestamp(data['T'] / 1000)
        timestamp_local = timestamp_utc.replace(tzinfo=pytz.utc).astimezone(pytz.timezone("Africa/Tunis"))

        bids, asks, spread, spread_pct = get_order_book(symbol)

        trade = {
            "symbol": symbol.upper(),
            "timestamp": timestamp_utc.isoformat(),
            "timestamp_local": timestamp_local.isoformat(),
            "price": float(data['p']),
            "quantity": float(data['q']),
            "trade_id": data['t'],
            "buyer_market_maker": data['m'],
            "side": "sell" if data['m'] else "buy",
            "service": "binance-websocket",
            "level": "info",
            "message": f"Trade {symbol.upper()}: {data['p']} @ {data['q']}",
            "event_time": data['E'],
            "trade_time": data['T'],
            "type": "binance-trade",
            "bids": bids,
            "asks": asks,
            "spread": spread,
            "spread_percentage": spread_pct
        }

        # Sauvegarde dans le fichier NDJSON
        file_path = os.path.join(NDJSON_DIR, SYMBOLS[symbol])
        with open(file_path, "a") as f:
            f.write(json.dumps(trade) + "\n")

        # Envoie à Logstash
        send_to_logstash(trade)

        print(f"[{symbol.upper()}] {timestamp_local.strftime('%H:%M:%S')} - {trade['side'].upper()} - Prix: {trade['price']} - Spread: {spread}")
    return handler

def on_error(ws, error):
    print("[WS ERROR]", error)
    with open(os.path.join(LOGS_DIR, "ws_errors.log"), "a") as log:
        log.write(f"{datetime.now().isoformat()}: {str(error)}\n")

def start_stream(symbol):
    url = f"wss://stream.binance.com:9443/ws/{symbol}@trade"

    def connect():
        while True:
            print(f"[CONNECT] {symbol.upper()} → {url}")
            ws = websocket.WebSocketApp(
                url,
                on_message=on_message(symbol),
                on_error=on_error,
                on_close=lambda ws, *args: print(f"[CLOSED] {symbol.upper()}")
            )
            try:
                ws.run_forever()
            except Exception as e:
                print(f"[EXCEPTION] {symbol.upper()} - {e}")
            print(f"[RETRY] {symbol.upper()} → reconnexion dans 5 secondes...")
            time.sleep(5)

    connect()

if __name__ == "__main__":
    print("[START] Binance WebSocket to ELK Stack")
    print(f"[CONFIG] Logstash URL: {LOGSTASH_URL}")
    print(f"[CONFIG] Data directory: {NDJSON_DIR}")

    threads = []
    for symbol in SYMBOLS:
        t = threading.Thread(target=start_stream, args=(symbol,))
        t.daemon = True
        t.start()
        threads.append(t)

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\n[EXIT] Arrêt du script.")
