import Koa from 'koa';
import bodyParser from 'koa-bodyparser';
import { config } from './config.js';
import { MBTilesReader } from './services/mbtiles.js';
import { createTileRouter } from './routes/tiles.js';
import { createRouteRouter } from './routes/route.js';
import { createAuthRouter } from './routes/auth.js';
import { authMiddleware } from './auth/middleware.js';
import { getKeys } from './auth/keys.js';

await getKeys();

const app = new Koa();
const mbtiles = new MBTilesReader(config.mbtilesPath);

app.use(bodyParser());

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

app.use(authMiddleware);

const authRouter = createAuthRouter();
app.use(authRouter.routes());
app.use(authRouter.allowedMethods());

const tileRouter = createTileRouter(mbtiles);
app.use(tileRouter.routes());
app.use(tileRouter.allowedMethods());

const routeRouter = createRouteRouter();
app.use(routeRouter.routes());
app.use(routeRouter.allowedMethods());

app.listen(config.port, () => {
    console.log(`TerraTrail backend kører på http://localhost:${config.port}`);
    console.log(`MBTiles: ${config.mbtilesPath}`);
});

process.on('SIGINT', () => {
    mbtiles.close();
    process.exit(0);
});
