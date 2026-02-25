import Router from '@koa/router';
import { createUser, authenticateUser } from '../auth/users.js';
import { signToken } from '../auth/jwt.js';

const USERNAME_RE = /^[A-Za-z0-9_-]{1,23}$/;

export function createAuthRouter(): Router {
    const router = new Router({ prefix: '/api/auth' });

    router.post('/register', async (ctx) => {
        const { username, password } = ctx.request.body as { username?: string; password?: string };

        if (!username || !password) {
            ctx.status = 400;
            ctx.body = { error: 'Username og password er påkrævet' };
            return;
        }

        if (!USERNAME_RE.test(username)) {
            ctx.status = 400;
            ctx.body = { error: 'Username må kun indeholde A-Z, a-z, 0-9, _ og - (1-23 tegn)' };
            return;
        }

        if (password.length < 8) {
            ctx.status = 400;
            ctx.body = { error: 'Password skal være mindst 8 tegn' };
            return;
        }

        try {
            const player = await createUser(username, password);
            const token = await signToken(player.playerId, username);
            ctx.status = 201;
            ctx.body = { token, player };
        } catch (err: unknown) {
            if (err instanceof Error && err.message.includes('UNIQUE')) {
                ctx.status = 409;
                ctx.body = { error: 'Username er allerede taget' };
                return;
            }
            throw err;
        }
    });

    router.post('/login', async (ctx) => {
        const { username, password } = ctx.request.body as { username?: string; password?: string };

        if (!username || !password) {
            ctx.status = 400;
            ctx.body = { error: 'Username og password er påkrævet' };
            return;
        }

        const player = await authenticateUser(username, password);
        if (!player) {
            ctx.status = 401;
            ctx.body = { error: 'Forkert username eller password' };
            return;
        }

        const token = await signToken(player.playerId, player.username);
        ctx.body = { token, player };
    });

    return router;
}
