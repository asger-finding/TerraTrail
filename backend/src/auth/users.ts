import { Database } from 'bun:sqlite';
import { config } from '../config.js';
import type { PlayerDetails } from '../types/index.js';

const db = new Database(config.userDbPath, { create: true });

db.run(`
    CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT UNIQUE NOT NULL,
        password_hash TEXT NOT NULL,
        created INTEGER NOT NULL,
        last_login INTEGER NOT NULL
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
