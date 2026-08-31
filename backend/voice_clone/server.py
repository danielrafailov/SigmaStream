import os
os.environ["COQUI_TOS_AGREED"] = "1"
import io
import time
import asyncio
import torch
import soundfile as sf
import numpy as np
import edge_tts
from pathlib import Path
from fastapi import FastAPI, HTTPException
from fastapi.responses import Response
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

# Device selection: Apple Silicon Metal (mps) or CPU
device = "mps" if torch.backends.mps.is_available() else "cpu"
print(f"[VoiceCloneServer] 🚀 Initializing Voice Clone & RVC Engine on device: {device}...")

BASE_DIR = Path(__file__).resolve().parent
WEIGHTS_DIR = BASE_DIR / "weights"
VOICES_DIR = BASE_DIR.parent / "voices"

# Import RVC Engine
from rvc_engine import RVCEngine

app = FastAPI(title="SigmaStream Local 1:1 Celebrity Voice Cloning Engine", version="2.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

rvc_engine = None

# Pitch adjustments per character if needed (semitones)
PITCH_OFFSETS = {
    "eric_cartman": 6,      # High-pitched cartoon
    "daffy_duck": 4,        # Cartoon duck
    "morgan_freeman": -2,   # Deep resonance
    "arnold_schwarzenegger": -1,
    "trump": 0,
    "michael_jackson": 2,
    "gordon_ramsay": 0,
    "mandalorian": -2,
    "snoop_dogg": 0,
    "walter_white": -1,
    "joe_rogan": 0
}

# Base TTS voice selection per character for ideal acoustic timbre match
BASE_VOICES = {
    "eric_cartman": "en-US-AnaNeural",
    "daffy_duck": "en-US-GuyNeural",
    "morgan_freeman": "en-US-BrianNeural",
    "michael_jackson": "en-US-AndrewNeural",
    "arnold_schwarzenegger": "en-US-GuyNeural",
    "trump": "en-US-GuyNeural",
    "gordon_ramsay": "en-GB-RyanNeural",
    "mandalorian": "en-US-ChristopherNeural"
}

@app.on_event("startup")
def startup_event():
    global rvc_engine
    print("[VoiceCloneServer] ⏳ Initializing Neural RVC Pipeline...")
    rvc_engine = RVCEngine()
    
    # Pre-warm available models
    available_weights = [f.stem for f in WEIGHTS_DIR.glob("*.pth")]
    print(f"[VoiceCloneServer] ✅ RVC Engine loaded with models: {available_weights}")

class TTSRequest(BaseModel):
    text: str
    voice: str = "trump"
    language: str = "en"

@app.get("/health")
def health_check():
    available_rvc = [f.stem for f in WEIGHTS_DIR.glob("*.pth")]
    available_wavs = [f.stem for f in VOICES_DIR.glob("*.wav")]
    return {
        "status": "online",
        "engine": "rvc_v2",
        "device": device,
        "rvc_models": sorted(available_rvc),
        "total_voices": len(list(set(available_rvc + available_wavs)))
    }

@app.get("/api/voices")
def list_voices():
    available_rvc = [f.stem for f in WEIGHTS_DIR.glob("*.pth")]
    available_wavs = [f.stem for f in VOICES_DIR.glob("*.wav")]
    return {"voices": sorted(list(set(available_rvc + available_wavs)))}

async def generate_base_tts(text: str, voice_slug: str) -> tuple[np.ndarray, int]:
    edge_voice = BASE_VOICES.get(voice_slug, "en-US-GuyNeural")
    communicate = edge_tts.Communicate(text, edge_voice)
    
    buffer = io.BytesIO()
    async for chunk in communicate.stream():
        if chunk["type"] == "audio":
            buffer.write(chunk["data"])
    
    buffer.seek(0)
    audio_data, sr = sf.read(buffer)
    return audio_data, sr

@app.post("/api/tts")
async def generate_cloned_tts(req: TTSRequest):
    if not rvc_engine:
        raise HTTPException(status_code=503, detail="RVC Engine is initializing")
    
    clean_text = req.text.strip()
    if not clean_text:
        raise HTTPException(status_code=400, detail="Text cannot be empty")
    
    voice_slug = req.voice.lower().strip()
    pth_file = WEIGHTS_DIR / f"{voice_slug}.pth"
    
    start_time = time.time()
    print(f"[VoiceCloneServer] 🎙️ Synthesizing 1:1 ({voice_slug}): \"{clean_text[:50]}...\"")
    
    try:
        # 1. Generate clean baseline neural speech via EdgeTTS
        base_audio, base_sr = await generate_base_tts(clean_text, voice_slug)
        t_base = time.time() - start_time
        
        # 2. Convert voice using RVC neural weights with RMVPE pitch alignment
        pitch_shift = PITCH_OFFSETS.get(voice_slug, 0)
        
        if pth_file.exists():
            converted_audio, out_sr = rvc_engine.convert_audio(
                base_audio, base_sr, voice_slug, pitch_shift=pitch_shift
            )
        else:
            # Fallback to nearest available RVC model
            fallback_slug = "trump"
            converted_audio, out_sr = rvc_engine.convert_audio(
                base_audio, base_sr, fallback_slug, pitch_shift=pitch_shift
            )
        
        t_total = time.time() - start_time
        
        # 3. Write output to WAV buffer
        out_buffer = io.BytesIO()
        sf.write(out_buffer, converted_audio, out_sr, format="WAV")
        out_buffer.seek(0)
        wav_bytes = out_buffer.read()
        
        print(f"[VoiceCloneServer] ✨ 1:1 Celebrity Audio generated in {t_total:.2f}s (Base: {t_base:.2f}s, {len(wav_bytes)} bytes @ {out_sr}Hz)")
        return Response(content=wav_bytes, media_type="audio/wav")
    except Exception as e:
        print(f"[VoiceCloneServer] ❌ Error generating speech: {e}")
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=5050)
