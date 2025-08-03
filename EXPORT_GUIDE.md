# 📊 Guide d'export des données ELK

## 🎯 Scripts d'export disponibles

### 1. **Export JSON Standard** (`export-to-json.sh`)
```bash
# Export basique (5000 documents, format lisible)
./export-to-json.sh

# Export spécifique
./export-to-json.sh binance-trades-2025.08.02 1000 pretty

# Formats disponibles :
# - pretty    : JSON formaté et lisible
# - compact   : JSON compact (une ligne)
# - ndjson    : Un document JSON par ligne
# - data-only : Seulement les données (sans métadonnées Elasticsearch)
```

### 2. **Export CSV** (`export-to-csv.sh`)
```bash
# Export pour Excel/Google Sheets
./export-to-csv.sh binance-trades-2025.08.02 5000
```

### 3. **Export en lot** (`export-bulk.sh`)
```bash
# Pour de gros volumes (export par batch)
./export-bulk.sh binance-trades-* 1000 20
# Exporte 20 lots de 1000 documents chacun
```

### 4. **Export professionnel** (`export-elasticdump.sh`)
```bash
# Installation automatique d'elasticdump + export
./export-elasticdump.sh binance-trades-2025.08.02 all
```

## 📁 Structure des exports

```
exports/
├── binance-trades-2025.08.02_20250802_154941_pretty.json
├── binance-trades-2025.08.02_20250802_154941.csv
├── bulk_20250802_154941/
│   ├── batch_1_0.json
│   ├── batch_2_1000.json
│   └── ...
└── elasticdump/
    ├── mapping.json
    ├── settings.json
    └── data.json
```

## 🚀 Exemples d'utilisation

### Export des données du jour (JSON)
```bash
./export-to-json.sh binance-trades-$(date +%Y.%m.%d) 10000 data-only
```

### Export historique complet (CSV)
```bash
./export-to-csv.sh "binance-trades-*" 50000
```

### Export pour backup complet
```bash
./export-elasticdump.sh "binance-trades-*" all
```

## 📊 Indices disponibles

Vérifiez vos indices avec :
```bash
kubectl exec -n elk-stack deployment/elasticsearch -- curl -u chater:Protel2025! -X GET "localhost:9200/_cat/indices?v"
```

## 🔧 Troubleshooting

### Port déjà utilisé
Si vous voyez "address already in use", c'est normal - le port-forward est déjà actif.

### Erreur d'authentification
Vérifiez les credentials dans les scripts (ES_USER et ES_PASSWORD).

### Fichier vide
Vérifiez que l'indice existe et contient des données.

## 💡 Conseils

1. **Petits tests d'abord** : Commencez avec 10-100 documents
2. **Surveillance des ressources** : Les gros exports consomment de la mémoire
3. **Format NDJSON** : Idéal pour le traitement ligne par ligne
4. **CSV** : Parfait pour l'analyse dans Excel/Google Sheets
5. **ElasticDump** : Le plus robuste pour les backups complets
