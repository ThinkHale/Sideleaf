import { it, expect } from 'vitest';
import { mkdtemp } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { openDatabase } from '../server/database';
import { user } from '../server/schema';
it('reopens a filesystem PostgreSQL database without losing accepted data', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'notebook-persistence-'));
  let database = await openDatabase(undefined, directory);
  await database.db.insert(user).values({
    id: 'persistence-check',
    name: 'Synthetic Test',
    email: 'persist@example.test',
    createdAt: new Date(),
    updatedAt: new Date(),
  });
  await database.close();
  database = await openDatabase(undefined, directory);
  expect((await database.db.select().from(user))[0].email).toBe('persist@example.test');
  await database.close();
});
