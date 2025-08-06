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
echo -e "${BLUE}  📊 EXPORT BITCOIN AVANCÉ - VOLUME & ORDERBOOK  ${NC}"
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
                    "volume_weighted_price": {
                        "weighted_avg": {
                            "value": {"field": "price"},
                            "weight": {"field": "quantity"}
                        }
                    },
                    "large_trades": {
                        "filter": {"range": {"quantity": {"gte": 1}}},
                        "aggs": {
                            "count": {"value_count": {"field": "trade_id"}},
                            "volume": {"sum": {"field": "quantity"}}
                        }
                    },
                    "volume_distribution": {
                        "histogram": {
                            "field": "quantity",
                            "interval": 0.1
                        }
                    },
                    "price_levels": {
                        "histogram": {
                            "field": "price",
                            "interval": 100
                        },
                        "aggs": {
                            "volume_at_level": {"sum": {"field": "quantity"}}
                        }
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
    echo "timestamp,open_price,high_price,low_price,close_price,avg_price,vwap,volume_total,trade_count,buy_volume,sell_volume,buy_sell_ratio,large_trades_count,large_trades_volume,avg_spread,price_change,price_change_pct,volume_change" > "$csv_file"
    
    # Conversion des données avec calculs avancés
    local prev_volume=0
    jq -r '
        [.aggregations.hourly_data.buckets[] |
        {
            timestamp: .key_as_string,
            open: (.first_price.hits.hits[0]._source.price // 0),
            high: (.price_stats.max // 0),
            low: (.price_stats.min // 0),
            close: (.last_price.hits.hits[0]._source.price // 0),
            avg: (.price_stats.avg // 0),
            vwap: (.volume_weighted_price.value // 0),
            volume: (.volume_total.value // 0),
            trades: (.trade_count.value // 0),
            buy_vol: (.buy_volume.total.value // 0),
            sell_vol: (.sell_volume.total.value // 0),
            large_trades_count: (.large_trades.count.value // 0),
            large_trades_volume: (.large_trades.volume.value // 0),
            spread: (.avg_spread.value // 0)
        }] |
        . as $data |
        to_entries |
        map(.value + {
            buy_sell_ratio: (if .value.sell_vol > 0 then (.value.buy_vol / .value.sell_vol) else 0 end),
            price_change: (.value.close - .value.open),
            price_change_pct: (if .value.open > 0 then ((.value.close - .value.open) / .value.open * 100) else 0 end),
            volume_change: (if .key > 0 then (.value.volume - $data[.key-1].volume) else 0 end)
        } | .value) |
        map([.timestamp, .open, .high, .low, .close, .avg, .vwap, .volume, .trades, .buy_vol, .sell_vol, .buy_sell_ratio, .large_trades_count, .large_trades_volume, .spread, .price_change, .price_change_pct, .volume_change] |
        @csv) |
        .[]
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

# Fonction pour export avancé du carnet d'ordres
export_orderbook_analysis() {
    local period_hours=${1:-24}  # Par défaut: 24 heures
    local output_file="$EXPORT_DIR/BTCUSDT_orderbook_analysis_${period_hours}h_${DATE}.json"
    local csv_file="$EXPORT_DIR/BTCUSDT_orderbook_analysis_${period_hours}h_${DATE}.csv"
    local depth_file="$EXPORT_DIR/BTCUSDT_market_depth_${period_hours}h_${DATE}.csv"
    
    echo -e "${YELLOW}📖 Analyse avancée du carnet d'ordres Bitcoin (dernières $period_hours heures)...${NC}"
    
    # Requête pour analyser la profondeur du carnet d'ordres avec métriques avancées
    local query='{
        "size": 0,
        "query": {
            "bool": {
                "must": [
                    {"term": {"symbol.keyword": "'$SYMBOL'"}},
                    {"range": {"timestamp": {"gte": "now-'$period_hours'h"}}}
                ]
            }
        },
        "aggs": {
            "market_depth": {
                "histogram": {
                    "field": "price",
                    "interval": 25
                },
                "aggs": {
                    "buy_orders": {
                        "filter": {"term": {"side.keyword": "buy"}},
                        "aggs": {
                            "volume": {"sum": {"field": "quantity"}},
                            "count": {"value_count": {"field": "trade_id"}},
                            "avg_size": {"avg": {"field": "quantity"}},
                            "max_size": {"max": {"field": "quantity"}},
                            "time_spread": {
                                "date_histogram": {
                                    "field": "timestamp",
                                    "calendar_interval": "hour"
                                },
                                "aggs": {
                                    "hourly_volume": {"sum": {"field": "quantity"}}
                                }
                            }
                        }
                    },
                    "sell_orders": {
                        "filter": {"term": {"side.keyword": "sell"}},
                        "aggs": {
                            "volume": {"sum": {"field": "quantity"}},
                            "count": {"value_count": {"field": "trade_id"}},
                            "avg_size": {"avg": {"field": "quantity"}},
                            "max_size": {"max": {"field": "quantity"}},
                            "time_spread": {
                                "date_histogram": {
                                    "field": "timestamp",
                                    "calendar_interval": "hour"
                                },
                                "aggs": {
                                    "hourly_volume": {"sum": {"field": "quantity"}}
                                }
                            }
                        }
                    },
                    "liquidity_metrics": {
                        "stats": {"field": "quantity"}
                    },
                    "price_volatility": {
                        "stats": {"field": "price"}
                    }
                }
            },
            "orderbook_imbalance": {
                "date_histogram": {
                    "field": "timestamp",
                    "calendar_interval": "15m"
                },
                "aggs": {
                    "buy_pressure": {
                        "filter": {"term": {"side.keyword": "buy"}},
                        "aggs": {
                            "volume": {"sum": {"field": "quantity"}},
                            "orders": {"value_count": {"field": "trade_id"}}
                        }
                    },
                    "sell_pressure": {
                        "filter": {"term": {"side.keyword": "sell"}},
                        "aggs": {
                            "volume": {"sum": {"field": "quantity"}},
                            "orders": {"value_count": {"field": "trade_id"}}
                        }
                    },
                    "price_action": {
                        "stats": {"field": "price"}
                    }
                }
            },
            "support_resistance": {
                "significant_terms": {
                    "field": "price",
                    "size": 20,
                    "min_doc_count": 10
                },
                "aggs": {
                    "level_volume": {"sum": {"field": "quantity"}},
                    "level_trades": {"value_count": {"field": "trade_id"}},
                    "side_distribution": {
                        "terms": {"field": "side.keyword"},
                        "aggs": {
                            "volume": {"sum": {"field": "quantity"}}
                        }
                    }
                }
            },
            "large_order_impact": {
                "filter": {"range": {"quantity": {"gte": 5}}},
                "aggs": {
                    "price_levels": {
                        "histogram": {
                            "field": "price",
                            "interval": 100
                        },
                        "aggs": {
                            "impact_volume": {"sum": {"field": "quantity"}},
                            "impact_orders": {"value_count": {"field": "trade_id"}},
                            "side_breakdown": {
                                "terms": {"field": "side.keyword"},
                                "aggs": {
                                    "volume": {"sum": {"field": "quantity"}}
                                }
                            }
                        }
                    }
                }
            }
        }
    }'
    
    curl -s -u $ES_USER:$ES_PASSWORD -H "Content-Type: application/json" \
        -X POST "http://$ES_HOST/$INDEX/_search?timeout=60s" \
        -d "$query" > "$output_file"
    
    if [ ! -s "$output_file" ]; then
        echo -e "${RED}❌ Aucune donnée de carnet d'ordres récupérée${NC}"
        return 1
    fi
    
    # Conversion en CSV - Profondeur du marché
    echo "price_level,buy_volume,sell_volume,net_volume,buy_orders,sell_orders,total_orders,liquidity_ratio,volume_imbalance,avg_buy_size,avg_sell_size,max_buy_size,max_sell_size,price_std_dev" > "$csv_file"
    
    jq -r '
        .aggregations.market_depth.buckets[] |
        {
            price: .key,
            buy_vol: (.buy_orders.volume.value // 0),
            sell_vol: (.sell_orders.volume.value // 0),
            buy_count: (.buy_orders.count.value // 0),
            sell_count: (.sell_orders.count.value // 0),
            buy_avg: (.buy_orders.avg_size.value // 0),
            sell_avg: (.sell_orders.avg_size.value // 0),
            buy_max: (.buy_orders.max_size.value // 0),
            sell_max: (.sell_orders.max_size.value // 0),
            price_std: (.price_volatility.std_deviation // 0)
        } |
        . + {
            net_volume: (.buy_vol - .sell_vol),
            total_orders: (.buy_count + .sell_count),
            liquidity_ratio: (if (.buy_vol + .sell_vol) > 0 then (.buy_vol + .sell_vol) else 0 end),
            volume_imbalance: (if (.buy_vol + .sell_vol) > 0 then ((.buy_vol - .sell_vol) / (.buy_vol + .sell_vol)) else 0 end)
        } |
        [.price, .buy_vol, .sell_vol, .net_volume, .buy_count, .sell_count, .total_orders, .liquidity_ratio, .volume_imbalance, .buy_avg, .sell_avg, .buy_max, .sell_max, .price_std] |
        @csv
    ' "$output_file" >> "$csv_file"
    
    # Fichier CSV pour les déséquilibres temporels
    local imbalance_file="$EXPORT_DIR/BTCUSDT_orderbook_imbalance_${period_hours}h_${DATE}.csv"
    echo "timestamp,buy_pressure_volume,sell_pressure_volume,buy_pressure_orders,sell_pressure_orders,pressure_imbalance,price_min,price_max,price_range,market_sentiment" > "$imbalance_file"
    
    jq -r '
        .aggregations.orderbook_imbalance.buckets[] |
        {
            timestamp: .key_as_string,
            buy_vol: (.buy_pressure.volume.value // 0),
            sell_vol: (.sell_pressure.volume.value // 0),
            buy_orders: (.buy_pressure.orders.value // 0),
            sell_orders: (.sell_pressure.orders.value // 0),
            price_min: (.price_action.min // 0),
            price_max: (.price_action.max // 0)
        } |
        . + {
            pressure_imbalance: (if (.buy_vol + .sell_vol) > 0 then ((.buy_vol - .sell_vol) / (.buy_vol + .sell_vol)) else 0 end),
            price_range: (.price_max - .price_min),
            market_sentiment: (if (.buy_vol > .sell_vol) then "bullish" elif (.sell_vol > .buy_vol) then "bearish" else "neutral" end)
        } |
        [.timestamp, .buy_vol, .sell_vol, .buy_orders, .sell_orders, .pressure_imbalance, .price_min, .price_max, .price_range, .market_sentiment] |
        @csv
    ' "$output_file" >> "$imbalance_file"
    
    # Fichier CSV pour les niveaux de support/résistance
    local levels_file="$EXPORT_DIR/BTCUSDT_support_resistance_${period_hours}h_${DATE}.csv"
    echo "price_level,significance_score,total_volume,total_trades,buy_volume,sell_volume,level_strength,level_type" > "$levels_file"
    
    jq -r '
        .aggregations.support_resistance.buckets[] |
        {
            price: .key,
            score: .score,
            volume: (.level_volume.value // 0),
            trades: (.level_trades.value // 0),
            buy_vol: ((.side_distribution.buckets[] | select(.key == "buy") | .volume.value) // 0),
            sell_vol: ((.side_distribution.buckets[] | select(.key == "sell") | .volume.value) // 0)
        } |
        . + {
            strength: (.score * .volume),
            level_type: (if .buy_vol > .sell_vol then "support" elif .sell_vol > .buy_vol then "resistance" else "neutral" end)
        } |
        [.price, .score, .volume, .trades, .buy_vol, .sell_vol, .strength, .level_type] |
        @csv
    ' "$output_file" >> "$levels_file"
    
    # Statistiques du carnet d'ordres
    local total_buy_volume=$(jq '[.aggregations.market_depth.buckets[].buy_orders.volume.value] | add' "$output_file")
    local total_sell_volume=$(jq '[.aggregations.market_depth.buckets[].sell_orders.volume.value] | add' "$output_file")
    local market_imbalance=$(echo "scale=4; ($total_buy_volume - $total_sell_volume) / ($total_buy_volume + $total_sell_volume)" | bc -l)
    
    echo -e "${GREEN}✅ Analyse avancée du carnet d'ordres terminée!${NC}"
    echo -e "${GREEN}📁 Fichier principal: $output_file${NC}"
    echo -e "${GREEN}📊 Profondeur marché: $csv_file${NC}"
    echo -e "${GREEN}⚖️  Déséquilibres: $imbalance_file${NC}"
    echo -e "${GREEN}📈 Support/Résistance: $levels_file${NC}"
    echo -e "${GREEN}📊 Métriques du carnet:${NC}"
    echo -e "   - Volume buy total: ${total_buy_volume} BTC"
    echo -e "   - Volume sell total: ${total_sell_volume} BTC"
    echo -e "   - Déséquilibre marché: ${market_imbalance}"
}

# Fonction pour analyse en temps réel du carnet d'ordres
export_realtime_orderbook() {
    local minutes=${1:-60}  # Par défaut: dernière heure
    local output_file="$EXPORT_DIR/BTCUSDT_realtime_orderbook_${minutes}m_${DATE}.json"
    local csv_file="$EXPORT_DIR/BTCUSDT_realtime_orderbook_${minutes}m_${DATE}.csv"
    
    echo -e "${YELLOW}⚡ Analyse en temps réel du carnet d'ordres (dernières $minutes minutes)...${NC}"
    
    local query='{
        "size": 0,
        "query": {
            "bool": {
                "must": [
                    {"term": {"symbol.keyword": "'$SYMBOL'"}},
                    {"range": {"timestamp": {"gte": "now-'$minutes'm"}}}
                ]
            }
        },
        "aggs": {
            "minute_by_minute": {
                "date_histogram": {
                    "field": "timestamp",
                    "calendar_interval": "1m"
                },
                "aggs": {
                    "bid_ask_spread": {
                        "percentiles": {
                            "field": "price",
                            "percents": [10, 25, 50, 75, 90]
                        }
                    },
                    "order_flow": {
                        "terms": {"field": "side.keyword"},
                        "aggs": {
                            "volume": {"sum": {"field": "quantity"}},
                            "orders": {"value_count": {"field": "trade_id"}},
                            "avg_size": {"avg": {"field": "quantity"}},
                            "price_impact": {"stats": {"field": "price"}}
                        }
                    },
                    "liquidity_tiers": {
                        "range": {
                            "field": "quantity",
                            "ranges": [
                                {"to": 0.1, "key": "retail"},
                                {"from": 0.1, "to": 1, "key": "small_trader"},
                                {"from": 1, "to": 10, "key": "medium_trader"},
                                {"from": 10, "to": 100, "key": "institution"},
                                {"from": 100, "key": "whale"}
                            ]
                        },
                        "aggs": {
                            "side_flow": {
                                "terms": {"field": "side.keyword"},
                                "aggs": {
                                    "volume": {"sum": {"field": "quantity"}}
                                }
                            }
                        }
                    },
                    "market_microstructure": {
                        "stats": {"field": "quantity"}
                    }
                }
            },
            "order_book_depth": {
                "histogram": {
                    "field": "price",
                    "interval": 10
                },
                "aggs": {
                    "depth_analysis": {
                        "terms": {"field": "side.keyword"},
                        "aggs": {
                            "cumulative_volume": {"sum": {"field": "quantity"}},
                            "order_density": {"value_count": {"field": "trade_id"}},
                            "avg_order_size": {"avg": {"field": "quantity"}}
                        }
                    }
                }
            },
            "market_makers_activity": {
                "filter": {"range": {"quantity": {"lte": 0.5}}},
                "aggs": {
                    "mm_volume": {"sum": {"field": "quantity"}},
                    "mm_orders": {"value_count": {"field": "trade_id"}},
                    "mm_price_range": {"stats": {"field": "price"}}
                }
            }
        }
    }'
    
    curl -s -u $ES_USER:$ES_PASSWORD -H "Content-Type: application/json" \
        -X POST "http://$ES_HOST/$INDEX/_search?timeout=60s" \
        -d "$query" > "$output_file"
    
    if [ ! -s "$output_file" ]; then
        echo -e "${RED}❌ Aucune donnée temps réel récupérée${NC}"
        return 1
    fi
    
    # CSV pour analyse minute par minute
    echo "timestamp,buy_volume,sell_volume,buy_orders,sell_orders,buy_avg_size,sell_avg_size,spread_p50,spread_p90,order_flow_imbalance,retail_activity,whale_activity,market_efficiency" > "$csv_file"
    
    jq -r '
        .aggregations.minute_by_minute.buckets[] |
        {
            timestamp: .key_as_string,
            buy: ((.order_flow.buckets[] | select(.key == "buy")) // {}),
            sell: ((.order_flow.buckets[] | select(.key == "sell")) // {}),
            spread_50: (.bid_ask_spread.values."50.0" // 0),
            spread_90: (.bid_ask_spread.values."90.0" // 0),
            retail: ((.liquidity_tiers.buckets[] | select(.key == "retail")) // {}),
            whale: ((.liquidity_tiers.buckets[] | select(.key == "whale")) // {})
        } |
        {
            timestamp: .timestamp,
            buy_vol: (.buy.volume.value // 0),
            sell_vol: (.sell.volume.value // 0),
            buy_orders: (.buy.orders.value // 0),
            sell_orders: (.sell.orders.value // 0),
            buy_avg: (.buy.avg_size.value // 0),
            sell_avg: (.sell.avg_size.value // 0),
            spread_50: .spread_50,
            spread_90: .spread_90,
            retail_vol: ((.retail.side_flow.buckets | map(.volume.value) | add) // 0),
            whale_vol: ((.whale.side_flow.buckets | map(.volume.value) | add) // 0)
        } |
        . + {
            flow_imbalance: (if (.buy_vol + .sell_vol) > 0 then ((.buy_vol - .sell_vol) / (.buy_vol + .sell_vol)) else 0 end),
            market_efficiency: (if .spread_90 > 0 then (.spread_50 / .spread_90) else 0 end)
        } |
        [.timestamp, .buy_vol, .sell_vol, .buy_orders, .sell_orders, .buy_avg, .sell_avg, .spread_50, .spread_90, .flow_imbalance, .retail_vol, .whale_vol, .market_efficiency] |
        @csv
    ' "$output_file" >> "$csv_file"
    
    echo -e "${GREEN}✅ Analyse temps réel terminée!${NC}"
    echo -e "${GREEN}📁 Données JSON: $output_file${NC}"
    echo -e "${GREEN}⚡ Données temps réel: $csv_file${NC}"
}

# Fonction pour analyser les volumes par taille de trade
export_volume_profile() {
    local period_days=${1:-1}  # Par défaut: 1 jour
    local output_file="$EXPORT_DIR/BTCUSDT_volume_profile_${period_days}d_${DATE}.json"
    local csv_file="$EXPORT_DIR/BTCUSDT_volume_profile_${period_days}d_${DATE}.csv"
    
    echo -e "${YELLOW}📊 Profil de volume Bitcoin (derniers $period_days jours)...${NC}"
    
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
            "price_volume_profile": {
                "histogram": {
                    "field": "price",
                    "interval": 25
                },
                "aggs": {
                    "total_volume": {"sum": {"field": "quantity"}},
                    "buy_volume": {
                        "filter": {"term": {"side.keyword": "buy"}},
                        "aggs": {"volume": {"sum": {"field": "quantity"}}}
                    },
                    "sell_volume": {
                        "filter": {"term": {"side.keyword": "sell"}},
                        "aggs": {"volume": {"sum": {"field": "quantity"}}}
                    },
                    "time_distribution": {
                        "date_histogram": {
                            "field": "timestamp",
                            "calendar_interval": "hour"
                        },
                        "aggs": {
                            "hourly_volume": {"sum": {"field": "quantity"}}
                        }
                    }
                }
            },
            "whale_trades": {
                "filter": {"range": {"quantity": {"gte": 10}}},
                "aggs": {
                    "by_price": {
                        "histogram": {
                            "field": "price",
                            "interval": 100
                        },
                        "aggs": {
                            "whale_volume": {"sum": {"field": "quantity"}},
                            "whale_count": {"value_count": {"field": "trade_id"}}
                        }
                    }
                }
            }
        }
    }'
    
    curl -s -u $ES_USER:$ES_PASSWORD -H "Content-Type: application/json" \
        -X POST "http://$ES_HOST/$INDEX/_search?timeout=60s" \
        -d "$query" > "$output_file"
    
    if [ ! -s "$output_file" ]; then
        echo -e "${RED}❌ Aucune donnée de profil de volume récupérée${NC}"
        return 1
    fi
    
    # Conversion en CSV pour le profil de volume
    echo "price_level,total_volume,buy_volume,sell_volume,volume_ratio,activity_hours" > "$csv_file"
    
    jq -r '
        .aggregations.price_volume_profile.buckets[] |
        {
            price: .key,
            total_vol: (.total_volume.value // 0),
            buy_vol: (.buy_volume.volume.value // 0),
            sell_vol: (.sell_volume.volume.value // 0),
            hours_active: (.time_distribution.buckets | length)
        } |
        . + {
            volume_ratio: (if .sell_vol > 0 then (.buy_vol / .sell_vol) else 0 end)
        } |
        [.price, .total_vol, .buy_vol, .sell_vol, .volume_ratio, .hours_active] |
        @csv
    ' "$output_file" >> "$csv_file"
    
    echo -e "${GREEN}✅ Profil de volume terminé!${NC}"
    echo -e "${GREEN}📁 Fichier JSON: $output_file${NC}"
    echo -e "${GREEN}📊 Fichier CSV: $csv_file${NC}"
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
    echo -e "\n${BLUE}📋 OPTIONS D'EXPORT BITCOIN AVANCÉ:${NC}"
    echo "1. 🚀 Export rapide (dernières 24 heures)"
    echo "2. 📅 Export hebdomadaire (7 jours)"
    echo "3. 📆 Export mensuel (30 jours)"
    echo "4. ⚙️  Période personnalisée"
    echo "5. 📊 Statistiques détaillées"
    echo "6. 📖 Analyse carnet d'ordres avancée"
    echo "7. ⚡ Carnet d'ordres temps réel"
    echo "8. 📈 Profil de volume détaillé"
    echo "9. 🐋 Analyse des gros trades (whales)"
    echo "0. ❌ Quitter"
    echo
}

# Fonction pour analyser les gros trades (whales)
export_whale_analysis() {
    local min_volume=${1:-5}  # Volume minimum pour être considéré comme "whale"
    local period_hours=${2:-24}  # Période d'analyse
    local output_file="$EXPORT_DIR/BTCUSDT_whale_analysis_${period_hours}h_${DATE}.json"
    local csv_file="$EXPORT_DIR/BTCUSDT_whale_analysis_${period_hours}h_${DATE}.csv"
    
    echo -e "${YELLOW}🐋 Analyse des gros trades Bitcoin (>$min_volume BTC, dernières $period_hours heures)...${NC}"
    
    local query='{
        "size": 0,
        "query": {
            "bool": {
                "must": [
                    {"term": {"symbol.keyword": "'$SYMBOL'"}},
                    {"range": {"timestamp": {"gte": "now-'$period_hours'h"}}},
                    {"range": {"quantity": {"gte": '$min_volume'}}}
                ]
            }
        },
        "aggs": {
            "whale_activity": {
                "date_histogram": {
                    "field": "timestamp",
                    "calendar_interval": "hour"
                },
                "aggs": {
                    "buy_whales": {
                        "filter": {"term": {"side.keyword": "buy"}},
                        "aggs": {
                            "count": {"value_count": {"field": "trade_id"}},
                            "volume": {"sum": {"field": "quantity"}},
                            "avg_price": {"avg": {"field": "price"}},
                            "max_trade": {"max": {"field": "quantity"}}
                        }
                    },
                    "sell_whales": {
                        "filter": {"term": {"side.keyword": "sell"}},
                        "aggs": {
                            "count": {"value_count": {"field": "trade_id"}},
                            "volume": {"sum": {"field": "quantity"}},
                            "avg_price": {"avg": {"field": "price"}},
                            "max_trade": {"max": {"field": "quantity"}}
                        }
                    },
                    "price_impact": {
                        "stats": {"field": "price"}
                    }
                }
            },
            "whale_size_distribution": {
                "range": {
                    "field": "quantity",
                    "ranges": [
                        {"from": '$min_volume', "to": 20, "key": "medium_whale"},
                        {"from": 20, "to": 100, "key": "large_whale"},
                        {"from": 100, "key": "mega_whale"}
                    ]
                },
                "aggs": {
                    "side_breakdown": {
                        "terms": {"field": "side.keyword"},
                        "aggs": {
                            "volume": {"sum": {"field": "quantity"}},
                            "count": {"value_count": {"field": "trade_id"}}
                        }
                    }
                }
            }
        }
    }'
    
    curl -s -u $ES_USER:$ES_PASSWORD -H "Content-Type: application/json" \
        -X POST "http://$ES_HOST/$INDEX/_search?timeout=60s" \
        -d "$query" > "$output_file"
    
    if [ ! -s "$output_file" ]; then
        echo -e "${RED}❌ Aucune donnée whale récupérée${NC}"
        return 1
    fi
    
    # Conversion en CSV
    echo "timestamp,buy_whale_count,buy_whale_volume,buy_avg_price,sell_whale_count,sell_whale_volume,sell_avg_price,net_whale_volume,price_min,price_max,price_volatility" > "$csv_file"
    
    jq -r '
        .aggregations.whale_activity.buckets[] |
        {
            timestamp: .key_as_string,
            buy_count: (.buy_whales.count.value // 0),
            buy_volume: (.buy_whales.volume.value // 0),
            buy_price: (.buy_whales.avg_price.value // 0),
            sell_count: (.sell_whales.count.value // 0),
            sell_volume: (.sell_whales.volume.value // 0),
            sell_price: (.sell_whales.avg_price.value // 0),
            price_min: (.price_impact.min // 0),
            price_max: (.price_impact.max // 0)
        } |
        . + {
            net_volume: (.buy_volume - .sell_volume),
            price_volatility: (.price_max - .price_min)
        } |
        [.timestamp, .buy_count, .buy_volume, .buy_price, .sell_count, .sell_volume, .sell_price, .net_volume, .price_min, .price_max, .price_volatility] |
        @csv
    ' "$output_file" >> "$csv_file"
    
    # Statistiques des whales
    local total_whales=$(jq '[.aggregations.whale_activity.buckets[].buy_whales.count.value, .aggregations.whale_activity.buckets[].sell_whales.count.value] | add' "$output_file")
    local total_whale_volume=$(jq '[.aggregations.whale_activity.buckets[].buy_whales.volume.value, .aggregations.whale_activity.buckets[].sell_whales.volume.value] | add' "$output_file")
    
    echo -e "${GREEN}✅ Analyse des whales terminée!${NC}"
    echo -e "${GREEN}📁 Fichier JSON: $output_file${NC}"
    echo -e "${GREEN}📊 Fichier CSV: $csv_file${NC}"
    echo -e "${GREEN}🐋 Statistiques whales:${NC}"
    echo -e "   - Trades whales: $total_whales"
    echo -e "   - Volume whale total: $total_whale_volume BTC"
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
            6)
                echo -e "${YELLOW}Période pour l'analyse avancée du carnet d'ordres (heures):${NC}"
                read -p "Nombre d'heures (défaut: 24): " hours
                hours=${hours:-24}
                export_orderbook_analysis "$hours"
                ;;
            7)
                echo -e "${YELLOW}Période pour l'analyse temps réel (minutes):${NC}"
                read -p "Nombre de minutes (défaut: 60): " minutes
                minutes=${minutes:-60}
                export_realtime_orderbook "$minutes"
                ;;
            8)
                echo -e "${YELLOW}Période pour le profil de volume (jours):${NC}"
                read -p "Nombre de jours (défaut: 1): " days
                days=${days:-1}
                export_volume_profile "$days"
                ;;
            9)
                echo -e "${YELLOW}Configuration de l'analyse des whales:${NC}"
                read -p "Volume minimum (BTC, défaut: 5): " min_vol
                read -p "Période d'analyse (heures, défaut: 24): " hours
                min_vol=${min_vol:-5}
                hours=${hours:-24}
                export_whale_analysis "$min_vol" "$hours"
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

command -v bc >/dev/null 2>&1 || { 
    echo -e "${RED}❌ bc est requis mais non installé.${NC}" >&2
    echo -e "${YELLOW}💡 Installation: sudo apt-get install bc${NC}"
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
        "orderbook")
            check_elasticsearch
            hours=${2:-24}
            export_orderbook_analysis "$hours"
            ;;
        "realtime")
            check_elasticsearch
            minutes=${2:-60}
            export_realtime_orderbook "$minutes"
            ;;
        "volume")
            check_elasticsearch
            days=${2:-1}
            export_volume_profile "$days"
            ;;
        "whales")
            check_elasticsearch
            min_vol=${2:-5}
            hours=${3:-24}
            export_whale_analysis "$min_vol" "$hours"
            ;;
        *)
            if [[ "$1" =~ ^[0-9]+$ ]]; then
                check_elasticsearch
                export_hourly_data "$1"
            else
                echo -e "${RED}❌ Argument invalide: $1${NC}"
                echo -e "${YELLOW}💡 Usage: $0 [24h|7d|30d|orderbook|realtime|volume|whales|nombre_de_jours]${NC}"
                echo -e "${YELLOW}   Exemples:${NC}"
                echo -e "${YELLOW}   $0 orderbook 48          # Carnet d'ordres avancé 48h${NC}"
                echo -e "${YELLOW}   $0 realtime 30           # Analyse temps réel 30min${NC}"
                echo -e "${YELLOW}   $0 volume 3              # Profil volume 3 jours${NC}"
                echo -e "${YELLOW}   $0 whales 10 12          # Whales >10 BTC sur 12h${NC}"
                exit 1
            fi
            ;;
    esac
else
    main
fi
