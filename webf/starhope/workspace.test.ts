import { expect, it } from "vitest";
import {
  Workspace,
  gradeAnswer,
  validateQuestion,
  type Bridge,
  type Entity,
} from "./workspace";
import type { Question } from "./types";
import { fromSnake, toSnake } from "./mapping";
const context = { userId: "user-1", locale: "en-US", dark: false };

it("maps API fields without changing answer IDs or inheriting special keys", () => {
  const row = JSON.parse(
    '{"user_id":"user-1","updated_at":"2026-11-13T00:00:00Z","question_ids":["updated_at"],"answers":{"updated_at":"4"},"__proto__":{"polluted":true}}',
  );
  const mapped = fromSnake(row);
  expect(mapped.userId).toBe(context.userId);
  expect(mapped.questionIds).toEqual(["updated_at"]);
  expect(mapped.answers).toEqual({ updated_at: "4" });
  expect(Object.getPrototypeOf(mapped)).toBeNull();
  expect(mapped.__proto__).toEqual({ polluted: true });
  const pushed = toSnake(mapped);
  expect(pushed).not.toHaveProperty("user_id");
  expect(pushed.updated_at).toBe(row.updated_at);
  expect(pushed.answers).toEqual(row.answers);
});
const q = {
  type: "single" as const,
  content: "2 + 2?",
  options: ["3", "4"],
  answer: "4",
  tags: ["math"],
  difficulty: 2 as const,
};
class Host implements Bridge {
  raw: string | null = null;
  offline = false;
  failSave = false;
  malformed = false;
  count = 0;
  requests: { method: string; args: unknown[] }[] = [];
  remote: Record<Entity, Record<string, Record<string, unknown>>> = {
    questions: {},
    folders: {},
    sessions: {},
  };
  tombs: Record<Entity, { id: string; deleted_at: string }[]> = {
    questions: [],
    folders: [],
    sessions: [],
  };
  hold: (() => Promise<void>) | undefined;
  async call<T>(method: string, ...args: unknown[]): Promise<T> {
    this.requests.push({ method, args: JSON.parse(JSON.stringify(args)) });
    let result: unknown;
    if (method === "newId") result = `id-${++this.count}`;
    else if (method === "load") result = this.raw;
    else if (method === "save") {
      if (this.failSave) throw new Error("storage");
      this.raw = args[0] as string;
      result = true;
    } else {
      if (this.offline) throw new Error("offline");
      const entity = args[0] as Entity;
      if (method === "pull")
        result = {
          items: Object.values(this.remote[entity]),
          tombstones: this.tombs[entity],
          server_time: this.malformed ? "bad-time" : new Date().toISOString(),
        };
      else if (method === "push") {
        await this.hold?.();
        for (const row of args[1] as Record<string, unknown>[])
          this.remote[entity][row.id as string] = {
            ...row,
            user_id: context.userId,
          };
        for (const tomb of args[2] as { id: string; deleted_at: string }[]) {
          delete this.remote[entity][tomb.id];
          this.tombs[entity].push(tomb);
        }
        result = { synced: 1, server_time: "2099-01-01T00:00:00Z" };
      } else throw new Error(method);
    }
    return result as T;
  }
}
async function open(host: Host): Promise<Workspace> {
  const w = new Workspace(host, context);
  await w.load();
  return w;
}

it("persists offline questions, retries and pulls consistently on a second client", async () => {
  const host = new Host();
  host.offline = true;
  const w = await open(host),
    id = await w.saveQuestion(q);
  await w.sync();
  expect(w.pending).toBe(1);
  expect(w.syncError).toBe("offline");
  const reopened = await open(host);
  expect(reopened.questions[0]).toMatchObject({ id, ...q });
  host.offline = false;
  await reopened.sync();
  expect(reopened.pending).toBe(0);
  const push = host.requests.find((r) => r.method === "push")!;
  expect(push.args[1]).toEqual([
    expect.objectContaining({ id, updated_at: expect.any(String) }),
  ]);
  expect((push.args[1] as Record<string, unknown>[])[0]).not.toHaveProperty(
    "user_id",
  );
  host.raw = null;
  const other = await open(host);
  await other.sync();
  expect(other.questions).toEqual(reopened.questions);
  const pulls = host.requests.filter(
    (r) => r.method === "pull" && r.args[0] === "questions",
  );
  expect(pulls.some((r) => typeof r.args[1] === "string")).toBe(true);
  expect(pulls.some((r) => r.args[1] === "2099-01-01T00:00:00Z")).toBe(false);
});
it("retains failed deletions and cascades folder removal while keeping questions", async () => {
  const host = new Host(),
    w = await open(host);
  await w.saveFolder("Parent");
  const folder = w.folders[0];
  await w.saveFolder("Child", folder.id);
  const id = await w.saveQuestion({ ...q, folderId: folder.id });
  await w.sync();
  host.offline = true;
  await w.deleteFolder(folder.id);
  await w.sync();
  expect(w.folders[0].parentId).toBeNull();
  expect(w.questions[0].folderId).toBeNull();
  expect(w.pending).toBe(3);
  await w.deleteQuestion(id);
  const reopened = await open(host);
  expect(reopened.questions).toEqual([]);
  host.offline = false;
  await reopened.sync();
  expect(reopened.questions).toEqual([]);
  expect(reopened.pending).toBe(0);
  expect(host.tombs.folders[0].id).toBe(folder.id);
  expect(host.tombs.questions[0].id).toBe(id);
});
it("does not clear a newer edit made during an in-flight push", async () => {
  const host = new Host(),
    w = await open(host),
    id = await w.saveQuestion(q);
  let release!: () => void, started!: () => void;
  const pushing = new Promise<void>((resolve) => {
    started = resolve;
  });
  host.hold = () => {
    started();
    return new Promise<void>((resolve) => {
      release = resolve;
    });
  };
  const syncing = w.sync();
  await pushing;
  await w.saveQuestion({ ...q, content: "New edit" }, id);
  release();
  await syncing;
  host.hold = undefined;
  expect(w.pending).toBe(1);
  expect(w.questions[0].content).toBe("New edit");
  await w.sync();
  expect(w.pending).toBe(0);
  expect(host.remote.questions[id].content).toBe("New edit");
});
it("merges newer remote updates and tombstones, rejects another account's data", async () => {
  const host = new Host(),
    w = await open(host),
    id = await w.saveQuestion(q);
  host.remote.questions[id] = {
    id,
    ...q,
    user_id: context.userId,
    updated_at: "2090-01-01T00:00:00Z",
    content: "Remote",
  };
  await w.sync();
  expect(w.questions[0].content).toBe("Remote");
  expect(w.pending).toBe(0);
  host.tombs.questions = [{ id, deleted_at: "2091-01-01T00:00:00Z" }];
  await w.sync();
  expect(w.questions).toEqual([]);
  host.remote.questions.foreign = {
    id: "foreign",
    user_id: "other",
    updated_at: "2092-01-01T00:00:00Z",
  };
  await w.sync();
  expect(w.syncError).toBe("sync");
  expect(w.questions).toEqual([]);
});
it("preserves the cursor and local state on malformed pulls or storage failures", async () => {
  const host = new Host(),
    w = await open(host);
  await w.saveQuestion(q);
  const saved = host.raw;
  host.malformed = true;
  await w.sync();
  expect(host.raw).toBe(saved);
  expect(w.pending).toBe(1);
  host.failSave = true;
  await expect(w.saveQuestion({ ...q, content: "Unsaved" })).rejects.toThrow(
    "storage",
  );
  expect(w.questions).toHaveLength(1);
  expect(host.raw).toBe(saved);
  host.failSave = false;
  host.malformed = false;
  await w.sync();
  expect(w.pending).toBe(0);
  host.raw = "{}";
  await expect(open(host)).rejects.toThrow("storage");
});
it("splits pending operations at the server's 500-record limit", async () => {
  const host = new Host(),
    time = "2025-01-01T00:00:00Z";
  host.raw = JSON.stringify({
    version: 1,
    entries: {
      questions: Object.fromEntries(
        Array.from({ length: 501 }, (_, i) => [
          `q-${i}`,
          {
            data: {
              ...q,
              id: `q-${i}`,
              userId: context.userId,
              updatedAt: time,
            },
            time,
            dirty: true,
          },
        ]),
      ),
      folders: {},
      sessions: {},
    },
    cursors: {},
  });
  const w = await open(host);
  await w.sync();
  expect(
    host.requests
      .filter((r) => r.method === "push")
      .map((r) => (r.args[1] as unknown[]).length),
  ).toEqual([500, 1]);
  expect(w.pending).toBe(0);
});
it("persists progress, resumes practice and includes unanswered questions in wrong answers", async () => {
  const host = new Host(),
    w = await open(host),
    q1 = await w.saveQuestion(q),
    q2 = await w.saveQuestion({ ...q, content: "Other" });
  const id = await w.start([q1, q2], false);
  await w.answer(id, q1, "4");
  expect(w.sessions[0].results?.[q1].correct).toBe(true);
  await w.pause(id);
  await expect(w.answer(id, q2, "4")).rejects.toThrow("invalid");
  const reopened = await open(host);
  expect(reopened.sessions[0].status).toBe("paused");
  await reopened.pause(id, true);
  await reopened.finish(id);
  expect(reopened.sessions[0].results).toEqual({
    [q1]: { correct: true },
    [q2]: { correct: false },
  });
  expect(reopened.wrongQuestions.map((v) => v.id)).toEqual([q2]);
  await reopened.finish(id);
  expect(reopened.sessions[0].status).toBe("completed");
});
it("defers exam grading and enforces the persisted deadline after reopening", async () => {
  const host = new Host(),
    w = await open(host),
    id = await w.saveQuestion(q),
    sid = await w.start([id], true, 1, 0);
  await w.answer(sid, id, "4");
  expect(w.sessions[0].results).toEqual({});
  expect(w.sessions[0].passingGrade).toBe(0);
  await expect(w.pause(sid)).rejects.toThrow("invalid");
  const state = JSON.parse(host.raw!);
  state.entries.sessions[sid].data.startedAt = "2020-01-01T00:00:00Z";
  host.raw = JSON.stringify(state);
  const reopened = await open(host);
  expect(reopened.expired(reopened.sessions[0])).toBe(true);
  await expect(reopened.answer(sid, id, "3")).rejects.toThrow("expired");
  await reopened.finish(sid);
  expect(reopened.sessions[0].results?.[id].correct).toBe(true);
});
it("validates choices and grades arrays and text without changing the user's answer", () => {
  expect(() => validateQuestion({ ...q, answer: "missing" })).toThrow(
    "invalid",
  );
  expect(() => validateQuestion({ ...q, options: ["4", "4"] })).toThrow(
    "invalid",
  );
  expect(() => validateQuestion({ ...q, difficulty: 6 as 3 })).toThrow(
    "invalid",
  );
  const answer = ["b", "a"];
  expect(
    gradeAnswer(
      { ...q, type: "multiple", answer: ["a", "b"] } as Question,
      answer,
    ),
  ).toBe(true);
  expect(answer).toEqual(["b", "a"]);
  expect(gradeAnswer({ ...q, answer: " Word " } as Question, "word")).toBe(
    true,
  );
  expect(gradeAnswer(q as Question, "")).toBe(false);
  expect(gradeAnswer(q as Question, undefined)).toBe(false);
});
