#!/bin/bash

# Export des données en CSV pour analyse Excel/Sheets
# Usage: ./export-to-csv.sh [index_name] [nombre_de_documents]

ES_USER="chater" 
ES_PASSWORD="Protel2025!"
ES_HOST="localhost:9200"
INDEX=${1:-"binance-trades-*"}
LIMIT=${2:-10000}

# Check if we need to use kubectl port-forward
if ! curl -s "http://localhost:9200" > /dev/null 2>&1; then
    echo "⚡ Setting up connection to Kubernetes Elasticsearch..."
    kubectl port-forward -n elk-stack svc/elasticsearch 9200:9200 > /dev/null 2>&1 &
    PORT_FORWARD_PID=$!
    sleep 3
    trap "kill $PORT_FORWARD_PID 2>/dev/null" EXIT
fi

DATE=$(date +"%Y%m%d_%H%M%S")

echo "📊 Export CSV des données..."
echo "📋 Indice: $INDEX"
echo "📊 Limite: $LIMIT documents"

# Création du dossier exports
mkdir -p exports

# Récupération des données
echo "🔄 Récupération des données..."
curl -s -u $ES_USER:$ES_PASSWORD -H "Content-Type: application/json" \
    -X POST "http://$ES_HOST/$INDEX/_search?size=$LIMIT&timeout=60s" \
    -d '{
        "query": {"match_all": {}},
        "sort": [{"timestamp": {"order": "desc"}}]
    }' > "/tmp/raw_data.json"

# Vérification si des données ont été récupérées
if [ ! -s "/tmp/raw_data.json" ]; then
    echo "❌ Aucune donnée récupérée. Vérifiez la connexion à Elasticsearch."
    echo "Debug: Contenu du fichier raw_data.json:"
    cat /tmp/raw_data.json
    exit 1
fi

# Vérification de la structure JSON et des erreurs Elasticsearch
if ! jq -e '.hits' /tmp/raw_data.json > /dev/null 2>&1; then
    echo "❌ Erreur dans la réponse Elasticsearch:"
    cat /tmp/raw_data.json
    exit 1
fi

HITS_COUNT=$(cat /tmp/raw_data.json | jq '.hits.hits | length // 0')
TOTAL_HITS=$(cat /tmp/raw_data.json | jq '.hits.total.value // 0')
echo "📦 $HITS_COUNT documents récupérés sur $TOTAL_HITS total"

# Vérification qu'on a au moins un document
if [ "$HITS_COUNT" -eq 0 ]; then
    echo "❌ Aucun document trouvé dans l'indice $INDEX"
    echo "Debug: Structure de la réponse:"
    jq '.' /tmp/raw_data.json
    exit 1
fi

# Conversion en CSV
echo "📝 Conversion en CSV..."
OUTPUT_FILE="exports/${INDEX//\*/_}_${DATE}.csv"
echo "timestamp,symbol,price,quantity,trade_id,buyer_market_maker" > "$OUTPUT_FILE"

# Conversion avec gestion d'erreurs améliorée
if ! cat /tmp/raw_data.json | jq -r '
    .hits.hits[]._source | 
    [(.timestamp // ""), (.symbol // ""), (.price // ""), (.quantity // ""), (.trade_id // ""), (.buyer_market_maker // "")] | 
    @csv
' >> "$OUTPUT_FILE"; then
    echo "❌ Erreur lors de la conversion en CSV"
    exit 1
fi

echo "✅ Export CSV terminé: $OUTPUT_FILE"
echo "📋 Nombre de lignes: $(wc -l < "$OUTPUT_FILE")"

# Nettoyage
rm -f /tmp/raw_data.json
