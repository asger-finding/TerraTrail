import { extrudePolygons } from 'poly-extrude';
import type { MeshLayer, ParsedFeature } from '../../types/index.js';
import { extentToMeters } from '../coordinates.js';
import { mergeMeshLayers, polyExtrudeToMeshLayer } from './utils.js';

const DEFAULT_HEIGHT = 10;

/**
 * Generer 3D mesh for bygninger med tag, gulv og vægge.
 * @param features - Bygningspolygoner fra en Mapbox Vector Tile
 * @param extent - Tilens extent (typisk 4096)
 * @param tileSizeM - Tilens størrelse i meter
 * @returns MeshLayer med vertices, indices og normals
 */
export function generateBuildingMesh(
    features: ParsedFeature[],
    extent: number,
    tileSizeM: number
): MeshLayer {
    const layers: MeshLayer[] = [];

    for (const feature of features) {
        const height = getHeight(feature.properties);
        const rings = feature.geometry;
        if (rings.length === 0 || rings[0].length < 3) continue;

        const polygon: number[][][] = rings.map(ring =>
            ring.map(([ex, ey]) => [
                extentToMeters(ex, extent, tileSizeM),
                extentToMeters(ey, extent, tileSizeM)
            ])
        );

        const result = extrudePolygons([polygon], { depth: height });
        if (result.indices.length === 0) continue;

        layers.push(polyExtrudeToMeshLayer(result));
    }

    return mergeMeshLayers(layers);
}

/**
 * Udtræk bygningshøjde fra bygningens feature properties.
 * Bruger render_height eller height (brugbart hvis en bygning er specielt udtegnet, som f.eks. Kbh Rådhus).
 * Fallback til DEFAULT_HEIGHT.
 */
function getHeight(props: Record<string, unknown>): number {
    const h = Number(props.render_height ?? props.height);
    return h > 0 ? h : DEFAULT_HEIGHT;
}
