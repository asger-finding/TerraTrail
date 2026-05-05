import { SQLiteError } from 'bun:sqlite';
import { db } from '../db.js';
import { addExp } from '../users/db.js';
import type { WaypointRow, WaypointResponse } from '../types/index.js';

const EXP_PER_DIFFICULTY = 20;

db.run(`
    CREATE TABLE IF NOT EXISTS waypoints (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        creator_id INTEGER NOT NULL REFERENCES users(id),
        title TEXT NOT NULL,
        description TEXT NOT NULL,
        difficulty INTEGER NOT NULL CHECK(difficulty BETWEEN 1 AND 3),
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        qr_secret TEXT UNIQUE NOT NULL,
        image_path TEXT,
        created INTEGER NOT NULL,
        updated INTEGER NOT NULL,
        active INTEGER NOT NULL DEFAULT 1,
        activated INTEGER NOT NULL DEFAULT 0
    )
`);

db.run(`
    CREATE TABLE IF NOT EXISTS waypoint_completions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL REFERENCES users(id),
        waypoint_id INTEGER NOT NULL REFERENCES waypoints(id),
        completed_at INTEGER NOT NULL,
        UNIQUE(user_id, waypoint_id)
    )
`);

db.run(`
    CREATE TABLE IF NOT EXISTS waypoint_favourites (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL REFERENCES users(id),
        waypoint_id INTEGER NOT NULL REFERENCES waypoints(id),
        created_at INTEGER NOT NULL,
        UNIQUE(user_id, waypoint_id)
    )
`);

const insertWaypoint = db.prepare<WaypointRow, [number, string, string, number, string, number, number]>(
    `INSERT INTO waypoints (creator_id, title, description, difficulty, latitude, longitude, qr_secret, created, updated, activated)
     VALUES (?, ?, ?, ?, 0, 0, ?, ?, ?, 0)
     RETURNING *`
);

const finalizeStatement = db.prepare<{ id: number }, [string, number, number, number, number, number]>(
    `UPDATE waypoints SET image_path = ?, latitude = ?, longitude = ?, activated = 1, updated = ?
     WHERE id = ? AND creator_id = ? AND activated = 0
     RETURNING id`
);

const selectInBBox = db.prepare<
    WaypointRow & { is_completed: number; is_favourited: number },
    [number, number, number, number, number, number]
>(
    `SELECT w.*,
            (wc.id IS NOT NULL) AS is_completed,
            (wf.id IS NOT NULL) AS is_favourited
     FROM waypoints w
     LEFT JOIN waypoint_completions wc ON wc.waypoint_id = w.id AND wc.user_id = ?
     LEFT JOIN waypoint_favourites  wf ON wf.waypoint_id = w.id AND wf.user_id = ?
     WHERE w.active = 1 AND w.activated = 1
       AND w.longitude BETWEEN ? AND ?
       AND w.latitude  BETWEEN ? AND ?`
);

const selectById = db.prepare<
    WaypointRow & { is_completed: number; is_favourited: number },
    [number, number, number]
>(
    `SELECT w.*,
            (wc.id IS NOT NULL) AS is_completed,
            (wf.id IS NOT NULL) AS is_favourited
     FROM waypoints w
     LEFT JOIN waypoint_completions wc ON wc.waypoint_id = w.id AND wc.user_id = ?
     LEFT JOIN waypoint_favourites  wf ON wf.waypoint_id = w.id AND wf.user_id = ?
     WHERE w.id = ? AND w.active = 1 AND w.activated = 1`
);

const selectFavourites = db.prepare<
    WaypointRow & { is_completed: number; is_favourited: number },
    [number, number]
>(
    `SELECT w.*,
            (wc.id IS NOT NULL) AS is_completed,
            1 AS is_favourited
     FROM waypoints w
     INNER JOIN waypoint_favourites wf ON wf.waypoint_id = w.id AND wf.user_id = ?
     LEFT JOIN waypoint_completions wc ON wc.waypoint_id = w.id AND wc.user_id = ?
     WHERE w.active = 1 AND w.activated = 1
     ORDER BY wf.created_at DESC`
);

const selectCompletions = db.prepare<
    WaypointRow & { is_completed: number; is_favourited: number },
    [number, number]
>(
    `SELECT w.*,
            1 AS is_completed,
            (wf.id IS NOT NULL) AS is_favourited
     FROM waypoints w
     INNER JOIN waypoint_completions wc ON wc.waypoint_id = w.id AND wc.user_id = ?
     LEFT JOIN waypoint_favourites wf ON wf.waypoint_id = w.id AND wf.user_id = ?
     WHERE w.active = 1 AND w.activated = 1
     ORDER BY wc.completed_at DESC`
);

const selectMyWaypoints = db.prepare<
    WaypointRow & { is_completed: number; is_favourited: number },
    [number, number]
>(
    `SELECT w.*,
            0 AS is_completed,
            (wf.id IS NOT NULL) AS is_favourited
     FROM waypoints w
     LEFT JOIN waypoint_favourites wf ON wf.waypoint_id = w.id AND wf.user_id = ?
     WHERE w.creator_id = ? AND w.active = 1
     ORDER BY w.created DESC`
);

const updateStatement = db.prepare<WaypointRow, [string, string, number, number, number, number]>(
    `UPDATE waypoints SET title = ?, description = ?, difficulty = ?, updated = ?
     WHERE id = ? AND creator_id = ?
     RETURNING *`
);

const softDeleteStatement = db.prepare<{ id: number }, [number, number, number]>(
    `UPDATE waypoints SET active = 0, updated = ?
     WHERE id = ? AND creator_id = ?
     RETURNING id`
);

const updateImageStatement = db.prepare<{ id: number }, [string | null, number, number, number]>(
    `UPDATE waypoints SET image_path = ?, updated = ?
     WHERE id = ? AND creator_id = ?
     RETURNING id`
);

const selectBySecret = db.prepare<WaypointRow, [string]>(
    'SELECT * FROM waypoints WHERE qr_secret = ? AND active = 1'
);

const insertCompletion = db.prepare<{ id: number }, [number, number, number]>(
    'INSERT INTO waypoint_completions (user_id, waypoint_id, completed_at) VALUES (?, ?, ?) RETURNING id'
);

const selectFavourite = db.prepare<{ id: number }, [number, number]>(
    'SELECT id FROM waypoint_favourites WHERE user_id = ? AND waypoint_id = ?'
);

const insertFavourite = db.prepare<{ id: number }, [number, number, number]>(
    'INSERT INTO waypoint_favourites (user_id, waypoint_id, created_at) VALUES (?, ?, ?) RETURNING id'
);

const deleteFavourite = db.prepare<void, [number, number]>(
    'DELETE FROM waypoint_favourites WHERE user_id = ? AND waypoint_id = ?'
);

const selectQrInfoByIdAndCreator = db.prepare<{ qr_secret: string; title: string }, [number, number]>(
    'SELECT qr_secret, title FROM waypoints WHERE id = ? AND creator_id = ? AND active = 1'
);

const selectOwnership = db.prepare<{ id: number }, [number, number]>(
    'SELECT id FROM waypoints WHERE id = ? AND creator_id = ? AND active = 1'
);

function toFormattedResponse(row: WaypointRow & { is_completed: number; is_favourited: number }): WaypointResponse {
    return {
        id: row.id,
        creatorId: row.creator_id,
        title: row.title,
        description: row.description,
        difficulty: row.difficulty,
        latitude: row.latitude,
        longitude: row.longitude,
        imagePath: row.image_path ?? '',
        created: row.created,
        updated: row.updated,
        isCompleted: row.is_completed === 1,
        isFavourited: row.is_favourited === 1,
        activated: row.activated === 1
    };
}

export function createWaypoint(
    creatorId: number, title: string, description: string, difficulty: number
): WaypointRow {
    const qrSecret = crypto.randomUUID();
    const now = Date.now();
    return insertWaypoint.get(creatorId, title, description, difficulty, qrSecret, now, now)!;
}

export function getWaypointsInBBox(
    minLon: number, minLat: number, maxLon: number, maxLat: number, userId: number
): WaypointResponse[] {
    return selectInBBox.all(userId, userId, minLon, maxLon, minLat, maxLat).map(toFormattedResponse);
}

export function getWaypoint(id: number, userId: number): WaypointResponse | null {
    const row = selectById.get(userId, userId, id);
    return row ? toFormattedResponse(row) : null;
}

export function getFavourites(userId: number): WaypointResponse[] {
    return selectFavourites.all(userId, userId).map(toFormattedResponse);
}

export function getCompletions(userId: number): WaypointResponse[] {
    return selectCompletions.all(userId, userId).map(toFormattedResponse);
}

export function getMyWaypoints(userId: number): WaypointResponse[] {
    return selectMyWaypoints.all(userId, userId).map(toFormattedResponse);
}

export function updateWaypoint(
    id: number, creatorId: number, title: string, description: string, difficulty: number
): WaypointRow | null {
    const now = Date.now();
    return updateStatement.get(title, description, difficulty, now, id, creatorId) ?? null;
}

export function deleteWaypoint(id: number, creatorId: number): boolean {
    const now = Date.now();
    return softDeleteStatement.get(now, id, creatorId) !== null;
}

export function setWaypointImage(id: number, creatorId: number, filename: string | null): boolean {
    const now = Date.now();
    return updateImageStatement.get(filename, now, id, creatorId) !== null;
}

export type ScanResult =
    | { pending: true; waypoint: WaypointRow }
    | { completed: true; waypoint: WaypointRow }
    | { error: string };

/**
 * Validerer QR-koden. Hvis ejeren scanner et uaktiveret waypoint returneres
 * `pending`, og selve aktiveringen sker først når hint-billedet uploades.
 */
export function scanWaypoint(userId: number, qrSecret: string): ScanResult {
    const waypoint = selectBySecret.get(qrSecret);
    if (!waypoint) return { error: 'Waypoint ikke fundet' };

    if (waypoint.creator_id === userId) {
        if (waypoint.activated === 1) return { error: 'Egen waypoint, allerede aktiveret' };
        return { pending: true, waypoint };
    }

    if (waypoint.activated === 0) return { error: 'Waypoint ikke aktiveret endnu' };

    try {
        insertCompletion.get(userId, waypoint.id, Date.now());
    } catch (err: unknown) {
        if (err instanceof SQLiteError && err.code === 'SQLITE_CONSTRAINT_UNIQUE') return { error: 'Allerede gennemført' };
        throw err;
    }

    addExp(userId, waypoint.difficulty * EXP_PER_DIFFICULTY);
    return { completed: true, waypoint };
}

/**
 * Sætter image_path og aktiverer i ét UPDATE-statement med lat/lon.
 */
export function finalizeWaypoint(
    id: number, creatorId: number, filename: string, latitude: number, longitude: number
): boolean {
    return finalizeStatement.get(filename, latitude, longitude, Date.now(), id, creatorId) !== null;
}

export function toggleFavourite(userId: number, waypointId: number): boolean {
    const existing = selectFavourite.get(userId, waypointId);
    if (existing) {
        deleteFavourite.run(userId, waypointId);
        return false;
    }
    insertFavourite.get(userId, waypointId, Date.now());
    return true;
}

export function getWaypointQrInfo(id: number, creatorId: number): { qrSecret: string; title: string } | null {
    const row = selectQrInfoByIdAndCreator.get(id, creatorId);
    return row ? { qrSecret: row.qr_secret, title: row.title } : null;
}

export function isWaypointCreator(id: number, creatorId: number): boolean {
    return selectOwnership.get(id, creatorId) !== null;
}
