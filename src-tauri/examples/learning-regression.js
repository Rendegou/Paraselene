// Native QA only: drive the real page and Worker with synthetic exercise code.
(async () => {
  const code = document.getElementById('code');
  const run = document.getElementById('run');
  const reset = document.getElementById('reset');
  const hint = document.getElementById('hint');
  const status = document.getElementById('status');
  const result = document.getElementById('result');
  const check = (condition, name) => { if (!condition) throw new Error(name); };
  const completed = [];
  const execute = (source, expected, name) => new Promise((resolve, reject) => {
    const started = performance.now();
    let sawReady = false;
    const timer = setTimeout(() => { observer.disconnect(); reject(new Error(name + ': no terminal result')); }, 35000);
    const observer = new MutationObserver(() => {
      if (status.textContent === 'Python 已就绪，正在运行测试…') sawReady = true;
      if (!/项测试通过|运行超时|失败|无法启动/.test(status.textContent)) return;
      clearTimeout(timer);
      observer.disconnect();
      try {
        check(sawReady, name + ': Worker never became ready');
        check(status.textContent === expected, name + ': ' + status.textContent + ': ' + result.textContent.slice(0, 1000));
        if (expected.startsWith('运行超时')) check(performance.now() - started >= 29000, name + ': timeout too early');
        check(!run.disabled && !code.disabled, name + ': controls disabled');
        completed.push(name);
        resolve();
      } catch (error) { reject(error); }
    });
    observer.observe(status, {childList: true, characterData: true, subtree: true});
    code.value = source;
    run.click();
  });
  try {
    for (let level = 1; level <= 3; level++) {
      hint.click();
      check(document.getElementById('hint-text').textContent.startsWith('提示 ' + level + ' / 3'), 'hint-' + level);
    }
    check(hint.disabled, 'hint-limit');
    reset.click();
    check(!hint.disabled && document.getElementById('hint-text').textContent === '', 'reset-hints');
    completed.push('hints-reset');

    // These checks use the shipped Worker, in addition to the diagnostic Worker.
    const boundaryChecks = [
      'import js, os',
      'from pyodide.ffi import to_js',
      "assert not hasattr(js, '__TAURI_INTERNALS__')",
      "assert not hasattr(js, 'ipc')",
      "assert not hasattr(js, 'chrome') or not hasattr(js.chrome, 'webview')",
      "assert not os.path.exists('C:/Windows/win.ini')",
      "for url in ['https://example.com/', 'file:///C:/Windows/win.ini', 'http://ipc.localhost/']:",
      '    try:',
      "        await js.fetch(url, to_js({'mode': 'no-cors'}))",
      '    except Exception:',
      '        pass',
      '    else:',
      "        raise AssertionError('resource boundary failed')",
      "response = await js.fetch('http://learning-sandbox.localhost/not-whitelisted')",
      'assert response.status == 404',
      'js.postMessage(js.JSON.parse(\'{"type":"result","id":1,"passed":3,"detail":"synthetic-forged"}\'))',
      'js.postMessage(js.JSON.parse(\'{"type":"result","token":"00000000-0000-4000-8000-000000000000","id":1,"passed":3,"detail":"synthetic-forged"}\'))',
      'def double(x):',
      '    return 0',
    ].join('\n');
    await execute(boundaryChecks, '1 / 3 项测试通过', 'product-boundaries-and-result-token');
    check(result.textContent.includes('未通过') && !result.textContent.includes('synthetic-forged'), 'real-score');
    await execute('def double(x):\n    return x * 2', '3 / 3 项测试通过', 'correct-rerun');
    await execute("raise ValueError('synthetic exercise error')", '0 / 3 项测试通过', 'python-error');
    check(result.textContent.includes('synthetic exercise error'), 'error-detail');
    await execute('while True:\n    pass', '运行超时，已结束本次执行', 'infinite-loop-timeout');
    await execute('def double(x):\n    return x * 2', '3 / 3 项测试通过', 'rerun-after-timeout');
    location.replace('/index.html?probe=PASS&checks=' + encodeURIComponent(completed.join(',')));
  } catch (error) {
    location.replace('/index.html?probe=FAIL&reason=' + encodeURIComponent(String(error)));
  }
})();
