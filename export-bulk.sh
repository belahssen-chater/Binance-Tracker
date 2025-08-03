#!/bin/bash

# Export en lot (bulk) pour de gros volumes de données
# Usage: ./export-bulk.sh [index_name] [batch_size] [max_batches]

ES_USER="chater" 
ES_PASSWORD="Protel2025!"
ES_HOST="localhost:9200"
INDEX=${1:-"binance-trades-*"}
BATCH_SIZE=${2:-1000}
MAX_BATCHES=${3:-10}
DATE=$(date +"%Y%m%d_%H%M%S")

echo "📦 Export en lot des données..."
echo "📋 Indice: $INDEX"
echo "📊 Taille du lot: $BATCH_SIZE documents"
echo "🔢 Nombre max de lots: $MAX_BATCHES"

# Création du dossier exports
mkdir -p exports/bulk_$DATE

# Port-forward vers Elasticsearch
echo "🔗 Configuration du port-forward..."
kubectl port-forward -n elk-stack svc/elasticsearch 9200:9200 &
PF_PID=$!
sleep 3

# Fonction pour exporter un lot
export_batch() {
    local from=$1
    local batch_num=$2
    local filename="exports/bulk_$DATE/batch_${batch_num}_${from}.json"
    
    echo "📥 Export lot $batch_num (documents $from à $((from + BATCH_SIZE - 1)))..."
    
    curl -s -u $ES_USER:$ES_PASSWORD -H "Content-Type: application/json" \
        -X POST "http://$ES_HOST/$INDEX/_search" \
        -d "{
            \"from\": $from,
            \"size\": $BATCH_SIZE,
            \"query\": {\"match_all\": {}},
            \"sort\": [{\"@timestamp\": {\"order\": \"desc\"}}]
        }" | jq '.hits.hits[]._source' > "$filename"
    
    local doc_count=$(jq length "$filename" 2>/dev/null || echo "0")
    echo "   ✅ Lot $batch_num: $doc_count documents exportés"
    
    return $doc_count
}

# Export par lots
total_exported=0
for ((i=0; i<MAX_BATCHES; i++)); do
    from=$((i * BATCH_SIZE))
    export_batch $from $((i+1))
    batch_count=$?
    
    total_exported=$((total_exported + batch_count))
    
    # Arrêt si moins de documents que la taille du lot (fin des données)
    if [ $batch_count -lt $BATCH_SIZE ]; then
        echo "📋 Fin des données détectée au lot $((i+1))"
        break
    fi
done

# Création d'un fichier consolidé
echo "🔄 Consolidation des lots..."
echo "[" > "exports/bulk_${DATE}_consolidated.json"

first_file=true
for file in exports/bulk_$DATE/batch_*.json; do
    if [ -f "$file" ]; then
        if [ "$first_file" = false ]; then
            echo "," >> "exports/bulk_${DATE}_consolidated.json"
        fi
        cat "$file" | jq -c '.[]' | sed 's/$/,/' | sed '$s/,$//' >> "exports/bulk_${DATE}_consolidated.json"
        first_file=false
    fi
done

echo "]" >> "exports/bulk_${DATE}_consolidated.json"

# Nettoyage et statistiques
echo "📊 Statistiques d'export:"
echo "   📦 Total de documents exportés: $total_exported"
echo "   📁 Fichiers de lot: $(ls exports/bulk_$DATE/batch_*.json 2>/dev/null | wc -l)"
echo "   📋 Fichier consolidé: exports/bulk_${DATE}_consolidated.json"
echo "   💾 Taille totale: $(du -sh exports/bulk_$DATE/ | cut -f1)"

# Arrêt du port-forward
kill $PF_PID 2>/dev/null

echo "🎉 Export en lot terminé!"
echo "💡 Pour supprimer les fichiers temporaires: rm -rf exports/bulk_$DATE/"
