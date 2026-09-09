import { describe, expect, it, vi } from 'vitest';
import {
  CAPTURE_PAGE_EXIT_MESSAGE,
  captureBlocksPageExit,
  protectBrowserPageExit,
  runWithPageExitGuard,
} from '../src/pageExit';

describe('live-capture page exit protection', () => {
  it.each(['connecting', 'listening', 'finalizing'] as const)(
    'blocks page exit while capture is %s',
    (state) => {
      expect(captureBlocksPageExit({ state, interim: '', unconfirmedText: [] })).toBe(true);
    },
  );

  it('keeps the page locked until transient and unconfirmed text are resolved', () => {
    expect(
      captureBlocksPageExit({
        state: 'paused',
        interim: 'Still transcribing',
        unconfirmedText: [],
      }),
    ).toBe(true);
    expect(
      captureBlocksPageExit({ state: 'interrupted', interim: '', unconfirmedText: ['Keep this'] }),
    ).toBe(true);
    expect(captureBlocksPageExit({ state: 'paused', interim: '', unconfirmedText: [] })).toBe(
      false,
    );
  });

  it('runs navigation only after capture no longer blocks leaving', () => {
    const onBlocked = vi.fn();
    const action = vi.fn();

    expect(runWithPageExitGuard(true, onBlocked, action)).toBe(false);
    expect(onBlocked).toHaveBeenLastCalledWith(CAPTURE_PAGE_EXIT_MESSAGE);
    expect(action).not.toHaveBeenCalled();

    expect(runWithPageExitGuard(false, onBlocked, action)).toBe(true);
    expect(onBlocked).toHaveBeenLastCalledWith('');
    expect(action).toHaveBeenCalledOnce();
  });

  it('requests the browser confirmation for reloads and tab exits only while blocked', () => {
    const preventDefault = vi.fn();
    const event = { preventDefault, returnValue: undefined } as unknown as BeforeUnloadEvent;

    expect(protectBrowserPageExit(event, false)).toBe(false);
    expect(preventDefault).not.toHaveBeenCalled();
    expect(event.returnValue).toBeUndefined();

    expect(protectBrowserPageExit(event, true)).toBe(true);
    expect(preventDefault).toHaveBeenCalledOnce();
    expect(event.returnValue).toBe('');
  });
});
