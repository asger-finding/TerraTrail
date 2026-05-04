import Router from '@koa/router';
import { getAllAchievements } from '../achievements/db.js';

export function createAchievementsRouter(): Router {
    const router = new Router({ prefix: '/api/achievements' });

    router.get('/', async (ctx) => {
        ctx.body = { achievements: getAllAchievements() };
    });

    return router;
}
