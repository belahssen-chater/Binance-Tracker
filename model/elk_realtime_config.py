"""
Configuration ELK Temps Réel - Binance Predictions
=================================================

Ce fichier configure la connexion à votre stack ELK-K3s pour les prédictions temps réel.

Pour utiliser le service de prédiction:
1. Modifiez les paramètres ci-dessous selon votre environnement
2. Assurez-vous que votre cluster ELK-K3s est actif
3. Lancez: python realtime_prediction_service.py
"""

import json
import os
from datetime import datetime

class ElkRealtimeConfig:
    """Configuration pour le service de prédiction temps réel"""
    
    def __init__(self):
        # Configuration de base ELK Stack
        self.elk_config = {
            # 🔧 Configuration Elasticsearch - À adapter selon votre environnement
            "host": "localhost",                    # IP de votre cluster K3s ou localhost
            "port": 9200,                          # Port Elasticsearch (standard: 9200)
            "user": "chater",                      # Utilisateur ELK (défini dans votre stack)
            "password": "Protel2025!",             # ⚠️ Mot de passe à modifier si différent
            "use_ssl": False,                      # SSL désactivé pour K3s local
            "verify_certs": False,                 # Vérification certificats
            
            # 📊 Configuration des données Binance
            "index_pattern": "binance-trades-*",   # Pattern des index Elasticsearch
            "symbol": "BTCUSDT",                   # Symbole crypto à analyser
            
            # 🔍 Paramètres de requête
            "default_lookback_hours": 48,          # Heures de données à récupérer
            "max_records": 2000,                   # Nombre max de records par requête
            
            # 🤖 Configuration du modèle
            "model_config": {
                "lookback_window": 10,             # Fenêtre de données historiques
                "min_training_samples": 50,        # Minimum d'échantillons pour entraînement
                "validation_split": 0.8,           # Ratio train/validation
                "xgboost_params": {
                    "n_estimators": 100,
                    "max_depth": 6,
                    "learning_rate": 0.1,
                    "subsample": 0.8,
                    "colsample_bytree": 0.8,
                    "random_state": 42
                }
            },
            
            # ⏱️ Configuration temps réel
            "realtime_config": {
                "default_interval_seconds": 60,    # Intervalle entre prédictions
                "default_max_predictions": 10,     # Nombre max de prédictions continues
                "save_predictions": True,           # Sauvegarder l'historique
                "log_level": "INFO"                # Niveau de logging
            }
        }
    
    def save_config(self, filename: str = "elk_config.json"):
        """Sauvegarder la configuration dans un fichier JSON"""
        try:
            with open(filename, 'w') as f:
                json.dump(self.elk_config, f, indent=2)
            print(f"✅ Configuration sauvée: {filename}")
            return True
        except Exception as e:
            print(f"❌ Erreur sauvegarde: {e}")
            return False
    
    def load_config(self, filename: str = "elk_config.json") -> dict:
        """Charger la configuration depuis un fichier JSON"""
        try:
            if os.path.exists(filename):
                with open(filename, 'r') as f:
                    loaded_config = json.load(f)
                
                # Fusionner avec la config par défaut
                self.elk_config.update(loaded_config)
                print(f"✅ Configuration chargée: {filename}")
            else:
                print(f"⚠️ Fichier {filename} non trouvé, utilisation config par défaut")
                self.save_config(filename)
            
            return self.elk_config
            
        except Exception as e:
            print(f"❌ Erreur chargement: {e}")
            return self.elk_config
    
    def validate_connection_config(self) -> bool:
        """Valider la configuration de connexion"""
        required_fields = ['host', 'port', 'user', 'password', 'index_pattern', 'symbol']
        
        for field in required_fields:
            if field not in self.elk_config or not self.elk_config[field]:
                print(f"❌ Configuration manquante: {field}")
                return False
        
        print("✅ Configuration de connexion valide")
        return True
    
    def get_cluster_info_commands(self) -> list:
        """Retourner les commandes pour vérifier le cluster ELK"""
        return [
            "# Vérifier le statut du cluster ELK-K3s",
            "kubectl get pods -n elk-stack",
            "kubectl get services -n elk-stack",
            "",
            "# Vérifier les logs",
            "kubectl logs -f deployment/elasticsearch -n elk-stack",
            "kubectl logs -f deployment/logstash -n elk-stack",
            "kubectl logs -f deployment/binance-backend -n elk-stack",
            "",
            "# Tester l'API Elasticsearch",
            f"curl -u {self.elk_config['user']}:{self.elk_config['password']} http://{self.elk_config['host']}:{self.elk_config['port']}/_cluster/health",
            "",
            "# Vérifier les index Binance",
            f"curl -u {self.elk_config['user']}:{self.elk_config['password']} http://{self.elk_config['host']}:{self.elk_config['port']}/_cat/indices/{self.elk_config['index_pattern']}"
        ]
    
    def print_setup_instructions(self):
        """Afficher les instructions de configuration"""
        print("🚀 " + "="*70)
        print("🚀 INSTRUCTIONS CONFIGURATION ELK TEMPS RÉEL")
        print("🚀 " + "="*70)
        print()
        
        print("1️⃣ VÉRIFIER LE CLUSTER ELK-K3S:")
        for cmd in self.get_cluster_info_commands():
            if cmd.startswith("#"):
                print(f"   {cmd}")
            elif cmd.strip():
                print(f"   $ {cmd}")
            else:
                print()
        
        print()
        print("2️⃣ CONFIGURATION RÉSEAU:")
        print("   - Vérifier /etc/hosts pour les domaines locaux")
        print("   - Ou modifier 'host' dans elk_config.json avec l'IP du cluster")
        print()
        
        print("3️⃣ CREDENTIALS:")
        print(f"   - User: {self.elk_config['user']}")
        print(f"   - Password: {self.elk_config['password']}")
        print("   - Modifier elk_config.json si nécessaire")
        print()
        
        print("4️⃣ DONNÉES BINANCE:")
        print("   - Vérifier que binance-backend collecte les données")
        print("   - Index pattern: binance-trades-*")
        print(f"   - Symbole: {self.elk_config['symbol']}")
        print()
        
        print("5️⃣ LANCEMENT:")
        print("   # Prédiction unique")
        print("   python realtime_prediction_service.py --single")
        print()
        print("   # Prédictions continues (intervalle 30s, 5 prédictions)")
        print("   python realtime_prediction_service.py --interval 30 --predictions 5")
        print()
        print("   # Test de connexion seulement")
        print("   python realtime_prediction_service.py --test-connection")
        print()
        print("="*70)

def main():
    """Fonction principale pour initialiser la configuration"""
    print("🔧 Configuration ELK Temps Réel - Service de Prédiction Binance")
    print("="*65)
    
    # Créer la configuration
    config = ElkRealtimeConfig()
    
    # Valider
    if config.validate_connection_config():
        # Sauvegarder
        config.save_config()
        
        # Afficher les instructions
        config.print_setup_instructions()
        
        print(f"✅ Configuration prête!")
        print(f"📁 Fichier créé: elk_config.json")
        print(f"🚀 Lancez: python realtime_prediction_service.py")
    
    else:
        print("❌ Configuration invalide")

if __name__ == "__main__":
    main()
