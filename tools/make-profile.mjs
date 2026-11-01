// 生成本地调试签名用的 profile.json 与 app 证书文件。
// 注意：这条路用的是 OpenHarmony 的根证书链，只为验证商业版设备是否放行。
import fs from 'node:fs';
import path from 'node:path';

const LIB = 'D:/DevEco Studio/sdk/default/openharmony/toolchains/lib';
const OUT = 'F:/AI/QoderCN-Data/output/harmony-comic-origin/signwork';
const UDID = 'B564AE4F3EB7785556DC1E315402C03CB3CCBEBA05D29D0048AF4132240D863B';
const BUNDLE = 'com.manyu.reader';

fs.mkdirSync(OUT, { recursive: true });

const template = JSON.parse(fs.readFileSync(path.join(LIB, 'UnsgnedDebugProfileTemplate.json'), 'utf8'));
const now = Math.floor(Date.now() / 1000);

template['version-name'] = '1.0.0';
template['version-code'] = 1000000;
template['uuid'] = '9a7c2c4e-1f35-4b1e-9d2a-' + Math.random().toString(16).slice(2, 14);
template['validity'] = { 'not-before': now - 3600, 'not-after': now + 365 * 86400 };
template['type'] = 'debug';
template['bundle-info']['bundle-name'] = BUNDLE;
template['bundle-info']['developer-id'] = 'OpenHarmony';
template['debug-info']['device-ids'] = [UDID];
template['debug-info']['device-id-type'] = 'udid';

fs.writeFileSync(path.join(OUT, 'profile.json'), JSON.stringify(template, null, 2), 'utf8');

// 把模板里的开发证书单独导出，签 HAP 时要用
fs.writeFileSync(path.join(OUT, 'app-release.cer'), template['bundle-info']['development-certificate'], 'utf8');

console.log('bundle:', BUNDLE);
console.log('udid  :', UDID);
console.log('valid :', new Date((now - 3600) * 1000).toISOString(), '→', new Date((now + 365 * 86400) * 1000).toISOString());
console.log('written to', OUT);
