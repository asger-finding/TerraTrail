import { createWaypoint, scanWaypoint } from '../waypoints/db.js';

const CREATOR_ID = 1;
const DESCRIPTION = 'Lorem ipsum og lidt beskrivelse';

const WAYPOINTS = [
    { title: 'Spawn', difficulty: 1, lat: 55.7641, lon: 12.5431 },
    { title: 'Havfruen', difficulty: 3, lat: 55.6929, lon: 12.5992 }
];

for (const { title, difficulty, lat, lon } of WAYPOINTS) {
    const row = createWaypoint(CREATOR_ID, title, DESCRIPTION, difficulty);
    scanWaypoint(CREATOR_ID, row.qr_secret, lat, lon);
    console.log(`+ ${row.id}: ${title}`);
}
