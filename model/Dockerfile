FROM python:3.11-slim

# Définir le répertoire de travail
WORKDIR /app

# Installer les dépendances système
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    && rm -rf /var/lib/apt/lists/*

# Copier et installer les dépendances Python
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copier le service de prédiction et la configuration
COPY realtime_prediction_service.py .
COPY elk_config.json .

# Créer un utilisateur non-root pour la sécurité
RUN useradd -m -u 1000 predictor && chown -R predictor:predictor /app
USER predictor

# Créer le répertoire pour les logs
RUN mkdir -p /app/logs

# Variables d'environnement
ENV PYTHONPATH=/app
ENV PYTHONUNBUFFERED=1

# Commande par défaut - prédictions continues
CMD ["python", "realtime_prediction_service.py", "--predictions", "1000", "--interval", "60"]
