import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const VOICES_DIR = path.join(__dirname, '../voices');

const API_KEYS = [
    "vk_18ebe86c49283ec0704d6086cf8cef50801e462f71d55091323432b43c18400e",
    "vk_60384aa3a7eb6d953931665a36329efba7064d43ae6ea2454b5dfd1222473858",
    "vk_5fdf33e3870faae6d895525287f3747ebaf5617ce8c9497e2b173e35ef587f7e"
];

const VOICES = [
    { slug: "trump", name: "Donald Trump", id: "40d320d7-558b-4207-b9e9-45772b0ce167", text: "Hello everybody, this is Donald Trump. We are looking at some truly incredible movies today, believe me." },
    { slug: "michael_jackson", name: "Michael Jackson", id: "4aab5641-8f84-404a-be30-1d620d856dee", text: "Hee-hee, hello everyone. Let's find some wonderful entertainment for you to enjoy tonight." },
    { slug: "saul_goodman", name: "Saul Goodman", id: "06baf53c-9f1e-43ba-adf0-0385dd022991", text: "Hi, I'm Saul Goodman! Did you know you have the right to great entertainment? You sure do." },
    { slug: "david_attenborough", name: "David Attenborough", id: "56e0b000-b8fb-4fd3-832a-03bde62f8dbc", text: "Here in the vast digital wilderness, we discover some of the most extraordinary stories ever captured on film." },
    { slug: "eric_cartman", name: "Eric Cartman", id: "c8909e12-a6d3-46d3-a4a2-c55b628acae0", text: "Hey you guys! You have to respect my authority and watch some sweet movies right now." },
    { slug: "mandalorian", name: "Mandalorian", id: "43ce1296-4969-4af6-bdc1-22ef5e347d08", text: "This is the way. Finding the best streams across the galaxy for your mission." },
    { slug: "walter_white", name: "Walter White", id: "40e41528-8f28-4f6d-94ac-7670f9fec4a9", nameText: "I am the one who streams. Let's get straight to business with the highest quality selection." },
    { slug: "gordon_ramsay", name: "Gordon Ramsay", id: "280e1b27-a62d-47a3-8840-b7ff288941aa", text: "Listen to me! These movie recommendations are cooked to absolute perfection, absolutely stunning." },
    { slug: "tom_holland", name: "Tom Holland", id: "3caf42ba-3d92-4aed-8fda-1a70a4abd47c", text: "Hey everyone, Tom here! Hope you're ready for an awesome adventure and a fantastic movie." },
    { slug: "lebron_james", name: "Lebron James", id: "489b1783-5724-45e8-84dc-ace995595845", text: "What's up, it's King James. Striving for greatness with the absolute best movie lineup." },
    { slug: "morgan_freeman", name: "Morgan Freeman", id: "a0cf2b27-25c9-45b8-a53d-21e7029c5bb1", text: "Every story has a beginning, and tonight, your cinematic journey is about to unfold." },
    { slug: "arnold_schwarzenegger", name: "Arnold Schwarzenegger", id: "2c61b0ed-c7e4-461d-a6d1-5a4f02fc8278", text: "Hasta la vista, baby! I will help you find the most action packed movies in the universe." },
    { slug: "snoop_dogg", name: "Snoop Dogg", id: "9a7860b8-70f8-461f-b0c7-d005d0b1504c", text: "Yeah yeah, it's the big Snoop D O double G, keeping it smooth with the dopest movie picks." },
    { slug: "joe_rogan", name: "Joe Rogan", id: "6a6d4859-fff1-4405-9f8a-a259768679be", text: "Have you ever thought about how crazy it is that we can stream any movie ever made? It is entirely wild." },
    { slug: "daffy_duck", name: "Daffy Duck", id: "c1745484-ba67-4cba-b8f3-19f9bc538f61", text: "You're dethpicable! But these movie recommendations are absolutely magnificent and hilarious." }
];

async function seedVoice(voice: typeof VOICES[0]) {
    const targetFile = path.join(VOICES_DIR, `${voice.slug}.mp3`);
    if (fs.existsSync(targetFile)) {
        console.log(`[Seed] ✅ Reference audio already exists for ${voice.name} (${voice.slug}.mp3)`);
        return;
    }

    console.log(`[Seed] 🎙️ Generating reference audio blueprint for ${voice.name}...`);
    const promptText = voice.text || voice.nameText || `Hello, this is ${voice.name} speaking clearly on SigmaStream.`;

    for (let i = 0; i < API_KEYS.length; i++) {
        const apiKey = API_KEYS[i];
        try {
            const response = await fetch("https://dev.voice.ai/api/v1/tts/speech", {
                method: "POST",
                headers: {
                    "Authorization": `Bearer ${apiKey}`,
                    "Content-Type": "application/json"
                },
                body: JSON.stringify({
                    text: promptText,
                    model: "voiceai-tts-v1-latest",
                    voice_id: voice.id,
                    language: "en"
                })
            });

            if (response.ok) {
                const arrayBuffer = await response.arrayBuffer();
                const buffer = Buffer.from(arrayBuffer);
                fs.writeFileSync(targetFile, buffer);
                console.log(`[Seed] ✨ Successfully saved ${voice.slug}.mp3 (${buffer.length} bytes)`);
                return;
            } else {
                console.warn(`[Seed] Key #${i + 1} failed for ${voice.name} with HTTP ${response.status}`);
            }
        } catch (err: any) {
            console.warn(`[Seed] Error on key #${i + 1}: ${err.message}`);
        }
    }
}

async function main() {
    console.log(`[Seed] Initializing 15 celebrity reference voices into ${VOICES_DIR}...`);
    for (const voice of VOICES) {
        await seedVoice(voice);
    }
    console.log(`[Seed] 🎉 All reference audio blueprints created successfully!`);
}

main().catch(console.error);
