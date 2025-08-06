#!/bin/bash

# Export COMPLET des données BTCUSDT en CSV
# Ce script utilise la pagination Elasticsearch pour récupérer TOUTES les données

ES_USER="chater" 
ES_PASSWORD="Protel2025!"
ES_HOST="localhost:9200"
INDEX=${1:-"binance-trades-*"}
SYMBOL=${2:-"BTCUSDT"}

# Check if we need to use kubectl port-forward
if ! curl -s "http://localhost:9200" > /dev/null 2>&1; then
    echo "⚡ Setting up connection to Kubernetes Elasticsearch..."
    kubectl port-forward -n elk-stack svc/elasticsearch 9200:9200 > /dev/null 2>&1 &
    PORT_FORWARD_PID=$!
    sleep 3
    trap "kill $PORT_FORWARD_PID 2>/dev/null" EXIT
fi

DATE=$(date +"%Y%m%d_%H%M%S")

echo "📊 Export COMPLET des données $SYMBOL..."
echo "📋 Indice: $INDEX"
echo "🪙 Symbole: $SYMBOL"
echo "⏱️  Utilisation du scroll Elasticsearch pour récupérer toutes les données"

# Création du dossier exports
mkdir -p exports

OUTPUT_FILE="exports/${SYMBOL}_complete_${DATE}.csv"
echo "timestamp,symbol,price,quantity,trade_id,buyer_market_maker" > "$OUTPUT_FILE"

# Première requête avec scroll
echo "🔄 Initialisation du scroll..."
SCROLL_ID=$(curl -s -u $ES_USER:$ES_PASSWORD -H "Content-Type: application/json" \
    -X POST "http://$ES_HOST/$INDEX/_search?scroll=5m&size=10000" \
    -d '{
        "query": {
            "bool": {
                "must": [
                    {"term": {"symbol.keyword": "'$SYMBOL'"}}
                ]
            }
        },
        "sort": [{"timestamp": {"order": "desc"}}]
    }' | tee /tmp/scroll_response.json | jq -r '._scroll_id // empty')

if [ -z "$SCROLL_ID" ]; then
    echo "❌ Erreur lors de l'initialisation du scroll"
    cat /tmp/scroll_response.json
    exit 1
fi

# Traitement de la première page
TOTAL_DOCS=0
HITS_COUNT=$(cat /tmp/scroll_response.json | jq '.hits.hits | length')
TOTAL_AVAILABLE=$(cat /tmp/scroll_response.json | jq '.hits.total.value // 0')

echo "📦 Total de documents $SYMBOL disponibles: $TOTAL_AVAILABLE"
echo "📄 Traitement de la première page: $HITS_COUNT documents"

# Conversion de la première page
cat /tmp/scroll_response.json | jq -r '
    .hits.hits[]._source | 
    [(.timestamp // ""), (.symbol // ""), (.price // ""), (.quantity // ""), (.trade_id // ""), (.buyer_market_maker // "")] | 
    @csv
' >> "$OUTPUT_FILE"

TOTAL_DOCS=$((TOTAL_DOCS + HITS_COUNT))

# Pagination avec scroll
PAGE=2
while [ "$HITS_COUNT" -gt 0 ]; do
    echo "📄 Récupération page $PAGE..."
    
    curl -s -u $ES_USER:$ES_PASSWORD -H "Content-Type: application/json" \
        -X POST "http://$ES_HOST/_search/scroll" \
        -d '{
            "scroll": "5m",
            "scroll_id": "'$SCROLL_ID'"
        }' > /tmp/scroll_response.json
    
    # Vérification de la réponse
    if ! jq -e '.hits.hits' /tmp/scroll_response.json > /dev/null 2>&1; then
        echo "❌ Erreur dans la réponse scroll:"
        cat /tmp/scroll_response.json
        break
    fi
    
    HITS_COUNT=$(cat /tmp/scroll_response.json | jq '.hits.hits | length')
    
    if [ "$HITS_COUNT" -gt 0 ]; then
        echo "   ✅ $HITS_COUNT documents récupérés"
        
        # Conversion des données de cette page
        cat /tmp/scroll_response.json | jq -r '
            .hits.hits[]._source | 
            [(.timestamp // ""), (.symbol // ""), (.price // ""), (.quantity // ""), (.trade_id // ""), (.buyer_market_maker // "")] | 
            @csv
        ' >> "$OUTPUT_FILE"
        
        TOTAL_DOCS=$((TOTAL_DOCS + HITS_COUNT))
        echo "   📊 Total récupéré jusqu'à présent: $TOTAL_DOCS documents"
    fi
    
    PAGE=$((PAGE + 1))
done

# Nettoyage du scroll
echo "🧹 Nettoyage du scroll..."
curl -s -u $ES_USER:$ES_PASSWORD -H "Content-Type: application/json" \
    -X DELETE "http://$ES_HOST/_search/scroll" \
    -d '{"scroll_id": "'$SCROLL_ID'"}' > /dev/null

echo ""
echo "✅ Export COMPLET terminé!"
echo "📁 Fichier: $OUTPUT_FILE"
echo "📊 Total de documents $SYMBOL exportés: $TOTAL_DOCS"
echo "📋 Nombre de lignes dans le CSV: $(wc -l < "$OUTPUT_FILE")"
echo "💾 Taille du fichier: $(du -h "$OUTPUT_FILE" | cut -f1)"

# Nettoyage
rm -f /tmp/scroll_response.json
