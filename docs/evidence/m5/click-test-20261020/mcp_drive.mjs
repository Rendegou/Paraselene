import { spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

// MCP stdio driver for dsh-computer-use-win.
// Usage:
//   node mcp_drive.mjs schemas <tool> [<tool> ...]
//   node mcp_drive.mjs call <tool> [json-arguments]
// Screenshot/OCR image payloads are written next to this script.
const child = spawn('npx -y dsh-computer-use-win', {
  shell: true,
  windowsHide: true,
  stdio: ['pipe', 'pipe', 'pipe'],
});
const here = path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'));
const outDir = path.join(here, 'out');
fs.mkdirSync(outDir, { recursive: true });

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

function request(method, params, timeoutMs = 90000) {
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
const notify = (method, params) =>
  child.stdin.write(`${JSON.stringify({ jsonrpc: '2.0', method, params })}\n`);

function saveImages(result) {
  const saved = [];
  const content = result?.result?.content ?? [];
  for (let i = 0; i < content.length; i++) {
    const item = content[i];
    if (item?.type !== 'image' || typeof item.data !== 'string') continue;
    const ext = item.mimeType === 'image/jpeg' ? 'jpg' : 'png';
    const file = path.join(outDir, `image-${Date.now()}-${i}.${ext}`);
    fs.writeFileSync(file, Buffer.from(item.data, 'base64'));
    saved.push(file);
  }
  return saved;
}

try {
  await request('initialize', {
    protocolVersion: '2024-11-05',
    capabilities: {},
    clientInfo: { name: 'dsh-computer-use-driver', version: '1.0.0' },
  });
  notify('notifications/initialized');
  await new Promise((resolve) => setTimeout(resolve, 300));
  const [command, ...rest] = process.argv.slice(2);
  if (command === 'schemas') {
    const listed = await request('tools/list', {});
    const tools = listed.result?.tools ?? [];
    for (const name of rest) {
      const tool = tools.find((entry) => entry.name === name);
      console.log(name, JSON.stringify(tool?.inputSchema ?? null));
    }
  } else if (command === 'call') {
    const [name, rawArguments] = rest;
    const args = rawArguments ? JSON.parse(rawArguments) : {};
    const result = await request('tools/call', { name, arguments: args });
    const images = saveImages(result);
    const textual = (result.result?.content ?? [])
      .filter((item) => item.type === 'text')
      .map((item) => item.text)
      .join('\n');
    console.log('RESULT', JSON.stringify(result.result?.isError ? result.result : { ok: true, images, textual: textual.slice(0, 20000) }));
  } else {
    console.error('unknown command; use schemas|call');
    process.exitCode = 2;
  }
} catch (error) {
  console.error('ERR', error);
  process.exitCode = 1;
} finally {
  child.stdin.end();
  setTimeout(() => child.kill(), 500);
  setTimeout(() => process.exit(process.exitCode ?? 0), 1500);
}
