import os
import io
import time
import torch
import numpy as np
import soundfile as sf
import librosa
from pathlib import Path
from transformers import HubertModel

# Set device
if torch.backends.mps.is_available():
    device = "mps"
    is_half = False  # MPS works best with float32 for complex convolutions
elif torch.cuda.is_available():
    device = "cuda"
    is_half = True
else:
    device = "cpu"
    is_half = False

print(f"[RVCEngine] 🚀 Initializing on device: {device}")

from rvc.module.models import SynthesizerTrnMs768NSFsid, SynthesizerTrnMs256NSFsid
from rvc.rmvpe import RMVPE

BASE_DIR = Path(__file__).resolve().parent
MODELS_DIR = BASE_DIR / "models"
WEIGHTS_DIR = BASE_DIR / "weights"

class RVCEngine:
    def __init__(self):
        self.device = device
        self.is_half = is_half
        self.loaded_models = {}
        
        # 1. Load HuBERT
        print("[RVCEngine] ⏳ Loading HuBERT embedding model...")
        self.hubert = HubertModel.from_pretrained("facebook/hubert-base-ls960").to(self.device)
        self.hubert.eval()
        print("[RVCEngine] ✅ HuBERT loaded.")
        
        # 2. Load RMVPE Pitch Extractor
        rmvpe_path = MODELS_DIR / "rmvpe.pt"
        if rmvpe_path.exists():
            print("[RVCEngine] ⏳ Loading RMVPE pitch estimator...")
            self.rmvpe = RMVPE(str(rmvpe_path), is_half=self.is_half, device=self.device)
            print("[RVCEngine] ✅ RMVPE loaded.")
        else:
            self.rmvpe = None
            print("[RVCEngine] ⚠️ rmvpe.pt not found, pitch will be estimated via crepe/harvest.")
    
    def get_model(self, model_slug: str):
        if model_slug in self.loaded_models:
            return self.loaded_models[model_slug]
        
        pth_path = WEIGHTS_DIR / f"{model_slug}.pth"
        if not pth_path.exists():
            # Check fallback or first available
            available = list(WEIGHTS_DIR.glob("*.pth"))
            if available:
                pth_path = available[0]
                print(f"[RVCEngine] ⚠️ Model '{model_slug}' not found, falling back to '{pth_path.stem}'")
            else:
                raise FileNotFoundError(f"No .pth models found in {WEIGHTS_DIR}")
        
        print(f"[RVCEngine] ⏳ Loading model weights: {pth_path.name}...")
        cpt = torch.load(pth_path, map_location="cpu", weights_only=False)
        tgt_sr = cpt.get("sr", "40k")
        if tgt_sr == "40k":
            target_sr = 40000
        elif tgt_sr == "48k":
            target_sr = 48000
        else:
            target_sr = 32000
        
        version = cpt.get("version", "v2")
        f0 = cpt.get("f0", 1)
        config = cpt.get("config", [1025, 32, 192, 192, 768, 2, 6, 3, 0, "1", [3, 7, 11], [[1, 3, 5], [1, 3, 5], [1, 3, 5]], [10, 10, 2, 2], 512, [16, 16, 4, 4], 109, 256, 768])
        
        if version == "v1":
            net_g = SynthesizerTrnMs256NSFsid(*config, is_half=self.is_half)
        else:
            net_g = SynthesizerTrnMs768NSFsid(*config, is_half=self.is_half)
        
        net_g.load_state_dict(cpt["weight"], strict=False)
        net_g.eval().to(self.device)
        if self.is_half:
            net_g = net_g.half()
        else:
            net_g = net_g.float()
        
        model_info = {
            "net_g": net_g,
            "target_sr": target_sr,
            "f0": f0,
            "version": version
        }
        self.loaded_models[model_slug] = model_info
        print(f"[RVCEngine] ✅ Loaded {pth_path.name} (SR: {target_sr}, Version: {version})")
        return model_info

    def convert_audio(self, audio_data: np.ndarray, sr: int, voice_slug: str, pitch_shift: int = 0) -> tuple[np.ndarray, int]:
        """
        Converts input voice waveform into target celebrity voice.
        """
        model_info = self.get_model(voice_slug)
        net_g = model_info["net_g"]
        target_sr = model_info["target_sr"]
        
        # 1. Resample to 16kHz mono for HuBERT & RMVPE
        if audio_data.ndim > 1:
            audio_data = np.mean(audio_data, axis=1)
        
        if sr != 16000:
            audio_16k = librosa.resample(audio_data, orig_sr=sr, target_sr=16000)
        else:
            audio_16k = audio_data
        
        # 2. Extract HuBERT features
        feats_tensor = torch.from_numpy(audio_16k).float().unsqueeze(0).to(self.device)
        with torch.no_grad():
            outputs = self.hubert(feats_tensor, output_hidden_states=True)
            # RVC v2 uses 12th layer (index 12 in hidden_states) or last_hidden_state
            feats = outputs.hidden_states[12] if len(outputs.hidden_states) > 12 else outputs.last_hidden_state
            feats = feats.squeeze(0) # [T, 768]
            feats = torch.repeat_interleave(feats, 2, dim=0) # [2T, 768]
        
        # 3. Extract F0 Pitch using RMVPE
        if self.rmvpe is not None:
            f0_arr = self.rmvpe.infer_from_audio(audio_16k, thred=0.03)
        else:
            f0_arr = np.zeros(feats.shape[0])
        
        # Apply pitch shift (semitones)
        if pitch_shift != 0:
            f0_arr = f0_arr * (2 ** (pitch_shift / 12.0))
        
        # Align lengths
        min_len = min(feats.shape[0], len(f0_arr))
        feats = feats[:min_len].unsqueeze(0) # [1, T, 768]
        f0_arr = f0_arr[:min_len]
        
        # Quantize coarse pitch for NSF
        f0_mel = 1127 * np.log(1 + f0_arr / 700)
        f0_mel[f0_arr <= 0] = 0
        f0_mel_min = 1127 * np.log(1 + 50 / 700)
        f0_mel_max = 1127 * np.log(1 + 1100 / 700)
        f0_coarse = (f0_mel - f0_mel_min) * 254 / (f0_mel_max - f0_mel_min) + 1
        f0_coarse[f0_coarse <= 1] = 1
        f0_coarse[f0_coarse > 255] = 255
        f0_coarse = f0_coarse.astype(int)
        
        pitch = torch.from_numpy(f0_arr).float().unsqueeze(0).to(self.device)
        pitchf = pitch.clone()
        pitch_coarse = torch.from_numpy(f0_coarse).long().unsqueeze(0).to(self.device)
        
        # 4. Synthesizer Inference
        p_len = torch.tensor([min_len], device=self.device).long()
        sid = torch.tensor([0], device=self.device).long()
        
        with torch.no_grad():
            audio_out = net_g.infer(feats, p_len, pitch_coarse, pitchf, sid)[0][0, 0].data.cpu().float().numpy()
        
        return audio_out, target_sr

if __name__ == "__main__":
    engine = RVCEngine()
    print("Testing conversion...")
