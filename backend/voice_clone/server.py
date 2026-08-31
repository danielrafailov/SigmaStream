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
print(f"[VoiceCloneServer] 🚀 Initializing Voice Clone Engine on device: {device}...")

BASE_DIR = Path(__file__).resolve().parent
WEIGHTS_DIR = BASE_DIR / "weights"
VOICES_DIR = BASE_DIR.parent / "voices"

# Import RVC Engine
from rvc_engine import RVCEngine

# Global state
rvc_engine = None
xtts_model = None

app = FastAPI(title="SigmaStream Local Celebrity Voice Engine", version="3.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Natural pitch adjustments per character
PITCH_OFFSETS = {
    "eric_cartman": 0,
    "daffy_duck": 0,
    "morgan_freeman": -2,
    "arnold_schwarzenegger": -1,
    "trump": 0,
    "michael_jackson": 0,
    "gordon_ramsay": 0,
    "mandalorian": -2,
    "snoop_dogg": 0,
    "joe_rogan": 0,
    "tom_holland": 0
}

# Base TTS voice selection for RVC conversion
BASE_VOICES = {
    "eric_cartman": "en-US-GuyNeural",
    "daffy_duck": "en-US-GuyNeural",
    "morgan_freeman": "en-US-BrianNeural",
    "michael_jackson": "en-US-GuyNeural",
    "arnold_schwarzenegger": "en-US-GuyNeural",
    "trump": "en-US-GuyNeural",
    "gordon_ramsay": "en-GB-RyanNeural",
    "mandalorian": "en-US-ChristopherNeural",
    "snoop_dogg": "en-US-ChristopherNeural",
    "joe_rogan": "en-US-GuyNeural",
    "tom_holland": "en-GB-ThomasNeural"
}

def get_xtts():
    global xtts_model
    if xtts_model is None:
        print("[VoiceCloneServer] ⏳ Loading XTTS-v2 Zero-Shot Voice Cloner...")
        from TTS.api import TTS
        xtts_model = TTS("tts_models/multilingual/multi-dataset/xtts_v2").to(device)
        print("[VoiceCloneServer] ✅ XTTS-v2 loaded.")
    return xtts_model

@app.on_event("startup")
def startup_event():
    global rvc_engine
    print("[VoiceCloneServer] ⏳ Initializing Neural RVC Pipeline...")
    rvc_engine = RVCEngine()
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
        "device": device,
        "rvc_models": sorted(available_rvc),
        "reference_wavs": sorted(available_wavs)
    }

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
    clean_text = req.text.strip()
    if not clean_text:
        raise HTTPException(status_code=400, detail="Text cannot be empty")
    
    voice_slug = req.voice.lower().strip()
    pth_file = WEIGHTS_DIR / f"{voice_slug}.pth"
    ref_wav_file = VOICES_DIR / f"{voice_slug}.wav"
    
    start_time = time.time()
    print(f"[VoiceCloneServer] 🎙️ Synthesizing ({voice_slug}): \"{clean_text[:50]}...\"")
    
    try:
        # PATH 1: Dedicated RVC .pth Model
        if pth_file.exists() and rvc_engine is not None:
            base_audio, base_sr = await generate_base_tts(clean_text, voice_slug)
            pitch_shift = PITCH_OFFSETS.get(voice_slug, 0)
            converted_audio, out_sr = rvc_engine.convert_audio(
                base_audio, base_sr, voice_slug, pitch_shift=pitch_shift
            )
        # PATH 2: XTTS-v2 Zero-Shot Voice Clone from Reference Audio Sample
        elif ref_wav_file.exists():
            print(f"[VoiceCloneServer] ⚡ Using XTTS-v2 reference cloning with {ref_wav_file.name}...")
            tts = get_xtts()
            wav = tts.tts(text=clean_text, speaker_wav=str(ref_wav_file), language="en")
            converted_audio = np.array(wav)
            out_sr = 24000
        # PATH 3: Default to Trump RVC
        else:
            base_audio, base_sr = await generate_base_tts(clean_text, "trump")
            converted_audio, out_sr = rvc_engine.convert_audio(
                base_audio, base_sr, "trump", pitch_shift=0
            )
        
        t_total = time.time() - start_time
        
        out_buffer = io.BytesIO()
        sf.write(out_buffer, converted_audio, out_sr, format="WAV")
        out_buffer.seek(0)
        wav_bytes = out_buffer.read()
        
        print(f"[VoiceCloneServer] ✨ Voice generated in {t_total:.2f}s ({len(wav_bytes)} bytes @ {out_sr}Hz)")
        return Response(content=wav_bytes, media_type="audio/wav")
    except Exception as e:
        print(f"[VoiceCloneServer] ❌ Error generating speech: {e}")
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=5050)
