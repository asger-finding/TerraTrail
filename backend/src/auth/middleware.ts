import type { Middleware } from 'koa';
import { verifyToken } from './jwt.js';
import { isRevoked } from './revoked.js';

export const authMiddleware: Middleware = async (ctx, next) => {
    if (!ctx.path.startsWith('/api/') || ctx.path === '/api/auth/login' || ctx.path === '/api/auth/signup') {
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
        if (isRevoked(payload.jti)) {
            ctx.status = 401;
            ctx.body = { error: 'Token er tilbagekaldt' };
            return;
        }
        ctx.state.user = {
            playerId: Number(payload.sub),
            username: payload.username,
            jti: payload.jti,
            tokenExp: payload.exp
        };
        return next();
    } catch {
        ctx.status = 401;
        ctx.body = { error: 'Ugyldig token' };
    }
};
