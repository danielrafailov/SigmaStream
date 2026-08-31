#!/bin/bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

export COQUI_TOS_AGREED=1
source .venv/bin/activate
lsof -ti :5050 | xargs kill -9 2>/dev/null || true
echo "🎙️ Starting SigmaStream Local Voice Cloning Engine on http://127.0.0.1:5050..."
exec uvicorn server:app --host 127.0.0.1 --port 5050
