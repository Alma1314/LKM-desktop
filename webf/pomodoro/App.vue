<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from 'vue';
import { miniApp } from '../sdk';
import { initialTimer, timeLeft, toggleTimer, type TimerState } from './timer';
const state = ref(initialTimer()), now = ref(Date.now());
const ready = ref(false), busy = ref(false), dark = ref(false), en = ref(false), tw = ref(false), error = ref('');
const t = computed(() => en.value ? {
  title: 'Focus timer', hint: 'Make room for one thing at a time.', focus: 'Focus · 25 min', break: 'Break · 5 min',
  start: 'Start', pause: 'Pause', resume: 'Resume', reset: 'Reset', done: 'Time’s up. Take a breath.',
  saved: 'Your timer continues when you leave. Reopen to check the remaining time.',
  failure: 'Could not load or save. Retry before leaving.', retry: 'Retry', loading: 'Loading…',
} : {
  title: tw.value ? '番茄鐘' : '番茄钟', hint: tw.value ? '留一段時間，只做一件事。' : '留一段时间，只做一件事。',
  focus: tw.value ? '專注 · 25 分鐘' : '专注 · 25 分钟', break: tw.value ? '休息 · 5 分鐘' : '休息 · 5 分钟',
  start: tw.value ? '開始' : '开始', pause: tw.value ? '暫停' : '暂停', resume: tw.value ? '繼續' : '继续', reset: '重置',
  done: tw.value ? '時間到了，放鬆一下吧。' : '时间到了，放松一下吧。',
  saved: tw.value ? '離開後仍繼續計時，重新開啟可查看剩餘時間。' : '离开后仍继续计时，重新打开可查看剩余时间。',
  failure: tw.value ? '讀取或儲存失敗，請在離開前重試。' : '读取或保存失败，请在离开前重试。', retry: tw.value ? '重試' : '重试', loading: tw.value ? '載入中…' : '加载中…',
});
const remaining = computed(() => Math.ceil(timeLeft(state.value, now.value) / 1000));
const display = computed(() => `${String(Math.floor(remaining.value / 60)).padStart(2, '0')}:${String(remaining.value % 60).padStart(2, '0')}`);
let retryState: TimerState | undefined;
async function change(next: TimerState) {
  if (busy.value) return;
  busy.value = true; error.value = '';
  try { await miniApp.save(next); state.value = next; retryState = undefined; }
  catch { error.value = t.value.failure; retryState = next; }
  finally { busy.value = false; }
}
async function boot() {
  error.value = '';
  try {
    const context = await miniApp.context();
    en.value = context.locale.startsWith('en'); tw.value = /tw|hk|hant/i.test(context.locale); dark.value = context.dark;
    const saved = await miniApp.load<TimerState>();
    if (saved) {
      if (!['focus', 'break'].includes(saved.mode) || !Number.isFinite(saved.remainingMs) || saved.remainingMs < 0
        || (saved.endsAt !== null && !Number.isFinite(saved.endsAt))) throw new Error('invalid');
      state.value = saved;
    }
    now.value = Date.now(); ready.value = true;
  } catch { error.value = t.value.failure; }
}
const clock = setInterval(() => {
  now.value = Date.now();
  if (ready.value && state.value.endsAt !== null && remaining.value === 0 && !error.value) {
    void change({ ...state.value, remainingMs: 0, endsAt: null });
  }
}, 1000);
onMounted(boot);
onUnmounted(() => clearInterval(clock));
</script>
<template>
  <div class="app" :class="{ dark }"><div class="page">
    <h1>{{ t.title }}</h1><p class="muted">{{ t.hint }}</p>
    <p v-if="error" class="error" role="alert">{{ error }}
      <button @click="retryState ? change(retryState) : boot()" :disabled="busy">{{ t.retry }}</button></p>
    <div v-if="!ready" class="card">{{ t.loading }}</div>
    <div v-else class="card timer">
      <div class="row"><button :class="{ active: state.mode === 'focus' }" :disabled="busy || state.endsAt !== null" @click="change(initialTimer('focus'))">{{ t.focus }}</button>
        <button :class="{ active: state.mode === 'break' }" :disabled="busy || state.endsAt !== null" @click="change(initialTimer('break'))">{{ t.break }}</button></div>
      <div class="clock" role="timer">{{ display }}</div>
      <p v-if="remaining === 0">{{ t.done }}</p>
      <div class="row"><button class="primary" :disabled="busy || remaining === 0" @click="change(toggleTimer(state, Date.now()))">
        {{ state.endsAt !== null ? t.pause : state.remainingMs < initialTimer(state.mode).remainingMs ? t.resume : t.start }}</button>
        <button :disabled="busy" @click="change(initialTimer(state.mode))">{{ t.reset }}</button></div>
      <p class="muted">{{ t.saved }}</p>
    </div>
  </div></div>
</template>
