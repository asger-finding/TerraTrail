import Router from '@koa/router';
import { getLeaderboard } from '../users/db.js';
import type { AuthUser } from '../types/index.js';

export function createLeaderboardRouter(): Router {
    const router = new Router({ prefix: '/api/leaderboard' });

    router.get('/', async (ctx) => {
        const user = ctx.state.user as AuthUser;
        ctx.body = { entries: getLeaderboard(user.playerId) };
    });

    return router;
}
