#!/bin/bash

# Export des données en CSV pour analyse Excel/Sheets
# Usage: ./export-to-csv.sh [index_name] [nombre_de_documents] [symbole]
# Exemples:
#   ./export-to-csv.sh                           # Export 10000 docs BTCUSDT
#   ./export-to-csv.sh binance-trades-* 0 BTCUSDT # Export toutes les données BTCUSDT
#   ./export-to-csv.sh binance-trades-* 5000 ETHUSDT # Export 5000 docs ETHUSDT

ES_USER="chater" 
ES_PASSWORD="Protel2025!"
ES_HOST="localhost:9200"
INDEX=${1:-"binance-trades-*"}
LIMIT=${2:-10000}
SYMBOL=${3:-"BTCUSDT"}

# Check if we need to use kubectl port-forward
if ! curl -s "http://localhost:9200" > /dev/null 2>&1; then
    echo "⚡ Setting up connection to Kubernetes Elasticsearch..."
    kubectl port-forward -n elk-stack svc/elasticsearch 9200:9200 > /dev/null 2>&1 &
    PORT_FORWARD_PID=$!
    sleep 3
    trap "kill $PORT_FORWARD_PID 2>/dev/null" EXIT
fi

DATE=$(date +"%Y%m%d_%H%M%S")

echo "📊 Export CSV des données BTCUSDT..."
echo "📋 Indice: $INDEX"
echo "🪙 Symbole: $SYMBOL"
echo "📊 Limite: $LIMIT documents (0 = toutes les données)"

# Création du dossier exports
mkdir -p exports

# Récupération des données avec filtre sur le symbole
echo "🔄 Récupération des données pour $SYMBOL..."

# Construction de la query avec filtre sur le symbole
QUERY='{
    "query": {
        "bool": {
            "must": [
                {"term": {"symbol.keyword": "'$SYMBOL'"}}
            ]
        }
    },
    "sort": [{"timestamp": {"order": "desc"}}]
}'

# Si LIMIT est 0, on récupère toutes les données (pas de paramètre size)
if [ "$LIMIT" -eq 0 ]; then
    curl -s -u $ES_USER:$ES_PASSWORD -H "Content-Type: application/json" \
        -X POST "http://$ES_HOST/$INDEX/_search?timeout=60s&scroll=1m" \
        -d "$QUERY" > "/tmp/raw_data.json"
else
    curl -s -u $ES_USER:$ES_PASSWORD -H "Content-Type: application/json" \
        -X POST "http://$ES_HOST/$INDEX/_search?size=$LIMIT&timeout=60s" \
        -d "$QUERY" > "/tmp/raw_data.json"
fi

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
OUTPUT_FILE="exports/${SYMBOL}_${INDEX//\*/_}_${DATE}.csv"
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
