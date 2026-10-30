import type { IScannerControls } from '@zxing/browser';
import { useCallback, useEffect, useRef, useState } from 'react';

export type CameraIssue = 'unsupported' | 'insecure' | 'permissionDenied' | 'noCamera' | 'inUse' | 'failed';

export type CameraState =
  | { status: 'starting' }
  | { status: 'running'; torch: boolean | null }
  | { status: 'stopped' }
  | { status: 'issue'; issue: CameraIssue };

/** Why the camera could not start, from the browser's error. */
export function classifyCameraError(error: unknown): CameraIssue {
  const name = error instanceof Error || (error && typeof error === 'object' && 'name' in error) ? String((error as { name: unknown }).name) : '';
  switch (name) {
    case 'NotAllowedError':
    case 'PermissionDeniedError':
    case 'SecurityError':
      return 'permissionDenied';
    case 'NotFoundError':
    case 'DevicesNotFoundError':
    case 'OverconstrainedError':
      return 'noCamera';
    case 'NotReadableError':
    case 'TrackStartError':
    case 'AbortError':
      return 'inUse';
    // This page cannot use the camera at all (also how headless browsers refuse).
    case 'NotSupportedError':
      return 'unsupported';
    default:
      return 'failed';
  }
}

/** Whether this browser can scan at all, before asking for the camera. */
export function cameraSupport(): CameraIssue | null {
  if (typeof window === 'undefined') return 'unsupported';
  // Browsers only expose the camera on HTTPS (and on localhost).
  if (!window.isSecureContext) return 'insecure';
  if (!navigator.mediaDevices?.getUserMedia) return 'unsupported';
  return null;
}

/**
 * Reads QR codes from the rear camera into [videoRef]. [onCode] receives
 * each decoded text; returning `true` means "handled", after which the
 * camera stops and no further code is reported (no double navigation).
 *
 * The camera is released when the component unmounts or the tab is hidden,
 * and started again when it comes back.
 */
export function useQrScanner(
  videoRef: React.RefObject<HTMLVideoElement | null>,
  onCode: (text: string) => boolean,
  enabled = true,
) {
  const [state, setState] = useState<CameraState>(() => {
    const issue = cameraSupport();
    return issue ? { status: 'issue', issue } : { status: 'starting' };
  });
  const controls = useRef<IScannerControls | null>(null);
  const handled = useRef(false);
  const generation = useRef(0);
  const onCodeRef = useRef(onCode);
  onCodeRef.current = onCode;

  const stop = useCallback(() => {
    generation.current++;
    controls.current?.stop();
    controls.current = null;
    // Belt and braces: release any track the reader left on the element.
    const stream = videoRef.current?.srcObject as MediaStream | null | undefined;
    if (stream && typeof stream.getTracks === 'function') for (const track of stream.getTracks()) track.stop();
    if (videoRef.current) videoRef.current.srcObject = null;
  }, [videoRef]);

  const start = useCallback(async () => {
    const issue = cameraSupport();
    if (issue) {
      setState({ status: 'issue', issue });
      return;
    }
    const video = videoRef.current;
    if (!video || handled.current) return;
    stop();
    const run = ++generation.current;
    setState({ status: 'starting' });
    try {
      const { BrowserQRCodeReader } = await import('@zxing/browser');
      if (run !== generation.current) return;
      const reader = new BrowserQRCodeReader(undefined, { delayBetweenScanAttempts: 120, delayBetweenScanSuccess: 400 });
      video.setAttribute('playsinline', 'true');
      video.muted = true;
      const started = await reader.decodeFromConstraints(
        { audio: false, video: { facingMode: { ideal: 'environment' }, width: { ideal: 1280 }, height: { ideal: 720 } } },
        video,
        (result, _error, scanControls) => {
          if (!result || handled.current || run !== generation.current) return;
          if (onCodeRef.current(result.getText())) {
            handled.current = true;
            scanControls.stop();
          }
        },
      );
      if (run !== generation.current) {
        started.stop();
        return;
      }
      controls.current = started;
      let torch: boolean | null = null;
      try {
        const caps = started.streamVideoCapabilitiesGet?.((track) => [track]) as (MediaTrackCapabilities & { torch?: boolean }) | undefined;
        torch = caps?.torch ? false : null;
      } catch {
        torch = null;
      }
      setState({ status: 'running', torch });
    } catch (error) {
      if (run !== generation.current) return;
      setState({ status: 'issue', issue: classifyCameraError(error) });
    }
  }, [stop, videoRef]);

  useEffect(() => {
    if (!enabled) return;
    void start();
    const onVisibility = () => {
      if (handled.current) return;
      if (document.visibilityState === 'hidden') {
        stop();
        setState({ status: 'stopped' });
      } else {
        void start();
      }
    };
    document.addEventListener('visibilitychange', onVisibility);
    return () => {
      document.removeEventListener('visibilitychange', onVisibility);
      stop();
    };
  }, [enabled, start, stop]);

  const toggleTorch = useCallback(async () => {
    if (state.status !== 'running' || state.torch == null || !controls.current?.switchTorch) return false;
    const next = !state.torch;
    await controls.current.switchTorch(next);
    setState({ status: 'running', torch: next });
    return true;
  }, [state]);

  /** Marks the scan as done from outside (manual entry, saved table). */
  const markHandled = useCallback(() => {
    handled.current = true;
    stop();
  }, [stop]);

  return { state, retry: start, toggleTorch, markHandled };
}
