import Router from '@koa/router';
import { pack } from 'msgpackr';
import { getRoute } from '../services/brouter.js';

/**
 * Opret route-endpoint der returnerer vandretur fra BRouter ud fra koordinatsæt.
 * Ruten er CSR og skal tegnes i Godot.
 * @returns Konfigureret router med GET /api/route endpoint
 */
export function createRouteRouter(): Router {
    const router = new Router({ prefix: '/api' });

    router.get('/route', async (ctx) => {
        const { from: fromStr, to: toStr } = ctx.query;

        // Query valdering
        if (typeof fromStr !== 'string' || typeof toStr !== 'string') {
            ctx.status = 400;
            ctx.body = { error: 'Mangler from eller to parameter' };
            return;
        }

        const fromParts = fromStr.split(',').map(Number);
        const toParts = toStr.split(',').map(Number);

        if (fromParts.length !== 2 || fromParts.some(isNaN)) {
            ctx.status = 400;
            ctx.body = { error: 'from skal være lon,lat' };
            return;
        }

        if (toParts.length !== 2 || toParts.some(isNaN)) {
            ctx.status = 400;
            ctx.body = { error: 'to skal være lon,lat' };
            return;
        }

        let refLon: number | undefined;
        let refLat: number | undefined;
        const originStr = ctx.query.origin;
        if (typeof originStr === 'string') {
            const originParts = originStr.split(',').map(Number);
            if (originParts.length === 2 && !originParts.some(isNaN)) {
                refLon = originParts[0];
                refLat = originParts[1];
            }
        }

        try {
            const route = await getRoute(
                fromParts[0], fromParts[1],
                toParts[0], toParts[1],
                refLon, refLat
            );

            const format = ctx.query.format;
            if (format === 'json') {
                ctx.type = 'application/json';
                ctx.body = JSON.stringify(route);
            } else {
                ctx.type = 'application/x-msgpack';
                ctx.body = pack(route);
            }
        } catch (err) {
            console.error('Route error:', err);

            ctx.status = 502;
            ctx.body = {
                error: err instanceof Error
                    ? `Rutberegning fejlede: ${err.message}`
                    : 'Ukendt fejl ved rutberegning'
            };
        }
    });

    return router;
}
