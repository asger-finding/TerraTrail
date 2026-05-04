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
    updateWaypoint,
    deleteWaypoint,
    completeWaypoint,
    toggleFavourite,
    getWaypointSecret,
    setWaypointImage,
    isWaypointCreator
} from '../waypoints/db.js';

const IMAGE_DIR = path.resolve('data/waypoint_images');
mkdirSync(IMAGE_DIR, { recursive: true });

async function readBody(ctx: { req: NodeJS.ReadableStream }): Promise<Buffer> {
    const chunks: Buffer[] = [];
    for await (const chunk of ctx.req) {
        chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk as Uint8Array));
    }
    return Buffer.concat(chunks);
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
     * Create a new waypoint as a user
     */
    router.post('/', async (ctx) => {
        const user = ctx.state.user as AuthUser;
        const body = ctx.request.body as Record<string, unknown>;
        const { title, description, difficulty, latitude, longitude } = body as {
            title?: string; description?: string; difficulty?: number;
            latitude?: number; longitude?: number;
        };

        const fieldError = validateWaypointFields(body);
        if (fieldError || latitude == null || longitude == null) {
            ctx.status = 400;
            ctx.body = { error: fieldError ?? 'Latitude og longitude er påkrævet' };
            return;
        }

        if (typeof latitude !== 'number' || typeof longitude !== 'number'
            || latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
            ctx.status = 400;
            ctx.body = { error: 'Ugyldige koordinater' };
            return;
        }

        const waypoint = createWaypoint(user.playerId, title!, description!, difficulty!, latitude, longitude);
        ctx.status = 201;
        ctx.body = { waypoint };
    });

    /**
     * List relevant waypoints in the bbox
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
     * List the current user's favourited waypoints
     */
    router.get('/favourites', async (ctx) => {
        const user = ctx.state.user as AuthUser;
        ctx.body = { waypoints: getFavourites(user.playerId) };
    });

    /**
     * List the current user's completed waypoints
     */
    router.get('/completed', async (ctx) => {
        const user = ctx.state.user as AuthUser;
        ctx.body = { waypoints: getCompletions(user.playerId) };
    });

    /**
     * Complete a waypoint via the QR secret code
     */
    router.post('/complete', async (ctx) => {
        const user = ctx.state.user as AuthUser;
        const { qrSecret } = ctx.request.body as { qrSecret?: string };

        if (!qrSecret) {
            ctx.status = 400;
            ctx.body = { error: 'qrSecret er påkrævet' };
            return;
        }

        const result = completeWaypoint(user.playerId, qrSecret);
        if ('error' in result) {
            ctx.status = 400;
            ctx.body = { error: result.error };
            return;
        }

        ctx.body = { completed: true, waypointId: result.waypoint.id };
    });

    /**
     * Get a waypoint by waypoint ID
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
     * Upload an image hint for a waypoint. Body is the raw image bytes (any
     * common format). The server resizes to 256x256, encodes as WebP at 80%
     * quality, and stores it under data/waypoint_images/.
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
     * Serve a waypoint's image hint. Anyone authenticated can view.
     */
    router.get('/:id/image', async (ctx) => {
        const id = Number(ctx.params.id);
        if (!Number.isInteger(id)) {
            ctx.status = 400;
            ctx.body = { error: 'Ugyldigt waypoint id' };
            return;
        }
        const filepath = path.join(IMAGE_DIR, `${id}.webp`);
        if (!existsSync(filepath)) {
            ctx.status = 404;
            ctx.body = { error: 'Billede ikke fundet' };
            return;
        }
        ctx.type = 'image/webp';
        ctx.body = createReadStream(filepath);
    });

    /**
     * Update own waypoint title, description, difficulty
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
     * Soft delete own waypoint
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
     * Get the QR code as a GIF
     */
    router.get('/:id/qr', async (ctx) => {
        const user = ctx.state.user as AuthUser;
        const id = Number(ctx.params.id);

        const secret = getWaypointSecret(id, user.playerId);
        if (!secret) {
            ctx.status = 403;
            ctx.body = { error: 'Waypoint ikke fundet eller er ikke din' };
            return;
        }

        const gif = encodeQR(secret, 'gif');
        ctx.type = 'image/gif';
        ctx.body = Buffer.from(gif);
    });

    /**
     * Toggle any waypoint as a favourite
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
