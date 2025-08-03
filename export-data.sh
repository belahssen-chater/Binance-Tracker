#!/bin/bash

# Script d'exportation des données ELK
# Auteur: Assistant GitHub Copilot
# Date: 2 Août 2025

set -e

# Configuration
NAMESPACE="elk-stack"
ES_USER="chater"
ES_PASSWORD="Protel2025!"
ES_HOST="localhost:9200"
EXPORT_DIR="./exports"
DATE=$(date +"%Y%m%d_%H%M%S")

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}    🚀 EXPORTATION DES DONNÉES ELK    ${NC}"
echo -e "${BLUE}========================================${NC}"

# Création du dossier d'export
mkdir -p $EXPORT_DIR

# Fonction pour vérifier la connexion Elasticsearch
check_elasticsearch() {
    echo -e "${YELLOW}🔍 Vérification de la connexion Elasticsearch...${NC}"
    if curl -s -u $ES_USER:$ES_PASSWORD http://$ES_HOST/_cluster/health > /dev/null; then
        echo -e "${GREEN}✅ Connexion Elasticsearch OK${NC}"
    else
        echo -e "${RED}❌ Erreur de connexion Elasticsearch${NC}"
        echo -e "${YELLOW}💡 Assurez-vous que le port-forward est actif: kubectl port-forward svc/elasticsearch 9200:9200 -n elk-stack${NC}"
        exit 1
    fi
}

# Fonction pour lister les indices
list_indices() {
    echo -e "${YELLOW}📋 Indices disponibles:${NC}"
    curl -s -u $ES_USER:$ES_PASSWORD "http://$ES_HOST/_cat/indices?v&h=index,docs.count,store.size" | grep -E "(binance|logs)" || true
}

# Fonction pour exporter un indice complet
export_full_index() {
    local index_name=$1
    local output_file="$EXPORT_DIR/${index_name}_full_${DATE}.json"
    
    echo -e "${YELLOW}📦 Exportation complète de l'indice: $index_name${NC}"
    
    curl -s -u $ES_USER:$ES_PASSWORD -H "Content-Type: application/json" \
        -X POST "http://$ES_HOST/$index_name/_search?scroll=5m&size=1000" \
        -d '{"query": {"match_all": {}}}' > "$output_file.tmp"
    
    # Extraction des documents
    jq -r '.hits.hits[]._source' "$output_file.tmp" > "$output_file"
    rm "$output_file.tmp"
    
    echo -e "${GREEN}✅ Export sauvegardé: $output_file${NC}"
}

# Fonction pour exporter les dernières données
export_recent_data() {
    local index_name=$1
    local hours=$2
    local output_file="$EXPORT_DIR/${index_name}_last_${hours}h_${DATE}.json"
    
    echo -e "${YELLOW}⏰ Exportation des données des dernières $hours heures de: $index_name${NC}"
    
    curl -s -u $ES_USER:$ES_PASSWORD -H "Content-Type: application/json" \
        -X POST "http://$ES_HOST/$index_name/_search?size=10000" \
        -d "{
            \"query\": {
                \"range\": {
                    \"@timestamp\": {
                        \"gte\": \"now-${hours}h\"
                    }
                }
            },
            \"sort\": [{\"@timestamp\": {\"order\": \"desc\"}}]
        }" | jq -r '.hits.hits[]._source' > "$output_file"
    
    echo -e "${GREEN}✅ Export récent sauvegardé: $output_file${NC}"
}

# Fonction pour exporter en CSV
export_to_csv() {
    local index_name=$1
    local output_file="$EXPORT_DIR/${index_name}_${DATE}.csv"
    
    echo -e "${YELLOW}📊 Exportation CSV de: $index_name${NC}"
    
    # Récupération d'un échantillon pour déterminer les champs
    curl -s -u $ES_USER:$ES_PASSWORD -H "Content-Type: application/json" \
        -X POST "http://$ES_HOST/$index_name/_search?size=1" \
        -d '{"query": {"match_all": {}}}' | jq -r '.hits.hits[0]._source | keys[]' > /tmp/fields.txt
    
    # Création de l'en-tête CSV
    paste -sd ',' /tmp/fields.txt > "$output_file"
    
    # Exportation des données
    curl -s -u $ES_USER:$ES_PASSWORD -H "Content-Type: application/json" \
        -X POST "http://$ES_HOST/$index_name/_search?scroll=5m&size=1000" \
        -d '{"query": {"match_all": {}}}' | \
        jq -r '.hits.hits[]._source | [.[] | tostring] | @csv' >> "$output_file"
    
    echo -e "${GREEN}✅ Export CSV sauvegardé: $output_file${NC}"
}

# Fonction pour créer un backup Elasticsearch
create_snapshot() {
    echo -e "${YELLOW}📸 Création d'un snapshot Elasticsearch...${NC}"
    
    # Configuration du repository (si pas déjà fait)
    curl -s -u $ES_USER:$ES_PASSWORD -H "Content-Type: application/json" \
        -X PUT "http://$ES_HOST/_snapshot/backup_repo" \
        -d '{
            "type": "fs",
            "settings": {
                "location": "/usr/share/elasticsearch/backup"
            }
        }' || echo -e "${YELLOW}⚠️  Repository déjà configuré ou erreur de configuration${NC}"
    
    # Création du snapshot
    local snapshot_name="snapshot_$DATE"
    curl -s -u $ES_USER:$ES_PASSWORD -H "Content-Type: application/json" \
        -X PUT "http://$ES_HOST/_snapshot/backup_repo/$snapshot_name" \
        -d '{
            "indices": "binance-*,logs-*",
            "ignore_unavailable": true,
            "include_global_state": false
        }'
    
    echo -e "${GREEN}✅ Snapshot créé: $snapshot_name${NC}"
}

# Menu interactif
show_menu() {
    echo -e "\n${BLUE}📋 OPTIONS D'EXPORTATION:${NC}"
    echo "1. 📊 Lister les indices disponibles"
    echo "2. 📦 Exporter un indice complet (JSON)"
    echo "3. ⏰ Exporter les données récentes (dernières heures)"
    echo "4. 📈 Exporter en format CSV"
    echo "5. 📸 Créer un snapshot Elasticsearch"
    echo "6. 🚀 Export rapide - Toutes les données Binance (JSON)"
    echo "7. 📋 Export résumé - Statistiques des trades"
    echo "0. ❌ Quitter"
    echo
}

# Fonction d'export rapide
quick_export_binance() {
    echo -e "${YELLOW}🚀 Export rapide de toutes les données Binance...${NC}"
    
    # Export des indices binance
    for index in $(curl -s -u $ES_USER:$ES_PASSWORD "http://$ES_HOST/_cat/indices?h=index" | grep "binance-trades"); do
        export_recent_data "$index" 24
    done
}

# Fonction d'export statistiques
export_statistics() {
    local output_file="$EXPORT_DIR/binance_statistics_${DATE}.json"
    
    echo -e "${YELLOW}📊 Génération des statistiques de trading...${NC}"
    
    curl -s -u $ES_USER:$ES_PASSWORD -H "Content-Type: application/json" \
        -X POST "http://$ES_HOST/binance-trades-*/_search?size=0" \
        -d '{
            "aggs": {
                "symbols": {
                    "terms": {"field": "symbol.keyword", "size": 20}
                },
                "daily_volume": {
                    "date_histogram": {
                        "field": "@timestamp",
                        "calendar_interval": "day"
                    },
                    "aggs": {
                        "total_volume": {"sum": {"field": "volume"}}
                    }
                },
                "price_stats": {
                    "stats": {"field": "price"}
                }
            }
        }' > "$output_file"
    
    echo -e "${GREEN}✅ Statistiques sauvegardées: $output_file${NC}"
}

# Main script
main() {
    check_elasticsearch
    
    while true; do
        show_menu
        read -p "$(echo -e ${YELLOW}Choisissez une option: ${NC})" choice
        
        case $choice in
            1)
                list_indices
                ;;
            2)
                read -p "Nom de l'indice à exporter: " index_name
                export_full_index "$index_name"
                ;;
            3)
                read -p "Nom de l'indice: " index_name
                read -p "Nombre d'heures (ex: 24): " hours
                export_recent_data "$index_name" "$hours"
                ;;
            4)
                read -p "Nom de l'indice à exporter en CSV: " index_name
                export_to_csv "$index_name"
                ;;
            5)
                create_snapshot
                ;;
            6)
                quick_export_binance
                ;;
            7)
                export_statistics
                ;;
            0)
                echo -e "${GREEN}👋 Au revoir!${NC}"
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
command -v jq >/dev/null 2>&1 || { echo -e "${RED}❌ jq est requis mais non installé.${NC}" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo -e "${RED}❌ curl est requis mais non installé.${NC}" >&2; exit 1; }

# Démarrage du script
main "$@"
