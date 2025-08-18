#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from flask import Flask, request, jsonify
from flask_cors import CORS
import os
import yt_dlp
import uuid
from datetime import datetime
import tempfile

app = Flask(__name__)
CORS(app)

# Configuration
API_KEY = os.environ.get('API_KEY', 'sk_prod_2025_youtube_shorts_secure_key_xyz789')
BASE_URL = os.environ.get('BASE_URL', 'https://your-app.up.railway.app')
TEMP_DIR = os.environ.get('TEMP_DIR', '/tmp')

# Stockage temporaire des URLs de vidéos
VIDEO_STORAGE = {}

@app.route('/')
def home():
    """Page d'accueil avec infos API"""
    return jsonify({
        "service": "YouTube Shorts Automation API",
        "version": "1.0.0",
        "status": "operational",
        "endpoints": {
            "POST /download": "Télécharge une vidéo YouTube",
            "GET /status": "Statut du service",
            "GET /health": "Vérification santé"
        },
        "documentation": {
            "authentication": "Header 'X-API-Key' requis",
            "example": "curl -X POST /download -H 'X-API-Key: YOUR_KEY' -H 'Content-Type: application/json' -d '{\"video_url\": \"https://youtube.com/watch?v=...\"}'",
        }
    })

@app.route('/health')
def health():
    """Endpoint de santé pour Railway"""
    return jsonify({
        "status": "healthy",
        "timestamp": datetime.now().isoformat()
    })

@app.route('/download', methods=['POST'])
def download_video():
    """Télécharge une vidéo YouTube et retourne les infos"""
    
    # Vérifier l'API Key
    api_key = request.headers.get('X-API-Key')
    if api_key != API_KEY:
        return jsonify({"error": "API Key invalide ou manquante"}), 401
    
    try:
        # Récupérer l'URL de la vidéo
        data = request.get_json()
        if not data or 'video_url' not in data:
            return jsonify({"error": "URL de vidéo manquante"}), 400
        
        video_url = data['video_url']
        
        # Générer un ID unique pour cette vidéo
        video_id = str(uuid.uuid4())
        
        # Configuration yt-dlp
        ydl_opts = {
            'format': 'best[ext=mp4]/best',
            'outtmpl': os.path.join(TEMP_DIR, f'{video_id}.%(ext)s'),
            'quiet': True,
            'no_warnings': True,
            'extract_flat': False,
        }
        
        # Extraire les infos de la vidéo
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            print(f"[INFO] Extraction des infos pour: {video_url}")
            info = ydl.extract_info(video_url, download=False)
            
            # Infos importantes
            video_info = {
                "title": info.get('title', 'Sans titre'),
                "duration": info.get('duration', 0),
                "channel": info.get('channel', 'Inconnu'),
                "upload_date": info.get('upload_date', ''),
                "view_count": info.get('view_count', 0),
                "like_count": info.get('like_count', 0),
                "description": info.get('description', '')[:500],  # Limiter la description
                "thumbnail": info.get('thumbnail', ''),
                "video_id": video_id
            }
            
            # Télécharger la vidéo
            print(f"[INFO] Téléchargement de: {video_info['title']}")
            ydl.download([video_url])
            
            # Trouver le fichier téléchargé
            downloaded_file = None
            for ext in ['mp4', 'webm', 'mkv']:
                file_path = os.path.join(TEMP_DIR, f'{video_id}.{ext}')
                if os.path.exists(file_path):
                    downloaded_file = file_path
                    break
            
            if not downloaded_file:
                return jsonify({"error": "Échec du téléchargement"}), 500
            
            # Obtenir la taille du fichier
            file_size = os.path.getsize(downloaded_file)
            
            # Stocker les infos
            VIDEO_STORAGE[video_id] = {
                "file_path": downloaded_file,
                "info": video_info,
                "downloaded_at": datetime.now().isoformat(),
                "file_size_mb": round(file_size / (1024 * 1024), 2)
            }
            
            # Retourner les infos
            return jsonify({
                "success": True,
                "video_id": video_id,
                "video_info": video_info,
                "file_size_mb": round(file_size / (1024 * 1024), 2),
                "message": f"Vidéo téléchargée avec succès: {video_info['title']}",
                "next_step": "Utilisez /process-short avec ce video_id pour créer des shorts"
            })
    
    except yt_dlp.utils.DownloadError as e:
        print(f"[ERROR] Erreur yt-dlp: {str(e)}")
        return jsonify({
            "error": "Erreur de téléchargement",
            "details": str(e),
            "tips": "Vérifiez que l'URL est valide et que la vidéo est publique"
        }), 400
    
    except Exception as e:
        print(f"[ERROR] Erreur inattendue: {str(e)}")
        return jsonify({
            "error": "Erreur serveur",
            "details": str(e)
        }), 500

@app.route('/status')
def status():
    """Statut du service et vidéos en mémoire"""
    
    # Nettoyer les vieilles vidéos (plus de 1 heure)
    current_time = datetime.now()
    videos_to_remove = []
    
    for vid_id, data in VIDEO_STORAGE.items():
        downloaded_time = datetime.fromisoformat(data['downloaded_at'])
        if (current_time - downloaded_time).seconds > 3600:  # 1 heure
            videos_to_remove.append(vid_id)
            # Supprimer le fichier
            try:
                os.remove(data['file_path'])
                print(f"[CLEANUP] Fichier supprimé: {data['file_path']}")
            except:
                pass
    
    # Supprimer de la mémoire
    for vid_id in videos_to_remove:
        del VIDEO_STORAGE[vid_id]
    
    # Préparer la réponse
    videos_list = []
    total_size = 0
    
    for vid_id, data in VIDEO_STORAGE.items():
        videos_list.append({
            "video_id": vid_id,
            "title": data['info']['title'],
            "duration": data['info']['duration'],
            "size_mb": data['file_size_mb'],
            "downloaded_at": data['downloaded_at']
        })
        total_size += data['file_size_mb']
    
    return jsonify({
        "status": "operational",
        "videos_count": len(VIDEO_STORAGE),
        "total_size_mb": round(total_size, 2),
        "videos": videos_list,
        "server_info": {
            "temp_dir": TEMP_DIR,
            "cleanup_after": "1 hour",
            "yt_dlp_version": yt_dlp.version.__version__
        }
    })

# Route de test pour n8n
@app.route('/test', methods=['POST'])
def test_endpoint():
    """Endpoint de test pour vérifier la connexion depuis n8n"""
    api_key = request.headers.get('X-API-Key')
    if api_key != API_KEY:
        return jsonify({"error": "API Key invalide"}), 401
    
    return jsonify({
        "success": True,
        "message": "Connexion réussie !",
        "timestamp": datetime.now().isoformat(),
        "ready_for": "YouTube video download"
    })

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 5000))
    
    print("="*60)
    print("🎥 YouTube Shorts Automation Server")
    print("="*60)
    print(f"📍 Port: {port}")
    print(f"🔑 API Key: {API_KEY[:10]}...")
    print(f"📁 Temp Dir: {TEMP_DIR}")
    print(f"🌐 Base URL: {BASE_URL}")
    print("="*60)
    print("📝 Endpoints:")
    print("   POST /download - Télécharger une vidéo YouTube")
    print("   GET  /status   - Voir les vidéos téléchargées")
    print("   POST /test     - Tester la connexion")
    print("="*60)
    
    app.run(host='0.0.0.0', port=port, debug=True)
