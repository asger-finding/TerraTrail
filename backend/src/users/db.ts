import { SQLiteError } from 'bun:sqlite';
import { db } from '../db.js';
import type { PlayerDetails, MeResponse, LeaderboardEntry } from '../types/index.js';

db.run(`
    CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT UNIQUE NOT NULL,
        password_hash TEXT NOT NULL,
        created INTEGER NOT NULL,
        last_login INTEGER NOT NULL,
        exp INTEGER NOT NULL DEFAULT 0
    )
`);

const insertUser = db.prepare<{ id: number; username: string; created: number; last_login: number }, [string, string, number, number]>(
    'INSERT INTO users (username, password_hash, created, last_login) VALUES (?, ?, ?, ?) RETURNING id, username, created, last_login'
);

const findByUsername = db.prepare<{ id: number; username: string; password_hash: string; created: number; last_login: number }, [string]>(
    'SELECT id, username, password_hash, created, last_login FROM users WHERE username = ?'
);

const updateLastLogin = db.prepare<void, [number, number]>(
    'UPDATE users SET last_login = ? WHERE id = ?'
);

const selectPasswordHash = db.prepare<{ password_hash: string }, [number]>(
    'SELECT password_hash FROM users WHERE id = ?'
);

const updateUsernameStatement = db.prepare<void, [string, number]>(
    'UPDATE users SET username = ? WHERE id = ?'
);

const updatePasswordHashStatement = db.prepare<void, [string, number]>(
    'UPDATE users SET password_hash = ? WHERE id = ?'
);

const addExpStatement = db.prepare<void, [number, number]>(
    'UPDATE users SET exp = exp + ? WHERE id = ?'
);

export function addExp(userId: number, amount: number): void {
    addExpStatement.run(amount, userId);
}

const selectMe = db.prepare<{ username: string; exp: number }, [number]>(
    'SELECT username, exp FROM users WHERE id = ?'
);

export function getMe(playerId: number): MeResponse | null {
    const row = selectMe.get(playerId);
    return row ? { username: row.username, exp: row.exp } : null;
}

const selectLeaderboard = db.prepare<LeaderboardEntry, [number]>(`
    WITH ranked AS (
        SELECT id, username, exp,
               ROW_NUMBER() OVER (ORDER BY exp DESC, id ASC) AS rank
        FROM users
    )
    SELECT rank, username, exp FROM ranked WHERE rank <= 10
    UNION
    SELECT rank, username, exp FROM ranked WHERE id = ? AND rank > 10
    ORDER BY rank ASC
`);

export function getLeaderboard(playerId: number): LeaderboardEntry[] {
    return selectLeaderboard.all(playerId);
}

export async function createUser(username: string, password: string): Promise<PlayerDetails> {
    const hash = await Bun.password.hash(password, { algorithm: 'argon2id' });
    const now = Date.now();
    const row = insertUser.get(username, hash, now, now)!;
    return { playerId: row.id, username: row.username, created: row.created, lastLogin: row.last_login };
}

export async function authenticateUser(username: string, password: string): Promise<PlayerDetails | null> {
    const user = findByUsername.get(username);
    if (!user) return null;

    const valid = await Bun.password.verify(password, user.password_hash);
    if (!valid) return null;

    const now = Date.now();
    updateLastLogin.run(now, user.id);

    return { playerId: user.id, username: user.username, created: user.created, lastLogin: now };
}

export async function updateCredentials(
    playerId: number,
    currentPassword: string,
    newUsername: string | null,
    newPassword: string | null
): Promise<{ ok: true } | { error: string }> {
    const row = selectPasswordHash.get(playerId);
    if (!row) return { error: 'Bruger ikke fundet' };

    const valid = await Bun.password.verify(currentPassword, row.password_hash);
    if (!valid) return { error: 'Forkert nuværende password' };

    if (newUsername !== null) {
        try {
            updateUsernameStatement.run(newUsername, playerId);
        } catch (err: unknown) {
            if (err instanceof SQLiteError && err.code === 'SQLITE_CONSTRAINT_UNIQUE') {
                return { error: 'Brugernavn er allerede taget' };
            }
            throw err;
        }
    }

    if (newPassword !== null) {
        const hash = await Bun.password.hash(newPassword, { algorithm: 'argon2id' });
        updatePasswordHashStatement.run(hash, playerId);
    }

    return { ok: true };
}
