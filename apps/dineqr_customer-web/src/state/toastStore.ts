import { Store } from './store';

export type ToastTone = 'info' | 'success' | 'error';

export interface Toast {
  id: number;
  message: string;
  tone: ToastTone;
  actionLabel?: string;
  onAction?: () => void;
  durationMs: number;
}

/** Snackbar-style messages, one at a time (a new one replaces the last). */
export class ToastStore extends Store {
  current: Toast | null = null;
  private nextId = 1;
  private timer: ReturnType<typeof setTimeout> | null = null;

  show(message: string, options: Partial<Omit<Toast, 'id' | 'message'>> = {}): void {
    if (this.timer) clearTimeout(this.timer);
    const toast: Toast = { id: this.nextId++, message, tone: 'info', durationMs: 4000, ...options };
    this.current = toast;
    this.notify();
    this.timer = setTimeout(() => this.dismiss(toast.id), toast.durationMs);
  }

  dismiss(id?: number): void {
    if (!this.current || (id != null && this.current.id !== id)) return;
    this.current = null;
    this.notify();
  }
}
