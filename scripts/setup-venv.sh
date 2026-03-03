#!/bin/bash
# Setup Python venv with all dependencies for RealtimeVoiceChat + Kokoro on Jetson
# Usage: ssh thor 'bash -s' < scripts/setup-venv.sh

set -e

WORKDIR="$HOME/workspace/realtimevoicechat"

echo "=== Cloning RealtimeVoiceChat ==="
mkdir -p "$HOME/workspace"
git clone https://github.com/KoljaB/RealtimeVoiceChat.git "$WORKDIR" 2>/dev/null || echo "Already cloned"
cd "$WORKDIR"

echo "=== Creating venv ==="
python3 -m venv venv
source venv/bin/activate

echo "=== Installing PyTorch with CUDA (Jetson aarch64) ==="
pip install torch --index-url https://download.pytorch.org/whl/cu130

echo "=== Installing base requirements ==="
pip install -r requirements.txt 2>/dev/null || echo "requirements.txt not found, installing manually"

echo "=== Installing dependencies ==="
pip install sse-starlette starlette-context pydantic-settings
pip install snac einops transformers requests pydub resampy
pip install stream2sentence numba sounddevice scipy halo
pip install openwakeword kokoro

echo "=== Patching pvporcupine (unsupported on aarch64) ==="
RECORDER_FILE="venv/lib/python3.12/site-packages/RealtimeSTT/audio_recorder.py"
if [ -f "$RECORDER_FILE" ]; then
  sed -i 's/^import pvporcupine/# import pvporcupine  # Patched: unsupported on aarch64/' "$RECORDER_FILE"
  echo "Patched: commented out pvporcupine import"
fi
pip uninstall -y pvporcupine 2>/dev/null || true

echo ""
echo "Done! Activate with: source $WORKDIR/venv/bin/activate"
