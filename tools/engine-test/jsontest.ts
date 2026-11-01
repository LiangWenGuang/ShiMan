// JSON 解析健壮性回归：死循环、双重编码、脏字符
import { parseJson, JsonKind } from './Json.ts';

let pass = 0, fail = 0;
const check = (n: string, ok: boolean, d: string) => {
  if (ok) { pass++; console.log(`  PASS  ${n}  ${d}`); } else { fail++; console.log(`  FAIL  ${n}  ${d}`); }
};

const urls = '["https://a.example/1.jpg","https://a.example/2.jpg"]';
const a = parseJson(urls);
check('普通数组', a.kind === JsonKind.Array && a.items.length === 2, `len=${a.items.length}`);

// runJavaScript 返回的双重编码形态
const doubled = JSON.stringify(urls);
const b = parseJson(doubled);
check('双重编码可解开', b.kind === JsonKind.Array && b.items.length === 2, `len=${b.items.length}`);

// 脏输入不能挂
const t0 = Date.now();
const c = parseJson('[\\"x\\", \\"y\\"]');
check('残留反斜杠不死循环', Date.now() - t0 < 2000, `${Date.now() - t0}ms kind=${c.kind}`);
const d2 = parseJson('garbage###');
check('纯垃圾输入不死循环', Date.now() - t0 < 4000, `${Date.now() - t0}ms`);

console.log(`\n===== JSON: PASS ${pass} / FAIL ${fail} =====`);
process.exit(fail === 0 ? 0 : 1);
