export interface TimerState {
  mode: 'focus' | 'break';
  remainingMs: number;
  endsAt: number | null;
}
export function initialTimer(mode: TimerState['mode'] = 'focus'): TimerState {
  return { mode, remainingMs: (mode === 'focus' ? 25 : 5) * 60000, endsAt: null };
}
export function timeLeft(timer: TimerState, now: number): number {
  return Math.max(0, timer.endsAt === null ? timer.remainingMs : timer.endsAt - now);
}
export function toggleTimer(timer: TimerState, now: number): TimerState {
  const remainingMs = timeLeft(timer, now);
  return { ...timer, remainingMs, endsAt: timer.endsAt === null && remainingMs > 0 ? now + remainingMs : null };
}
