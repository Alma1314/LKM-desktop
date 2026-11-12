export interface Question {
  id: string;
  userId: string;
  type: "single" | "multiple" | "true-false" | "essay" | "fill";
  content: string;
  options?: string[];
  answer: string | string[];
  analysis?: string;
  tags: string[];
  folderId?: string;
  difficulty: 1 | 2 | 3 | 4 | 5;
  createdAt: string;
  updatedAt: string;
}

export interface Folder {
  id: string;
  userId: string;
  name: string;
  parentId: string | null;
  sort: number;
  updatedAt: string;
}

export interface PracticeSession {
  id: string;
  userId: string;
  type: "practice" | "exam";
  mode: "realtime" | "batch";
  questionIds: string[];
  answers: Record<string, string | string[]>;
  results?: Record<string, { correct: boolean; score?: number }>;
  status: "ongoing" | "paused" | "completed";
  startedAt: string;
  completedAt?: string;
  timeLimit?: number;
  passingGrade?: number;
  updatedAt: string;
}

