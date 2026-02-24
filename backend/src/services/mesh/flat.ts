import { polygons } from 'poly-extrude';
import type { MeshLayer, ParsedFeature } from '../../types/index.js';
import { extentToMeters } from '../coordinates.js';
import { flattenLayer, mergeMeshLayers, polyExtrudeToMeshLayer } from './utils.js';

/**
 * Trianguler polygon-features som flade overflader (vand, landcover, etc.) og offset til en given Y-højde (undgå z-fighting)
 * @param features - Polygon-features fra en Mapbox Vector Tile
 * @param extent - Tilens extent (default = `4096`)
 * @param tileSizeM - Tilens størrelse i meter
 * @param y - Y-forskydning for den flade overflade
 * @returns MeshLayer med vertices, indices og normals
 */
export function generateFlatMesh(
    features: ParsedFeature[],
    extent = 4096,
    tileSizeM: number,
    y: number
): MeshLayer {
    const layers: MeshLayer[] = [];

    for (const feature of features) {
        const rings = feature.geometry;
        if (rings.length === 0 || rings[0].length < 3) continue;

        const polygon: number[][][] = rings.map(ring =>
            ring.map(([ex, ey]) => [
                extentToMeters(ex, extent, tileSizeM),
                extentToMeters(ey, extent, tileSizeM)
            ])
        );

        const result = polygons([polygon]);
        if (result.indices.length === 0) continue;

        const layer = polyExtrudeToMeshLayer(result);
        flattenLayer(layer, y);
        layers.push(layer);
    }

    return mergeMeshLayers(layers);
}
