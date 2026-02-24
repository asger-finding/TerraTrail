import { expandPaths } from 'poly-extrude';
import type { MeshLayer, ParsedFeature } from '../../types/index.js';
import { extentToMeters } from '../coordinates.js';
import { flattenLayer, mergeMeshLayers, polyExtrudeToMeshLayer } from './utils.js';

const ROAD_Y = 1.5;

const ROAD_RADII: Record<string, number> = {
    motorway: 6,
    trunk: 5,
    primary: 4,
    secondary: 3,
    tertiary: 2.5,
    minor: 2,
    residential: 2,
    service: 1.5,
    track: 1.5,
    path: 0.75,
    footway: 0.5,
    cycleway: 0.75
};

const DEFAULT_RADIUS = 2;

/**
 * Generer fladt band mesh for vejene
 * @param features - Vej-linestrings fra en Mapbox Vector Tile
 * @param extent - Tilens extent (default = `4096`)
 * @param tileSizeM - Tilens størrelse i meter
 * @returns MeshLayer med vertices, indices og normals
 */
export function generateRoadMesh(
    features: ParsedFeature[],
    extent = 4096,
    tileSizeM: number
): MeshLayer {
    const layers: MeshLayer[] = [];

    for (const feature of features) {
        const radius = getRoadRadius(feature.properties);

        for (const line of feature.geometry) {
            if (line.length < 2) continue;

            const points: number[][] = line.map(([ex, ey]) => [
                extentToMeters(ex, extent, tileSizeM),
                extentToMeters(ey, extent, tileSizeM)
            ]);

            const result = expandPaths([points], { lineWidth: radius * 2 });
            if (result.indices.length === 0) continue;

            const layer = polyExtrudeToMeshLayer(result);
            flattenLayer(layer, ROAD_Y);
            layers.push(layer);
        }
    }

    return mergeMeshLayers(layers);
}

/**
 * Slå vejens halve bredde op baseret på vejklassen fra properties.
 */
function getRoadRadius(properties: Record<string, unknown>): number {
    const cls = String(properties.class ?? '');
    return ROAD_RADII[cls] ?? DEFAULT_RADIUS;
}
