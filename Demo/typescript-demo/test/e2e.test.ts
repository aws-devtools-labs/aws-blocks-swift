import { test } from 'node:test';
import assert from 'node:assert';
import { spawn, type ChildProcess } from 'node:child_process';
import { setTimeout } from 'node:timers/promises';
import type { api as apiType, hello as helloType } from 'aws-blocks';

let server: ChildProcess | null = null;
let api: typeof apiType;
let hello: typeof helloType;

test.before(async () => {

  // Start dev server
  console.log('🚀 Starting dev server...');
  server = spawn('npm', ['run', 'dev:server'], {
    cwd: process.cwd(),
    stdio: ['ignore', 'inherit', 'inherit'],
    detached: true,
    env: { ...process.env, NODE_OPTIONS: '' }
  });
  server.unref();

  await setTimeout(2000);

  // Import API via browser conditional export (client proxy)
  const mod = await import('aws-blocks');
  api = mod.api;
  hello = mod.hello;

  // Wait for server to be ready
  for (let i = 0; i < 60; i++) {
    try { await hello.greet('ping'); return; } catch (e) {
      if (i % 10 === 9) console.log(`  Still waiting... (${i+1}s) ${(e as Error).message}`);
    }
    await setTimeout(1000);
  }
  throw new Error('Server not ready');
});

test.after(() => {
  if (server?.pid) {
    try { process.kill(-server.pid, 'SIGTERM'); } catch {}
  }
});

test('greet returns message and timestamp', async () => {
  const result = await hello.greet('World');
  assert.strictEqual(result.message, 'Hello, World!');
  assert.ok(typeof result.timestamp === 'number');
});

test('KV Store - set and get', async () => {
  const setResult = await api.setValue('test-key', 'test-value');
  assert.strictEqual(setResult.success, true);

  const value = await api.getValue('test-key');
  assert.strictEqual(value, 'test-value');
});
