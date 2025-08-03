#!/bin/bash

# Génération de statistiques détaillées des trades Binance
# Usage: ./export-statistics.sh

ES_USER="chater"
ES_PASSWORD="Protel2025!"
ES_HOST="localhost:9200"
DATE=$(date +"%Y%m%d_%H%M%S")

echo "📊 Génération des statistiques de trading..."

# Création du dossier exports
mkdir -p exports

# Statistiques globales
echo "📈 Statistiques globales..."
curl -s -u $ES_USER:$ES_PASSWORD -H "Content-Type: application/json" \
    -X POST "http://$ES_HOST/binance-trades-*/_search?size=0" \
    -d '{
        "aggs": {
            "total_trades": {"value_count": {"field": "trade_id"}},
            "unique_symbols": {"cardinality": {"field": "symbol.keyword"}},
            "price_stats": {"stats": {"field": "price"}},
            "volume_stats": {"stats": {"field": "volume"}},
            "top_symbols": {
                "terms": {"field": "symbol.keyword", "size": 20},
                "aggs": {
                    "avg_price": {"avg": {"field": "price"}},
                    "total_volume": {"sum": {"field": "volume"}}
                }
            },
            "trades_by_hour": {
                "date_histogram": {
                    "field": "@timestamp",
                    "calendar_interval": "hour"
                }
            }
        }
    }' > "exports/statistics_global_${DATE}.json"

# Statistiques par jour
echo "📅 Statistiques quotidiennes..."
curl -s -u $ES_USER:$ES_PASSWORD -H "Content-Type: application/json" \
    -X POST "http://$ES_HOST/binance-trades-*/_search?size=0" \
    -d '{
        "aggs": {
            "daily_stats": {
                "date_histogram": {
                    "field": "@timestamp",
                    "calendar_interval": "day"
                },
                "aggs": {
                    "trade_count": {"value_count": {"field": "trade_id"}},
                    "volume_sum": {"sum": {"field": "volume"}},
                    "avg_price": {"avg": {"field": "price"}},
                    "top_symbols": {
                        "terms": {"field": "symbol.keyword", "size": 10}
                    }
                }
            }
        }
    }' > "exports/statistics_daily_${DATE}.json"

# Création d'un résumé lisible
echo "📋 Création du résumé..."
echo "=== RÉSUMÉ STATISTIQUES BINANCE ===" > "exports/resume_${DATE}.txt"
echo "Date de génération: $(date)" >> "exports/resume_${DATE}.txt"
echo "" >> "exports/resume_${DATE}.txt"

# Extraction des métriques principales
TOTAL_TRADES=$(cat "exports/statistics_global_${DATE}.json" | jq -r '.aggregations.total_trades.value')
UNIQUE_SYMBOLS=$(cat "exports/statistics_global_${DATE}.json" | jq -r '.aggregations.unique_symbols.value')
AVG_PRICE=$(cat "exports/statistics_global_${DATE}.json" | jq -r '.aggregations.price_stats.avg')
TOTAL_VOLUME=$(cat "exports/statistics_global_${DATE}.json" | jq -r '.aggregations.volume_stats.sum')

echo "📊 MÉTRIQUES GLOBALES:" >> "exports/resume_${DATE}.txt"
echo "- Total des trades: $TOTAL_TRADES" >> "exports/resume_${DATE}.txt"
echo "- Symboles uniques: $UNIQUE_SYMBOLS" >> "exports/resume_${DATE}.txt"
echo "- Prix moyen: $AVG_PRICE" >> "exports/resume_${DATE}.txt"
echo "- Volume total: $TOTAL_VOLUME" >> "exports/resume_${DATE}.txt"
echo "" >> "exports/resume_${DATE}.txt"

echo "🏆 TOP 10 SYMBOLES:" >> "exports/resume_${DATE}.txt"
cat "exports/statistics_global_${DATE}.json" | jq -r '
    .aggregations.top_symbols.buckets[] | 
    "- \(.key): \(.doc_count) trades, Volume: \(.total_volume.value), Prix moyen: \(.avg_price.value)"
' | head -10 >> "exports/resume_${DATE}.txt"

echo "✅ Statistiques générées:"
echo "   📊 exports/statistics_global_${DATE}.json"
echo "   📅 exports/statistics_daily_${DATE}.json"
echo "   📋 exports/resume_${DATE}.txt"

echo ""
echo "📋 APERÇU DU RÉSUMÉ:"
cat "exports/resume_${DATE}.txt"
