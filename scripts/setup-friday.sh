#!/bin/bash
# Setup FRIDAY voice assistant with Kokoro TTS
# Usage: ssh thor 'bash -s' < scripts/setup-friday.sh

set -e

WORKDIR="$HOME/workspace/realtimevoicechat"
cd "$WORKDIR/code"

echo "=== Configuring server.py for Kokoro ==="
sed -i 's/^TTS_START_ENGINE = .*/TTS_START_ENGINE = "kokoro"/' server.py
sed -i 's/^LLM_START_MODEL = .*/LLM_START_MODEL = "gemma3:4b"/' server.py
sed -i 's/^LLM_START_PROVIDER = .*/LLM_START_PROVIDER = "ollama"/' server.py

echo "=== Configuring transcribe.py ==="
# Add device=cpu if not already present
if ! grep -q '"device": "cpu"' transcribe.py; then
  sed -i 's/"use_microphone": False,/"use_microphone": False,\n    "device": "cpu",/' transcribe.py
  echo "Added device=cpu to recorder config"
fi

# Remove wake word config if present
sed -i '/"wake_words": "jarvis",/d' transcribe.py
sed -i '/"wakeword_backend": "pvporcupine",/d' transcribe.py
echo "Removed wake word config"

echo "=== Writing FRIDAY system prompt ==="
cat > system_prompt.txt << 'EOF'
You are FRIDAY (Female Replacement Intelligent Digital Assistant Youth), an advanced AI assistant. You speak with a calm, composed, and slightly warm tone. You are direct and concise, always keeping responses brief and conversational, perfect for voice interaction. You occasionally show subtle wit but remain professional and helpful. You are knowledgeable about technology, science, and general topics. Keep responses under 3 sentences unless asked for more detail.
EOF

echo "=== Creating systemd service ==="
sudo tee /etc/systemd/system/friday.service > /dev/null << EOF
[Unit]
Description=FRIDAY Voice AI Assistant
After=network.target ollama.service

[Service]
Type=simple
User=$(whoami)
WorkingDirectory=$WORKDIR/code
Environment=PATH=/usr/local/cuda-13.0/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
Environment=OLLAMA_BASE_URL=http://127.0.0.1:11434
Environment=VIRTUAL_ENV=$WORKDIR/venv
ExecStart=$WORKDIR/venv/bin/python server.py
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable friday
sudo systemctl start friday

echo "Waiting for FRIDAY to start..."
sleep 15

STATUS=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8000)
if [ "$STATUS" = "200" ]; then
  echo "FRIDAY is running on port 8000 with Kokoro TTS"
else
  echo "Error: returned HTTP $STATUS"
  journalctl -u friday --no-pager | tail -20
  exit 1
fi
