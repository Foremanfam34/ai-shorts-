#!/usr/bin/env bash
# One-time setup: Python packages, ffmpeg + espeak-ng, the Inter font, and the local
# voice / transcription models (~1.4 GB, all free and run offline).
set -euo pipefail
cd "$(dirname "$0")"

pip install -r requirements.txt

need=()
command -v ffmpeg >/dev/null || need+=(ffmpeg)
command -v espeak-ng >/dev/null || need+=(espeak-ng)
if [ ${#need[@]} -gt 0 ]; then
  if command -v brew >/dev/null; then brew install "${need[@]}"
  elif command -v apt-get >/dev/null; then sudo apt-get install -y "${need[@]}"
  else echo "Please install: ${need[*]}"; exit 1; fi
fi

if [ ! -f fonts/Inter-Black.otf ] && [ ! -f /usr/share/fonts/opentype/inter/Inter-Black.otf ]; then
  mkdir -p fonts
  curl -fsSL -o /tmp/inter.zip https://github.com/rsms/inter/releases/download/v4.0/Inter-4.0.zip
  unzip -j -o -q /tmp/inter.zip 'extras/otf/Inter-*.otf' -d fonts && rm /tmp/inter.zip
fi

mkdir -p models && cd models
base=https://github.com/k2-fsa/sherpa-onnx/releases/download
[ -d kokoro-multi-lang-v1_0 ] || curl -fsSL "$base/tts-models/kokoro-multi-lang-v1_0.tar.bz2" | tar xj
[ -d sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8 ] || \
  curl -fsSL "$base/asr-models/sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8.tar.bz2" | tar xj
[ -f silero_vad.onnx ] || curl -fsSL -o silero_vad.onnx "$base/asr-models/silero_vad.onnx"
echo "Setup complete."
