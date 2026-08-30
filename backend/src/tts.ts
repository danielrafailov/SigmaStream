import { KokoroTTS } from 'kokoro-js';

let ttsInstance: KokoroTTS | null = null;
let initPromise: Promise<KokoroTTS> | null = null;

export async function getTTS(): Promise<KokoroTTS> {
    if (ttsInstance) return ttsInstance;
    if (initPromise) return initPromise;

    initPromise = (async () => {
        console.log('[TTS] Loading local Kokoro Neural TTS model...');
        const tts = await KokoroTTS.from_pretrained(
            'onnx-community/Kokoro-82M-v1.0-ONNX',
            {
                dtype: 'q8'
            }
        );
        ttsInstance = tts;
        console.log('[TTS] Kokoro Neural TTS model ready for synthesis!');
        return tts;
    })();

    return initPromise;
}

export async function generateSpeechWav(
    text: string,
    voice: string = 'af_heart'
): Promise<Buffer> {
    const tts = await getTTS();
    const audio = await tts.generate(text, { voice: voice as any });
    const wavArrayBuffer = audio.toWav();
    return Buffer.from(wavArrayBuffer);
}
