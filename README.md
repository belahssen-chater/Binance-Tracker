# ELK Stack Kubernetes avec Authentification

Stack ELK (Elasticsearch, Logstash, Kibana) déployée sur Kubernetes avec authentification sécurisée.

## 🔐 Identifiants d'authentification

- **Utilisateur** : `chater`
- **Mot de passe** : `Protel2025!`

## 🚀 Déploiement rapide

### Option 1 : Déploiement automatique complet
```bash
./quick-deploy.sh
```
Ce script fait tout automatiquement :
- Déploie la stack ELK
- Configure /etc/hosts
- Teste l'authentification

### Option 2 : Déploiement manuel étape par étape

1. **Déployer la stack** :
```bash
./deploy.sh
```

2. **Configurer /etc/hosts** :
```bash
./setup-hosts.sh
```

3. **Tester l'authentification** :
```bash
./test-auth.sh
```

## 🌐 Accès aux services

Une fois déployé et /etc/hosts configuré :

- **Kibana** : http://kibana.local
- **Elasticsearch** : http://elasticsearch.local  
- **Logstash** : http://logstash.local

### Connexion
- **Utilisateur** : `chater`
- **Mot de passe** : `Protel2025!`

## 📁 Structure des fichiers

### Fichiers de configuration Kubernetes :
- `namespace.yaml` - Namespace elk-stack
- `elasticsearch.yaml` - Déploiement Elasticsearch avec auth
- `elasticsearch-config.yaml` - Configuration Elasticsearch
- `elasticsearch-storage.yaml` - Stockage persistant
- `kibana.yaml` - Déploiement Kibana avec auth
- `kibana-config.yaml` - Configuration Kibana
- `logstash.yaml` - Déploiement Logstash
- `logstash-config.yaml` - Configuration Logstash
- `ingress.yaml` - Règles d'ingress Traefik

### Fichiers d'authentification :
- `elk-credentials.yaml` - Secrets Kubernetes
- `elasticsearch-user-setup.yaml` - Job de création utilisateur

### Scripts :
- `quick-deploy.sh` - Déploiement automatique complet
- `deploy.sh` - Déploiement de la stack
- `setup-hosts.sh` - Configuration /etc/hosts
- `test-auth.sh` - Tests d'authentification

### Documentation :
- `README-Auth.md` - Documentation authentification détaillée
- `MODIFICATIONS-SUMMARY.md` - Résumé des modifications

## 🔧 Binance Backend (optionnel)

Pour déployer aussi le backend Binance WebSocket :
```bash
./deploy.sh --with-binance
```

## 📊 Monitoring et logs

### Vérifier le statut des pods :
```bash
kubectl get pods -n elk-stack
```

### Voir les logs :
```bash
# Elasticsearch
kubectl logs -f deployment/elasticsearch -n elk-stack

# Kibana  
kubectl logs -f deployment/kibana -n elk-stack

# Logstash
kubectl logs -f deployment/logstash -n elk-stack
```

### Envoyer des données test :
```bash
# Via HTTP
curl -X POST http://logstash.local \
  -H "Content-Type: application/json" \
  -d '{"message": "Test log", "timestamp": "'$(date -Iseconds)'"}'

# Via TCP
echo '{"message": "Test TCP log"}' | nc logstash.local 5000
```

## 🛠️ Dépannage

### Problème de connexion Kibana :
1. Vérifier qu'Elasticsearch est démarré
2. Vérifier que le job de setup utilisateur s'est bien exécuté :
```bash
kubectl logs job/elasticsearch-setup-users -n elk-stack
```

### Problème /etc/hosts :
```bash
# Vérifier les entrées
grep -E "(kibana|elasticsearch|logstash)\.local" /etc/hosts

# Reconfigurer si nécessaire  
./setup-hosts.sh
```

### Test manuel de l'API Elasticsearch :
```bash
curl -u chater:Protel2025! http://elasticsearch.local/_cluster/health
```

## 🗑️ Nettoyage

Pour supprimer complètement la stack :
```bash
kubectl delete namespace elk-stack
```

Pour nettoyer /etc/hosts :
```bash
sudo sed -i '/kibana\.local\|elasticsearch\.local\|logstash\.local/d' /etc/hosts
```

## 🔒 Sécurité

- ✅ Authentification activée sur Elasticsearch et Kibana
- ✅ Mots de passe stockés dans des secrets Kubernetes
- ✅ Utilisateur personnalisé `chater` avec droits superuser
- ⚠️ SSL/TLS désactivé pour simplifier (recommandé pour la production)

## 📚 Documentation additionnelle

- [Documentation authentification complète](README-Auth.md)
- [Résumé des modifications](MODIFICATIONS-SUMMARY.md)
