import type { CaptureState } from '../shared/domain';

export const CAPTURE_PAGE_EXIT_MESSAGE =
  'Finish live transcription before leaving this page. Pause, cancel, or stop capture, wait for it to finish, then download or discard any unconfirmed text.';

type ExitSensitiveCapture = {
  state: CaptureState;
  interim: string;
  unconfirmedText: readonly string[];
};

export function captureBlocksPageExit(capture: ExitSensitiveCapture) {
  return (
    ['connecting', 'listening', 'finalizing'].includes(capture.state) ||
    capture.interim.length > 0 ||
    capture.unconfirmedText.length > 0
  );
}

export function runWithPageExitGuard(
  captureActive: boolean,
  onBlocked: (message: string) => void,
  action: () => void,
) {
  if (captureActive) {
    onBlocked(CAPTURE_PAGE_EXIT_MESSAGE);
    return false;
  }
  onBlocked('');
  action();
  return true;
}

export function protectBrowserPageExit(event: BeforeUnloadEvent, captureActive: boolean) {
  if (!captureActive) return false;
  event.preventDefault();
  event.returnValue = '';
  return true;
}
