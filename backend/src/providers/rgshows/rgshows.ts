import { BaseProvider } from '@omss/framework';
import type {
    ProviderCapabilities,
    ProviderMediaObject,
    ProviderResult,
    Source,
    Subtitle
} from '@omss/framework';
import axios from 'axios';
import { RgShowsResponse } from './rgshows.types.js';

export class RgShowsProvider extends BaseProvider {
    readonly id = 'RgShows';
    readonly name = 'RgShows';
    readonly enabled = true;
    readonly BASE_URL = 'https://api.rgshows.ru/main';
    private readonly FRONTEND_URL = 'https://www.rgshows.ru';
    readonly HEADERS = {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150 Safari/537.36',
        Accept: 'application/json, text/javascript, */*; q=0.01',
        'Accept-Language': 'en-US,en;q=0.9',
        Referer: this.FRONTEND_URL,
        Origin: this.FRONTEND_URL
    };

    readonly capabilities: ProviderCapabilities = {
        supportedContentTypes: ['movies', 'tv']
    };

    /**
     * Fetch movie sources
     */
    async getMovieSources(media: ProviderMediaObject): Promise<ProviderResult> {
        return this.getSources(media);
    }

    /**
     * Fetch TV episode sources
     */
    async getTVSources(media: ProviderMediaObject): Promise<ProviderResult> {
        return this.getSources(media);
    }

    /**
     * Main scraping logic
     */
    private async getSources(
        media: ProviderMediaObject
    ): Promise<ProviderResult> {
        try {
            // Build page URL
            const pageUrl = this.buildPageUrl(media);

            // Fetch page json
            const data = await this.fetchPage(pageUrl, media);
            if (!data) {
                return this.emptyResult('Failed to fetch page', media);
            }
            const resp: RgShowsResponse = data as unknown as RgShowsResponse;
            const validation = await this.validateStreamChain(resp.stream.url);
            if (!validation.ok) {
                return this.emptyResult(
                    `Rejected stream: ${validation.reason}`,
                    media
                );
            }

            const result: ProviderResult = {
                sources: [
                    {
                        url: this.createProxyUrl(resp.stream.url, this.HEADERS),
                        quality: '1080p',
                        type: 'mp4',
                        audioTracks: [
                            {
                                label: 'English',
                                language: 'eng'
                            }
                        ],
                        provider: {
                            name: this.name,
                            id: this.id
                        }
                    }
                ],
                subtitles: [],
                diagnostics: []
            };

            return result;
        } catch (error) {
            return this.emptyResult(
                error instanceof Error
                    ? error.message
                    : 'Unknown provider error',
                media
            );
        }
    }

    /**
     * Build page URL based on media type
     */
    private buildPageUrl(media: ProviderMediaObject): string {
        if (media.type === 'movie') {
            return `${this.BASE_URL}/movie/${media.tmdbId}`;
        } else {
            return `${this.BASE_URL}/tv/${media.tmdbId}/${media.s}/${media.e}`;
        }
    }

    /**
     * Fetch page Json
     */
    private async fetchPage(
        url: string,
        media: ProviderMediaObject
    ): Promise<string | null> {
        try {
            const response = await axios.get(url, {
                headers: this.HEADERS,
                timeout: 10000
            });

            if (response.status !== 200) {
                return null;
            }

            return response.data;
        } catch (error) {
            return null;
        }
    }

    private async validateStreamChain(
        streamUrl: string
    ): Promise<{ ok: boolean; reason?: string }> {
        try {
            if (!streamUrl || !streamUrl.includes('.m3u8')) {
                return { ok: true };
            }

            const master = await this.fetchText(streamUrl);
            const childPath = this.firstMediaLine(master);
            if (!childPath) {
                return { ok: false, reason: 'master playlist has no media lines' };
            }

            const childUrl = this.resolveRelativeUrl(streamUrl, childPath);
            const child = await this.fetchText(childUrl);
            const segmentPath = this.firstMediaLine(child);
            if (!segmentPath) {
                return { ok: false, reason: 'child playlist has no segment lines' };
            }

            const segmentUrl = this.resolveRelativeUrl(childUrl, segmentPath);
            const segResp = await axios.get<ArrayBuffer>(segmentUrl, {
                headers: { ...this.HEADERS, Range: 'bytes=0-15' },
                timeout: 10000,
                responseType: 'arraybuffer',
                validateStatus: () => true
            });

            if (segResp.status >= 400) {
                return { ok: false, reason: `segment request failed (${segResp.status})` };
            }

            const contentType = String(segResp.headers['content-type'] ?? '');
            const bytes = Buffer.from(segResp.data);
            if (
                contentType.toLowerCase().includes('image/') ||
                this.isPngSignature(bytes)
            ) {
                return {
                    ok: false,
                    reason: `segment is image payload (${contentType || 'unknown content-type'})`
                };
            }

            return { ok: true };
        } catch (error) {
            return { ok: false, reason: 'stream validation failed' };
        }
    }

    private async fetchText(url: string): Promise<string> {
        const response = await axios.get<string>(url, {
            headers: this.HEADERS,
            timeout: 10000,
            responseType: 'text'
        });
        if (response.status !== 200 || typeof response.data !== 'string') {
            throw new Error(`failed to fetch text (${response.status})`);
        }
        return response.data;
    }

    private firstMediaLine(playlist: string): string | undefined {
        const lines = playlist
            .split('\n')
            .map((line) => line.trim())
            .filter((line) => line.length > 0 && !line.startsWith('#'));
        return lines[0];
    }

    private resolveRelativeUrl(base: string, maybeRelative: string): string {
        if (maybeRelative.startsWith('http')) return maybeRelative;
        return new URL(maybeRelative, base).toString();
    }

    private isPngSignature(bytes: Buffer): boolean {
        if (bytes.length < 8) return false;
        return (
            bytes[0] === 0x89 &&
            bytes[1] === 0x50 &&
            bytes[2] === 0x4e &&
            bytes[3] === 0x47 &&
            bytes[4] === 0x0d &&
            bytes[5] === 0x0a &&
            bytes[6] === 0x1a &&
            bytes[7] === 0x0a
        );
    }

    /**
     * Return empty result with diagnostic
     */
    private emptyResult(
        message: string,
        media: ProviderMediaObject
    ): ProviderResult {
        return {
            sources: [],
            subtitles: [],
            diagnostics: [
                {
                    code: 'PROVIDER_ERROR',
                    message: `${this.name}: ${message}`,
                    field: '',
                    severity: 'error'
                }
            ]
        };
    }

    /**
     * Health check
     */
    async healthCheck(): Promise<boolean> {
        try {
            const response = await axios.head(this.BASE_URL, {
                timeout: 5000,
                headers: this.HEADERS
            });
            return response.status === 200;
        } catch {
            return false;
        }
    }
}
