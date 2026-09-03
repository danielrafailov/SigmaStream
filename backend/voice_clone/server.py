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

# Comprehensive character acoustic profiles for authentic RVC timbre & prosody
VOICE_PROFILES = {
    "michael_jackson": {
        "base_voice": "en-US-JennyNeural",
        "pitch_shift": 0,
        "rate": "-3%",
        "pitch_hz": "+0Hz"
    },
    "morgan_freeman": {
        "base_voice": "en-US-RogerNeural",
        "pitch_shift": -5,
        "rate": "-12%",
        "pitch_hz": "-5Hz"
    },
    "snoop_dogg": {
        "base_voice": "en-US-GuyNeural",
        "pitch_shift": -2,
        "rate": "-10%",
        "pitch_hz": "-3Hz"
    },
    "tom_holland": {
        "base_voice": "en-GB-RyanNeural",
        "pitch_shift": 2,
        "rate": "+4%",
        "pitch_hz": "+5Hz"
    },
    "trump": {
        "base_voice": "en-US-GuyNeural",
        "pitch_shift": 0,
        "rate": "+0%",
        "pitch_hz": "+0Hz"
    },
    "arnold_schwarzenegger": {
        "base_voice": "en-US-GuyNeural",
        "pitch_shift": -1,
        "rate": "-4%",
        "pitch_hz": "-5Hz"
    },
    "gordon_ramsay": {
        "base_voice": "en-GB-RyanNeural",
        "pitch_shift": 0,
        "rate": "+6%",
        "pitch_hz": "+0Hz"
    },
    "mandalorian": {
        "base_voice": "en-US-ChristopherNeural",
        "pitch_shift": -3,
        "rate": "-8%",
        "pitch_hz": "-8Hz"
    },
    "joe_rogan": {
        "base_voice": "en-US-GuyNeural",
        "pitch_shift": 0,
        "rate": "+2%",
        "pitch_hz": "+0Hz"
    },
    "eric_cartman": {
        "base_voice": "en-US-GuyNeural",
        "pitch_shift": 0,
        "rate": "+2%",
        "pitch_hz": "+0Hz"
    },
    "daffy_duck": {
        "base_voice": "en-US-GuyNeural",
        "pitch_shift": 0,
        "rate": "+0%",
        "pitch_hz": "+0Hz"
    },
    "barack_obama": {
        "base_voice": "en-US-GuyNeural",
        "pitch_shift": 0,
        "rate": "-6%",
        "pitch_hz": "-2Hz"
    },
    "darth_vader": {
        "base_voice": "en-US-ChristopherNeural",
        "pitch_shift": -6,
        "rate": "-14%",
        "pitch_hz": "-15Hz"
    },
    "joe_biden": {
        "base_voice": "en-US-GuyNeural",
        "pitch_shift": 0,
        "rate": "-8%",
        "pitch_hz": "-2Hz"
    }
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
    profile = VOICE_PROFILES.get(voice_slug, {
        "base_voice": "en-US-GuyNeural",
        "pitch_shift": 0,
        "rate": "+0%",
        "pitch_hz": "+0Hz"
    })
    communicate = edge_tts.Communicate(
        text,
        profile["base_voice"],
        rate=profile["rate"],
        pitch=profile["pitch_hz"]
    )
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
            profile = VOICE_PROFILES.get(voice_slug, {})
            pitch_shift = profile.get("pitch_shift", 0)
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
