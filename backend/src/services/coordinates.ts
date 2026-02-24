import type { BBox, TileCoord } from '../types/index.js';

/** Jordens omkreds ved ækvator i meter */
const EARTH_CIRCUMFERENCE_M = 40_075_016.686;

/** Jordens gennemsnitlige radius i meter */
const EARTH_RADIUS_M = 6_371_000;

/** Antal pixels pr. tile i Web Mercator-standarden. */
const TILE_SIZE_PX = 256;

/** Grader til radianer. */
const DEG2RAD = Math.PI / 180;

/**
 * Konverter længdegrad til tile X-koordinat ved et givet zoomniveau.
 * Bruger Web Mercator-projektion: lon [-180, 180] -> tile-indeks [0, 2^zoom).
 * @param lon - Længdegrad i decimalgrader
 * @param zoom - Zoomniveau (0-14)
 * @returns Tile X-indeks
 */
export function lonToTileX(lon: number, zoom: number): number {
    return Math.floor(((lon + 180) / 360) * (1 << zoom));
}

/**
 * Konverter breddegrad til tile Y-koordinat (XYZ/slippy-konvention).
 * Bruger Mercator-formlen: lat -> Y stiger sydover (Y=0 er nordligst).
 * @param lat - Breddegrad i decimalgrader
 * @param zoom - Zoomniveau (0-14)
 * @returns Tile Y-indeks
 */
export function latToTileY(lat: number, zoom: number): number {
    const latRad = lat * DEG2RAD;
    return Math.floor(
        ((1 - Math.log(Math.tan(latRad) + 1 / Math.cos(latRad)) / Math.PI) / 2) *
      (1 << zoom)
    );
}

/**
 * Konverter XYZ tile Y til TMS tile Y.
 * MBTiles bruger TMS-konvention (Y=0 er sydligst), mens slippy maps bruger XYZ (Y=0 er nordligst).
 * @param y - XYZ tile Y-koordinat
 * @param zoom - Zoomniveau
 * @returns TMS Y-koordinat
 */
export function xyzToTmsY(y: number, zoom: number): number {
    return (1 << zoom) - 1 - y;
}

/**
 * Find alle tile-koordinater der overlapper en bounding box ved et givet zoomniveau.
 * @param bbox - Bounding box (lon/lat)
 * @param zoom - Zoomniveau (0-14)
 * @returns Liste af tile-koordinater (XYZ-konvention)
 */
export function bboxToTiles(bbox: BBox, zoom: number): TileCoord[] {
    const minX = lonToTileX(bbox.minLon, zoom);
    const maxX = lonToTileX(bbox.maxLon, zoom);
    const minY = latToTileY(bbox.maxLat, zoom); // NB: højere breddegrad = lavere Y
    const maxY = latToTileY(bbox.minLat, zoom);

    const tiles: TileCoord[] = [];
    for (let x = minX; x <= maxX; x++) {
        for (let y = minY; y <= maxY; y++) {
            tiles.push({ z: zoom, x, y });
        }
    }
    return tiles;
}

/**
 * Returner øverste venstre hjørne af en tile som lon/lat.
 * Invers af lonToTileX/latToTileY — går fra tile-indeks tilbage til WGS  
 * Se: https://wiki.openstreetmap.org/wiki/Slippy_map_tilenames (Tile numbers to lon./lat.)
 * @param x - Tile X-koordinat
 * @param y - Tile Y-koordinat
 * @param zoom - Zoomniveau
 * @returns Lon/lat for tilens øverste venstre hjørne
 */
export function tileToLonLat(
    x: number,
    y: number,
    zoom: number
): { lon: number; lat: number } {
    const n = 1 << zoom;
    const lon = (x / n) * 360 - 180;
    const latRad = Math.atan(Math.sinh(Math.PI * (1 - (2 * y) / n)));
    const lat = latRad / DEG2RAD;
    return { lon, lat };
}

/**
 * Beregn opløsning i meter pr. pixel ved en given breddegrad og zoomniveau.
 *
 * Resultatet vil variere med breddegraden fordi Mercator-projektion forvrænger ekstremer
 * @param lat - Breddegrad i decimalgrader
 * @param zoom - Zoomniveau
 * @returns Meter pr. pixel
 */
export function metersPerPixel(lat: number, zoom: number): number {
    return (EARTH_CIRCUMFERENCE_M * Math.cos(lat * DEG2RAD)) / (1 << zoom) / TILE_SIZE_PX;
}

/**
 * Beregn bredde/højde af en tile i meter ved en given breddegrad og zoomniveau.
 * @param lat - Breddegrad i decimalgrader
 * @param zoom - Zoomniveau
 * @returns Tilestørrelse i meter
 */
export function tileSizeMeters(lat: number, zoom: number): number {
    return metersPerPixel(lat, zoom) * TILE_SIZE_PX;
}

/**
 * Konverter Mapbox Vector Tile extent-koordinater til meter relativt til tilens øverste venstre hjørne.
 *
 * Koordinatsystemer:  
 * Extent-rum: Heltalsgitter 0..extent (typisk 4096) inden i en enkelt MVT-tile  
 * Meter: Fysisk afstand i verdenskoordinater, relativt til tilens hjørne
 * @param coord - Koordinat i extent-rum (0..extent)
 * @param extent - Tilens extent (typisk 4096 for OpenMapTiles)
 * @param tileSizeM - Tilens fysiske størrelse i meter (fra {@link tileSizeMeters})
 * @returns Position i meter
 */
export function extentToMeters(
    coord: number,
    extent: number,
    tileSizeM: number
): number {
    return (coord / extent) * tileSizeM;
}

/**
 * Konverter lon/lat til meter-offset fra et referencepunkt via equirektangulær projektion.
 *
 * Returnerer (x, y) i meter hvor:  
 * x = øst/vest-afstand (positiv mod øst)  
 * y = nord/syd-afstand (positiv mod nord)  
 *
 * Tilstrækkelig approksimation.
 * Se: https://www.movable-type.co.uk/scripts/latlong.html#equirectangular
 * @param lon - Længdegrad i decimalgrader
 * @param lat - Breddegrad i decimalgrader
 * @param refLon - Referencepunktets længdegrad
 * @param refLat - Referencepunktets breddegrad
 * @returns Offset i meter som {x, y}
 */
export function lonLatToMeters(
    lon: number,
    lat: number,
    refLon: number,
    refLat: number
): { x: number; y: number } {
    const refLatRad = refLat * DEG2RAD;
    const x = (lon - refLon) * DEG2RAD * EARTH_RADIUS_M * Math.cos(refLatRad);
    const y = (lat - refLat) * DEG2RAD * EARTH_RADIUS_M;
    return { x, y };
}
