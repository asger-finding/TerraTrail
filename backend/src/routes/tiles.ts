import Router from '@koa/router';
import { pack } from 'msgpackr';
import type { BBox, MeshLayer, TileCoord, TileMeshData, TileResponse } from '../types/index.js';
import { MBTilesReader } from '../services/mbtiles.js';
import { parseMvtTile } from '../services/mvt-parser.js';
import { bboxToTiles, tileToLonLat, tileSizeMeters } from '../services/coordinates.js';
import { generateBuildingMesh } from '../services/mesh/buildings.js';
import { generateRoadMesh } from '../services/mesh/roads.js';
import { generateFlatMesh } from '../services/mesh/flat.js';

const EMPTY: MeshLayer = { vertices: [], indices: [], normals: [] };

/**
 * Byg mesh-data for en enkelt tile. Vertex-koordinater er tile-lokale i meter.
 * Klienten beregner selv tile-position fra (x, y, z).
 */
function buildTileMesh(mbtiles: MBTilesReader, coord: TileCoord): TileMeshData | null {
    const rawTile = mbtiles.getTile(coord.z, coord.x, coord.y);
    if (!rawTile) return null;

    const tileTopLeft = tileToLonLat(coord.x, coord.y, coord.z);
    const tileSizeM = tileSizeMeters(tileTopLeft.lat, coord.z);
    const { parsed, extent } = parseMvtTile(rawTile);

    const mesh = (features: typeof parsed.buildings, gen: typeof generateBuildingMesh) =>
        features.length > 0 ? gen(features, extent, tileSizeM) : EMPTY;

    const size = tileSizeM;

    return {
        x: coord.x,
        y: coord.y,
        z: coord.z,
        ground: {
            vertices: [0, 0, 0, size, 0, 0, size, 0, size, 0, 0, size],
            indices: [0, 1, 2, 0, 2, 3],
            normals: [0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0]
        },
        buildings: mesh(parsed.buildings, generateBuildingMesh),
        roads: mesh(parsed.roads, generateRoadMesh),
        water: mesh(parsed.water, (f, e, t) => generateFlatMesh(f, e, t, 1)),
        landcover: mesh(parsed.landcover, (f, e, t) => generateFlatMesh(f, e, t, 0.5))
    };
}

export function createTileRouter(mbtiles: MBTilesReader): Router {
    const router = new Router({ prefix: '/api' });

    /**
     * Hent mesh-data for alle tiles i en bounding box.
     */
    router.get('/tiles', (ctx) => {
        const { bbox: bboxStr, zoom: zoomStr } = ctx.query;

        if (typeof bboxStr !== 'string' || typeof zoomStr !== 'string') {
            ctx.status = 400;
            ctx.body = { error: 'Mangler bbox eller zoom parameter' };
            return;
        }

        const parts = bboxStr.split(',').map(Number);
        if (parts.length !== 4 || parts.some(isNaN)) {
            ctx.status = 400;
            ctx.body = { error: 'bbox skal være minLon,minLat,maxLon,maxLat' };
            return;
        }

        const zoom = parseInt(zoomStr, 10);
        if (isNaN(zoom) || zoom < 0 || zoom > 14) {
            ctx.status = 400;
            ctx.body = { error: 'zoom skal være heltal mellem 0-14' };
            return;
        }

        const bbox: BBox = { minLon: parts[0], minLat: parts[1], maxLon: parts[2], maxLat: parts[3] };

        const tileCoords = bboxToTiles(bbox, zoom);
        const response: TileResponse = {
            tiles: tileCoords
                .map(coord => buildTileMesh(mbtiles, coord))
                .filter(t => t !== null)
        };

        const format = ctx.query.format;
        if (format === 'json') {
            ctx.type = 'application/json';
            ctx.body = JSON.stringify(response);
        } else {
            ctx.type = 'application/x-msgpack';
            ctx.body = pack(response);
        }
    });

    /**
     * Hent mesh-data for en enkelt tile.
     */
    router.get('/tile', (ctx) => {
        const { x: xStr, y: yStr, z: zStr } = ctx.query;

        if (typeof xStr !== 'string' || typeof yStr !== 'string' || typeof zStr !== 'string') {
            ctx.status = 400;
            ctx.body = { error: 'Mangler x, y eller z parameter' };
            return;
        }

        const x = parseInt(xStr, 10);
        const y = parseInt(yStr, 10);
        const z = parseInt(zStr, 10);

        if ([x, y, z].some(isNaN) || z < 0 || z > 14) {
            ctx.status = 400;
            ctx.body = { error: 'Ugyldige parametre' };
            return;
        }

        const tile = buildTileMesh(mbtiles, { x, y, z });
        if (!tile) {
            ctx.status = 404;
            ctx.body = { error: 'Tile ikke fundet' };
            return;
        }

        const response = { tile };

        const format = ctx.query.format;
        if (format === 'json') {
            ctx.type = 'application/json';
            ctx.body = JSON.stringify(response);
        } else {
            ctx.type = 'application/x-msgpack';
            ctx.body = pack(response);
        }
    });

    return router;
}
