#!/bin/bash

# Export des données en CSV pour analyse Excel/Sheets
# Usage: ./export-to-csv.sh [index_name] [nombre_de_documents]

ES_USER="chater" 
ES_PASSWORD="Protel2025!"
ES_HOST="localhost:9200"
INDEX=${1:-"binance-trades-*"}
LIMIT=${2:-5000}
DATE=$(date +"%Y%m%d_%H%M%S")

echo "📊 Export CSV des données..."
echo "📋 Indice: $INDEX"
echo "📊 Limite: $LIMIT documents"

# Création du dossier exports
mkdir -p exports

# Récupération des données
echo "🔄 Récupération des données..."
curl -s -u $ES_USER:$ES_PASSWORD -H "Content-Type: application/json" \
    -X POST "http://$ES_HOST/$INDEX/_search?size=$LIMIT" \
    -d '{
        "query": {"match_all": {}},
        "sort": [{"@timestamp": {"order": "desc"}}]
    }' > "/tmp/raw_data.json"

# Conversion en CSV
echo "📝 Conversion en CSV..."
echo "timestamp,symbol,price,volume,trade_id,is_buyer_maker" > "exports/${INDEX//\*/_}_${DATE}.csv"

cat /tmp/raw_data.json | jq -r '
    .hits.hits[]._source | 
    [.timestamp, .symbol, .price, .volume, .trade_id, .is_buyer_maker] | 
    @csv
' >> "exports/${INDEX//\*/_}_${DATE}.csv"

echo "✅ Export CSV terminé: exports/${INDEX//\*/_}_${DATE}.csv"
echo "📋 Nombre de lignes: $(wc -l < exports/${INDEX//\*/_}_${DATE}.csv)"

# Nettoyage
rm -f /tmp/raw_data.json
