import { db } from '../db.js';
import type { AchievementResponse } from '../types/index.js';

db.run(`
    CREATE TABLE IF NOT EXISTS achievements (
        id INTEGER PRIMARY KEY,
        title TEXT NOT NULL,
        description TEXT NOT NULL
    )
`);

const SEED: AchievementResponse[] = [
    { id: 0, title: 'Alpe d\'Huez', description: 'Du har overkommet 1.860 højdemeter' },
    { id: 1, title: 'Off the Beaten Path', description: 'Du har indsamlet et waypoint mere end 5 km fra nærmeste civilisation' },
    { id: 2, title: 'Go-getter', description: 'Du har indsamlet 10 waypoints' },
    { id: 3, title: 'One Small Step for Man', description: 'Du har gået 5 km' },
    { id: 4, title: 'Slap af Kejelcha', description: 'Du har gået 10 km' },
    { id: 5, title: 'EZ25K', description: 'Du har gået 25 km' },
    { id: 6, title: 'One Giant Leap for Mankind', description: 'Du har gået 50 km' }
];

const insertAchievement = db.prepare<void, [number, string, string]>(
    'INSERT OR REPLACE INTO achievements (id, title, description) VALUES (?, ?, ?)'
);

for (const a of SEED) {
    insertAchievement.run(a.id, a.title, a.description);
}

const selectAll = db.prepare<AchievementResponse, []>(
    'SELECT id, title, description FROM achievements ORDER BY id ASC'
);

export function getAllAchievements(): AchievementResponse[] {
    return selectAll.all();
}
