# WhisperBox — How To

## What Is It
macOS menu bar app for speech-to-text. Push a hotkey, talk, release — your speech gets transcribed locally using Whisper. No cloud, no subscription.

## Three Modes

### 1. Hotkey Mode (default)
- Press hotkey → talk → release
- Text gets transcribed and copied to clipboard
- Optional: auto-paste into frontmost app
- Optional: Claude cleanup (fixes grammar/punctuation)

### 2. Live Mode
- Always listening, auto-detects when you speak
- Transcribes each speech segment automatically
- Configurable silence timeout and volume threshold

### 3. Voice Chat Mode 🎤
- Press hotkey → talk → release
- Transcribes your speech
- Sends it to Aladin via OpenClaw gateway (localhost)
- Aladin responds with voice (Qwen3-TTS or macOS say)
- Full voice conversation, ~5 seconds round-trip

## Setup

### First Launch
1. Open WhisperBox from `/Applications` (or run from `~/code/WhisperBox`)
2. Grant microphone permission when prompted
3. Wait for Whisper model download (~150MB, one-time)
4. Look for the waveform icon in your menu bar

### Configure
Click the menu bar icon → **Settings**:
- **Recording Mode** — Hotkey / Live / Voice Chat
- **Hotkey** — Default: Right Option. Click "Record" to change.
- **Input Device** — Select your mic
- **Claude Cleanup** — Toggle grammar fixing (needs API key)
- **Auto-Paste** — Auto-paste transcription into active app

### Voice Chat Setup
Voice chat talks to Aladin through the OpenClaw gateway on localhost:18789. This works out of the box if the gateway is running (it's a LaunchAgent, always on).

No API key needed in WhisperBox settings for this mode — it routes through OpenClaw.

## Building from Source

```bash
cd ~/code/WhisperBox
swift build -c release
```

Binary lands at `.build/release/WhisperBox`.

To update the app bundle:
```bash
cp .build/release/WhisperBox /Applications/WhisperBox.app/Contents/MacOS/WhisperBox
```

## Hotkey Tips
- **Right Option** is the default — it's a standalone key, no modifier combo needed
- Works globally, even when WhisperBox isn't focused
- In Voice Chat mode, press during playback to stop Aladin speaking

## Architecture

```
You speak
  │
  ▼
Mic → AVAudioEngine (capture)
  │
  ▼
SwiftWhisper (local whisper.cpp, ~1-2s)
  │
  ├─ Hotkey/Live mode → Clipboard + paste
  │
  └─ Voice Chat mode:
       │
       ▼
     OpenClaw Gateway (localhost:18789, ~2-3s)
       │
       ▼
     Qwen3-TTS or macOS say (~1-2s)
       │
       ▼
     Audio playback → You hear the response
```

## Files
- **App:** `/Applications/WhisperBox.app`
- **Source:** `~/code/WhisperBox/`
- **Whisper model:** `~/Library/Application Support/WhisperBox/ggml-base.en.bin`
- **Repo:** https://github.com/AladinMini/WhisperBox

## Troubleshooting

**No transcription / silence:**
- Check mic permissions: System Settings → Privacy → Microphone → WhisperBox
- Check input device in WhisperBox settings
- Test mic level meter in settings

**Voice Chat not responding:**
- Check gateway is running: `curl http://127.0.0.1:18789/v1/models`
- If not: `launchctl load ~/Library/LaunchAgents/ai.openclaw.gateway.plist`

**Qwen3-TTS not working (falls back to macOS say):**
- Check venv exists: `ls ~/.openclaw/workspace/qwen3-tts/.venv/bin/python3`
- Test manually: `cd ~/.openclaw/workspace/qwen3-tts && source .venv/bin/activate && python3 speak.py "test" /tmp/test.wav`

**Build errors:**
- Needs Xcode command line tools: `xcode-select --install`
- Needs macOS 14+ for SwiftUI Observable macro
