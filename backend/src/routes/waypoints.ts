import Router from '@koa/router';
import { encodeQR } from 'qr';
import sharp from 'sharp';
import { mkdirSync, existsSync, createReadStream } from 'node:fs';
import path from 'node:path';
import type { AuthUser } from '../types/index.js';
import {
    createWaypoint,
    getWaypointsInBBox,
    getWaypoint,
    getFavourites,
    getCompletions,
    getMyWaypoints,
    updateWaypoint,
    deleteWaypoint,
    scanWaypoint,
    toggleFavourite,
    getWaypointQrInfo,
    setWaypointImage,
    isWaypointCreator
} from '../waypoints/db.js';

const IMAGE_DIR = path.resolve('data/waypoint_images');
const DEFAULT_WAYPOINT_IMAGE = path.join(IMAGE_DIR, '_default.webp');
mkdirSync(IMAGE_DIR, { recursive: true });

async function readBody(ctx: { req: NodeJS.ReadableStream }): Promise<Buffer> {
    const chunks: Buffer[] = [];
    for await (const chunk of ctx.req) {
        chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
    }
    return Buffer.concat(chunks);
}

function escapeXml(s: string): string {
    return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

/**
 * Bygger en SVG med QR-koden øverst og titlen som tekst nedenunder.
 */
function buildQrSvg(secret: string, title: string): string {
    const matrix = encodeQR(secret, 'raw') as boolean[][];
    const size = matrix.length;
    const cells: string[] = [];
    for (let y = 0; y < size; y++)
        for (let x = 0; x < size; x++)
            if (matrix[y][x]) cells.push(`M${x} ${y}h1v1h-1Z`);
    return `<svg viewBox="0 0 ${size} ${size + 6}" xmlns="http://www.w3.org/2000/svg" fill="black"><path d="${cells.join('')}"/><text x="${size / 2}" y="${size + 4}" text-anchor="middle" font-size="3" font-family="sans-serif">${escapeXml(title)}</text></svg>`;
}

function validateWaypointFields(body: Record<string, unknown>): string | null {
    const { title, description, difficulty } = body as {
        title?: string; description?: string; difficulty?: number;
    };

    if (!title || !description || difficulty == null) return 'Felterne titel, beskrivelse og sværhedsgrad er påkrævet';
    if (title.length > 13) return 'Et waypoints titel må maks. være 13 tegn';
    if (description.length > 1_000) return 'Et waypoints beskrivelse må maks. være 1 000 tegn';
    if (!Number.isInteger(difficulty) || difficulty < 1 || difficulty > 3) return 'Et waypoints sværhedsgrad skal være 1, 2 eller 3';
    return null;
}

export function createWaypointRouter(): Router {
    const router = new Router({ prefix: '/api/waypoints' });

    /**
     * Opret et nyt (uaktiveret) waypoint. GPS-koordinater sættes når brugeren
     * scanner det printede QR-kode på lokationen.
     */
    router.post('/', async (ctx) => {
        const user = ctx.state.user as AuthUser;
        const body = ctx.request.body as Record<string, unknown>;
        const { title, description, difficulty } = body as {
            title?: string; description?: string; difficulty?: number;
        };

        const fieldError = validateWaypointFields(body);
        if (fieldError) {
            ctx.status = 400;
            ctx.body = { error: fieldError };
            return;
        }

        const waypoint = createWaypoint(user.playerId, title!, description!, difficulty!);
        ctx.status = 201;
        ctx.body = { waypoint };
    });

    /**
     * Returner waypoints i den givne bounding box
     */
    router.get('/', async (ctx) => {
        const user = ctx.state.user as AuthUser;
        const bbox = ctx.query.bbox as string | undefined;

        if (!bbox) {
            ctx.status = 400;
            ctx.body = { error: 'bbox query parameter er påkrævet (minLon,minLat,maxLon,maxLat)' };
            return;
        }

        const parts = bbox.split(',').map(Number);
        if (parts.length !== 4 || parts.some(isNaN)) {
            ctx.status = 400;
            ctx.body = { error: 'bbox skal være minLon,minLat,maxLon,maxLat' };
            return;
        }

        const [minLon, minLat, maxLon, maxLat] = parts;
        const waypoints = getWaypointsInBBox(minLon, minLat, maxLon, maxLat, user.playerId);
        ctx.body = { waypoints };
    });

    /**
     * Returnér brugerens favourited waypoints
     */
    router.get('/favourites', async (ctx) => {
        const user = ctx.state.user as AuthUser;
        ctx.body = { waypoints: getFavourites(user.playerId) };
    });

    /**
     * Returnér brugerens færdige waypoints
     */
    router.get('/completed', async (ctx) => {
        const user = ctx.state.user as AuthUser;
        ctx.body = { waypoints: getCompletions(user.playerId) };
    });

    /**
     * Returnér waypoints der er oprettet af brugeren
     */
    router.get('/mine', async (ctx) => {
        const user = ctx.state.user as AuthUser;
        ctx.body = { waypoints: getMyWaypoints(user.playerId) };
    });

    /**
     * Scan et QR-kode. Hvis brugeren er creator og waypointet er uaktiveret -> aktiver
     * med de medsendte GPS-koordinater. Ellers -> færdiggør (samme bruger må kun en gang).
     */
    router.post('/scan', async (ctx) => {
        const user = ctx.state.user as AuthUser;
        const { qrSecret, latitude, longitude } = ctx.request.body as {
            qrSecret?: string; latitude?: number; longitude?: number;
        };

        if (!qrSecret) {
            ctx.status = 400;
            ctx.body = { error: 'qrSecret er påkrævet' };
            return;
        }
        if (typeof latitude !== 'number' || typeof longitude !== 'number'
            || latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
            ctx.status = 400;
            ctx.body = { error: 'Ugyldige koordinater' };
            return;
        }

        const result = scanWaypoint(user.playerId, qrSecret, latitude, longitude);
        if ('error' in result) {
            ctx.status = 400;
            ctx.body = { error: result.error };
            return;
        }

        if ('activated' in result) {
            ctx.body = { activated: true, waypointId: result.waypoint.id };
        } else {
            ctx.body = { completed: true, waypointId: result.waypoint.id };
        }
    });

    /**
     * Få et waypoint fra dets ID
     */
    router.get('/:id', async (ctx) => {
        const user = ctx.state.user as AuthUser;
        const id = Number(ctx.params.id);

        if (!Number.isInteger(id)) {
            ctx.status = 400;
            ctx.body = { error: 'Ugyldigt waypoint id' };
            return;
        }

        const waypoint = getWaypoint(id, user.playerId);
        if (!waypoint) {
            ctx.status = 404;
            ctx.body = { error: 'Waypoint ikke fundet' };
            return;
        }

        ctx.body = { waypoint };
    });

    /**
     * Upload et billede for et waypoint, resize og ændrer format, og gem server-side.
     */
    router.post('/:id/image', async (ctx) => {
        const user = ctx.state.user as AuthUser;
        const id = Number(ctx.params.id);
        if (!Number.isInteger(id)) {
            ctx.status = 400;
            ctx.body = { error: 'Ugyldigt waypoint id' };
            return;
        }

        if (!isWaypointCreator(id, user.playerId)) {
            ctx.status = 403;
            ctx.body = { error: 'Waypoint ikke fundet eller er ikke din' };
            return;
        }

        let raw: Buffer;
        try {
            raw = await readBody(ctx);
        } catch (err: unknown) {
            ctx.status = 413;
            ctx.body = { error: err instanceof Error ? err.message : 'Upload fejlede' };
            return;
        }
        if (!raw.length) {
            ctx.status = 400;
            ctx.body = { error: 'Intet billede uploadet' };
            return;
        }

        const filename = `${id}.webp`;
        try {
            await sharp(raw)
                .resize(256, 256, { fit: 'cover' })
                .webp({ quality: 80 })
                .toFile(path.join(IMAGE_DIR, filename));
        } catch (err) {
            console.error('sharp failed for waypoint %d: %o', id, err);
            ctx.status = 400;
            ctx.body = { error: 'Ugyldigt billedformat' };
            return;
        }

        setWaypointImage(id, user.playerId, filename);
        ctx.status = 204;
    });

    /**
     * Serve et waypoint-image. Falder tilbage til default (timeglas) hvis
     * brugeren ikke har uploadet et eget billede.
     */
    router.get('/:id/image', async (ctx) => {
        const id = Number(ctx.params.id);
        if (!Number.isInteger(id)) {
            ctx.status = 400;
            ctx.body = { error: 'Ugyldigt waypoint id' };
            return;
        }
        const ownPath = path.join(IMAGE_DIR, `${id}.webp`);
        const filepath = existsSync(ownPath) ? ownPath : DEFAULT_WAYPOINT_IMAGE;
        ctx.type = 'image/webp';
        ctx.body = createReadStream(filepath);
    });

    /**
     * Opdater eget waypoints titel, beskrivelse og sværhedsgrad
     */
    router.put('/:id', async (ctx) => {
        const user = ctx.state.user as AuthUser;
        const id = Number(ctx.params.id);
        const body = ctx.request.body as Record<string, unknown>;

        const fieldError = validateWaypointFields(body);
        if (fieldError) {
            ctx.status = 400;
            ctx.body = { error: fieldError };
            return;
        }

        const { title, description, difficulty } = body as {
            title: string; description: string; difficulty: number;
        };

        const updated = updateWaypoint(id, user.playerId, title, description, difficulty);
        if (!updated) {
            ctx.status = 403;
            ctx.body = { error: 'Waypoint ikke fundet eller er ikke din' };
            return;
        }

        ctx.body = { waypoint: updated };
    });

    /**
     * Soft delete et eget waypoint
     */
    router.delete('/:id', async (ctx) => {
        const user = ctx.state.user as AuthUser;
        const id = Number(ctx.params.id);

        if (!deleteWaypoint(id, user.playerId)) {
            ctx.status = 403;
            ctx.body = { error: 'Waypoint ikke fundet eller er ikke din' };
            return;
        }

        // 204 No Content
        ctx.status = 204;
    });

    /**
     * Få waypoint QR-koden som PNG (1024x1024 for at kunne printes/deles)
     */
    router.get('/:id/qr', async (ctx) => {
        const user = ctx.state.user as AuthUser;
        const id = Number(ctx.params.id);

        const info = getWaypointQrInfo(id, user.playerId);
        if (!info) {
            ctx.status = 403;
            ctx.body = { error: 'Waypoint ikke fundet eller er ikke din' };
            return;
        }

        const svg = buildQrSvg(info.qrSecret, info.title);
        const png = await sharp(Buffer.from(svg))
            .resize({ width: 1024, kernel: 'nearest' })
            .png()
            .toBuffer();
        ctx.type = 'image/png';
        ctx.body = png;
    });

    /**
     * Toggle et waypoint som favourit
     */
    router.post('/:id/favourite', async (ctx) => {
        const user = ctx.state.user as AuthUser;
        const id = Number(ctx.params.id);

        const waypoint = getWaypoint(id, user.playerId);
        if (!waypoint) {
            ctx.status = 404;
            ctx.body = { error: 'Waypoint ikke fundet' };
            return;
        }

        const favourited = toggleFavourite(user.playerId, id);
        ctx.body = { favourited };
    });

    return router;
}
