import { Database } from 'bun:sqlite';
import { xyzToTmsY } from './coordinates.js';

/**
 * Læser tile-data fra en MBTiles-fil (SQLite-database).
 */
export class MBTilesReader {
    private db: Database;
    private statement: ReturnType<Database['prepare']>;

    constructor(path: string) {
        this.db = new Database(path, { readonly: true });

        // Preload et statement
        this.statement = this.db.prepare(
            'SELECT tile_data FROM tiles WHERE zoom_level = ? AND tile_column = ? AND tile_row = ?'
        );
    }

    /**
     * Hent rå tile-blob (gzippet MVT) for XYZ-koordinater.
     * Konverterer automatisk Y fra XYZ- til TMS-konvention.
     * @param z - Zoomniveau
     * @param x - Tile X-koordinat
     * @param y - Tile Y-koordinat (XYZ-konvention)
     * @returns Rå tile-data eller null hvis tilen ikke findes
     */
    getTile(z: number, x: number, y: number): Buffer | null {
        const tmsY = xyzToTmsY(y, z);
        const row = this.statement.get(z, x, tmsY) as { tile_data: Buffer } | null;
        return row?.tile_data ?? null;
    }

    /**
     * Luk databaseforbindelsen.
     */
    close(): void {
        this.db.close();
    }
}
