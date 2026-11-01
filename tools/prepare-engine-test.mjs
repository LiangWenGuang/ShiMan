// 把 ArkTS 的纯逻辑模块（无 ArkUI 依赖）抽到 Node 里做等价回归，
// 验证 HTML 解析 / 选择器 / 规则引擎在真实页面上确实能取到数据。
import fs from 'node:fs';
import path from 'node:path';

const ETS = 'F:/AI/QoderCN-Data/output/harmony-comic-origin/app/entry/src/main/ets';
const OUT = 'F:/AI/QoderCN-Data/output/harmony-comic-origin/tools/engine-test';

const FILES = [
  ['model/Models.ets', 'Models.ts'],
  ['util/Text.ets', 'Text.ts'],
  ['parse/Html.ets', 'Html.ts'],
  ['parse/Selector.ets', 'Selector.ts'],
  ['parse/Json.ets', 'Json.ts'],
  ['rule/Rules.ets', 'Rules.ts'],
  ['rule/Engine.ets', 'Engine.ts']
];

fs.mkdirSync(OUT, { recursive: true });

const IMPORT_MAP = {
  '../model/Models': './Models.ts',
  '../parse/Html': './Html.ts',
  '../parse/Selector': './Selector.ts',
  '../parse/Json': './Json.ts',
  '../util/Text': './Text.ts',
  './Rules': './Rules.ts'
};

for (const [src, dst] of FILES) {
  let code = fs.readFileSync(path.join(ETS, src), 'utf8');
  for (const [from, to] of Object.entries(IMPORT_MAP)) {
    code = code.split(`from '${from}'`).join(`from '${to}'`);
    code = code.split(`from "${from}"`).join(`from "${to}"`);
  }
  fs.writeFileSync(path.join(OUT, dst), code, 'utf8');
  console.log('copied', dst, code.length);
}
