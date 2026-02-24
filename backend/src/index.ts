import Koa from 'koa';
import { MBTilesReader } from './services/mbtiles.js';
import { createTileRouter } from './routes/tiles.js';
import { createRouteRouter } from './routes/route.js';
import path from 'path';

const PORT = '3000';
const MBTILES_PATH = path.resolve(import.meta.dir, '../../data/sjaelland.mbtiles');

const app = new Koa();
const mbtiles = new MBTilesReader(MBTILES_PATH);

app.use(async (ctx, next) => {
    const start = Date.now();
    await next();
    const ms = Date.now() - start;
    console.log(`${ctx.method} ${ctx.url} ${ctx.status} ${ms}ms`);
});

app.use(async (ctx, next) => {
    try {
        await next();
    } catch (err: unknown) {
        console.error('Request error:', err);
        const status = err instanceof Error && 'status' in err ? (err as { status: number }).status : 500;
        const message = err instanceof Error ? err.message : '500 Intern serverfejl';
        ctx.status = status;
        ctx.body = { error: message };
    }
});

const tileRouter = createTileRouter(mbtiles);
app.use(tileRouter.routes());
app.use(tileRouter.allowedMethods());

const routeRouter = createRouteRouter();
app.use(routeRouter.routes());
app.use(routeRouter.allowedMethods());

app.listen(PORT, () => {
    console.log(`TerraTrail backend kører på http://localhost:${PORT}`);
    console.log(`MBTiles: ${MBTILES_PATH}`);
});

process.on('SIGINT', () => {
    mbtiles.close();
    process.exit(0);
});
