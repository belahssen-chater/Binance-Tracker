#!/bin/bash

# Export rapide des données Binance en JSON
# Usage: ./quick-export-binance.sh [nombre_de_documents]

ES_USER="chater"
ES_PASSWORD="Protel2025!"
ES_HOST="localhost:9200"
LIMIT=${1:-1000}
DATE=$(date +"%Y%m%d_%H%M%S")

echo "🚀 Export rapide des données Binance..."
echo "📊 Limite: $LIMIT documents"

# Création du dossier exports
mkdir -p exports

# Export des données Binance récentes
curl -s -u $ES_USER:$ES_PASSWORD -H "Content-Type: application/json" \
    -X POST "http://$ES_HOST/binance-trades-*/_search?size=$LIMIT" \
    -d '{
        "query": {
            "range": {
                "@timestamp": {
                    "gte": "now-24h"
                }
            }
        },
        "sort": [{"@timestamp": {"order": "desc"}}]
    }' | jq -r '.hits.hits[]._source' > "exports/binance_recent_${DATE}.json"

echo "✅ Export terminé: exports/binance_recent_${DATE}.json"
echo "📋 Nombre de lignes: $(wc -l < exports/binance_recent_${DATE}.json)"
