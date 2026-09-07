import { createAuthClient } from 'better-auth/react';
export const authClient = createAuthClient();
export type ProductConfig = {
  name: string;
  development: boolean;
  passwordAuth: boolean;
  googleAuth: boolean;
  freeMinutes: number;
  meetingMinutes: number;
  price: number;
  capture: { ready: boolean; reason: string };
};
export class ApiError extends Error {
  constructor(
    public status: number,
    public data: Record<string, unknown>,
  ) {
    super(String(data.error || 'Request failed'));
  }
}
export async function api<T>(path: string, options: RequestInit = {}): Promise<T> {
  const response = await fetch(`/api${path}`, {
    signal: AbortSignal.timeout(15000),
    ...options,
    credentials: 'same-origin',
    headers: { 'Content-Type': 'application/json', ...options.headers },
  });
  const data = await response.json();
  if (!response.ok) throw new ApiError(response.status, data);
  return data as T;
}
export function download(content: string, name: string, type = 'text/markdown') {
  // Only text notebook artifacts. Audio is never accepted by this function.
  const url = URL.createObjectURL(new Blob([content], { type }));
  const a = document.createElement('a');
  a.href = url;
  a.download = name;
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
