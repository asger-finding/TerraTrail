import Router from '@koa/router';
import { pack } from 'msgpackr';
import type { BBox, MeshLayer, TileResponse } from '../types/index.js';
import { MBTilesReader } from '../services/mbtiles.js';
import { parseMvtTile } from '../services/mvt-parser.js';
import { bboxToTiles, tileToLonLat, lonLatToMeters, tileSizeMeters } from '../services/coordinates.js';
import { generateBuildingMesh } from '../services/mesh/buildings.js';
import { generateRoadMesh } from '../services/mesh/roads.js';
import { generateFlatMesh } from '../services/mesh/flat.js';

const EMPTY: MeshLayer = { vertices: [], indices: [], normals: [] };

/**
 * Opret tile-endpoint der returnerer mesh-data for en bounding box af kortet.
 * Kortet er SSR og tegnes i Godot direkte ud fra dataen.
 * @param mbtiles - MBTiles reader til opslag af tile-data
 * @returns Konfigureret router med GET /api/tiles endpoint
 */
export function createTileRouter(mbtiles: MBTilesReader): Router {
    const router = new Router({ prefix: '/api' });

    router.get('/tiles', (ctx) => {
        const { bbox: bboxStr, zoom: zoomStr } = ctx.query;

        // Query valdering
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
        const originLon = (bbox.minLon + bbox.maxLon) / 2;
        const originLat = (bbox.minLat + bbox.maxLat) / 2;

        const tileCoords = bboxToTiles(bbox, zoom);

        const response: TileResponse = {
            origin: { lon: originLon, lat: originLat },
            tiles: tileCoords.map(coord => {
                const rawTile = mbtiles.getTile(coord.z, coord.x, coord.y);
                if (!rawTile) return null;

                const tileTopLeft = tileToLonLat(coord.x, coord.y, coord.z);
                const tileOffset = lonLatToMeters(tileTopLeft.lon, tileTopLeft.lat, originLon, originLat);
                const tileSizeM = tileSizeMeters(tileTopLeft.lat, coord.z);
                const { parsed, extent } = parseMvtTile(rawTile);

                const mesh = (features: typeof parsed.buildings, gen: typeof generateBuildingMesh) =>
                    features.length > 0 ? gen(features, extent, tileSizeM) : EMPTY;

                const size = tileSizeM;

                return {
                    x: coord.x,
                    y: coord.y,
                    z: coord.z,
                    origin: { x: tileOffset.x, y: -tileOffset.y },
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
            }).filter(t => t !== null)
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

    return router;
}
