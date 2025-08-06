#!/bin/bash

# Script d'export des données Bitcoin par heure
# Exporte les données BTCUSDT agrégées par heure avec statistiques complètes

set -e

# Configuration
ES_USER="chater" 
ES_PASSWORD="Protel2025!"
ES_HOST="localhost:9200"
INDEX="binance-trades-*"
SYMBOL="BTCUSDT"
EXPORT_DIR="./exports"
DATE=$(date +"%Y%m%d_%H%M%S")

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}    📊 EXPORT BITCOIN DONNÉES HORAIRES    ${NC}"
echo -e "${BLUE}========================================${NC}"

# Création du dossier d'export
mkdir -p $EXPORT_DIR

# Vérification de la connexion Elasticsearch
check_elasticsearch() {
    echo -e "${YELLOW}🔍 Vérification de la connexion Elasticsearch...${NC}"
    
    # Check if we need to use kubectl port-forward
    if ! curl -s "http://localhost:9200" > /dev/null 2>&1; then
        echo -e "${YELLOW}⚡ Configuration de la connexion vers Kubernetes Elasticsearch...${NC}"
        kubectl port-forward -n elk-stack svc/elasticsearch 9200:9200 > /dev/null 2>&1 &
        PORT_FORWARD_PID=$!
        sleep 3
        trap "kill $PORT_FORWARD_PID 2>/dev/null" EXIT
    fi
    
    if curl -s -u $ES_USER:$ES_PASSWORD http://$ES_HOST/_cluster/health > /dev/null; then
        echo -e "${GREEN}✅ Connexion Elasticsearch OK${NC}"
    else
        echo -e "${RED}❌ Erreur de connexion Elasticsearch${NC}"
        exit 1
    fi
}

# Fonction pour obtenir les données agrégées par heure
export_hourly_data() {
    local period_days=${1:-7}  # Par défaut: 7 jours
    local output_file="$EXPORT_DIR/BTCUSDT_hourly_data_${period_days}days_${DATE}.json"
    local csv_file="$EXPORT_DIR/BTCUSDT_hourly_data_${period_days}days_${DATE}.csv"
    
    echo -e "${YELLOW}📊 Export des données Bitcoin par heure (derniers $period_days jours)...${NC}"
    echo -e "${YELLOW}📋 Indice: $INDEX${NC}"
    echo -e "${YELLOW}🪙 Symbole: $SYMBOL${NC}"
    
    # Requête Elasticsearch pour agrégation par heure
    local query='{
        "size": 0,
        "query": {
            "bool": {
                "must": [
                    {"term": {"symbol.keyword": "'$SYMBOL'"}},
                    {"range": {"timestamp": {"gte": "now-'$period_days'd"}}}
                ]
            }
        },
        "aggs": {
            "hourly_data": {
                "date_histogram": {
                    "field": "timestamp",
                    "calendar_interval": "hour",
                    "min_doc_count": 1
                },
                "aggs": {
                    "price_stats": {
                        "stats": {"field": "price"}
                    },
                    "volume_total": {
                        "sum": {"field": "quantity"}
                    },
                    "trade_count": {
                        "value_count": {"field": "trade_id"}
                    },
                    "buy_volume": {
                        "filter": {"term": {"side.keyword": "buy"}},
                        "aggs": {
                            "total": {"sum": {"field": "quantity"}}
                        }
                    },
                    "sell_volume": {
                        "filter": {"term": {"side.keyword": "sell"}},
                        "aggs": {
                            "total": {"sum": {"field": "quantity"}}
                        }
                    },
                    "avg_spread": {
                        "avg": {"field": "spread"}
                    },
                    "first_price": {
                        "top_hits": {
                            "size": 1,
                            "sort": [{"timestamp": {"order": "asc"}}],
                            "_source": ["price"]
                        }
                    },
                    "last_price": {
                        "top_hits": {
                            "size": 1,
                            "sort": [{"timestamp": {"order": "desc"}}],
                            "_source": ["price"]
                        }
                    }
                }
            }
        }
    }'
    
    # Exécution de la requête
    echo -e "${YELLOW}🔄 Récupération des données agrégées...${NC}"
    
    curl -s -u $ES_USER:$ES_PASSWORD -H "Content-Type: application/json" \
        -X POST "http://$ES_HOST/$INDEX/_search?timeout=60s" \
        -d "$query" > "$output_file"
    
    # Vérification de la réponse
    if [ ! -s "$output_file" ]; then
        echo -e "${RED}❌ Aucune donnée récupérée${NC}"
        exit 1
    fi
    
    if ! jq -e '.aggregations' "$output_file" > /dev/null 2>&1; then
        echo -e "${RED}❌ Erreur dans la réponse Elasticsearch:${NC}"
        cat "$output_file"
        exit 1
    fi
    
    # Conversion en format CSV pour analyse
    echo -e "${YELLOW}📝 Conversion en CSV...${NC}"
    
    # En-tête CSV
    echo "timestamp,open_price,high_price,low_price,close_price,avg_price,volume_total,trade_count,buy_volume,sell_volume,buy_sell_ratio,avg_spread,price_change,price_change_pct" > "$csv_file"
    
    # Conversion des données avec calculs avancés
    jq -r '
        .aggregations.hourly_data.buckets[] |
        {
            timestamp: .key_as_string,
            open: (.first_price.hits.hits[0]._source.price // 0),
            high: (.price_stats.max // 0),
            low: (.price_stats.min // 0),
            close: (.last_price.hits.hits[0]._source.price // 0),
            avg: (.price_stats.avg // 0),
            volume: (.volume_total.value // 0),
            trades: (.trade_count.value // 0),
            buy_vol: (.buy_volume.total.value // 0),
            sell_vol: (.sell_volume.total.value // 0),
            spread: (.avg_spread.value // 0)
        } |
        . + {
            buy_sell_ratio: (if .sell_vol > 0 then (.buy_vol / .sell_vol) else 0 end),
            price_change: (.close - .open),
            price_change_pct: (if .open > 0 then ((.close - .open) / .open * 100) else 0 end)
        } |
        [.timestamp, .open, .high, .low, .close, .avg, .volume, .trades, .buy_vol, .sell_vol, .buy_sell_ratio, .spread, .price_change, .price_change_pct] |
        @csv
    ' "$output_file" >> "$csv_file"
    
    # Statistiques finales
    local total_hours=$(jq '.aggregations.hourly_data.buckets | length' "$output_file")
    local total_trades=$(jq '.aggregations.hourly_data.buckets | map(.trade_count.value) | add' "$output_file")
    local total_volume=$(jq '.aggregations.hourly_data.buckets | map(.volume_total.value) | add' "$output_file")
    
    echo -e "${GREEN}✅ Export terminé!${NC}"
    echo -e "${GREEN}📁 Fichier JSON: $output_file${NC}"
    echo -e "${GREEN}📊 Fichier CSV: $csv_file${NC}"
    echo -e "${GREEN}📈 Statistiques:${NC}"
    echo -e "   - Heures analysées: $total_hours"
    echo -e "   - Trades totaux: $total_trades"
    echo -e "   - Volume total: $total_volume BTC"
    echo -e "   - Lignes CSV: $(wc -l < "$csv_file")"
}

# Fonction pour export rapide des dernières 24h
export_last_24h() {
    echo -e "${BLUE}🚀 Export rapide - Bitcoin dernières 24 heures${NC}"
    export_hourly_data 1
}

# Fonction pour export de la semaine
export_last_week() {
    echo -e "${BLUE}📅 Export hebdomadaire - Bitcoin derniers 7 jours${NC}"
    export_hourly_data 7
}

# Fonction pour export personnalisé
export_custom_period() {
    echo -e "${YELLOW}Période personnalisée pour l'export Bitcoin${NC}"
    read -p "Nombre de jours à analyser: " days
    
    if [[ "$days" =~ ^[0-9]+$ ]] && [ "$days" -gt 0 ]; then
        export_hourly_data "$days"
    else
        echo -e "${RED}❌ Veuillez entrer un nombre valide de jours${NC}"
    fi
}

# Menu principal
show_menu() {
    echo -e "\n${BLUE}📋 OPTIONS D'EXPORT BITCOIN HORAIRE:${NC}"
    echo "1. 🚀 Export rapide (dernières 24 heures)"
    echo "2. 📅 Export hebdomadaire (7 jours)"
    echo "3. 📆 Export mensuel (30 jours)"
    echo "4. ⚙️  Période personnalisée"
    echo "5. 📊 Statistiques détaillées"
    echo "0. ❌ Quitter"
    echo
}

# Fonction pour statistiques détaillées
show_detailed_stats() {
    echo -e "${YELLOW}📊 Génération des statistiques détaillées Bitcoin...${NC}"
    
    local stats_file="$EXPORT_DIR/BTCUSDT_detailed_stats_${DATE}.json"
    
    local query='{
        "size": 0,
        "query": {
            "bool": {
                "must": [
                    {"term": {"symbol.keyword": "'$SYMBOL'"}},
                    {"range": {"timestamp": {"gte": "now-7d"}}}
                ]
            }
        },
        "aggs": {
            "daily_stats": {
                "date_histogram": {
                    "field": "timestamp",
                    "calendar_interval": "day"
                },
                "aggs": {
                    "price_range": {"stats": {"field": "price"}},
                    "volume": {"sum": {"field": "quantity"}},
                    "trades": {"value_count": {"field": "trade_id"}}
                }
            },
            "price_distribution": {
                "histogram": {
                    "field": "price",
                    "interval": 1000
                }
            },
            "trading_hours": {
                "date_histogram": {
                    "field": "timestamp",
                    "calendar_interval": "hour"
                },
                "aggs": {
                    "activity": {"value_count": {"field": "trade_id"}}
                }
            }
        }
    }'
    
    curl -s -u $ES_USER:$ES_PASSWORD -H "Content-Type: application/json" \
        -X POST "http://$ES_HOST/$INDEX/_search?timeout=60s" \
        -d "$query" > "$stats_file"
    
    echo -e "${GREEN}✅ Statistiques détaillées sauvegardées: $stats_file${NC}"
}

# Script principal
main() {
    check_elasticsearch
    
    while true; do
        show_menu
        read -p "$(echo -e ${YELLOW}Choisissez une option: ${NC})" choice
        
        case $choice in
            1)
                export_last_24h
                ;;
            2)
                export_last_week
                ;;
            3)
                export_hourly_data 30
                ;;
            4)
                export_custom_period
                ;;
            5)
                show_detailed_stats
                ;;
            0)
                echo -e "${GREEN}👋 Export terminé!${NC}"
                break
                ;;
            *)
                echo -e "${RED}❌ Option invalide${NC}"
                ;;
        esac
        
        echo -e "\n${BLUE}─────────────────────────────────────${NC}"
    done
}

# Vérification des dépendances
command -v jq >/dev/null 2>&1 || { 
    echo -e "${RED}❌ jq est requis mais non installé.${NC}" >&2
    echo -e "${YELLOW}💡 Installation: sudo apt-get install jq${NC}"
    exit 1
}

command -v kubectl >/dev/null 2>&1 || { 
    echo -e "${RED}❌ kubectl est requis mais non installé.${NC}" >&2
    exit 1
}

# Arguments en ligne de commande
if [ $# -gt 0 ]; then
    case $1 in
        "24h"|"1d")
            check_elasticsearch
            export_last_24h
            ;;
        "7d"|"week")
            check_elasticsearch
            export_last_week
            ;;
        "30d"|"month")
            check_elasticsearch
            export_hourly_data 30
            ;;
        *)
            if [[ "$1" =~ ^[0-9]+$ ]]; then
                check_elasticsearch
                export_hourly_data "$1"
            else
                echo -e "${RED}❌ Argument invalide: $1${NC}"
                echo -e "${YELLOW}💡 Usage: $0 [24h|7d|30d|nombre_de_jours]${NC}"
                exit 1
            fi
            ;;
    esac
else
    main
fi
