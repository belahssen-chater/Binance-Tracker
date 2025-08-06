#!/bin/bash

# Export de TOUTES les données sans limite avec l'API Scroll
# Usage: ./export-all-data.sh [index_name] [format]

ES_USER="chater" 
ES_PASSWORD="Protel2025!"
ES_HOST="localhost:9200"
INDEX=${1:-"binance-trades-*"}
FORMAT=${2:-"pretty"}
DATE=$(date +"%Y%m%d_%H%M%S")
SCROLL_SIZE=1000
SCROLL_TIME="5m"

echo "📊 Export COMPLET des données (sans limite)..."
echo "📋 Indice: $INDEX"
echo "📝 Format: $FORMAT"
echo "⚙️  Taille par scroll: $SCROLL_SIZE"

# Création du dossier exports
mkdir -p exports

# Port-forward vers Elasticsearch si nécessaire
echo "🔗 Configuration du port-forward..."
kubectl port-forward -n elk-stack svc/elasticsearch 9200:9200 &
PF_PID=$!
sleep 3

OUTPUT_FILE="exports/${INDEX//\*/_}_${DATE}_complete_${FORMAT}.json"

echo "🔄 Initialisation du scroll..."

# Première requête pour initialiser le scroll
SCROLL_RESPONSE=$(curl -s -u $ES_USER:$ES_PASSWORD -H "Content-Type: application/json" \
    -X POST "http://$ES_HOST/$INDEX/_search?scroll=${SCROLL_TIME}&size=${SCROLL_SIZE}" \
    -d '{
        "query": {"match_all": {}},
        "sort": [{"@timestamp": {"order": "desc"}}]
    }')

# Extraction du scroll_id
SCROLL_ID=$(echo "$SCROLL_RESPONSE" | jq -r '._scroll_id')
TOTAL_HITS=$(echo "$SCROLL_RESPONSE" | jq -r '.hits.total.value // .hits.total')

echo "📊 Total de documents trouvés: $TOTAL_HITS"

# Initialisation du fichier de sortie selon le format
case $FORMAT in
    "pretty")
        echo "$SCROLL_RESPONSE" | jq '.' > "$OUTPUT_FILE"
        ;;
    "compact")
        echo "$SCROLL_RESPONSE" > "$OUTPUT_FILE"
        ;;
    "ndjson")
        echo "$SCROLL_RESPONSE" | jq -c '.hits.hits[]._source' > "$OUTPUT_FILE"
        ;;
    "data-only")
        echo "$SCROLL_RESPONSE" | jq '.hits.hits[]._source' > "$OUTPUT_FILE"
        ;;
esac

DOCUMENT_COUNT=$(echo "$SCROLL_RESPONSE" | jq '.hits.hits | length')
TOTAL_EXPORTED=$DOCUMENT_COUNT

echo "🔄 Export en cours... ($TOTAL_EXPORTED/$TOTAL_HITS documents)"

# Continuer à récupérer les données tant qu'il y en a
while [ "$DOCUMENT_COUNT" -gt 0 ]; do
    SCROLL_RESPONSE=$(curl -s -u $ES_USER:$ES_PASSWORD -H "Content-Type: application/json" \
        -X POST "http://$ES_HOST/_search/scroll" \
        -d "{
            \"scroll\": \"$SCROLL_TIME\",
            \"scroll_id\": \"$SCROLL_ID\"
        }")
    
    DOCUMENT_COUNT=$(echo "$SCROLL_RESPONSE" | jq '.hits.hits | length')
    
    if [ "$DOCUMENT_COUNT" -gt 0 ]; then
        case $FORMAT in
            "ndjson")
                echo "$SCROLL_RESPONSE" | jq -c '.hits.hits[]._source' >> "$OUTPUT_FILE"
                ;;
            "data-only")
                echo "$SCROLL_RESPONSE" | jq '.hits.hits[]._source' >> "$OUTPUT_FILE"
                ;;
            *)
                # Pour pretty et compact, on ajoute les nouveaux hits
                echo "$SCROLL_RESPONSE" | jq '.hits.hits[]' >> "${OUTPUT_FILE}.tmp"
                ;;
        esac
        
        TOTAL_EXPORTED=$((TOTAL_EXPORTED + DOCUMENT_COUNT))
        echo "🔄 Export en cours... ($TOTAL_EXPORTED/$TOTAL_HITS documents)"
    fi
    
    # Mise à jour du scroll_id
    SCROLL_ID=$(echo "$SCROLL_RESPONSE" | jq -r '._scroll_id')
done

# Nettoyage du scroll
curl -s -u $ES_USER:$ES_PASSWORD -X DELETE "http://$ES_HOST/_search/scroll" \
    -H "Content-Type: application/json" \
    -d "{\"scroll_id\": [\"$SCROLL_ID\"]}" > /dev/null

echo "📋 Taille du fichier: $(du -h "$OUTPUT_FILE" | cut -f1)"
echo "📊 Nombre de lignes: $(wc -l < "$OUTPUT_FILE")"
echo "📈 Total de documents exportés: $TOTAL_EXPORTED"

# Arrêt du port-forward
kill $PF_PID 2>/dev/null

echo "🎉 Export complet terminé avec succès!"
echo "📁 Fichier: $OUTPUT_FILE"
