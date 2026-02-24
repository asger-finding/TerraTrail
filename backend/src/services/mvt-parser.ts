import { VectorTile } from '@mapbox/vector-tile';
import Pbf from 'pbf';
import { gunzipSync } from 'zlib';
import type { ParsedFeature, ParsedTile } from '../types/index.js';

// OpenMapTiles-lagnavne fra Planetiler
const BUILDING_LAYERS = ['building'];
const ROAD_LAYERS = ['transportation'];
const WATER_LAYERS = ['water', 'waterway'];
const LANDCOVER_LAYERS = ['landcover', 'landuse'];

/**
 * Beregn fortegnsareal af en ring via shoelace-formlen.
 * I Mapbox Vector Tile skærmkoordinater (Y-ned): positivt = ydre ring (CW), negativt = hul (CCW)  
 * Se: https://github.com/mapbox/vector-tile-js/blob/main/index.js#L270-L278
 * @param ring - Ring som array af [x, y]-punkter
 * @returns Fortegnsareal
 */
function signedArea(ring: number[][]): number {
    let area = 0;
    for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
        area += (ring[j][0] - ring[i][0]) * (ring[i][1] + ring[j][1]);
    }
    return area;
}

/**
 * Opdel Mapbox Vector Tile-ringe i polygoner baseret på fortegnsareal.
 * En CW-ring (positivt areal) markerer starten på en ny polygon.
 * Efterfølgende CCW-ringe (negativt areal) tilføjes som huller i den aktuelle polygon.
 * @param rings - Alle ringe fra en MVT-feature
 * @returns Array af polygoner, hver med ydre ring + eventuelle huller
 */
function splitPolygons(rings: number[][][]): number[][][][] {
    const polygons: number[][][][] = [];
    let current: number[][][] | null = null;

    for (const ring of rings) {
        if (signedArea(ring) > 0) {
            current = [ring];
            polygons.push(current);
        } else if (current) {
            current.push(ring);
        }
    }

    return polygons;
}

/**
 * Udtræk features fra en VectorTile for de angivne lag og geometritype.
 * Multi-polygoner splittes i individuelle polygoner via CW/CCW fortegnsareal.
 * @param tile - Parset VectorTile
 * @param layerNames - Lagnavne at søge i (f.eks. ['building'])
 * @param type - Geometritype at filtrere på
 * @returns Array af parsede features
 */
function parseFeatures(
    tile: VectorTile,
    layerNames: string[],
    type: 'polygon' | 'linestring'
): ParsedFeature[] {
    const features: ParsedFeature[] = [];

    for (const name of layerNames) {
        const layer = tile.layers[name];
        if (!layer) continue;

        for (let i = 0; i < layer.length; i++) {
            const feature = layer.feature(i);
            const geomType = feature.type;

            // VectorTile geometrityper:
            // 1 = Point
            // 2 = LineString
            // 3 = Polygon
            if (type === 'polygon' && geomType !== 3) continue;
            if (type === 'linestring' && geomType !== 2) continue;

            const geometry = feature.loadGeometry();

            const properties = feature.properties ? { ...feature.properties } : {};
            const rings = geometry.map(ring => ring.map(p => [p.x, p.y]));

            if (type === 'polygon') {
                for (const polyRings of splitPolygons(rings)) {
                    features.push({ type, geometry: polyRings, properties });
                }
            } else {
                features.push({ type, geometry: rings, properties });
            }
        }
    }

    return features;
}

/**
 * Parse rå MBTiles tile-data (gzippet Mapbox Vector Tile) til features og extent.
 *
 * Pipeline: gzip -> gunzip -> Protobuf -> VectorTile -> feature-udtræk.
 *
 * Features returneres i extent-koordinater (heltalsgitter, typisk 0..4096).
 * Konvertering til meter sker via extentToMeters i mesh-generatorerne.
 * Extent læses fra tilen selv (fallback 4096) for at undgå hardcoded værdier.
 * @param data - Rå gzippet tile-data fra MBTiles-databasen
 * @returns Features opdelt i tematiske lag + tilens extent
 */
export function parseMvtTile(data: Buffer): { parsed: ParsedTile; extent: number } {
    const tile = new VectorTile(new Pbf(gunzipSync(data)));

    // Læs extent fra første tilgængelige lag (alle lag deler typisk samme extent).
    // Falder tilbage til 4096 hvis tilen ikke har nogen lag.
    let extent = 4096;
    for (const name of Object.keys(tile.layers)) {
        extent = tile.layers[name].extent;
        break;
    }

    return {
        parsed: {
            buildings: parseFeatures(tile, BUILDING_LAYERS, 'polygon'),
            roads: parseFeatures(tile, ROAD_LAYERS, 'linestring'),
            water: parseFeatures(tile, WATER_LAYERS, 'polygon'),
            landcover: parseFeatures(tile, LANDCOVER_LAYERS, 'polygon')
        },
        extent
    };
}
