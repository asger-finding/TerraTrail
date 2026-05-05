import Router from '@koa/router';
import QRCode from 'qrcode';
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
    finalizeWaypoint,
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

const QR_PX = 1024;
const TITLE_PX = 140;

/**
 * Genererer en PNG med QR-koden (1024px) og titlen i et felt nedenunder
 */
async function buildQrPng(secret: string, title: string): Promise<Buffer> {
    const qrPng = await QRCode.toBuffer(secret, {
        type: 'png',
        width: QR_PX,
        margin: 2,
        errorCorrectionLevel: 'M'
    });

    const fontSize = Math.floor(TITLE_PX * 0.5);
    const titleSvg = Buffer.from(
        `<svg xmlns="http://www.w3.org/2000/svg" width="${QR_PX}" height="${TITLE_PX}">`
        + '<rect width="100%" height="100%" fill="white"/>'
        + `<text x="${QR_PX / 2}" y="${TITLE_PX * 0.7}" text-anchor="middle" font-family="sans-serif" font-weight="bold" font-size="${fontSize}" fill="black">${escapeXml(title)}</text>`
        + '</svg>'
    );

    return sharp(qrPng)
        .extend({ bottom: TITLE_PX, background: 'white' })
        .composite([{ input: titleSvg, top: QR_PX, left: 0 }])
        .png()
        .toBuffer();
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
     * Scan et QR-kode. For ejeren (uaktiveret) returnerer vi `pending` uden at
     * mutere. Den endelige aktivering sker når hint-billedet uploades. For
     * andre brugere registrerer vi en gennemførsel.
     */
    router.post('/scan', async (ctx) => {
        const user = ctx.state.user as AuthUser;
        const { qrSecret } = ctx.request.body as { qrSecret?: string };

        if (!qrSecret) {
            ctx.status = 400;
            ctx.body = { error: 'qrSecret er påkrævet' };
            return;
        }

        const result = scanWaypoint(user.playerId, qrSecret);
        if ('error' in result) {
            ctx.status = 400;
            ctx.body = { error: result.error };
            return;
        }

        if ('pending' in result) {
            ctx.body = { pending: true, waypointId: result.waypoint.id };
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
     * Upload hint-billede. Hvis lat/lon medsendes, aktiveres et uaktiveret
     * waypoint i samme statement som billedet skrives.
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

        const latStr = ctx.query.lat;
        const lonStr = ctx.query.lon;
        let lat: number | null = null;
        let lon: number | null = null;
        if (typeof latStr === 'string' && typeof lonStr === 'string') {
            lat = Number(latStr);
            lon = Number(lonStr);
            if (!Number.isFinite(lat) || !Number.isFinite(lon)
                || lat < -90 || lat > 90 || lon < -180 || lon > 180) {
                ctx.status = 400;
                ctx.body = { error: 'Ugyldige koordinater' };
                return;
            }
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

        if (lat !== null && lon !== null) {
            finalizeWaypoint(id, user.playerId, filename, lat, lon);
        } else {
            setWaypointImage(id, user.playerId, filename);
        }
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

        ctx.type = 'image/png';
        ctx.body = await buildQrPng(info.qrSecret, info.title);
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
