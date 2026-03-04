/** Trianguleret mesh-lag. Flade arrays [x,y,z, ...] i meter, Godot Y-op. */
export interface MeshLayer {
    vertices: number[];
    indices: number[];
    normals: number[];
}

/** Mesh-data for 1 tile, opdelt i tematiske lag. */
export interface TileMeshData {
    x: number;
    y: number;
    z: number;
    /** Offset i meter fra responsens origin (x = øst, y = syd). */
    origin: { x: number; y: number };
    ground: MeshLayer;
    buildings: MeshLayer;
    roads: MeshLayer;
    water: MeshLayer;
    landcover: MeshLayer;
}

/** API-respons for `GET /api/tiles`. */
export interface TileResponse {
    /** Fælles WGS84-referencepunkt (bbox-centrum). */
    origin: { lon: number; lat: number };
    tiles: TileMeshData[];
}

/** WGS84 bounding box i decimalgrader. */
export interface BBox {
    minLon: number;
    minLat: number;
    maxLon: number;
    maxLat: number;
}

/** Tile-koordinat i XYZ/slippy map-konvention. Y=0 = nord. */
export interface TileCoord {
    z: number;
    x: number;
    y: number;
}

/**
 * En feature fra en Mapbox Vector Tile. Geometrien er i extent-koordinater (0..4096).
 * Polygon: ringe af [x,y]-punkter (første = ydre, resten = huller).
 * Linestring: linjestykker af [x,y]-punkter.
 */
export interface ParsedFeature {
    type: 'polygon' | 'linestring';
    geometry: number[][][];
    properties: Record<string, unknown>;
}

/** Parsede Mapbox Vector Tile-features grupperet i lag (OpenMapTiles-navne). */
export interface ParsedTile {
    buildings: ParsedFeature[];
    roads: ParsedFeature[];
    water: ParsedFeature[];
    landcover: ParsedFeature[];
}

/** Spillerdetaljer returneret fra auth-endpoints og gemt i DB. */
export interface PlayerDetails {
    playerId: number;
    username: string;
    /** Konto oprettelsestidspunkt (epoch i ms) */
    created: number;
    /** Seneste login (epoch i ms) */
    lastLogin: number;
}

/** Autentificeret bruger fra JWT-payload, sat på ctx.state.user. */
export interface AuthUser {
    playerId: number;
    username: string;
}

/** Waypoints som de står i SQLite. */
export interface WaypointRow {
    id: number;
    creator_id: number;
    title: string;
    description: string;
    difficulty: number;
    latitude: number;
    longitude: number;
    qr_secret: string;
    image_path: string | null;
    created: number;
    updated: number;
    active: number;
}

/** Waypoint med brugerspecifikke data (isCompleted, isFavourited). */
export interface WaypointResponse {
    id: number;
    creatorId: number;
    title: string;
    description: string;
    difficulty: number;
    latitude: number;
    longitude: number;
    imagePath: string | null;
    created: number;
    updated: number;
    isCompleted: boolean;
    isFavourited: boolean;
}

/** API-respons for `GET /api/route`. Koordinater i meter. */
export interface RouteResponse {
    origin: { lon: number; lat: number };
    /** Flad array [x,y,z, ...] i meter. */
    points: number[];
    /** Total distance i meter. */
    distance: number;
    /** Estimeret tid i sekunder. */
    time: number;
    /** Samlet stigning i meter. */
    ascend: number;
}
