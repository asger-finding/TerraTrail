import type { RouteResponse } from '../types/index.js';
import { lonLatToMeters } from './coordinates.js';

const BROUTER_BASE = 'https://brouter.de/brouter';

interface BRouterCoord {
    lon: number;
    lat: number;
    elevation: number;
}

interface BRouterResult {
    coordinates: BRouterCoord[];
    trackLength: number;
    totalTime: number;
    filteredAscend: number;
}

/**
 * Hent en rute fra BRouters API.
 */
async function fetchRoute(
    fromLon: number, fromLat: number,
    toLon: number, toLat: number
): Promise<BRouterResult> {
    const url = `${BROUTER_BASE}?lonlats=${fromLon},${fromLat}|${toLon},${toLat}&profile=trekking&alternativeidx=0&format=geojson`;

    const result = await fetch(url);
    if (!result.ok) {
        const text = await result.text();
        throw new Error(`BRouter-forespørgsel fejlede (${result.status}): ${text}`);
    }

    const geojson = await result.json();
    const feature = geojson.features?.[0];
    if (!feature?.geometry?.coordinates) {
        throw new Error('Uventet BRouter-responsstruktur');
    }

    const coordinates: BRouterCoord[] = feature.geometry.coordinates.map(
        (c: number[]) => ({ lon: c[0], lat: c[1], elevation: c[2] ?? 0 })
    );

    const props = feature.properties ?? {};

    return {
        coordinates,
        trackLength: Number(props['track-length'] ?? 0),
        totalTime: Number(props['total-time'] ?? 0),
        filteredAscend: Number(props['filtered ascend'] ?? 0)
    };
}

/**
 * Hent vandretur og konverter til meter-baseret lokalt koordinatsystem.
 * Bruger midtpunktet mellem from/to som origin med mindre refLon/refLat er inkluderet.
 */
export async function getRoute(
    fromLon: number, fromLat: number,
    toLon: number, toLat: number,
    refLon?: number, refLat?: number
): Promise<RouteResponse> {
    const result = await fetchRoute(fromLon, fromLat, toLon, toLat);

    const originLon = refLon ?? (fromLon + toLon) / 2;
    const originLat = refLat ?? (fromLat + toLat) / 2;

    // Konverter til flad [x, y, z, ...] i meter (Y-up: x=øst, y=elevation, z=nord)
    const points: number[] = new Array(result.coordinates.length * 3);
    for (let i = 0; i < result.coordinates.length; i++) {
        const coord = result.coordinates[i];
        const offset = lonLatToMeters(coord.lon, coord.lat, originLon, originLat);
        const base = i * 3;
        points[base] = offset.x;
        points[base + 1] = coord.elevation;
        points[base + 2] = -offset.y; // neger for at matche tile-konvention (tiles.ts:70)
    }

    return {
        origin: { lon: originLon, lat: originLat },
        points,
        distance: result.trackLength,
        time: result.totalTime,
        ascend: result.filteredAscend
    };
}
