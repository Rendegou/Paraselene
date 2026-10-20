import { spawn } from 'node:child_process';

// Minimal MCP stdio probe for dsh-computer-use-win. Read-only calls only.
const child = spawn('npx -y dsh-computer-use-win', {
  shell: true,
  windowsHide: true,
  stdio: ['pipe', 'pipe', 'pipe'],
});

let buffer = '';
let nextId = 1;
const pending = new Map();

child.stdout.on('data', (chunk) => {
  buffer += chunk.toString('utf8');
  let index;
  while ((index = buffer.indexOf('\n')) >= 0) {
    const line = buffer.slice(0, index).trim();
    buffer = buffer.slice(index + 1);
    if (!line) continue;
    let message;
    try {
      message = JSON.parse(line);
    } catch {
      console.error('[raw]', line.slice(0, 300));
      continue;
    }
    if (message.id && pending.has(message.id)) {
      pending.get(message.id)(message);
      pending.delete(message.id);
    }
  }
});
child.stderr.on('data', (chunk) => process.stderr.write(`[server] ${chunk}`));
child.on('exit', (code) => console.log(`[server exit] ${code}`));

function request(method, params, timeoutMs = 60000) {
  const id = nextId++;
  return new Promise((resolve, reject) => {
    pending.set(id, resolve);
    child.stdin.write(`${JSON.stringify({ jsonrpc: '2.0', id, method, params })}\n`);
    setTimeout(() => {
      if (!pending.has(id)) return;
      pending.delete(id);
      reject(new Error(`timeout ${method}`));
    }, timeoutMs);
  });
}
function notify(method, params) {
  child.stdin.write(`${JSON.stringify({ jsonrpc: '2.0', method, params })}\n`);
}

const args = process.argv.slice(2);
try {
  const init = await request('initialize', {
    protocolVersion: '2024-11-05',
    capabilities: {},
    clientInfo: { name: 'dsh-computer-use-probe', version: '1.0.0' },
  });
  console.log('INIT', JSON.stringify(init).slice(0, 800));
  notify('notifications/initialized');
  await new Promise((resolve) => setTimeout(resolve, 500));
  const tools = await request('tools/list', {});
  const names = (tools.result?.tools ?? []).map((tool) => tool.name);
  console.log('TOOLS', JSON.stringify(names));
  for (const name of args) {
    try {
      const result = await request('tools/call', { name, arguments: {} }, 60000);
      console.log(`CALL ${name}`, JSON.stringify(result).slice(0, 6000));
    } catch (error) {
      console.log(`CALL_FAIL ${name}`, error.message);
    }
  }
} catch (error) {
  console.error('ERR', error);
  process.exitCode = 1;
} finally {
  child.stdin.end();
  setTimeout(() => child.kill(), 500);
  setTimeout(() => process.exit(process.exitCode ?? 0), 1500);
}
