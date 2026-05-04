import { db } from '../db.js';

db.run(`
    CREATE TABLE IF NOT EXISTS revoked_tokens (
        jti TEXT PRIMARY KEY,
        expires_at INTEGER NOT NULL
    )
`);

const insertRevoked = db.prepare<void, [string, number]>(
    'INSERT OR IGNORE INTO revoked_tokens (jti, expires_at) VALUES (?, ?)'
);

const selectRevoked = db.prepare<{ jti: string }, [string]>(
    'SELECT jti FROM revoked_tokens WHERE jti = ?'
);

const deleteExpired = db.prepare<void, [number]>(
    'DELETE FROM revoked_tokens WHERE expires_at < ?'
);

export function revokeToken(jti: string, expSeconds: number): void {
    insertRevoked.run(jti, expSeconds);
    // Opportunistic cleanup so the table doesn't grow unbounded.
    deleteExpired.run(Math.floor(Date.now() / 1000));
}

export function isRevoked(jti: string): boolean {
    return selectRevoked.get(jti) !== null;
}
