import { expect, test } from 'vitest';
import { initialTimer, timeLeft, toggleTimer } from './timer';

test('a persisted running timer accounts for time spent outside the app', () => {
  const started = toggleTimer(initialTimer(), 1000);
  const reopened = JSON.parse(JSON.stringify(started));
  expect(timeLeft(reopened, 61000)).toBe(24 * 60000);
  expect(timeLeft(reopened, 1600000)).toBe(0);
});

test('pause freezes remaining time and resume uses a new deadline', () => {
  const paused = toggleTimer(toggleTimer(initialTimer('break'), 1000), 61000);
  expect(paused.endsAt).toBeNull();
  expect(timeLeft(paused, 200000)).toBe(4 * 60000);
  expect(toggleTimer(paused, 200000).endsAt).toBe(440000);
  expect(toggleTimer({ ...paused, remainingMs: 0 }, 200000).endsAt).toBeNull();
});
