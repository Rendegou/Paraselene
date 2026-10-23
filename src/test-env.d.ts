// node:test 的最小类型声明：仓库未安装 @types/node，测试由
// scripts/quality/run-web-tests.mjs 转译后以 Node 内置 test runner 执行。
// 只声明测试实际用到的 API；接入正式前端测试框架时替换为完整类型。

declare module "node:test" {
  export function test(name: string, fn: () => void | Promise<void>): void;
}

declare module "node:assert/strict" {
  interface AssertStrict {
    equal(actual: unknown, expected: unknown, message?: string): void;
    notEqual(actual: unknown, expected: unknown, message?: string): void;
    deepEqual(actual: unknown, expected: unknown, message?: string): void;
    ok(value: unknown, message?: string): asserts value;
    rejects(block: Promise<unknown> | (() => Promise<unknown>), expected?: RegExp | ((error: unknown) => boolean), message?: string): Promise<void>;
    throws(fn: () => unknown, expected?: RegExp, message?: string): void;
  }
  const assert: AssertStrict;
  export default assert;
}
