import { join, resolve } from 'node:path';
import { homedir } from 'node:os';
import { createHash } from 'node:crypto';
// Keep the development database and authentication secret outside synced
// source folders. OneDrive's directory attributes also break WASM POSIX writes.
// Preserve the original directory name across the Sideleaf rename for existing accounts.
const checkout = createHash('sha256').update(resolve('.')).digest('hex').slice(0, 12);
export const appDataDirectory =
  process.env.APP_DATA_DIR ||
  join(process.env.LOCALAPPDATA || join(homedir(), '.local', 'share'), 'MeetingNotebook', checkout);
