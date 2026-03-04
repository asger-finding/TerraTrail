import { Database } from 'bun:sqlite';
import { config } from './config.js';

export const db = new Database(config.dbPath, { create: true });
