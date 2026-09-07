import { openDatabase } from './database';
const database = await openDatabase(process.env.DATABASE_URL);
await database.close();
console.log('Notebook schema is up to date.');
