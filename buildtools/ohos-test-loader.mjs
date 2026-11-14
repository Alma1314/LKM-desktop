import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import ts from '../webf/node_modules/typescript/lib/typescript.js';

// These non-UI ArkTS modules are TypeScript; native SDK imports are test stubs.
export function loadArkTs(url, mocks) {
  const exports = {};
  const js = ts.transpileModule(readFileSync(url, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
  }).outputText;
  runInNewContext(js, {
    exports,
    require: id => {
      if (!mocks.has(id)) throw Error(`Missing SDK stub: ${id}`);
      return mocks.get(id);
    },
  });
  return exports;
}
