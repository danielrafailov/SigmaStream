#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

echo "=================================================="
echo "  SigmaStream Local Voice Cloning Setup"
echo "=================================================="

# Find suitable Python binary (prefer 3.11, then 3.12, then python3)
PYTHON_BIN=""
if command -v python3.11 &>/dev/null; then
    PYTHON_BIN="python3.11"
elif command -v /Library/Frameworks/Python.framework/Versions/3.11/bin/python3.11 &>/dev/null; then
    PYTHON_BIN="/Library/Frameworks/Python.framework/Versions/3.11/bin/python3.11"
elif command -v python3.12 &>/dev/null; then
    PYTHON_BIN="python3.12"
elif command -v python3 &>/dev/null; then
    PYTHON_BIN="python3"
else
    echo "❌ Error: Python 3 not found on system."
    exit 1
fi

echo "🔍 Using Python interpreter: $($PYTHON_BIN --version) at $(which $PYTHON_BIN || echo $PYTHON_BIN)"

if [ ! -d ".venv" ]; then
    echo "📦 Creating isolated virtual environment in .venv..."
    $PYTHON_BIN -m venv .venv
fi

echo "🚀 Activating virtual environment..."
source .venv/bin/activate

echo "⬆️  Upgrading pip and packaging tools..."
pip install --upgrade pip setuptools wheel

echo "📥 Installing Voice Cloning AI dependencies (Coqui XTTS-v2, PyTorch, FastAPI)..."
pip install -r requirements.txt

echo "=================================================="
echo "✅ Local Voice Cloning setup complete!"
echo "To start the server manually, run: ./start.sh"
echo "=================================================="
