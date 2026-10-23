// 前端行为测试运行器（T05A）：不引入新依赖。
// 用仓库自带的 TypeScript 把 src 下的 *.test.ts(x) 及其相对依赖转译为 CJS，
// 再由 Node 内置 node:test 执行；.css 与 @tauri-apps 依赖以空桩替代——
// 被测对象是纯领域函数，不允许触碰 React/IPC/Tauri。

import { createRequire } from "node:module";
import { execFileSync } from "node:child_process";
import {
  existsSync, mkdirSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync,
} from "node:fs";
import { dirname, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const require = createRequire(import.meta.url);
const ts = require("typescript");

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");
const SRC = join(ROOT, "src");
const TMP = join(ROOT, ".web-test-tmp");

function walk(dir, out = []) {
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) walk(full, out);
    else if (/\.test\.tsx?$/.test(entry)) out.push(full);
  }
  return out;
}

const testFiles = walk(SRC);
if (testFiles.length === 0) {
  console.log("WEB_TESTS:NOT_RUN (no *.test.ts under src/)");
  process.exit(3);
}

rmSync(TMP, { recursive: true, force: true });
mkdirSync(TMP, { recursive: true });
// 仓库是 "type":"module"；让转译产物按 CommonJS 解释，require("./x") 才能解析 .js。
writeFileSync(join(TMP, "package.json"), JSON.stringify({ type: "commonjs" }), "utf8");

const compiled = new Set();
function transpile(absPath) {
  const rel = relative(SRC, absPath);
  const outRel = rel.replace(/\.tsx?$/, ".js");
  const outAbs = join(TMP, outRel);
  if (compiled.has(outAbs)) return;
  compiled.add(outAbs);
  const source = readFileSync(absPath, "utf8");
  const result = ts.transpileModule(source, {
    compilerOptions: {
      module: ts.ModuleKind.CommonJS,
      target: ts.ScriptTarget.ES2021,
      jsx: ts.JsxEmit.ReactJSX,
      esModuleInterop: true,
    },
    fileName: absPath,
  });
  mkdirSync(dirname(outAbs), { recursive: true });
  writeFileSync(outAbs, result.outputText, "utf8");

  // 递归处理相对导入，css 与 @tauri-apps 落为空桩。
  const sf = ts.createSourceFile(absPath, source, ts.ScriptTarget.ES2021, true, ts.ScriptKind.TSX);
  sf.forEachChild((node) => {
    if (!ts.isImportDeclaration(node) || !ts.isStringLiteral(node.moduleSpecifier)) return;
    const spec = node.moduleSpecifier.text;
    if (spec.startsWith("@tauri-apps/")) {
      const stub = join(TMP, "tauri-stub.js");
      if (!existsSync(stub)) writeFileSync(stub, "module.exports = new Proxy({}, { get() { throw new Error('Tauri API stubbed in web tests'); } });\n", "utf8");
      return;
    }
    if (!spec.startsWith(".")) return;
    const target = resolve(dirname(absPath), spec);
    for (const candidate of [target, `${target}.ts`, `${target}.tsx`, `${target}.css`]) {
      if (!existsSync(candidate)) continue;
      if (candidate.endsWith(".css")) {
        const cssOut = join(TMP, relative(SRC, candidate));
        mkdirSync(dirname(cssOut), { recursive: true });
        writeFileSync(cssOut, "module.exports = {};\n", "utf8");
      } else {
        transpile(candidate);
      }
      break;
    }
  });
}

for (const file of testFiles) transpile(file);

const outTests = testFiles.map((f) => join(TMP, relative(SRC, f).replace(/\.tsx?$/, ".js")));
try {
  execFileSync(process.execPath, ["--test", ...outTests], { stdio: "inherit" });
  console.log("WEB_TESTS:PASS");
} catch {
  console.log("WEB_TESTS:FAIL");
  process.exitCode = 1;
} finally {
  rmSync(TMP, { recursive: true, force: true });
}
