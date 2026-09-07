import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const calls = vi.hoisted(() => ({ pool: vi.fn(), query: vi.fn(), end: vi.fn() }));
vi.mock('pg', () => ({
  default: {
    Pool: class {
      query = calls.query;
      end = calls.end;
      on() {
        return this;
      }
      constructor(options: unknown) {
        calls.pool(options);
      }
    },
  },
}));
vi.mock('drizzle-orm/node-postgres', () => ({ drizzle: () => ({}) }));

import { openDatabase } from '../server/database';
const connection = 'postgresql://synthetic.invalid/sideleaf?sslmode=verify-full';

beforeEach(() => {
  vi.stubEnv('NODE_ENV', 'production');
  vi.clearAllMocks();
  calls.query.mockResolvedValue({ rows: [] });
  calls.end.mockResolvedValue(undefined);
});
afterEach(() => vi.unstubAllEnvs());

describe('cloud database startup boundaries', () => {
  it('does not fall back to a local database in production', async () => {
    await expect(openDatabase(undefined, ':memory:')).rejects.toThrow('external PostgreSQL');
    expect(calls.pool).not.toHaveBeenCalled();
  });

  it.each([
    'postgresql://synthetic.invalid/sideleaf',
    'postgresql://synthetic.invalid/sideleaf?sslmode=disable',
    `${connection}&sslmode=disable`,
    `${connection}&ssl=no-verify`,
  ])('rejects a connection that does not enforce verified TLS: %s', async (address) => {
    await expect(openDatabase(address)).rejects.toThrow('sslmode=verify-full');
    expect(calls.pool).not.toHaveBeenCalled();
  });

  it('leaves schema DDL out of production request startup', async () => {
    const database = await openDatabase(connection);
    expect(database.pool).toBeDefined();
    expect(calls.query).not.toHaveBeenCalled();
    await database.close();
    expect(calls.end).toHaveBeenCalledOnce();
  });

  it('runs schema setup only for an explicit migration', async () => {
    const database = await openDatabase(connection, undefined, { migrate: true });
    expect(calls.query).toHaveBeenCalledWith(expect.stringContaining('CREATE TABLE'));
    await database.close();
  });

  it('releases the pool when an explicit migration fails', async () => {
    calls.query.mockRejectedValueOnce(new Error('Synthetic migration failure'));
    await expect(openDatabase(connection, undefined, { migrate: true })).rejects.toThrow(
      'Synthetic migration failure',
    );
    expect(calls.end).toHaveBeenCalledOnce();
  });
});
