import path from 'path';

export const config = {
    port: process.env.PORT || '3000',
    mbtilesPath: process.env.MBTILES_PATH || path.resolve(import.meta.dir, '../../lfs/map.mbtiles'),
    jwtKeysDir: process.env.JWT_KEYS_DIR || path.resolve(import.meta.dir, '../.keys'),
    jwtExpiration: process.env.JWT_EXPIRATION || '24h',
    userDbPath: process.env.USER_DB_PATH || path.resolve(import.meta.dir, '../../data/users.db')
};
