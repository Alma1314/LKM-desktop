<script setup lang="ts">
import { computed, onMounted, onUnmounted, reactive, ref } from "vue";
import type { PracticeSession, Question } from "./types";
import { hostBridge } from "./bridge";
import { Workspace, type Context } from "./workspace";
import { strings } from "./strings";

const labels = ref(strings("zh-CN"));
const tabs = ["dashboard", "bank", "practice", "exam", "wrongBook"] as const;
const types: Question["type"][] = [
  "single",
  "multiple",
  "true-false",
  "fill",
  "essay",
];
const tab = ref<(typeof tabs)[number]>("dashboard");
const ready = ref(false),
  dark = ref(false),
  error = ref(""),
  busy = ref(false),
  revision = ref(0);
let workspace: Workspace;
let retryTimer: ReturnType<typeof setInterval> | undefined;
let pushTimer: ReturnType<typeof setTimeout> | undefined;
const folder = ref("*"),
  query = ref(""),
  folderName = ref(""),
  selected = ref<string[]>([]);
const editing = ref(false),
  activeSession = ref(""),
  index = ref(0),
  response = ref("");
const minutes = ref("30"),
  passing = ref("60"),
  submitConfirm = ref(false),
  now = ref(Date.now());
const localAnswers = reactive<Record<string, string | string[]>>({});
const removal = ref<{ entity: "questions" | "folders"; id: string } | null>(
  null,
);
const draft = reactive({
  id: "",
  type: "single" as Question["type"],
  content: "",
  options: "",
  answer: "",
  analysis: "",
  tags: "",
  difficulty: "3",
  folderId: "",
});
const questions = computed(() => {
  void revision.value;
  return ready.value ? workspace.questions : [];
});
const folders = computed(() => {
  void revision.value;
  return ready.value ? workspace.folders : [];
});
const sessions = computed(() => {
  void revision.value;
  return ready.value ? workspace.sessions : [];
});
const pending = computed(() => {
  void revision.value;
  return ready.value ? workspace.pending : 0;
});
const syncing = computed(() => {
  void revision.value;
  return ready.value && workspace.busy;
});
const syncError = computed(() => {
  void revision.value;
  return ready.value ? workspace.syncError : "";
});
const filtered = computed(() =>
  questions.value.filter(
    (q) =>
      (folder.value === "*" || (q.folderId ?? "") === folder.value) &&
      (q.content.toLowerCase().includes(query.value.toLowerCase()) ||
        q.tags.some((t) =>
          t.toLowerCase().includes(query.value.toLowerCase()),
        )),
  ),
);
const wrong = computed(() => {
  void revision.value;
  return ready.value ? workspace.wrongQuestions : [];
});
const session = computed(() =>
  sessions.value.find((s) => s.id === activeSession.value),
);
const question = computed(() =>
  questions.value.find((q) => q.id === session.value?.questionIds[index.value]),
);
const result = computed(() =>
  question.value ? session.value?.results?.[question.value.id] : undefined,
);
const score = (s: PracticeSession): number =>
  s.questionIds.length
    ? Math.round(
        (Object.values(s.results ?? {}).filter((r) => r.correct).length /
          s.questionIds.length) *
          100,
      )
    : 0;
const remaining = computed(() =>
  session.value?.timeLimit
    ? Math.max(
        0,
        Math.ceil(
          (Date.parse(session.value.startedAt) +
            session.value.timeLimit * 60000 -
            now.value) /
            1000,
        ),
      )
    : 0,
);
function message(code: string): string {
  return (
    labels.value[code as "session" | "storage" | "invalid" | "host"] ??
    labels.value.offline
  );
}
function schedulePush(): void {
  clearTimeout(pushTimer);
  pushTimer = setTimeout(() => {
    void workspace.sync();
  }, 300);
}
async function act(action: () => Promise<unknown>): Promise<void> {
  if (busy.value) return;
  busy.value = true;
  error.value = "";
  try {
    await action();
    schedulePush();
  } catch (e) {
    error.value = message(e instanceof Error ? e.message : "storage");
  } finally {
    busy.value = false;
  }
}
async function boot(): Promise<void> {
  error.value = "";
  try {
    const context = await hostBridge.call<Context>("context");
    labels.value = strings(context.locale);
    dark.value = context.dark;
    workspace = new Workspace(hostBridge, context);
    workspace.onChange = () => {
      revision.value++;
    };
    await workspace.load();
    ready.value = true;
    void workspace.sync();
    retryTimer = setInterval(() => {
      void workspace.sync();
    }, 30000);
  } catch (e) {
    error.value = message(e instanceof Error ? e.message : "storage");
  }
}
const expiring = new Set<string>();
const clock = setInterval(() => {
  now.value = Date.now();
  if (!ready.value) return;
  for (const s of sessions.value) {
    if (
      s.status !== "completed" &&
      workspace.expired(s) &&
      !expiring.has(s.id)
    ) {
      expiring.add(s.id);
      void workspace
        .finish(s.id)
        .then(schedulePush)
        .catch(() => {
          error.value = labels.value.storage;
        })
        .finally(() => expiring.delete(s.id));
    }
  }
}, 1000);
onMounted(() => {
  void boot();
});
onUnmounted(() => {
  clearInterval(clock);
  clearInterval(retryTimer);
  clearTimeout(pushTimer);
});
function editQuestion(q?: Question): void {
  Object.assign(draft, {
    id: q?.id ?? "",
    type: q?.type ?? "single",
    content: q?.content ?? "",
    options: q?.options?.join("\n") ?? "",
    answer: Array.isArray(q?.answer) ? q.answer.join("\n") : (q?.answer ?? ""),
    analysis: q?.analysis ?? "",
    tags: q?.tags.join(", ") ?? "",
    difficulty: String(q?.difficulty ?? 3),
    folderId: q?.folderId ?? (folder.value === "*" ? "" : folder.value),
  });
  editing.value = true;
}
function saveQuestion(): void {
  void act(async () => {
    await workspace.saveQuestion(
      {
        type: draft.type,
        content: draft.content,
        options: ["single", "multiple"].includes(draft.type)
          ? draft.options
              .split("\n")
              .map((s) => s.trim())
              .filter(Boolean)
          : undefined,
        answer:
          draft.type === "multiple"
            ? draft.answer
                .split("\n")
                .map((s) => s.trim())
                .filter(Boolean)
            : draft.answer.trim(),
        analysis: draft.analysis,
        tags: draft.tags
          .split(/[,，]/)
          .map((s) => s.trim())
          .filter(Boolean),
        difficulty: Number(draft.difficulty) as Question["difficulty"],
        folderId: draft.folderId || undefined,
      },
      draft.id || undefined,
    );
    editing.value = false;
  });
}
function addFolder(): void {
  void act(async () => {
    await workspace.saveFolder(
      folderName.value,
      folder.value === "*" ? null : folder.value || null,
    );
    folderName.value = "";
  });
}
function remove(): void {
  const target = removal.value;
  if (!target) return;
  void act(async () => {
    if (target.entity === "questions")
      await workspace.deleteQuestion(target.id);
    else {
      await workspace.deleteFolder(target.id);
      if (folder.value === target.id) folder.value = "*";
    }
    selected.value = selected.value.filter((id) => id !== target.id);
    removal.value = null;
  });
}
function toggle(id: string): void {
  selected.value = selected.value.includes(id)
    ? selected.value.filter((v) => v !== id)
    : [...selected.value, id];
}
function openSession(s: PracticeSession): void {
  activeSession.value = s.id;
  index.value = Math.max(
    0,
    s.questionIds.findIndex((id) => s.answers[id] === undefined),
  );
  updateResponse();
  submitConfirm.value = false;
}
function updateResponse(): void {
  const answer = currentAnswer();
  response.value = typeof answer === "string" ? answer : "";
}
function move(amount: number): void {
  index.value += amount;
  updateResponse();
}
function start(): void {
  void act(async () => {
    const ids = filtered.value
      .filter((q) => selected.value.includes(q.id))
      .map((q) => q.id);
    const id = await workspace.start(
      ids,
      tab.value === "exam",
      Number(minutes.value),
      Number(passing.value),
    );
    const s = workspace.sessions.find((v) => v.id === id)!;
    openSession(s);
  });
}
function answerKey(): string {
  return `${session.value?.id}/${question.value?.id}`;
}
function currentAnswer(): string | string[] | undefined {
  return (
    localAnswers[answerKey()] ??
    (question.value ? session.value?.answers[question.value.id] : undefined)
  );
}
function answer(value: string | string[]): void {
  if (!session.value || !question.value) return;
  const key = answerKey();
  localAnswers[key] = value;
  const promise = workspace.answer(session.value.id, question.value.id, value);
  void promise
    .then(() => {
      if (JSON.stringify(localAnswers[key]) === JSON.stringify(value))
        delete localAnswers[key];
      schedulePush();
    })
    .catch((e) => {
      error.value = message(e instanceof Error ? e.message : "storage");
    });
}
function choose(option: string): void {
  if (question.value?.type === "multiple") {
    const current = currentAnswer();
    const values = Array.isArray(current) ? current : [];
    answer(
      values.includes(option)
        ? values.filter((v) => v !== option)
        : [...values, option],
    );
  } else answer(option);
}
function chosen(option: string): boolean {
  const value = currentAnswer();
  return Array.isArray(value) ? value.includes(option) : value === option;
}
</script>

<template>
  <div class="app" :class="{ dark }">
    <div class="top">
      <h1>StarHope</h1>
      <div class="nav">
        <button
          v-for="item in tabs"
          :key="item"
          :class="{ active: tab === item }"
          @click="
            tab = item;
            activeSession = '';
            submitConfirm = false;
          "
        >
          {{ labels[item] }}
        </button>
      </div>
    </div>
    <div v-if="!ready" class="card">
      <p>{{ error || labels.loading }}</p>
      <button v-if="error" @click="boot">{{ labels.retry }}</button>
    </div>
    <template v-else>
      <div class="sync">
        <span
          >{{
            syncing
              ? labels.syncing
              : syncError
                ? message(syncError)
                : labels.saved
          }}
          · {{ labels.pending }}: {{ pending }}</span
        ><button :disabled="syncing" @click="workspace.sync()">
          {{ labels.sync }}
        </button>
      </div>
      <div v-if="error" role="alert" class="error">
        {{ error
        }}<button
          v-if="localAnswers[answerKey()] !== undefined"
          @click="answer(localAnswers[answerKey()])"
        >
          {{ labels.retry }}
        </button>
      </div>
      <div v-if="removal" class="card" role="alert">
        <p>{{ labels.confirmDelete }}</p>
        <button :disabled="busy" @click="remove">{{ labels.remove }}</button
        ><button :disabled="busy" @click="removal = null">
          {{ labels.cancel }}
        </button>
      </div>
      <section v-if="tab === 'dashboard'">
        <div class="stats">
          <div class="card">
            {{ labels.questions }}
            <h2>{{ questions.length }}</h2>
          </div>
          <div class="card">
            {{ labels.folders }}
            <h2>{{ folders.length }}</h2>
          </div>
          <div class="card">
            {{ labels.sessions }}
            <h2>{{ sessions.length }}</h2>
          </div>
          <div class="card">
            {{ labels.wrongBook }}
            <h2>{{ wrong.length }}</h2>
          </div>
        </div>
        <button @click="tab = 'bank'">{{ labels.addQuestion }}</button>
      </section>
      <section
        v-if="
          tab === 'bank' || ((tab === 'practice' || tab === 'exam') && !session)
        "
      >
        <div class="card">
          <p>{{ labels.folderHint }}</p>
          <div class="row">
            <button :class="{ active: folder === '*' }" @click="folder = '*'">
              {{ labels.all }}</button
            ><button :class="{ active: folder === '' }" @click="folder = ''">
              {{ labels.root }}</button
            ><button
              v-for="f in folders"
              :key="f.id"
              :class="{ active: folder === f.id }"
              @click="folder = f.id"
            >
              {{ f.parentId ? "↳ " : "" }}{{ f.name }}
            </button>
          </div>
          <label>{{ labels.search }}<input v-model="query" /></label>
          <div v-if="tab === 'bank'" class="row">
            <label>{{ labels.name }}<input v-model="folderName" /></label
            ><button :disabled="busy || !folderName.trim()" @click="addFolder">
              {{
                folder && folder !== "*"
                  ? labels.newFolderHere
                  : labels.addFolder
              }}</button
            ><button
              v-if="folder && folder !== '*'"
              @click="removal = { entity: 'folders', id: folder }"
            >
              {{ labels.remove }}</button
            ><button @click="editQuestion()">{{ labels.addQuestion }}</button>
          </div>
        </div>
        <div v-if="editing && tab === 'bank'" class="card">
          <div class="row">
            <span>{{ labels.type }}</span
            ><button
              v-for="kind in types"
              :key="kind"
              :class="{ active: draft.type === kind }"
              @click="
                draft.type = kind;
                draft.answer = '';
              "
            >
              {{ labels[kind] }}
            </button>
          </div>
          <label
            >{{ labels.content
            }}<textarea v-model="draft.content" rows="4"></textarea>
          </label>
          <label v-if="draft.type === 'single' || draft.type === 'multiple'"
            >{{ labels.options
            }}<textarea v-model="draft.options" rows="4"></textarea>
          </label>
          <div v-if="draft.type === 'true-false'" class="row">
            <button
              v-for="value in ['true', 'false'] as const"
              :key="value"
              :class="{ active: draft.answer === value }"
              @click="draft.answer = value"
            >
              {{ labels[value] }}
            </button>
          </div>
          <label v-else
            >{{ labels.answer
            }}<textarea v-model="draft.answer" rows="2"></textarea>
          </label>
          <label
            >{{ labels.analysis
            }}<textarea v-model="draft.analysis" rows="3"></textarea></label
          ><label>{{ labels.tags }}<input v-model="draft.tags" /></label
          ><label
            >{{ labels.difficulty
            }}<input v-model="draft.difficulty" type="number"
          /></label>
          <div class="row">
            <span>{{ labels.folders }}</span
            ><button
              :class="{ active: !draft.folderId }"
              @click="draft.folderId = ''"
            >
              {{ labels.root }}</button
            ><button
              v-for="f in folders"
              :key="f.id"
              :class="{ active: draft.folderId === f.id }"
              @click="draft.folderId = f.id"
            >
              {{ f.name }}
            </button>
          </div>
          <button :disabled="busy" @click="saveQuestion">
            {{ labels.save }}</button
          ><button :disabled="busy" @click="editing = false">
            {{ labels.cancel }}
          </button>
        </div>
        <div class="row">
          <span
            >{{ labels.selected }}:
            {{
              selected.filter((id) => filtered.some((q) => q.id === id)).length
            }}</span
          ><button @click="selected = filtered.map((q) => q.id)">
            {{ labels.selectAll }}</button
          ><button @click="selected = []">{{ labels.clear }}</button>
        </div>
        <p v-if="!filtered.length">{{ labels.empty }}</p>
        <div v-for="q in filtered" :key="q.id" class="card">
          <div class="row">
            <button
              :aria-pressed="selected.includes(q.id)"
              @click="toggle(q.id)"
            >
              {{ selected.includes(q.id) ? "✓" : "＋" }}</button
            ><span
              >{{ labels[q.type] }} · {{ q.difficulty }} ·
              {{ q.tags.join(", ") }}</span
            >
          </div>
          <p class="text">{{ q.content }}</p>
          <div v-if="tab === 'bank'" class="row">
            <button @click="editQuestion(q)">{{ labels.edit }}</button
            ><button @click="removal = { entity: 'questions', id: q.id }">
              {{ labels.remove }}
            </button>
          </div>
        </div>
        <div v-if="tab === 'practice' || tab === 'exam'" class="card">
          <template v-if="tab === 'exam'"
            ><label
              >{{ labels.minutes
              }}<input v-model="minutes" type="number" /></label
            ><label
              >{{ labels.passing
              }}<input v-model="passing" type="number" /></label></template
          ><button
            :disabled="
              busy || !selected.some((id) => filtered.some((q) => q.id === id))
            "
            @click="start"
          >
            {{ labels.start }}
          </button>
        </div>
      </section>
      <section
        v-if="(tab === 'practice' || tab === 'exam') && session"
        class="card"
      >
        <div class="row">
          <span
            >{{ labels[session.status] }} · {{ index + 1 }} /
            {{ session.questionIds.length }}</span
          ><span
            v-if="session.type === 'exam' && session.status !== 'completed'"
            >{{ labels.remaining }}: {{ remaining }}</span
          >
        </div>
        <h2 v-if="session.status === 'completed'">
          {{ labels.score }}: {{ score(session) }} / 100
          <span v-if="session.type === 'exam'"
            >·
            {{
              score(session) >= (session.passingGrade ?? 60)
                ? labels.passed
                : labels.failed
            }}</span
          >
        </h2>
        <template v-if="question"
          ><p class="text">{{ question.content }}</p>
          <div
            v-if="question.options?.length || question.type === 'true-false'"
            class="choices"
          >
            <button
              v-for="option in question.type === 'true-false'
                ? ['true', 'false']
                : question.options"
              :key="option"
              :class="{ active: chosen(option) }"
              :disabled="
                session.status !== 'ongoing' ||
                (session.type === 'exam' && remaining === 0)
              "
              @click="choose(option)"
            >
              {{
                question.type === "true-false"
                  ? option === "true"
                    ? labels.true
                    : labels.false
                  : option
              }}
            </button>
          </div>
          <label v-else
            >{{ labels.response
            }}<textarea
              v-model="response"
              :disabled="
                session.status !== 'ongoing' ||
                (session.type === 'exam' && remaining === 0)
              "
              rows="4"
              @input="answer(response)"
            ></textarea>
          </label>
          <p v-if="question.type === 'essay' || question.type === 'fill'">
            {{ labels.exact }}
          </p>
          <div
            v-if="
              session.status === 'completed' ||
              (session.mode === 'realtime' && result)
            "
            class="feedback"
          >
            <strong>{{
              result?.correct ? labels.correct : labels.incorrect
            }}</strong>
            <p>
              {{ labels.answer }}:
              {{
                Array.isArray(question.answer)
                  ? question.answer.join(", ")
                  : question.answer
              }}
            </p>
            <p class="text">{{ question.analysis }}</p>
          </div>
        </template>
        <p v-else>{{ labels.missing }}</p>
        <div class="row">
          <button :disabled="index === 0" @click="move(-1)">
            {{ labels.previous }}</button
          ><button
            :disabled="index >= session.questionIds.length - 1"
            @click="move(1)"
          >
            {{ labels.next }}</button
          ><button
            v-if="session.type === 'practice' && session.status !== 'completed'"
            :disabled="busy"
            @click="
              act(() =>
                workspace.pause(session!.id, session!.status === 'paused'),
              )
            "
          >
            {{
              session.status === "paused" ? labels.resume : labels.pause
            }}</button
          ><button
            v-if="session.status !== 'completed'"
            :disabled="busy"
            @click="submitConfirm = true"
          >
            {{ labels.submit }}
          </button>
        </div>
        <div v-if="submitConfirm">
          <p>{{ labels.confirmSubmit }}</p>
          <button
            :disabled="busy"
            @click="
              act(async () => {
                await workspace.finish(session!.id);
                submitConfirm = false;
              })
            "
          >
            {{ labels.submit }}</button
          ><button @click="submitConfirm = false">{{ labels.cancel }}</button>
        </div>
      </section>
      <section v-if="tab === 'practice' || tab === 'exam'">
        <h2>{{ labels.history }}</h2>
        <p v-if="!sessions.some((s) => s.type === tab)">{{ labels.empty }}</p>
        <button
          v-for="s in sessions.filter((s) => s.type === tab)"
          :key="s.id"
          class="history"
          @click="openSession(s)"
        >
          {{ s.startedAt.slice(0, 19).replace("T", " ") }} ·
          {{ labels[s.status] }} · {{ s.questionIds.length }}
          {{ labels.questions }}
          <span v-if="s.status === 'completed'"> · {{ score(s) }} / 100</span>
        </button>
      </section>
      <section v-if="tab === 'wrongBook'">
        <p v-if="!wrong.length">{{ labels.empty }}</p>
        <div v-for="q in wrong" :key="q.id" class="card">
          <p class="text">{{ q.content }}</p>
          <p>
            {{ labels.answer }}:
            {{ Array.isArray(q.answer) ? q.answer.join(", ") : q.answer }}
          </p>
          <p class="text">{{ q.analysis }}</p>
          <button
            @click="
              tab = 'practice';
              selected = [q.id];
              folder = '*';
              query = '';
              activeSession = '';
            "
          >
            {{ labels.practice }}
          </button>
        </div>
      </section>
    </template>
  </div>
</template>
