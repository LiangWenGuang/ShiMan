// 离线验证 HTTP 重试/响应上限和阅读进度串行持久化，无需鸿蒙 SDK 或网络。
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const here = path.resolve(import.meta.dirname);
const root = path.resolve(here, '..', '..');
const ets = path.join(root, 'app', 'entry', 'src', 'main', 'ets');
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'shiman-runtime-'));
let passed = 0;
let failed = 0;
function check(name: string, valid: boolean): void {
  console.log((valid ? '  PASS  ' : '  FAIL  ') + name);
  if (valid) passed++; else failed++;
}
function mirror(relative: string, name: string): void {
  const source = fs.readFileSync(path.join(ets, relative), 'utf8')
    .replaceAll("'@kit.NetworkKit'", "'./netShim.mjs'")
    .replaceAll("'@kit.ArkTS'", "'./netShim.mjs'")
    .replaceAll("'@kit.BasicServicesKit'", "'./netShim.mjs'")
    .replaceAll("'@kit.ArkData'", "'./prefsShim.mjs'")
    .replaceAll("'@kit.AbilityKit'", "'./prefsShim.mjs'")
    .replaceAll("'../model/Models'", "'./Models.ts'");
  fs.writeFileSync(path.join(temp, name), source, 'utf8');
}
const netShim = String.raw`
const requests = [];
let callCount = 0;
export function configure(items) {
  requests.length = 0;
  requests.push(...items);
  callCount = 0;
}
export function calls() { return callCount; }
export const BusinessError = class BusinessError extends Error {};
export const util = {
  TextDecoder: {
    create: () => ({
      decodeToString: (bytes) => new TextDecoder().decode(bytes)
    })
  }
};
export const http = {
  RequestMethod: { GET: 'GET', HEAD: 'HEAD', POST: 'POST' },
  HttpDataType: { ARRAY_BUFFER: 'ARRAY_BUFFER' },
  createHttp: () => ({
    request: async () => {
      callCount++;
      const item = requests.shift();
      if (!item) throw Error('unexpected request');
      if (item.error) throw Error(item.error);
      return {
        responseCode: item.status ?? 200,
        result: item.body ?? new ArrayBuffer(0),
        header: item.headers ?? {}
      };
    },
    destroy: () => {}
  })
};
`;
const prefsShim = String.raw`
const values = new Map();
let active = 0;
let maximum = 0;
export const common = {};
export const preferences = {
  getPreferences: async () => ({
    get: async (_key, fallback) => fallback,
    put: async (key, value) => {
      if (key === 'progress') {
        active++;
        maximum = Math.max(maximum, active);
        await new Promise(resolve => setTimeout(resolve, 20));
        values.set(key, value);
        active--;
      } else {
        values.set(key, value);
      }
    },
    flush: async () => {}
  })
};
export function persistedProgress() { return values.get('progress') ?? ''; }
export function persistedChapterOrderFixes() { return values.get('chapter_order_fixes') ?? ''; }
export function maxConcurrent() { return maximum; }
`;
try {
  mirror('net/Http.ets', 'Http.ts');
  mirror('store/Library.ets', 'Library.ts');
  mirror('model/Models.ets', 'Models.ts');
  fs.writeFileSync(path.join(temp, 'netShim.mjs'), netShim, 'utf8');
  fs.writeFileSync(path.join(temp, 'prefsShim.mjs'), prefsShim, 'utf8');
  const net = await import(pathToFileURL(path.join(temp, 'netShim.mjs')).href);
  const pref = await import(pathToFileURL(path.join(temp, 'prefsShim.mjs')).href);
  const { Http } = await import(pathToFileURL(path.join(temp, 'Http.ts')).href);
  const { Library } = await import(pathToFileURL(path.join(temp, 'Library.ts')).href);
  const { ReadProgress } = await import(pathToFileURL(path.join(temp, 'Models.ts')).href);

  net.configure([
    { error: 'timeout' },
    { status: 200, body: new ArrayBuffer(9 * 1024 * 1024) }
  ]);
  const oversized = await Http.get('https://example.test/large', [], 'utf-8');
  check('HTTP 重试仍执行响应大小保护',
    !oversized.ok && oversized.error.includes('响应体过大') && net.calls() === 2);

  net.configure([{ status: 404, body: new ArrayBuffer(0) }]);
  const missing = await Http.getBytesDetailed('https://example.test/missing.png', []);
  check('图片 404 不重复请求', missing.bytes === null && missing.status === 404 && net.calls() === 1);

  net.configure([{ error: 'timeout' }, { status: 200, body: new ArrayBuffer(4) }]);
  const recovered = await Http.getBytesDetailed('https://example.test/transient.png', []);
  check('图片临时网络失败可重试', recovered.bytes !== null && net.calls() === 2);

  const library = Library.get();
  await library.init({});
  const first = new ReadProgress();
  first.sourceId = 'fixture'; first.comicId = 'fixture';
  first.chapterId = 'one'; first.chapterIndex = 1;
  library.saveProgress(first);
  const newest = new ReadProgress();
  newest.sourceId = 'fixture'; newest.comicId = 'fixture';
  newest.chapterId = 'two'; newest.chapterIndex = 2;
  library.saveProgress(newest);
  await new Promise(resolve => setTimeout(resolve, 120));
  const serialized = pref.persistedProgress();
  check('阅读进度写入串行', pref.maxConcurrent() === 1);
  check('最新章节进度最终落盘', serialized.split('\t')[5] === '2');

  library.setChapterOrderFlipped('source-A', 'manga-1', true);
  library.setChapterOrderFlipped('source-A', 'manga-2', true);
  library.setChapterOrderFlipped('source-A', 'manga-1', false);
  check('章节方向修正仅针对单本作品',
    !library.isChapterOrderFlipped('source-A', 'manga-1') &&
    library.isChapterOrderFlipped('source-A', 'manga-2') &&
    !library.isChapterOrderFlipped('source-B', 'manga-2'));
  await new Promise(resolve => setTimeout(resolve, 120));
  const fixes = pref.persistedChapterOrderFixes();
  check('快速切换后的阅读方向偏好可靠落盘',
    fixes.includes('manga-2') && !fixes.includes('manga-1'));

  console.log('\n===== Runtime regression: PASS ' + passed + ' / FAIL ' + failed + ' =====');
  process.exitCode = failed > 0 ? 1 : 0;
} finally {
  fs.rmSync(temp, { recursive: true, force: true });
}
