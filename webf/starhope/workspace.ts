import type { Folder, PracticeSession, Question } from "./types";
import { fromSnake, toSnake } from "./mapping";

export const entities = ["questions", "folders", "sessions"] as const;
export type Entity = (typeof entities)[number];
type Row = Record<string, unknown>;
interface Entry {
  data: Row | null;
  time: string;
  dirty: boolean;
}
interface Snapshot {
  version: 1;
  entries: Record<Entity, Record<string, Entry>>;
  cursors: Partial<Record<Entity, string>>;
}
export interface Bridge {
  call<T>(method: string, ...args: unknown[]): Promise<T>;
}
export interface Context {
  userId: string;
  locale: string;
  dark: boolean;
}
interface Pull {
  items: Row[];
  tombstones: { id: string; deleted_at: string }[];
  server_time: string;
}

const copy = <T>(value: T): T => JSON.parse(JSON.stringify(value));
const validTime = (value: unknown): value is string =>
  typeof value === "string" && Number.isFinite(Date.parse(value));
const validId = (value: unknown): value is string =>
  typeof value === "string" && value.length > 0 && value.length <= 36;

export function gradeAnswer(question: Question, answer: unknown): boolean {
  if (Array.isArray(question.answer) && Array.isArray(answer)) {
    const expected = [...question.answer].sort();
    const actual = [...answer].sort();
    return (
      expected.length === actual.length &&
      expected.every((value, index) => value === actual[index])
    );
  }
  return (
    typeof answer === "string" &&
    typeof question.answer === "string" &&
    answer.trim().length > 0 &&
    answer.trim().toLowerCase() === question.answer.trim().toLowerCase()
  );
}

export function validateQuestion(
  question: Omit<Question, "id" | "userId" | "createdAt" | "updatedAt">,
): void {
  if (
    !["single", "multiple", "true-false", "fill", "essay"].includes(
      question.type,
    ) ||
    !question.content.trim() ||
    !Number.isInteger(question.difficulty) ||
    question.difficulty < 1 ||
    question.difficulty > 5
  )
    throw new Error("invalid");
  if (question.type === "single" || question.type === "multiple") {
    const options = question.options ?? [];
    const answers = Array.isArray(question.answer)
      ? question.answer
      : [question.answer];
    if (
      options.length < 2 ||
      options.length > 26 ||
      options.some((v) => !v.trim()) ||
      new Set(options).size !== options.length ||
      !answers.length ||
      answers.some((v) => !options.includes(v)) ||
      (question.type === "single" && typeof question.answer !== "string") ||
      (question.type === "multiple" &&
        (!Array.isArray(question.answer) ||
          new Set(answers).size !== answers.length))
    )
      throw new Error("invalid");
  } else if (
    typeof question.answer !== "string" ||
    !question.answer.trim() ||
    (question.type === "true-false" &&
      !["true", "false"].includes(question.answer))
  ) {
    throw new Error("invalid");
  }
}

/** WebF has no IndexedDB adapter here: one durable Drift snapshot via the host.
 * ponytail: snapshot writes are O(n); split rows when large personal banks need it.
 */
export class Workspace {
  private state: Snapshot = {
    version: 1,
    entries: { questions: {}, folders: {}, sessions: {} },
    cursors: {},
  };
  private tail: Promise<unknown> = Promise.resolve();
  private syncing: Promise<void> | null = null;
  onChange = (): void => {};
  syncError = "";
  busy = false;

  constructor(
    readonly bridge: Bridge,
    readonly context: Context,
  ) {}

  async load(): Promise<void> {
    const raw = await this.bridge.call<string | null>("load");
    if (raw === null) return;
    const parsed = JSON.parse(raw) as Snapshot;
    if (parsed.version !== 1 || !parsed.entries || !parsed.cursors)
      throw new Error("storage");
    for (const entity of entities) {
      if (!parsed.entries[entity] || typeof parsed.entries[entity] !== "object")
        throw new Error("storage");
      for (const [id, entry] of Object.entries(parsed.entries[entity])) {
        if (
          !validId(id) ||
          !entry ||
          !validTime(entry.time) ||
          typeof entry.dirty !== "boolean" ||
          (entry.data !== null &&
            (entry.data?.id !== id ||
              entry.data?.userId !== this.context.userId))
        )
          throw new Error("storage");
      }
      const cursor = parsed.cursors[entity];
      if (cursor !== undefined && !validTime(cursor))
        throw new Error("storage");
    }
    this.state = parsed;
    this.onChange();
  }

  private async edit(change: (state: Snapshot) => void): Promise<void> {
    const operation = this.tail.then(async () => {
      const next = copy(this.state);
      change(next);
      // Save data, tombstones, outbox and cursors together before publishing UI.
      await this.bridge.call("save", JSON.stringify(next));
      this.state = next;
      this.onChange();
    });
    this.tail = operation.catch(() => {});
    await operation;
  }

  rows<T>(entity: Entity): T[] {
    return Object.values(this.state.entries[entity]).flatMap((entry) =>
      entry.data ? [copy(entry.data) as T] : [],
    );
  }
  get questions(): Question[] {
    return this.rows<Question>("questions");
  }
  get folders(): Folder[] {
    return this.rows<Folder>("folders");
  }
  get sessions(): PracticeSession[] {
    return this.rows<PracticeSession>("sessions").sort((a, b) =>
      b.startedAt.localeCompare(a.startedAt),
    );
  }
  get pending(): number {
    return entities.reduce(
      (sum, entity) =>
        sum +
        Object.values(this.state.entries[entity]).filter((entry) => entry.dirty)
          .length,
      0,
    );
  }
  get wrongQuestions(): Question[] {
    const ids = new Set<string>();
    for (const session of this.sessions.filter(
      (s) => s.status === "completed",
    )) {
      for (const [id, result] of Object.entries(session.results ?? {})) {
        if (!result.correct) ids.add(id);
      }
    }
    return this.questions.filter((q) => ids.has(q.id));
  }

  private write(
    state: Snapshot,
    entity: Entity,
    id: string,
    data: Row | null,
  ): void {
    const previous = state.entries[entity][id];
    const time = new Date(
      Math.max(Date.now(), previous ? Date.parse(previous.time) + 1 : 0),
    ).toISOString();
    state.entries[entity][id] = {
      data: data
        ? { ...data, id, userId: this.context.userId, updatedAt: time }
        : null,
      time,
      dirty: true,
    };
  }

  async saveQuestion(
    input: Omit<Question, "id" | "userId" | "createdAt" | "updatedAt">,
    id?: string,
  ): Promise<string> {
    validateQuestion(input);
    const key = id ?? (await this.bridge.call<string>("newId"));
    await this.edit((state) => {
      if (
        !validId(key) ||
        (id && !state.entries.questions[id]?.data) ||
        (input.folderId && !state.entries.folders[input.folderId]?.data)
      )
        throw new Error("invalid");
      this.write(state, "questions", key, {
        ...input,
        createdAt:
          state.entries.questions[key]?.data?.createdAt ??
          new Date().toISOString(),
      });
    });
    return key;
  }

  async deleteQuestion(id: string): Promise<void> {
    await this.edit((state) => {
      if (!state.entries.questions[id]?.data) throw new Error("invalid");
      this.write(state, "questions", id, null);
    });
  }

  async saveFolder(
    name: string,
    parentId: string | null = null,
  ): Promise<void> {
    if (!name.trim()) throw new Error("invalid");
    const id = await this.bridge.call<string>("newId");
    await this.edit((state) => {
      if (!validId(id) || (parentId && !state.entries.folders[parentId]?.data))
        throw new Error("invalid");
      this.write(state, "folders", id, {
        name: name.trim(),
        parentId,
        sort: this.folders.length,
      });
    });
  }

  async deleteFolder(id: string): Promise<void> {
    await this.edit((state) => {
      if (!state.entries.folders[id]?.data) throw new Error("invalid");
      this.write(state, "folders", id, null);
      for (const [key, entry] of Object.entries(state.entries.folders)) {
        if (entry.data?.parentId === id)
          this.write(state, "folders", key, { ...entry.data, parentId: null });
      }
      for (const [key, entry] of Object.entries(state.entries.questions)) {
        if (entry.data?.folderId === id)
          this.write(state, "questions", key, {
            ...entry.data,
            folderId: null,
          });
      }
    });
  }

  async start(
    questionIds: string[],
    exam: boolean,
    timeLimit = 30,
    passingGrade = 60,
  ): Promise<string> {
    if (
      !questionIds.length ||
      new Set(questionIds).size !== questionIds.length ||
      questionIds.some((id) => !this.questions.some((q) => q.id === id)) ||
      !Number.isInteger(timeLimit) ||
      timeLimit < 1 ||
      timeLimit > 180 ||
      !Number.isInteger(passingGrade) ||
      passingGrade < 0 ||
      passingGrade > 100
    )
      throw new Error("invalid");
    const id = await this.bridge.call<string>("newId");
    await this.edit((state) =>
      this.write(state, "sessions", id, {
        type: exam ? "exam" : "practice",
        mode: exam ? "batch" : "realtime",
        questionIds,
        answers: {},
        results: {},
        status: "ongoing",
        startedAt: new Date().toISOString(),
        ...(exam ? { timeLimit, passingGrade } : {}),
      }),
    );
    return id;
  }

  async answer(
    sessionId: string,
    questionId: string,
    answer: string | string[],
  ): Promise<void> {
    await this.edit((state) => {
      const session = state.entries.sessions[sessionId]?.data;
      const question = state.entries.questions[questionId]?.data as unknown as
        Question | undefined;
      if (
        !session ||
        session.status !== "ongoing" ||
        !question ||
        !(session.questionIds as string[]).includes(questionId)
      )
        throw new Error("invalid");
      if (
        session.type === "exam" &&
        this.expired(session as unknown as PracticeSession)
      )
        throw new Error("expired");
      const results = { ...((session.results as Row) ?? {}) };
      if (session.mode === "realtime")
        results[questionId] = { correct: gradeAnswer(question, answer) };
      this.write(state, "sessions", sessionId, {
        ...session,
        answers: { ...(session.answers as Row), [questionId]: answer },
        results,
      });
    });
  }

  expired(session: PracticeSession): boolean {
    return (
      session.type === "exam" &&
      !!session.timeLimit &&
      Date.now() >= Date.parse(session.startedAt) + session.timeLimit * 60000
    );
  }

  async finish(id: string): Promise<void> {
    await this.edit((state) => {
      const session = state.entries.sessions[id]
        ?.data as unknown as PracticeSession;
      if (!session || session.status === "completed") return;
      const results: NonNullable<PracticeSession["results"]> = {};
      for (const questionId of session.questionIds) {
        const question = state.entries.questions[questionId]
          ?.data as unknown as Question | undefined;
        results[questionId] = {
          correct: question
            ? gradeAnswer(question, session.answers[questionId])
            : false,
        };
      }
      this.write(state, "sessions", id, {
        ...session,
        results,
        status: "completed",
        completedAt: new Date().toISOString(),
      });
    });
  }

  async pause(id: string, resume = false): Promise<void> {
    await this.edit((state) => {
      const session = state.entries.sessions[id]?.data;
      if (!session || session.status === "completed" || session.type === "exam")
        throw new Error("invalid");
      this.write(state, "sessions", id, {
        ...session,
        status: resume ? "ongoing" : "paused",
      });
    });
  }

  sync(): Promise<void> {
    if (this.syncing) return this.syncing;
    this.busy = true;
    this.syncError = "";
    this.onChange();
    this.syncing = this.doSync()
      .catch((error: unknown) => {
        this.syncError = error instanceof Error ? error.message : "sync";
      })
      .finally(() => {
        this.syncing = null;
        this.busy = false;
        this.onChange();
      });
    return this.syncing;
  }

  private async pull(entity: Entity): Promise<void> {
    const result = await this.bridge.call<Pull>(
      "pull",
      entity,
      this.state.cursors[entity] ?? null,
    );
    if (
      !validTime(result.server_time) ||
      !Array.isArray(result.items) ||
      !Array.isArray(result.tombstones)
    )
      throw new Error("sync");
    await this.edit((state) => {
      const merge = (id: string, time: string, data: Row | null): void => {
        if (
          !validId(id) ||
          !validTime(time) ||
          (data && data.userId !== this.context.userId)
        )
          throw new Error("sync");
        const local = Object.prototype.hasOwnProperty.call(
          state.entries[entity],
          id,
        )
          ? state.entries[entity][id]
          : undefined;
        if (!local || Date.parse(time) >= Date.parse(local.time))
          Object.defineProperty(state.entries[entity], id, {
            value: { data, time, dirty: false },
            writable: true,
            enumerable: true,
            configurable: true,
          });
      };
      for (const raw of result.items) {
        const row = fromSnake(raw);
        merge(row.id as string, row.updatedAt as string, row);
      }
      for (const tomb of result.tombstones)
        merge(tomb.id, tomb.deleted_at, null);
      state.cursors[entity] = result.server_time;
    });
  }

  private async doSync(): Promise<void> {
    for (const entity of entities) {
      await this.pull(entity);
      await this.tail;
      const pending = Object.entries(this.state.entries[entity]).filter(
        ([, entry]) => entry.dirty,
      );
      for (let index = 0; index < pending.length; index += 500) {
        const batch = copy(pending.slice(index, index + 500));
        await this.bridge.call(
          "push",
          entity,
          batch.flatMap(([, entry]) =>
            entry.data ? [toSnake(entry.data)] : [],
          ),
          batch.flatMap(([id, entry]) =>
            entry.data ? [] : [{ id, deleted_at: entry.time }],
          ),
        );
        await this.edit((state) => {
          for (const [id, sent] of batch) {
            const current = state.entries[entity][id];
            // A keystroke while push was in flight must remain in the outbox.
            if (current?.time === sent.time) current.dirty = false;
          }
        });
      }
      // Push server_time never advances pull cursors: other devices may have written.
      if (pending.length) await this.pull(entity);
    }
  }
}
