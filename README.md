# Jetson Kokoro Voice Chat

Real-time voice assistant (FRIDAY) on NVIDIA Jetson AGX Thor using [RealtimeVoiceChat](https://github.com/KoljaB/RealtimeVoiceChat) with **Kokoro TTS**.

> This is the working configuration after benchmarking TTS engines. See [jetson-realtime-voice-chat](https://github.com/bujosa/jetson-realtime-voice-chat) for the full research, Jetson ARM64 fixes, and Orpheus TTS benchmarks.
>
> For the base Ollama + Open WebUI setup, see [thor-ai-setup](https://github.com/bujosa/thor-ai-setup).

![FRIDAY Voice Chat](assets/friday-voice-chat.png)

*FRIDAY running on Jetson Thor — real-time voice conversation about quantum computing. STT by Whisper base.en, LLM by Gemma 3 4B, TTS by Kokoro 82M (af_heart voice).*

## Stack

```
Browser (mic) --WebSocket--> FRIDAY server (:8000)
                                |
                    +-----------+-----------+
                    |           |           |
               STT (Whisper)  LLM (Ollama)  TTS (Kokoro)
               faster_whisper  gemma3:4b    82M params
               base.en (CPU)  :11434 (GPU)  inline (CPU)
```

| Component | Model | Speed |
|-----------|-------|-------|
| **STT** | Whisper base.en | Real-time on CPU (14 ARM cores) |
| **LLM** | Gemma 3 4B | ~47 tok/s on GPU |
| **TTS** | Kokoro 82M (`af_heart`) | ~192ms latency, zero slow chunks |

**Total pipeline latency: ~800ms** (LLM: 608ms + TTS: 192ms)

## Hardware

| Spec | Value |
|------|-------|
| **Board** | NVIDIA Jetson AGX Thor |
| **CPU** | 14-core ARM (Cortex-A78AE) |
| **GPU** | NVIDIA Thor (Blackwell), CUDA 13.0 |
| **RAM** | 128 GB LPDDR5X (unified) |
| **JetPack** | 7.0-b128 |

## Setup

### 1. Prerequisites

Ollama must be running with `gemma3:4b` available. See [thor-ai-setup](https://github.com/bujosa/thor-ai-setup).

### 2. Install

```bash
# Run all setup scripts in order
ssh thor 'bash -s' < scripts/setup-venv.sh
ssh thor 'bash -s' < scripts/setup-friday.sh
```

Or manually:

```bash
ssh thor
cd ~/workspace
git clone https://github.com/KoljaB/RealtimeVoiceChat.git realtimevoicechat
cd realtimevoicechat
python3 -m venv venv
source venv/bin/activate

# PyTorch with CUDA (required for Jetson aarch64)
pip install torch --index-url https://download.pytorch.org/whl/cu130

# Dependencies
pip install -r requirements.txt
pip install sse-starlette starlette-context pydantic-settings
pip install snac einops transformers requests pydub resampy
pip install stream2sentence numba sounddevice scipy halo
pip install openwakeword kokoro

# Patch pvporcupine (not supported on aarch64)
sed -i 's/^import pvporcupine/# import pvporcupine/' \
  venv/lib/python3.12/site-packages/RealtimeSTT/audio_recorder.py
pip uninstall -y pvporcupine 2>/dev/null
```

### 3. Configure

**`code/server.py`:**

```python
TTS_START_ENGINE = "kokoro"
LLM_START_PROVIDER = "ollama"
LLM_START_MODEL = "gemma3:4b"
```

**`code/transcribe.py`** — edit `DEFAULT_RECORDER_CONFIG`:

```python
DEFAULT_RECORDER_CONFIG = {
    "use_microphone": False,
    "device": "cpu",           # ADD: CTranslate2 has no CUDA on aarch64
    "spinner": False,
    # ...
    # "wake_words": "jarvis",          # REMOVE
    # "wakeword_backend": "pvporcupine",  # REMOVE
    # ...
}
```

**`code/system_prompt.txt`:**

```
You are FRIDAY (Female Replacement Intelligent Digital Assistant Youth), an advanced AI assistant. You speak with a calm, composed, and slightly warm tone. You are direct and concise, always keeping responses brief and conversational, perfect for voice interaction. You occasionally show subtle wit but remain professional and helpful. You are knowledgeable about technology, science, and general topics. Keep responses under 3 sentences unless asked for more detail.
```

### 4. Systemd Service

```bash
ssh thor 'bash -s' < scripts/setup-friday.sh
```

This creates and enables the `friday.service`:

```ini
[Unit]
Description=FRIDAY Voice AI Assistant
After=network.target ollama.service

[Service]
Type=simple
User=bujosa
WorkingDirectory=/home/bujosa/workspace/realtimevoicechat/code
Environment=PATH=/usr/local/cuda-13.0/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
Environment=OLLAMA_BASE_URL=http://127.0.0.1:11434
Environment=VIRTUAL_ENV=/home/bujosa/workspace/realtimevoicechat/venv
ExecStart=/home/bujosa/workspace/realtimevoicechat/venv/bin/python server.py
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

### 5. HTTPS (for microphone access)

Browsers require HTTPS for `getUserMedia()` on non-localhost. We use Pi-hole + Nginx Proxy Manager + mkcert:

```
Browser --> https://friday.home --> Pi (NPM :443) --> Thor (:8000)
```

See [jetson-realtime-voice-chat](https://github.com/bujosa/jetson-realtime-voice-chat) for HTTPS setup details.

### 6. Access

Open `https://friday.home` and start talking.

## Kokoro TTS

[Kokoro](https://github.com/hexgrad/kokoro) is an 82M parameter text-to-speech model using StyleTTS 2 architecture.

| Property | Value |
|----------|-------|
| **Size** | 82M params |
| **License** | Apache 2.0 |
| **GitHub Stars** | 5,800+ |
| **Latency** | ~192ms per chunk (within real-time threshold) |
| **Voice** | `af_heart` (American female, Grade A) |
| **Architecture** | StyleTTS 2 + ISTFTNet vocoder |
| **Telemetry** | None, fully local |

### Available Female Voices

| Voice | Language | Grade |
|-------|----------|-------|
| `af_heart` | American English | A |
| `af_bella` | American English | A- |
| `af_nova` | American English | - |
| `af_sky` | American English | - |
| `af_sarah` | American English | - |
| `bf_emma` | British English | B- |
| `bf_isabella` | British English | - |
| `ff_siwis` | French | B- |

To change voice, edit `audio_module.py`:

```python
self.engine = KokoroEngine(
    voice="af_heart",  # change this
    default_speed=1.26,
)
```

## Why Kokoro over Orpheus

| | Kokoro | Orpheus 3B |
|---|--------|------------|
| **Size** | 82M | 3B (36x larger) |
| **Latency** | 192ms/chunk | 190ms/chunk |
| **Real-time?** | Yes (within 85ms threshold) | No (exceeds threshold) |
| **Architecture** | StyleTTS 2 (direct audio) | LLM (token generation) |
| **Needs server?** | No (inline) | Yes (llama-cpp-python :1234) |
| **Emotional tags** | No | Yes (`<laugh>`, `<sigh>`) |
| **Voice quality** | Natural, clean | Expressive, rich |

Orpheus has better expressiveness but can't keep up with real-time streaming on Jetson. Kokoro runs inline without a separate server and stays within the real-time threshold.

## Management

```bash
# Check status
systemctl status friday

# View logs
journalctl -u friday -f

# Restart
sudo systemctl restart friday

# Stop
sudo systemctl stop friday

# Full status check
ssh thor 'bash -s' < scripts/status.sh
```

## Scripts

| Script | Description |
|--------|-------------|
| `scripts/setup-venv.sh` | Create venv, install PyTorch CUDA, all deps, patch pvporcupine |
| `scripts/setup-friday.sh` | Configure server.py, write system prompt, create systemd service |
| `scripts/status.sh` | Check services, ports, GPU, memory, and recent logs |

## References

- [RealtimeVoiceChat](https://github.com/KoljaB/RealtimeVoiceChat) - Base project by KoljaB (MIT, 3,600+ stars)
- [Kokoro TTS](https://github.com/hexgrad/kokoro) - 82M param TTS engine (Apache 2.0, 5,800+ stars)
- [Kokoro Model](https://huggingface.co/hexgrad/Kokoro-82M) - Hugging Face model page
- [RealtimeSTT](https://github.com/KoljaB/RealtimeSTT) - Speech-to-text library
- [RealtimeTTS](https://github.com/KoljaB/RealtimeTTS) - Text-to-speech library (multi-engine)
- [faster-whisper](https://github.com/SYSTRAN/faster-whisper) - CTranslate2-based Whisper
- [Ollama](https://ollama.com/) - LLM inference server
- [mkcert](https://github.com/FiloSottile/mkcert) - Local CA for HTTPS certificates
- [NVIDIA Jetson AGX Thor](https://developer.nvidia.com/embedded/jetson-agx-thor) - Hardware platform

## Related Repos

- [thor-ai-setup](https://github.com/bujosa/thor-ai-setup) - Ollama + Open WebUI setup on Jetson Thor
- [jetson-realtime-voice-chat](https://github.com/bujosa/jetson-realtime-voice-chat) - TTS engine research, Jetson ARM64 fixes, Orpheus benchmarks
