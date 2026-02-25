import type { Middleware } from 'koa';
import { verifyToken } from './jwt.js';

export const authMiddleware: Middleware = async (ctx, next) => {
    if (!ctx.path.startsWith('/api/') || ctx.path.startsWith('/api/auth/')) {
        return next();
    }

    const header = ctx.get('Authorization');
    if (!header?.startsWith('Bearer ')) {
        ctx.status = 401;
        ctx.body = { error: 'Token mangler' };
        return;
    }

    try {
        const token = header.slice(7);
        const payload = await verifyToken(token);
        ctx.state.user = { playerId: Number(payload.sub), username: payload.username };
        return next();
    } catch {
        ctx.status = 401;
        ctx.body = { error: 'Ugyldig token' };
    }
};
