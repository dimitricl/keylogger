#!/bin/bash
# Installation v3 avec cloudscraper
cd "$(dirname "$0")"
if [ ! -d "venv" ]; then
    python3 -m venv venv
fi
venv/bin/pip install -q --upgrade pip
venv/bin/pip install -q pynput requests cloudscraper
echo "✅ v3 installé (avec contournement Cloudflare)"
