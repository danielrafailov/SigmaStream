let transcriberInstance: any = null;
let initPromise: Promise<any> | null = null;

export async function getTranscriber(): Promise<any> {
    if (transcriberInstance) return transcriberInstance;
    if (initPromise) return initPromise;

    initPromise = (async () => {
        try {
            console.log('[STT] Loading local Whisper speech-to-text model...');
            const { pipeline } = await import('@huggingface/transformers');
            const transcriber = await pipeline(
                'automatic-speech-recognition',
                'onnx-community/whisper-tiny.en',
                { dtype: 'fp32' }
            );
            transcriberInstance = transcriber;
            console.log('[STT] Whisper speech-to-text model ready!');
            return transcriber;
        } catch (err) {
            console.warn('[STT] Could not initialize Whisper model:', err);
            initPromise = null;
            return null;
        }
    })();

    return initPromise;
}

export async function transcribeWav(wavBuffer: Buffer): Promise<string> {
    const transcriber = await getTranscriber();
    if (!transcriber) return '';
    const pkg = await import('wavefile');
    const WaveFile = (pkg as any).default?.WaveFile || (pkg as any).WaveFile;
    const wav = new WaveFile(wavBuffer);
    wav.toBitDepth('32f');
    wav.toSampleRate(16000);
    let samples = wav.getSamples();
    if (Array.isArray(samples)) {
        samples = samples[0];
    }
    const float32Array = new Float32Array(samples);
    const result = await transcriber(float32Array);
    const text = (result?.text || '').trim();
    return text;
}
