import os
os.environ["COQUI_TOS_AGREED"] = "1"
import io
import time
import torch
import soundfile as sf
import torchaudio
from pathlib import Path

# PyTorch 2.6+ compatibility for legacy TTS checkpoints
_orig_torch_load = torch.load
def _safe_torch_load(*args, **kwargs):
    if "weights_only" not in kwargs:
        kwargs["weights_only"] = False
    return _orig_torch_load(*args, **kwargs)
torch.load = _safe_torch_load

# Patch torchaudio.load to use soundfile (bypassing torchcodec dependency)
def _safe_torchaudio_load(filepath, *args, **kwargs):
    data, samplerate = sf.read(filepath)
    if data.ndim == 1:
        tensor = torch.from_numpy(data).unsqueeze(0).float()
    else:
        tensor = torch.from_numpy(data.T).float()
    return tensor, samplerate
torchaudio.load = _safe_torchaudio_load

from fastapi import FastAPI, HTTPException
from fastapi.responses import Response, JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from TTS.api import TTS

app = FastAPI(title="SigmaStream Local Voice Cloning Engine", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

BASE_DIR = Path(__file__).resolve().parent.parent
VOICES_DIR = BASE_DIR / "voices"

# Device selection: Apple Silicon Metal (mps) or CPU
device = "mps" if torch.backends.mps.is_available() else "cpu"
print(f"[VoiceCloneServer] 🚀 Initializing XTTS-v2 model on device: {device}...")

# Load XTTS-v2 Neural Voice Cloning Model
tts_model = None

@app.on_event("startup")
def load_model():
    global tts_model
    try:
        print("[VoiceCloneServer] ⏳ Loading XTTS-v2 zero-shot cloning weights...")
        tts_model = TTS(model_name="tts_models/multilingual/multi-dataset/xtts_v2", progress_bar=False).to(device)
        print("[VoiceCloneServer] ✅ XTTS-v2 Model loaded and ready for zero-shot cloning!")
    except Exception as e:
        print(f"[VoiceCloneServer] ⚠️ Failed to load on {device}, falling back to CPU: {e}")
        tts_model = TTS(model_name="tts_models/multilingual/multi-dataset/xtts_v2", progress_bar=False).to("cpu")
        print("[VoiceCloneServer] ✅ XTTS-v2 Model loaded on CPU successfully!")

class TTSRequest(BaseModel):
    text: str
    voice: str = "trump"
    language: str = "en"

@app.get("/health")
def health_check():
    return {
        "status": "online",
        "device": device,
        "model": "xtts_v2",
        "voices_count": len(list(VOICES_DIR.glob("*.wav")))
    }

@app.get("/api/voices")
def list_voices():
    voices = []
    for file in sorted(VOICES_DIR.glob("*.wav")):
        voices.append(file.stem)
    return {"voices": sorted(list(set(voices)))}

@app.post("/api/tts")
def generate_cloned_tts(req: TTSRequest):
    if not tts_model:
        raise HTTPException(status_code=503, detail="TTS Model is still loading")
    
    clean_text = req.text.strip()
    if not clean_text:
        raise HTTPException(status_code=400, detail="Text cannot be empty")
    
    voice_slug = req.voice.lower().strip()
    
    # Locate speaker reference audio
    speaker_file = VOICES_DIR / f"{voice_slug}.wav"
    if not speaker_file.exists():
        fallback = next(VOICES_DIR.glob("*.wav"), None)
        if fallback:
            speaker_file = fallback
            print(f"[VoiceCloneServer] ⚠️ Voice '{voice_slug}' not found, falling back to '{speaker_file.stem}'")
        else:
            raise HTTPException(status_code=404, detail=f"No voice files found in {VOICES_DIR}")
    
    print(f"[VoiceCloneServer] 🎙️ Synthesizing ({speaker_file.stem}): \"{clean_text[:50]}...\"")
    start_time = time.time()
    
    try:
        # Generate cloned audio in memory
        wav_output = tts_model.tts(
            text=clean_text,
            speaker_wav=str(speaker_file),
            language=req.language
        )
        
        # Convert numpy waveform to WAV bytes in memory
        buffer = io.BytesIO()
        sf.write(buffer, wav_output, 24000, format='WAV')
        buffer.seek(0)
        wav_bytes = buffer.read()
        
        elapsed = time.time() - start_time
        print(f"[VoiceCloneServer] ✨ Cloned audio generated in {elapsed:.2f}s ({len(wav_bytes)} bytes)")
        
        return Response(content=wav_bytes, media_type="audio/wav")
    except Exception as e:
        print(f"[VoiceCloneServer] ❌ Error generating speech: {e}")
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=5050)
