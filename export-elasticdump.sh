#!/bin/bash

# Export professionnel avec elasticdump
# Usage: ./export-elasticdump.sh [index_name] [type]

INDEX=${1:-"binance-trades-*"}
TYPE=${2:-"data"} # data, mapping, analyzer, settings
DATE=$(date +"%Y%m%d_%H%M%S")

echo "🔧 Export avec ElasticDump..."
echo "📋 Indice: $INDEX"
echo "📝 Type: $TYPE"

# Vérification si elasticdump est installé
if ! command -v elasticdump &> /dev/null; then
    echo "📦 Installation d'ElasticDump..."
    npm install -g elasticdump
fi

# Création du dossier exports
mkdir -p exports/elasticdump

# Port-forward vers Elasticsearch
echo "🔗 Configuration du port-forward..."
kubectl port-forward -n elk-stack svc/elasticsearch 9200:9200 &
PF_PID=$!
sleep 3

ES_URL="http://chater:Protel2025!@localhost:9200"

case $TYPE in
    "data")
        echo "📊 Export des données..."
        elasticdump \
            --input="$ES_URL/$INDEX" \
            --output="exports/elasticdump/${INDEX//\*/_}_${DATE}_data.json" \
            --type=data \
            --limit=1000
        ;;
        
    "mapping")
        echo "🗺️ Export du mapping..."
        elasticdump \
            --input="$ES_URL/$INDEX" \
            --output="exports/elasticdump/${INDEX//\*/_}_${DATE}_mapping.json" \
            --type=mapping
        ;;
        
    "settings")
        echo "⚙️ Export des paramètres..."
        elasticdump \
            --input="$ES_URL/$INDEX" \
            --output="exports/elasticdump/${INDEX//\*/_}_${DATE}_settings.json" \
            --type=settings
        ;;
        
    "all")
        echo "🎯 Export complet (mapping + settings + data)..."
        
        # Mapping
        elasticdump \
            --input="$ES_URL/$INDEX" \
            --output="exports/elasticdump/${INDEX//\*/_}_${DATE}_mapping.json" \
            --type=mapping
            
        # Settings
        elasticdump \
            --input="$ES_URL/$INDEX" \
            --output="exports/elasticdump/${INDEX//\*/_}_${DATE}_settings.json" \
            --type=settings
            
        # Data
        elasticdump \
            --input="$ES_URL/$INDEX" \
            --output="exports/elasticdump/${INDEX//\*/_}_${DATE}_data.json" \
            --type=data \
            --limit=1000
        ;;
        
    *)
        echo "❌ Type non reconnu. Utilisez: data, mapping, settings, ou all"
        kill $PF_PID 2>/dev/null
        exit 1
        ;;
esac

# Statistiques
echo "📊 Statistiques d'export:"
for file in exports/elasticdump/${INDEX//\*/_}_${DATE}_*.json; do
    if [ -f "$file" ]; then
        echo "   📄 $(basename "$file"): $(du -h "$file" | cut -f1)"
    fi
done

# Arrêt du port-forward
kill $PF_PID 2>/dev/null

echo "🎉 Export ElasticDump terminé!"
echo "📁 Fichiers dans: exports/elasticdump/"
