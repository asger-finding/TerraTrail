import Router from '@koa/router';
import { getMe } from '../users/db.js';
import type { AuthUser } from '../types/index.js';

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

    return router;
}
