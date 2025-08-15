#!/bin/bash

# Script optimisé pour exporter toutes les données Bitcoin par heure
# Fonctionne avec la structure de données Elasticsearch
# Usage: ./export-bitcoin-hourly-fixed.sh [nombre_de_jours|all]
# Exemples:
#   ./export-bitcoin-hourly-fixed.sh       # Exporte toutes les données historiques
#   ./export-bitcoin-hourly-fixed.sh 30    # Exporte les 30 derniers jours
#   ./export-bitcoin-hourly-fixed.sh all   # Exporte toutes les données historiques

set -e

# Configuration
ES_USER="chater" 
ES_PASSWORD="Protel2025!"
ES_HOST="localhost:9200"
INDEX="binance-trades-*"
SYMBOL="BTCUSDT"
EXPORT_DIR="./exports"
DATE=$(date +"%Y%m%d_%H%M%S")

# Colors for display
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  📊 BITCOIN HOURLY DATA EXPORTER  ${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "${YELLOW}🔍 Ce script exporte toutes les données Bitcoin par heure${NC}"

# Create export directory
mkdir -p $EXPORT_DIR

# Check Elasticsearch connection
check_elasticsearch() {
    echo -e "${YELLOW}🔍 Checking Elasticsearch connection...${NC}"
    
    # Check if we need to use kubectl port-forward
    if ! curl -s "http://localhost:9200" > /dev/null 2>&1; then
        echo -e "${YELLOW}⚡ Setting up connection to Kubernetes Elasticsearch...${NC}"
        
        # Kill any existing port-forward processes
        pkill -f "kubectl port-forward.*elasticsearch.*9200" 2>/dev/null || true
        
        # Start port-forward in background
        kubectl port-forward -n elk-stack svc/elasticsearch 9200:9200 > /dev/null 2>&1 &
        PORT_FORWARD_PID=$!
        
        # Set up cleanup trap
        trap "kill $PORT_FORWARD_PID 2>/dev/null; pkill -f 'kubectl port-forward.*elasticsearch.*9200' 2>/dev/null" EXIT
        
        # Wait for port-forward to be ready with retry logic
        echo -e "${YELLOW}⏳ Waiting for port-forward to be ready...${NC}"
        for i in {1..15}; do
            if curl -s "http://localhost:9200" > /dev/null 2>&1; then
                echo -e "${GREEN}✅ Port-forward established successfully${NC}"
                break
            fi
            if [ $i -eq 15 ]; then
                echo -e "${RED}❌ Port-forward failed to establish after 15 seconds${NC}"
                exit 1
            fi
            sleep 1
        done
    fi
    
    # Test Elasticsearch connection with authentication
    echo -e "${YELLOW}🔐 Testing Elasticsearch authentication...${NC}"
    if curl -s -u $ES_USER:$ES_PASSWORD http://$ES_HOST/_cluster/health > /dev/null; then
        # Get cluster status for additional info
        CLUSTER_STATUS=$(curl -s -u $ES_USER:$ES_PASSWORD http://$ES_HOST/_cluster/health | jq -r '.status' 2>/dev/null || echo "unknown")
        echo -e "${GREEN}✅ Elasticsearch connection OK (status: $CLUSTER_STATUS)${NC}"
    else
        echo -e "${RED}❌ Elasticsearch authentication failed${NC}"
        echo -e "${YELLOW}💡 Checking if Elasticsearch is accessible without auth...${NC}"
        if curl -s http://$ES_HOST/_cluster/health > /dev/null; then
            echo -e "${YELLOW}⚠️  Elasticsearch is accessible but authentication failed${NC}"
            echo -e "${YELLOW}💡 Please check credentials: ES_USER=$ES_USER${NC}"
        else
            echo -e "${RED}❌ Elasticsearch is not accessible at all${NC}"
        fi
        exit 1
    fi
}

# Export hourly aggregated data
export_hourly_data() {
    local period_days=${1:-0}  # Default: 0 = all data
    local period_label=""
    local range_query=""
    
    if [ "$period_days" -gt 0 ]; then
        period_label="${period_days}days_"
        range_query=',"range": {"@timestamp": {"gte": "now-'$period_days'd"}}'
        echo -e "${YELLOW}📊 Exporting Bitcoin hourly data (last $period_days days)...${NC}"
    else
        period_label="alltime_"
        echo -e "${YELLOW}📊 Exporting ALL Bitcoin hourly data...${NC}"
    fi
    
    local output_file="$EXPORT_DIR/BTCUSDT_hourly_data_${period_label}${DATE}_fixed.json"
    local csv_file="$EXPORT_DIR/BTCUSDT_hourly_data_${period_label}${DATE}_fixed.csv"
    
    echo -e "${YELLOW}📋 Index: $INDEX${NC}"
    echo -e "${YELLOW}🪙 Symbol: $SYMBOL${NC}"
    
    # Requête Elasticsearch simplifiée pour données OHLCV
    local query='{
        "size": 0,
        "query": {
            "bool": {
                "must": [
                    {"term": {"symbol.keyword": "'$SYMBOL'"}}
                    '"$range_query"'
                ]
            }
        },
        "aggs": {
            "hourly_data": {
                "date_histogram": {
                    "field": "@timestamp",
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
                    "first_price": {
                        "top_hits": {
                            "size": 1,
                            "sort": [{"@timestamp": {"order": "asc"}}],
                            "_source": ["price"]
                        }
                    },
                    "last_price": {
                        "top_hits": {
                            "size": 1,
                            "sort": [{"@timestamp": {"order": "desc"}}],
                            "_source": ["price"]
                        }
                    },
                    "spread_stats": {
                        "stats": {"field": "spread"}
                    },
                    "latest_order_book": {
                        "top_hits": {
                            "size": 1,
                            "sort": [{"@timestamp": {"order": "desc"}}],
                            "_source": ["bids", "asks", "spread"]
                        }
                    }
                }
            }
        }
    }'
    
    # Execute the query
    echo -e "${YELLOW}🔄 Retrieving aggregated data...${NC}"
    
    curl -s -u $ES_USER:$ES_PASSWORD -H "Content-Type: application/json" \
        -X POST "http://$ES_HOST/$INDEX/_search?timeout=120s" \
        -d "$query" > "$output_file"
    
    # Check response
    if [ ! -s "$output_file" ]; then
        echo -e "${RED}❌ No data retrieved${NC}"
        exit 1
    fi
    
    # Check if response contains error
    if jq -e '.error' "$output_file" > /dev/null 2>&1; then
        echo -e "${RED}❌ Elasticsearch error:${NC}"
        jq '.error' "$output_file"
        exit 1
    fi
    
    if ! jq -e '.aggregations' "$output_file" > /dev/null 2>&1; then
        echo -e "${RED}❌ No aggregations in response:${NC}"
        cat "$output_file"
        exit 1
    fi
    
    # Convert to CSV format
    echo -e "${YELLOW}📝 Converting to CSV...${NC}"
    
    # CSV header - OHLCV + Order Book format
    echo "Date,Open,High,Low,Close,Volume,best_bid,best_ask,spread,bid_volume,ask_volume,order_imbalance" > "$csv_file"
    
    # Convert data - format OHLCV + Order Book
    jq -r '
        .aggregations.hourly_data.buckets[] |
        . as $bucket |
        (.latest_order_book.hits.hits[0]._source // {}) as $order_book |
        ($order_book.bids // [[0,0]]) as $bids |
        ($order_book.asks // [[0,0]]) as $asks |
        ($bids[0][1] // 0) as $bid_vol |
        ($asks[0][1] // 0) as $ask_vol |
        [
            .key_as_string,
            ((.first_price.hits.hits[0]._source.price // 0) | tostring),
            ((.price_stats.max // 0) | tostring),
            ((.price_stats.min // 0) | tostring),
            ((.last_price.hits.hits[0]._source.price // 0) | tostring),
            ((.volume_total.value // 0) | tostring),
            (($bids[0][0] // 0) | tostring),
            (($asks[0][0] // 0) | tostring),
            (($order_book.spread // 0) | tostring),
            ($bid_vol | tostring),
            ($ask_vol | tostring),
            (if ($bid_vol + $ask_vol) > 0 then 
                (($bid_vol - $ask_vol) / ($bid_vol + $ask_vol)) 
             else 0 end | tostring)
        ] | @csv
    ' "$output_file" >> "$csv_file"
    
    # Statistiques finales avec Order Book
    local total_hours=$(jq '.aggregations.hourly_data.buckets | length' "$output_file")
    local total_volume=$(jq '.aggregations.hourly_data.buckets | map(.volume_total.value) | add' "$output_file" 2>/dev/null || echo "0")
    local avg_spread=$(jq '.aggregations.hourly_data.buckets | map(.spread_stats.avg) | add / length' "$output_file" 2>/dev/null || echo "0")
    
    echo -e "${GREEN}✅ Export OHLCV + Order Book completed!${NC}"
    echo -e "${GREEN}📁 JSON file: $output_file${NC}"
    echo -e "${GREEN}📊 CSV file: $csv_file${NC}"
    echo -e "${GREEN}📈 Statistics:${NC}"
    echo -e "   - Hours analyzed: $total_hours"
    echo -e "   - Total volume: $total_volume BTC"
    echo -e "   - Average spread: $avg_spread USD"
    echo -e "   - CSV lines: $(wc -l < "$csv_file")"
}

# Check required tools
command -v jq >/dev/null 2>&1 || { 
    echo -e "${RED}❌ jq is required but not installed.${NC}" >&2
    echo -e "${YELLOW}💡 Install with: sudo apt-get install jq${NC}"
    exit 1
}

command -v kubectl >/dev/null 2>&1 || { 
    echo -e "${RED}❌ kubectl is required but not installed.${NC}" >&2
    exit 1
}

# Main execution
check_elasticsearch

# Parse command line arguments
if [ $# -gt 0 ]; then
    if [[ "$1" =~ ^[0-9]+$ ]]; then
        export_hourly_data "$1"
    elif [ "$1" = "all" ]; then
        # Export all historical data
        export_hourly_data 0
    else
        echo -e "${RED}❌ Invalid argument: $1${NC}"
        echo -e "${YELLOW}Usage: $0 [number_of_days|all]${NC}"
        echo -e "${YELLOW}Examples:${NC}"
        echo -e "${YELLOW}  $0 30       # Export last 30 days${NC}"
        echo -e "${YELLOW}  $0 all      # Export ALL historical data${NC}"
        exit 1
    fi
else
    # Default: all data
    export_hourly_data 0
fi
