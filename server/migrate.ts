import { openDatabase } from './database.js';
const database = await openDatabase(
  process.env.MIGRATION_DATABASE_URL || process.env.DATABASE_URL,
  undefined,
  { migrate: true },
);
await database.close();
console.log('Notebook schema is up to date.');
