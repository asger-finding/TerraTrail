import Router from '@koa/router';
import sharp from 'sharp';
import { mkdirSync, existsSync, createReadStream } from 'node:fs';
import path from 'node:path';
import { getMe, updateCredentials } from '../users/db.js';
import { USERNAME_RE, MIN_PASSWORD_LENGTH } from './auth.js';
import type { AuthUser } from '../types/index.js';

const PROFILE_IMAGE_DIR = path.resolve('data/profile_images');
const DEFAULT_PROFILE_IMAGE = path.join(PROFILE_IMAGE_DIR, '_default.webp');
mkdirSync(PROFILE_IMAGE_DIR, { recursive: true });

async function readBody(ctx: { req: NodeJS.ReadableStream }): Promise<Buffer> {
    const chunks: Buffer[] = [];
    for await (const chunk of ctx.req) {
        chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
    }
    return Buffer.concat(chunks);
}

export function createMeRouter(): Router {
    const router = new Router({ prefix: '/api/me' });

    router.get('/', async (ctx) => {
        const user = ctx.state.user as AuthUser;
        const me = getMe(user.playerId);
        if (!me) {
            ctx.status = 404;
            ctx.body = { error: 'Bruger ikke fundet' };
            return;
        }
        ctx.body = me;
    });

    /**
     * Opdater username og/eller password. Nuværende pass er altid påkrævet.
     */
    router.patch('/', async (ctx) => {
        const user = ctx.state.user as AuthUser;
        const body = ctx.request.body as {
            currentPassword?: string;
            newUsername?: string;
            newPassword?: string;
        };

        if (!body.currentPassword) {
            ctx.status = 400;
            ctx.body = { error: 'Nuværende adganskode er påkrævet' };
            return;
        }
        if (!body.newUsername && !body.newPassword) {
            ctx.status = 400;
            ctx.body = { error: 'Ingen ændringer angivet' };
            return;
        }
        if (body.newUsername && !USERNAME_RE.test(body.newUsername)) {
            ctx.status = 400;
            ctx.body = { error: 'Brugernavn må kun indeholde A-Z, a-z, 0-9, _ og - (1-23 tegn)' };
            return;
        }
        if (body.newPassword && body.newPassword.length < MIN_PASSWORD_LENGTH) {
            ctx.status = 400;
            ctx.body = { error: 'Adgangskode skal være mindst 8 tegn' };
            return;
        }

        const result = await updateCredentials(
            user.playerId,
            body.currentPassword,
            body.newUsername ?? null,
            body.newPassword ?? null
        );
        if ('error' in result) {
            ctx.status = 400;
            ctx.body = { error: result.error };
            return;
        }
        ctx.status = 204;
    });

    /**
     * Hent egen profilbillede. Returnerer brugerens uploadede billede hvis det findes,
     * ellers returneres det fælles default profile pic.
     */
    router.get('/picture', async (ctx) => {
        const user = ctx.state.user as AuthUser;
        const ownPath = path.join(PROFILE_IMAGE_DIR, `${user.playerId}.webp`);
        const filepath = existsSync(ownPath) ? ownPath : DEFAULT_PROFILE_IMAGE;
        ctx.type = 'image/webp';
        ctx.body = createReadStream(filepath);
    });

    /**
     * Upload nyt profilbillede. Body er det rå billede. Vi resizer og gemmer som WebP.
     */
    router.post('/picture', async (ctx) => {
        const user = ctx.state.user as AuthUser;

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

        try {
            await sharp(raw)
                .resize(256, 256, { fit: 'cover' })
                .webp({ quality: 80 })
                .toFile(path.join(PROFILE_IMAGE_DIR, `${user.playerId}.webp`));
        } catch (err) {
            console.error('sharp failed for profile picture %d: %o', user.playerId, err);
            ctx.status = 400;
            ctx.body = { error: 'Ugyldigt billedformat' };
            return;
        }

        ctx.status = 204;
    });

    return router;
}
