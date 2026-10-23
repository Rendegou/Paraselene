// 幻月前端代码度量（T05A）：TypeScript AST 口径的函数/组件有效行与圈复杂度。
// 有效行 = 函数体内非空行且非整行注释；函数/组件通过 AST 节点识别，不用正则数行。
// 阈值来自 docs/engineering/code-standards.md：普通函数<=60、组件<=150、生产模块<=400、圈复杂度<=10。
// 用法：
//   node scripts/quality/code-metrics.mjs [--emit <基线.json> | --verify <基线.json>] [--json]
//   node scripts/quality/code-metrics.mjs --ipc-boundary
// 基线校验语义：当前违规集合必须是基线集合的子集；新增违规退出 1，基线内已消失计为 resolved。
import { createRequire } from "node:module";
import { readdirSync, readFileSync, statSync, writeFileSync, existsSync } from "node:fs";
import { join, relative, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const require = createRequire(import.meta.url);
const ts = require("typescript");

const TOOL_VERSION = "t05a-1";
const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");
const SRC = join(ROOT, "src");
const FUNC_LIMIT = 60;
const COMPONENT_LIMIT = 150;
const HOOK_LIMIT = 60;
const FILE_LIMIT = 400;
const COMPLEXITY_LIMIT = 10;

const args = process.argv.slice(2);
function argValue(flag) {
  const i = args.indexOf(flag);
  return i >= 0 ? args[i + 1] : null;
}
const emitPath = argValue("--emit");
const verifyPath = argValue("--verify");
const ipcBoundary = args.includes("--ipc-boundary");

function listSources(dir) {
  const out = [];
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    const st = statSync(full);
    if (st.isDirectory()) {
      if (entry === "node_modules" || entry.startsWith(".")) continue;
      out.push(...listSources(full));
    } else if (/\.(ts|tsx)$/.test(entry) && !/\.d\.ts$/.test(entry)) {
      out.push(full);
    }
  }
  return out;
}

// 用 Scanner 收集注释区间，用于把整行注释排除出有效行。
function commentRanges(text) {
  const ranges = [];
  const scanner = ts.createScanner(ts.ScriptTarget.ESNext, false, ts.LanguageVariant.Standard, text);
  let token = scanner.scan();
  while (token !== ts.SyntaxKind.EndOfFileToken) {
    if (token === ts.SyntaxKind.SingleLineCommentTrivia || token === ts.SyntaxKind.MultiLineCommentTrivia) {
      ranges.push([scanner.getTokenStart(), scanner.getTokenEnd()]);
    }
    token = scanner.scan();
  }
  return ranges;
}

function effectiveLines(text, start, end, comments) {
  let count = 0;
  const lineStarts = [0];
  for (let i = 0; i < text.length; i++) if (text[i] === "\n") lineStarts.push(i + 1);
  const inComment = (pos) => comments.some(([a, b]) => pos >= a && pos < b);
  for (let l = 0; l < lineStarts.length; l++) {
    const from = lineStarts[l];
    const to = l + 1 < lineStarts.length ? lineStarts[l + 1] - 1 : text.length;
    if (to < start || from >= end) continue;
    let code = -1;
    for (let i = Math.max(from, start); i < Math.min(to, end); i++) {
      if (!inComment(i) && !/\s/.test(text[i])) { code = i; break; }
    }
    if (code >= 0) count++;
  }
  return count;
}

function functionName(node, parent) {
  if ((ts.isFunctionDeclaration(node) || ts.isMethodDeclaration(node)) && node.name) {
    return node.name.getText();
  }
  if (ts.isVariableDeclaration(parent) && ts.isIdentifier(parent.name)) return parent.name.text;
  return "<anonymous>";
}

function isComponentName(name) {
  return /^[A-Z]/.test(name);
}
function isHookName(name) {
  return /^use[A-Z0-9]/.test(name);
}

// 圈复杂度口径（与 ESLint complexity 同口径）：if/for/while/do/case/catch/?:/&&/||/?? 各计 1，
// 基线为 1；不向下钻取嵌套函数体内的决策点（嵌套函数会作为独立符号单独列示）。
function cyclomatic(node) {
  let score = 1;
  const bump = new Set([
    ts.SyntaxKind.IfStatement, ts.SyntaxKind.ForStatement, ts.SyntaxKind.ForInStatement,
    ts.SyntaxKind.ForOfStatement, ts.SyntaxKind.WhileStatement, ts.SyntaxKind.DoStatement,
    ts.SyntaxKind.CaseClause, ts.SyntaxKind.CatchClause, ts.SyntaxKind.ConditionalExpression,
    ts.SyntaxKind.AmpersandAmpersandToken, ts.SyntaxKind.BarBarToken, ts.SyntaxKind.QuestionQuestionToken,
  ]);
  const nested = new Set([
    ts.SyntaxKind.FunctionDeclaration, ts.SyntaxKind.FunctionExpression,
    ts.SyntaxKind.ArrowFunction, ts.SyntaxKind.MethodDeclaration,
  ]);
  const walk = (n, isRoot) => {
    if (bump.has(n.kind)) score++;
    const descend = isRoot || !nested.has(n.kind);
    if (descend) n.forEachChild((child) => walk(child, false));
  };
  walk(node, true);
  return score;
}

function analyzeFile(path) {
  const text = readFileSync(path, "utf8");
  const sf = ts.createSourceFile(path, text, ts.ScriptTarget.ESNext, true, ts.ScriptKind.TSX);
  const comments = commentRanges(text);
  const rel = relative(ROOT, path).split("\\").join("/");
  const symbols = [];
  const isTest = /\.test\.tsx?$/.test(rel);

  const visit = (node, parent) => {
    if (ts.isFunctionDeclaration(node) || ts.isFunctionExpression(node) || ts.isArrowFunction(node) || ts.isMethodDeclaration(node)) {
      const name = functionName(node, parent);
      const start = node.getStart(sf);
      const end = node.getEnd();
      const lines = effectiveLines(text, start, end, comments);
      const complexity = cyclomatic(node);
      let kind = "function";
      let limit = FUNC_LIMIT;
      if (isComponentName(name)) { kind = "component"; limit = COMPONENT_LIMIT; }
      else if (isHookName(name)) { kind = "hook"; limit = HOOK_LIMIT; }
      // 嵌套函数归外层统计，不重复列出；测试文件只测行为，不计债务。
      if (!isTest) {
        symbols.push({ file: rel, name, kind, lines, complexity, limit });
      }
    }
    ts.forEachChild(node, (child) => visit(child, node));
  };
  visit(sf, sf);

  const fileLines = effectiveLines(text, 0, text.length, comments);
  return { file: rel, fileLines, symbols };
}

const files = listSources(SRC).sort();
const analyzed = files.map(analyzeFile);
const violations = [];
for (const f of analyzed) {
  const isTest = /\.test\.tsx?$/.test(f.file);
  if (!isTest && f.fileLines > FILE_LIMIT) {
    violations.push({ file: f.file, name: "<module>", kind: "module", lines: f.fileLines, complexity: 0, limit: FILE_LIMIT });
  }
  for (const s of f.symbols) {
    if (s.lines > s.limit || s.complexity > COMPLEXITY_LIMIT) {
      violations.push({ ...s, complexityLimit: COMPLEXITY_LIMIT });
    }
  }
}

if (ipcBoundary) {
  // IPC 集中封装：src 下只有 lib/ipc.ts 允许 import @tauri-apps/*。
  const allowed = new Set(["src/lib/ipc.ts"]);
  const offenders = [];
  for (const f of analyzed) {
    const text = readFileSync(join(ROOT, f.file), "utf8");
    const sf = ts.createSourceFile(f.file, text, ts.ScriptTarget.ESNext, true, ts.ScriptKind.TSX);
    sf.forEachChild((node) => {
      if (ts.isImportDeclaration(node) && ts.isStringLiteral(node.moduleSpecifier)) {
        const spec = node.moduleSpecifier.text;
        if (spec.startsWith("@tauri-apps/") && !allowed.has(f.file)) {
          offenders.push({ file: f.file, spec, line: sf.getLineAndCharacterOfPosition(node.getStart()).line + 1 });
        }
      }
    });
  }
  if (offenders.length > 0) {
    console.log(JSON.stringify({ tool: "ipc-boundary", offenders }, null, 2));
    console.log("IPC_BOUNDARY:FAIL");
    process.exit(1);
  }
  console.log(JSON.stringify({ tool: "ipc-boundary", offenders: [], allowed: [...allowed] }, null, 2));
  console.log("IPC_BOUNDARY:PASS");
  process.exit(0);
}

const key = (v) => `${v.file}#${v.name}`;
const report = {
  tool: "code-metrics",
  toolVersion: TOOL_VERSION,
  generatedAt: new Date().toISOString(),
  tsVersion: ts.version,
  limits: { function: FUNC_LIMIT, component: COMPONENT_LIMIT, hook: HOOK_LIMIT, module: FILE_LIMIT, complexity: COMPLEXITY_LIMIT },
  violationCount: violations.length,
  violations: violations.sort((a, b) => b.lines - a.lines),
};

if (emitPath) {
  const out = resolve(ROOT, emitPath);
  writeFileSync(out, JSON.stringify(report, null, 2) + "\n", "utf8");
  console.log(`EMIT ${emitPath}: violations=${violations.length}`);
}

if (verifyPath) {
  const baseFile = resolve(ROOT, verifyPath);
  if (!existsSync(baseFile)) {
    console.log(`TS_METRICS:NOT_RUN (baseline missing: ${verifyPath})`);
    process.exit(3);
  }
  const baseline = JSON.parse(readFileSync(baseFile, "utf8"));
  const baseKeys = new Set(baseline.violations.map(key));
  const currentKeys = new Set(violations.map(key));
  const added = violations.filter((v) => !baseKeys.has(key(v))).map(key);
  const resolved = baseline.violations.filter((v) => !currentKeys.has(key(v))).map(key);
  console.log(JSON.stringify({ tool: "ts-metrics", added, resolved, baselineCount: baseKeys.size, currentCount: currentKeys.size }, null, 2));
  if (added.length > 0) {
    console.log("TS_METRICS:FAIL");
    process.exit(1);
  }
  console.log("TS_METRICS:PASS");
  process.exit(0);
}

console.log(JSON.stringify(report, null, 2));
