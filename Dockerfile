FROM python:3.11-slim

# Installer FFmpeg et autres dépendances
RUN apt-get update && apt-get install -y \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/*

# Créer le répertoire de travail
WORKDIR /app

# Copier les fichiers requirements
COPY requirements.txt .

# Installer les dépendances Python
RUN pip install --no-cache-dir -r requirements.txt

# Copier le code
COPY . .

# Variables d'environnement par défaut
ENV PORT=8080
ENV TEMP_DIR=/tmp

# Exposer le port
EXPOSE 8080

# Commande de démarrage
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--timeout", "120", "server:app"]
