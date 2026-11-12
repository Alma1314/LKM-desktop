const KEY_MAP: Record<string, string> = {
  userId: "user_id",
  folderId: "folder_id",
  createdAt: "created_at",
  updatedAt: "updated_at",
  questionIds: "question_ids",
  startedAt: "started_at",
  completedAt: "completed_at",
  timeLimit: "time_limit",
  passingGrade: "passing_grade",
  parentId: "parent_id",
};

const REVERSE_KEY_MAP: Record<string, string> = Object.fromEntries(
  Object.entries(KEY_MAP).map(([camel, snake]) => [snake, camel]),
);

/**
 * 只映射顶层字段。StarHope 各实体目前都是扁平结构：数组/Record 的键是业务 id
 * （questionIds、answers 的 key 等），不是字段名，所以无需递归映射；
 * 若将来某个实体真嵌入了对象字段，需要在这里补递归（或改类型化 DTO）。
 */
function mapKeys(
  obj: Record<string, unknown>,
  toSnake: boolean,
): Record<string, unknown> {
  const out: Record<string, unknown> = Object.create(null);
  // 入参来自 API/DB 结果，类型上是 unknown：null/undefined 会让 Object.entries 抛
  // TypeError，字符串/数字则会产出无意义的数字下标键。这里统一按「无字段」处理。
  if (obj === null || typeof obj !== "object") return out;
  for (const [k, v] of Object.entries(obj)) {
    // 未登记的键原样透传（`?? k`）是有意的：KEY_MAP 只列需要改命名的字段，
    // 其余业务字段（title/content/name/type/difficulty…）本就无需转换。
    // 因此这里不能对「未命中映射」告警——那会对绝大多数合法字段刷日志；
    // 真要防漏映射，应给实体补类型化 DTO 而不是运行时启发式。
    const keys = toSnake ? KEY_MAP : REVERSE_KEY_MAP;
    const mapped = Object.prototype.hasOwnProperty.call(keys, k) ? keys[k] : k;
    out[mapped] = v;
  }
  return out;
}

/** 前端 camelCase → API snake_case；push 时丢弃 userId（后端以 JWT 为准）。 */
export function toSnake(record: unknown): Record<string, unknown> {
  const mapped = mapKeys(record as Record<string, unknown>, true);
  delete mapped.user_id;
  return mapped;
}

/** API snake_case → 前端 camelCase；userId 由 int 转 string。 */
export function fromSnake(record: unknown): Record<string, unknown> {
  const mapped = mapKeys(record as Record<string, unknown>, false);
  // null 也要跳过：String(null) 会得到字符串 "null"，污染 userId
  if (mapped.userId !== undefined && mapped.userId !== null) {
    mapped.userId = String(mapped.userId);
  }
  return mapped;
}
