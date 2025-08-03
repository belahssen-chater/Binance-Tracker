#!/bin/bash

# Export des données en JSON pour analyse ou backup
# Usage: ./export-to-json.sh [index_name] [nombre_de_documents] [format]

ES_USER="chater" 
ES_PASSWORD="Protel2025!"
ES_HOST="localhost:9200"
INDEX=${1:-"binance-trades-*"}
LIMIT=${2:-5000}
FORMAT=${3:-"pretty"} # pretty, compact, ndjson
DATE=$(date +"%Y%m%d_%H%M%S")

echo "📊 Export JSON des données..."
echo "📋 Indice: $INDEX"
echo "📊 Limite: $LIMIT documents"
echo "📝 Format: $FORMAT"

# Création du dossier exports
mkdir -p exports

# Port-forward vers Elasticsearch si nécessaire
echo "🔗 Configuration du port-forward..."
kubectl port-forward -n elk-stack svc/elasticsearch 9200:9200 &
PF_PID=$!
sleep 3

case $FORMAT in
    "pretty")
        echo "🔄 Export JSON formaté (lisible)..."
        curl -s -u $ES_USER:$ES_PASSWORD -H "Content-Type: application/json" \
            -X POST "http://$ES_HOST/$INDEX/_search?size=$LIMIT&pretty" \
            -d '{
                "query": {"match_all": {}},
                "sort": [{"@timestamp": {"order": "desc"}}]
            }' > "exports/${INDEX//\*/_}_${DATE}_pretty.json"
        
        echo "✅ Export JSON formaté terminé: exports/${INDEX//\*/_}_${DATE}_pretty.json"
        ;;
        
    "compact")
        echo "🔄 Export JSON compact..."
        curl -s -u $ES_USER:$ES_PASSWORD -H "Content-Type: application/json" \
            -X POST "http://$ES_HOST/$INDEX/_search?size=$LIMIT" \
            -d '{
                "query": {"match_all": {}},
                "sort": [{"@timestamp": {"order": "desc"}}]
            }' > "exports/${INDEX//\*/_}_${DATE}_compact.json"
        
        echo "✅ Export JSON compact terminé: exports/${INDEX//\*/_}_${DATE}_compact.json"
        ;;
        
    "ndjson")
        echo "🔄 Export NDJSON (un document par ligne)..."
        curl -s -u $ES_USER:$ES_PASSWORD -H "Content-Type: application/json" \
            -X POST "http://$ES_HOST/$INDEX/_search?size=$LIMIT" \
            -d '{
                "query": {"match_all": {}},
                "sort": [{"@timestamp": {"order": "desc"}}]
            }' | jq -c '.hits.hits[]._source' > "exports/${INDEX//\*/_}_${DATE}.ndjson"
        
        echo "✅ Export NDJSON terminé: exports/${INDEX//\*/_}_${DATE}.ndjson"
        ;;
        
    "data-only")
        echo "🔄 Export JSON (données seulement)..."
        curl -s -u $ES_USER:$ES_PASSWORD -H "Content-Type: application/json" \
            -X POST "http://$ES_HOST/$INDEX/_search?size=$LIMIT" \
            -d '{
                "query": {"match_all": {}},
                "sort": [{"@timestamp": {"order": "desc"}}]
            }' | jq '.hits.hits[]._source' > "exports/${INDEX//\*/_}_${DATE}_data.json"
        
        echo "✅ Export JSON (données) terminé: exports/${INDEX//\*/_}_${DATE}_data.json"
        ;;
        
    *)
        echo "❌ Format non reconnu. Utilisez: pretty, compact, ndjson, ou data-only"
        kill $PF_PID 2>/dev/null
        exit 1
        ;;
esac

# Informations sur le fichier créé
if [ -f "exports/${INDEX//\*/_}_${DATE}_$FORMAT.json" ]; then
    FILE_PATH="exports/${INDEX//\*/_}_${DATE}_$FORMAT.json"
elif [ -f "exports/${INDEX//\*/_}_${DATE}.ndjson" ]; then
    FILE_PATH="exports/${INDEX//\*/_}_${DATE}.ndjson"
elif [ -f "exports/${INDEX//\*/_}_${DATE}_data.json" ]; then
    FILE_PATH="exports/${INDEX//\*/_}_${DATE}_data.json"
else
    echo "❌ Erreur: fichier d'export non trouvé"
    kill $PF_PID 2>/dev/null
    exit 1
fi

echo "📋 Taille du fichier: $(du -h "$FILE_PATH" | cut -f1)"
echo "📊 Nombre de lignes: $(wc -l < "$FILE_PATH")"

# Arrêt du port-forward
kill $PF_PID 2>/dev/null

echo "🎉 Export terminé avec succès!"
