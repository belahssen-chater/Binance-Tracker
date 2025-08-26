#!/usr/bin/env python3
"""
Service de Prédiction Temps Réel - Binance ELK Stack
====================================================

Ce service se connecte à votre stack ELK-K3s existante pour récupérer les données
temps réel de Binance et effectuer des prédictions de prix Bitcoin avec XGBoost.

Features:
- Connexion directe à Elasticsearch
- Récupération des données Binance temps réel 
- Prédictions XGBoost optimisées
- Mode continu avec intervalle configurable
- Logs détaillés et métriques
- Sauvegarde des prédictions

Utilisation:
    python realtime_prediction_service.py
    python realtime_prediction_service.py --interval 30 --predictions 10
"""

import os
import sys
import json
import time
import argparse
import logging
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Tuple
import warnings
warnings.filterwarnings('ignore')

import pandas as pd
import numpy as np
from elasticsearch import Elasticsearch
from elasticsearch.helpers import scan
import xgboost as xgb
from sklearn.preprocessing import MinMaxScaler
from sklearn.metrics import mean_absolute_error, mean_squared_error
import urllib3
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

class ElkRealtimePredictor:
    """Service de prédiction temps réel connecté à votre stack ELK-K3s"""
    
    def __init__(self, config_file: str = "elk_config.json"):
        """
        Initialiser le service avec la configuration ELK
        
        Args:
            config_file: Fichier de configuration ELK
        """
        self.config = self._load_config(config_file)
        self.es_client = None
        self.connected = False
        self.scaler = MinMaxScaler(feature_range=(0, 1))
        self.last_model = None
        self.predictions_history = []
        
        # Configuration des logs
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler('realtime_predictions.log'),
                logging.StreamHandler()
            ]
        )
        self.logger = logging.getLogger(__name__)
        
    def _load_config(self, config_file: str) -> Dict:
        """Charger la configuration depuis le fichier JSON"""
        try:
            with open(config_file, 'r') as f:
                config = json.load(f)
            
            # Valeurs par défaut si fichier incomplet
            default_config = {
                'host': 'localhost',
                'port': 9200,
                'user': 'elastic',
                'password': 'Protel2025!',
                'index_pattern': 'binance-trades-*',
                'symbol': 'BTCUSDT',
                'use_ssl': False,
                'verify_certs': False
            }
            
            # Override avec les variables d'environnement si disponibles (pour Kubernetes)
            env_overrides = {
                'host': os.getenv('ELK_HOST'),
                'port': int(os.getenv('ELK_PORT', 9200)),
                'user': os.getenv('ELK_USER'),
                'password': os.getenv('ELK_PASSWORD'),
            }
            
            for key, value in env_overrides.items():
                if value is not None:
                    config[key] = value
            
            # Fusionner avec les valeurs par défaut
            for key, value in default_config.items():
                if key not in config:
                    config[key] = value
                    
            return config
            
        except FileNotFoundError:
            self.logger.error(f"❌ Fichier de configuration {config_file} non trouvé")
            self.logger.info("💡 Création d'un fichier de configuration par défaut...")
            
            # Créer un fichier de config par défaut
            default_config = {
                'host': 'localhost',
                'port': 9200,
                'user': 'elastic',
                'password': 'Protel2025!',
                'index_pattern': 'binance-trades-*',
                'symbol': 'BTCUSDT',
                'use_ssl': False,
                'verify_certs': False
            }
            
            with open(config_file, 'w') as f:
                json.dump(default_config, f, indent=2)
                
            self.logger.info(f"✅ Fichier {config_file} créé avec la configuration par défaut")
            self.logger.warning("⚠️ Modifiez les credentials dans elk_config.json si nécessaire")
            
            return default_config
            
        except Exception as e:
            self.logger.error(f"❌ Erreur lecture configuration: {e}")
            sys.exit(1)
    
    def connect_elasticsearch(self) -> bool:
        """Établir la connexion avec votre cluster Elasticsearch"""
        try:
            self.logger.info("🔌 Connexion à Elasticsearch...")
            self.logger.info(f"   Host: {self.config['host']}:{self.config['port']}")
            self.logger.info(f"   User: {self.config['user']}")
            self.logger.info(f"   Index: {self.config['index_pattern']}")
            
            self.es_client = Elasticsearch(
                [f"{'https' if self.config['use_ssl'] else 'http'}://{self.config['host']}:{self.config['port']}"],
                basic_auth=(self.config['user'], self.config['password']),
                verify_certs=self.config['verify_certs']
            )
            
            # Test de connexion
            info = self.es_client.info()
            self.connected = True
            
            self.logger.info("✅ Connexion Elasticsearch réussie!")
            self.logger.info(f"   Cluster: {info['cluster_name']}")
            self.logger.info(f"   Version: {info['version']['number']}")
            
            return True
            
        except Exception as e:
            self.logger.error(f"❌ Erreur connexion Elasticsearch: {e}")
            self.logger.error("💡 Vérifications à effectuer:")
            self.logger.error("   - Cluster ELK-K3s démarré ?")
            self.logger.error("   - kubectl get pods -n elk-stack")
            self.logger.error("   - Configuration réseau /etc/hosts ?")
            self.logger.error("   - Credentials corrects dans elk_config.json ?")
            
            self.connected = False
            return False
    
    def get_latest_binance_data(self, hours_back: int = 168, limit: int = 50000) -> pd.DataFrame:
        """
        Récupérer les données Binance les plus récentes depuis Elasticsearch
        
        Args:
            hours_back: Nombre d'heures de données à récupérer (défaut: 168h = 7 jours)
            limit: Nombre maximum de records (augmenté à 50000 pour couvrir plus d'heures)
            
        Returns:
            DataFrame avec les données OHLCV agrégées par heure
        """
        if not self.connected:
            self.logger.error("❌ Pas de connexion Elasticsearch active")
            return pd.DataFrame()
        
        try:
            # Nouvelle approche: utiliser l'agrégation Elasticsearch pour obtenir des données OHLCV directement
            # avec un échantillonnage distribué sur la période
            query = {
                "size": 0,
                "query": {
                    "bool": {
                        "must": [
                            {"term": {"symbol.keyword": self.config['symbol']}},
                            {"range": {
                                "timestamp": {
                                    "gte": f"now-{hours_back}h",
                                    "lte": "now"
                                }
                            }}
                        ]
                    }
                },
                "aggs": {
                    "price_over_time": {
                        "date_histogram": {
                            "field": "timestamp",
                            "fixed_interval": "1h",
                            "time_zone": "UTC",
                            "min_doc_count": 1
                        },
                        "aggs": {
                            "ohlc": {
                                "stats": {"field": "price"}
                            },
                            "first_price": {
                                "top_hits": {
                                    "size": 1,
                                    "sort": [{"timestamp": {"order": "asc"}}],
                                    "_source": {"includes": ["price"]}
                                }
                            },
                            "last_price": {
                                "top_hits": {
                                    "size": 1,
                                    "sort": [{"timestamp": {"order": "desc"}}],
                                    "_source": {"includes": ["price"]}
                                }
                            },
                            "volume": {
                                "sum": {"field": "quantity"}
                            },
                            "trade_count": {
                                "value_count": {"field": "trade_id"}
                            }
                        }
                    }
                }
            }
            
            self.logger.info(f"🔍 Recherche données {self.config['symbol']} ({hours_back}h)...")
            
            response = self.es_client.search(
                index=self.config['index_pattern'],
                body=query
            )
            
            # Traiter les agrégations
            aggs = response.get('aggregations', {})
            buckets = aggs.get('price_over_time', {}).get('buckets', [])
            
            if not buckets:
                self.logger.warning(f"⚠️ Aucune donnée agrégée trouvée pour {self.config['symbol']}")
                return pd.DataFrame()
            
            self.logger.info(f"📊 {len(buckets)} points horaires OHLCV trouvés")
            
            # Conversion en DataFrame OHLCV
            data = []
            for bucket in buckets:
                timestamp = bucket['key_as_string']
                stats = bucket['ohlc']
                first_hit = bucket.get('first_price', {}).get('hits', {}).get('hits', [])
                last_hit = bucket.get('last_price', {}).get('hits', {}).get('hits', [])
                
                # Obtenir les prix Open et Close
                open_price = first_hit[0]['_source']['price'] if first_hit else stats['min']
                close_price = last_hit[0]['_source']['price'] if last_hit else stats['max']
                
                data.append({
                    'Date': pd.to_datetime(timestamp),
                    'Open': float(open_price),
                    'High': float(stats['max']),
                    'Low': float(stats['min']),
                    'Close': float(close_price),
                    'Volume': float(bucket.get('volume', {}).get('value', 0)),
                    'Trades_Count': int(bucket.get('trade_count', {}).get('value', 0))
                })
            
            df_hourly = pd.DataFrame(data)
            
            if len(df_hourly) == 0:
                self.logger.warning("⚠️ DataFrame OHLCV vide après conversion")
                return df_hourly
            
            self.logger.info(f"✅ {len(df_hourly)} points horaires OHLCV créés")
            if len(df_hourly) > 0:
                self.logger.info(f"📅 Période: {df_hourly['Date'].min()} → {df_hourly['Date'].max()}")
                self.logger.info(f"💰 Prix: {df_hourly['Close'].iloc[-1]:.2f}$ (dernier)")
            
            return df_hourly
            
        except Exception as e:
            self.logger.error(f"❌ Erreur récupération données: {e}")
            return pd.DataFrame()
    
    def create_features(self, prices: np.ndarray, lookback: int = 10) -> np.ndarray:
        """
        Créer les features pour le modèle XGBoost, avec MACD et Bollinger Bands
        """
        features = []
        for i in range(lookback, len(prices)):
            price_features = prices[i-lookback:i].tolist()
            # SMA
            sma_3 = np.mean(prices[i-3:i]) if i >= 3 else prices[i-1]
            sma_5 = np.mean(prices[i-5:i]) if i >= 5 else prices[i-1]
            # Momentum et volatilité
            momentum = prices[i-1] - prices[i-2] if i >= 2 else 0
            volatility = np.std(prices[max(0, i-5):i]) if i >= 5 else 0
            # RSI simplifié
            gains = []
            losses = []
            for j in range(max(1, i-14), i):
                change = prices[j] - prices[j-1] if j > 0 else 0
                if change > 0:
                    gains.append(change)
                else:
                    losses.append(-change)
            avg_gain = np.mean(gains) if gains else 0
            avg_loss = np.mean(losses) if losses else 0.001
            rs = avg_gain / avg_loss
            rsi = 100 - (100 / (1 + rs))
            # MACD
            ema_12 = np.mean(prices[i-12:i]) if i >= 12 else prices[i-1]
            ema_26 = np.mean(prices[i-26:i]) if i >= 26 else prices[i-1]
            macd = ema_12 - ema_26
            # Bollinger Bands
            bb_window = 20
            if i >= bb_window:
                bb_ma = np.mean(prices[i-bb_window:i])
                bb_std = np.std(prices[i-bb_window:i])
                bb_upper = bb_ma + 2 * bb_std
                bb_lower = bb_ma - 2 * bb_std
            else:
                bb_ma = prices[i-1]
                bb_upper = prices[i-1]
                bb_lower = prices[i-1]
            all_features = price_features + [sma_3, sma_5, momentum, volatility, rsi, macd, bb_ma, bb_upper, bb_lower]
            features.append(all_features)
        return np.array(features)
    
    def train_xgboost_model(self, df: pd.DataFrame, target_col: str = 'Close') -> Tuple[Optional[xgb.XGBRegressor], float, float]:
        """
        Entraîner le modèle XGBoost avec early stopping et split train/val/test
        Retourne le modèle, le score validation et le score test
        """
        try:
            if len(df) < 60:
                self.logger.warning(f"⚠️ Pas assez de données: {len(df)} < 60")
                return None, 0.0, 0.0
            prices = df[target_col].values
            prices_scaled = self.scaler.fit_transform(prices.reshape(-1, 1)).flatten()
            X = self.create_features(prices_scaled, lookback=10)
            y = prices_scaled[10:]
            if len(X) < 30:
                self.logger.warning(f"⚠️ Pas assez de features: {len(X)} < 30")
                return None, 0.0, 0.0
            # Split: 70% train, 15% val, 15% test
            n = len(X)
            train_idx = int(0.7 * n)
            val_idx = int(0.85 * n)
            X_train, X_val, X_test = X[:train_idx], X[train_idx:val_idx], X[val_idx:]
            y_train, y_val, y_test = y[:train_idx], y[train_idx:val_idx], y[val_idx:]
            model = xgb.XGBRegressor(
                n_estimators=300,
                max_depth=8,
                learning_rate=0.05,
                subsample=0.8,
                colsample_bytree=0.8,
                random_state=42,
                objective='reg:squarederror',
                verbosity=0,
                n_jobs=-1
            )
            model.fit(
                X_train, y_train,
                eval_set=[(X_val, y_val)],
                early_stopping_rounds=20,
                verbose=False
            )
            y_val_pred = model.predict(X_val)
            y_test_pred = model.predict(X_test)
            mae_val = mean_absolute_error(y_val, y_val_pred)
            mae_test = mean_absolute_error(y_test, y_test_pred)
            self.logger.info(f"✅ Modèle entraîné - MAE val: {mae_val:.6f} | MAE test: {mae_test:.6f}")
            self.last_model = model
            return model, mae_val, mae_test
        except Exception as e:
            self.logger.error(f"❌ Erreur entraînement modèle: {e}")
            return None, 0.0, 0.0
    
    def make_prediction(self, df: pd.DataFrame, target_col: str = 'Close') -> Dict:
        """
        Faire une prédiction pour le prochain prix
        
        Args:
            df: DataFrame avec les données historiques
            target_col: Colonne cible
            
        Returns:
            Dict avec les informations de prédiction
        """
        try:
            # Entraîner le modèle
            model, mae_val, mae_test = self.train_xgboost_model(df, target_col)
            if model is None:
                return {
                    'success': False,
                    'error': 'Erreur entraînement modèle',
                    'timestamp': datetime.now()
                }
            prices = df[target_col].values
            prices_scaled = self.scaler.transform(prices.reshape(-1, 1)).flatten()
            X_pred = self.create_features(prices_scaled, lookback=10)
            if len(X_pred) == 0:
                return {
                    'success': False,
                    'error': 'Pas assez de données pour prédiction',
                    'timestamp': datetime.now()
                }
            next_price_scaled = model.predict(X_pred[-1].reshape(1, -1))[0]
            next_price = self.scaler.inverse_transform([[next_price_scaled]])[0][0]
            current_price = prices[-1]
            current_time = df['Date'].iloc[-1]
            price_change = next_price - current_price
            price_change_pct = (price_change / current_price) * 100
            prediction_info = {
                'success': True,
                'timestamp': datetime.now(),
                'data_timestamp': current_time,
                'current_price': float(current_price),
                'predicted_next_price': float(next_price),
                'price_change': float(price_change),
                'price_change_pct': float(price_change_pct),
                'model_score_val': float(mae_val),
                'model_score_test': float(mae_test),
                'data_points_used': len(df),
                'symbol': self.config['symbol']
            }
            self.predictions_history.append(prediction_info)
            self.save_prediction_to_elasticsearch(prediction_info)
            return prediction_info
        except Exception as e:
            self.logger.error(f"❌ Erreur prédiction: {e}")
            return {
                'success': False,
                'error': str(e),
                'timestamp': datetime.now()
            }
    
    def display_prediction(self, prediction: Dict):
        """Afficher une prédiction de manière formatée avec les scores de validation et test"""
        if not prediction['success']:
            self.logger.error(f"❌ Prédiction échouée: {prediction.get('error', 'Erreur inconnue')}")
            return
        self.logger.info("🎯 " + "="*60)
        self.logger.info(f"🔮 NOUVELLE PRÉDICTION {prediction['symbol']}")
        self.logger.info("🎯 " + "="*60)
        self.logger.info(f"🕐 Timestamp: {prediction['timestamp'].strftime('%Y-%m-%d %H:%M:%S')}")
        self.logger.info(f"📊 Données au: {prediction['data_timestamp']}")
        self.logger.info(f"💰 Prix actuel: ${prediction['current_price']:,.2f}")
        self.logger.info(f"🔮 Prix prédit: ${prediction['predicted_next_price']:,.2f}")
        self.logger.info(f"📈 Changement: {prediction['price_change']:+.2f}$ ({prediction['price_change_pct']:+.2f}%)")
        self.logger.info(f"🎯 MAE validation: {prediction['model_score_val']:.6f}")
        self.logger.info(f"🎯 MAE test: {prediction['model_score_test']:.6f}")
        self.logger.info(f"📊 Points utilisés: {prediction['data_points_used']}")
        # Signal trading
        if prediction['price_change_pct'] > 2:
            self.logger.info("🟢 SIGNAL: ACHAT FORT recommandé (>2%)")
        elif prediction['price_change_pct'] > 0.5:
            self.logger.info("🟢 Signal: Achat potentiel (0.5-2%)")
        elif prediction['price_change_pct'] < -2:
            self.logger.info("🔴 SIGNAL: VENTE FORTE recommandée (<-2%)")
        elif prediction['price_change_pct'] < -0.5:
            self.logger.info("🔴 Signal: Vente potentielle (-0.5 à -2%)")
        else:
            self.logger.info("🟡 Signal: HOLD - Mouvement faible")
    
    def save_prediction_to_elasticsearch(self, prediction: Dict) -> bool:
        """
        Sauvegarder une prédiction dans Elasticsearch pour visualisation Kibana
        
        Args:
            prediction: Dict avec les informations de prédiction
            
        Returns:
            bool: True si succès
        """
        if not self.connected or not prediction['success']:
            return False
        
        try:
            # Index spécialisé pour les prédictions
            index_name = f"binance-predictions-{datetime.now().strftime('%Y.%m')}"
            
            # Document à indexer
            doc = {
                '@timestamp': prediction['timestamp'].isoformat(),
                'data_timestamp': prediction['data_timestamp'].isoformat() if isinstance(prediction.get('data_timestamp'), (pd.Timestamp, datetime)) else prediction.get('data_timestamp'),
                'symbol': prediction['symbol'],
                'current_price': prediction['current_price'],
                'predicted_next_price': prediction['predicted_next_price'],
                'price_change': prediction['price_change'],
                'price_change_pct': prediction['price_change_pct'],
                'model_score': prediction['model_score'],
                'data_points_used': prediction['data_points_used'],
                'prediction_type': 'realtime_xgboost',
                'service_version': '1.0',
                # Signaux de trading
                'trading_signal': self._get_trading_signal(prediction['price_change_pct']),
                'signal_strength': self._get_signal_strength(prediction['price_change_pct']),
                # Métadonnées
                'prediction_interval_seconds': 3600,  # 1h par défaut
                'model_features': 15,  # Nombre de features utilisées
                'confidence_level': min(1.0, max(0.0, 1.0 - prediction['model_score']))
            }
            
            # Indexer dans Elasticsearch
            response = self.es_client.index(
                index=index_name,
                body=doc
            )
            
            self.logger.info(f"📊 Prédiction sauvée dans Elasticsearch: {index_name}")
            return True
            
        except Exception as e:
            self.logger.error(f"❌ Erreur sauvegarde Elasticsearch: {e}")
            return False
    
    def _get_trading_signal(self, price_change_pct: float) -> str:
        """Déterminer le signal de trading basé sur le changement de prix"""
        if price_change_pct > 2:
            return "STRONG_BUY"
        elif price_change_pct > 0.5:
            return "BUY"
        elif price_change_pct < -2:
            return "STRONG_SELL"
        elif price_change_pct < -0.5:
            return "SELL"
        else:
            return "HOLD"
    
    def _get_signal_strength(self, price_change_pct: float) -> float:
        """Calculer la force du signal (0-1)"""
        abs_change = abs(price_change_pct)
        if abs_change > 5:
            return 1.0
        elif abs_change > 2:
            return 0.8
        elif abs_change > 1:
            return 0.6
        elif abs_change > 0.5:
            return 0.4
        else:
            return 0.2

    def save_predictions_history(self, filename: str = None):
        """Sauvegarder l'historique des prédictions"""
        if not self.predictions_history:
            self.logger.warning("⚠️ Aucune prédiction à sauvegarder")
            return
        
        if filename is None:
            timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
            filename = f'predictions_history_{timestamp}.json'
        
        try:
            # Convertir les timestamps en string pour JSON
            history_json = []
            for pred in self.predictions_history:
                pred_copy = pred.copy()
                pred_copy['timestamp'] = pred_copy['timestamp'].isoformat()
                if isinstance(pred_copy.get('data_timestamp'), (pd.Timestamp, datetime)):
                    pred_copy['data_timestamp'] = pred_copy['data_timestamp'].isoformat()
                history_json.append(pred_copy)
            
            with open(filename, 'w') as f:
                json.dump(history_json, f, indent=2, default=str)
            
            self.logger.info(f"💾 Historique sauvé: {filename} ({len(history_json)} prédictions)")
            
        except Exception as e:
            self.logger.error(f"❌ Erreur sauvegarde: {e}")
    
    def run_continuous_predictions(self, interval_seconds: int = 60, max_predictions: int = 10):
        """
        Lancer des prédictions continues
        
        Args:
            interval_seconds: Intervalle entre les prédictions
            max_predictions: Nombre maximum de prédictions
        """
        self.logger.info("🚀 " + "="*70)
        self.logger.info("🚀 DÉMARRAGE PRÉDICTIONS CONTINUES - BINANCE ELK STACK")
        self.logger.info("🚀 " + "="*70)
        self.logger.info(f"⏱️  Intervalle: {interval_seconds} secondes")
        self.logger.info(f"🎯 Max prédictions: {max_predictions}")
        self.logger.info(f"📊 Symbole: {self.config['symbol']}")
        self.logger.info("⏹️  Ctrl+C pour arrêter")
        
        prediction_count = 0
        
        try:
            while prediction_count < max_predictions:
                start_time = time.time()
                
                self.logger.info(f"\n🔄 Prédiction #{prediction_count + 1} à {datetime.now().strftime('%H:%M:%S')}")
                
                # Récupérer les données fraîches
                df = self.get_latest_binance_data(hours_back=168, limit=50000)
                
                if len(df) < 20:
                    self.logger.warning(f"⚠️ Pas assez de données: {len(df)} points")
                    self.logger.info("💡 Vérifiez que le binance-backend collecte bien les données")
                else:
                    # Faire la prédiction
                    prediction = self.make_prediction(df)
                    
                    # Afficher le résultat
                    self.display_prediction(prediction)
                
                prediction_count += 1
                
                # Pause avant la prochaine prédiction
                if prediction_count < max_predictions:
                    execution_time = time.time() - start_time
                    sleep_time = max(0, interval_seconds - execution_time)
                    
                    if sleep_time > 0:
                        self.logger.info(f"⏳ Attente {sleep_time:.1f}s...")
                        time.sleep(sleep_time)
                
        except KeyboardInterrupt:
            self.logger.info("\n⏹️ Arrêt demandé par l'utilisateur")
        
        # Sauvegarder l'historique
        if self.predictions_history:
            self.save_predictions_history()
        
        self.logger.info(f"\n🏁 PRÉDICTIONS TERMINÉES - {len(self.predictions_history)} prédictions réalisées")

def main():
    """Fonction principale"""
    parser = argparse.ArgumentParser(description='Service de Prédiction Temps Réel Binance ELK')
    parser.add_argument('--config', default='elk_config.json', 
                       help='Fichier de configuration ELK (défaut: elk_config.json)')
    parser.add_argument('--interval', type=int, default=60,
                       help='Intervalle entre prédictions en secondes (défaut: 60)')
    parser.add_argument('--predictions', type=int, default=10,
                       help='Nombre maximum de prédictions (défaut: 10)')
    parser.add_argument('--single', action='store_true',
                       help='Faire une seule prédiction et arrêter')
    parser.add_argument('--test-connection', action='store_true',
                       help='Tester uniquement la connexion ELK')
    
    args = parser.parse_args()
    
    # Initialiser le service
    predictor = ElkRealtimePredictor(args.config)
    
    # Tester la connexion
    if not predictor.connect_elasticsearch():
        sys.exit(1)
    
    if args.test_connection:
        predictor.logger.info("✅ Test de connexion réussi!")
        return
    
    if args.single:
        # Prédiction unique
        predictor.logger.info("🎯 Mode prédiction unique")
        df = predictor.get_latest_binance_data(hours_back=168, limit=50000)
        
        if len(df) < 20:
            predictor.logger.error("❌ Pas assez de données pour prédiction")
            return
        
        prediction = predictor.make_prediction(df)
        predictor.display_prediction(prediction)
        predictor.save_predictions_history()
        
    else:
        # Prédictions continues
        predictor.run_continuous_predictions(args.interval, args.predictions)

if __name__ == "__main__":
    main()
