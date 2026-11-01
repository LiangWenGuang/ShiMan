// 解析 p7b 调试证书，读出有效期、绑定的包名与设备数，用于对比不同签名来源。
import fs from 'node:fs';

const FILES = [
  ['DevEco 调试证书（旧 VenHM 用的）', 'C:/Users/10245/.ohos/config/default_app_UUu9n7dUNyBuBJRgUIMVsHaH_9-g4A1Mjn1csqaLG1M=.p7b'],
  ['小白工具 xiaobai-debug', 'C:/Users/10245/Documents/hap_installer/store/xiaobai-debug.p7b'],
  ['小白工具 clashboxLTS', 'C:/Users/10245/Documents/hap_installer/store/org_xbgroup_clashboxLTS.p7b'],
  ['★ 本次 DevEco 自动签名生成的', 'C:/Users/10245/.ohos/config/default_app_H24bcsdXT8jl9n_lskZh9GsLzwxYxX5yxIAuD_YZ7PY=.p7b'],
  ['我给本地 OpenHarmony 试签的（未用上）', 'F:/AI/QoderCN-Data/output/harmony-comic-origin/signwork/profile.p7b']
];

function fmt(ts) {
  if (!ts) return '—';
  const d = new Date(ts * 1000);
  const pad = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

for (const [label, file] of FILES) {
  console.log('\n===== ' + label);
  if (!fs.existsSync(file)) {
    console.log('  文件不存在');
    continue;
  }
  const raw = fs.readFileSync(file);
  const start = raw.indexOf(Buffer.from('{"version-name"'));
  if (start < 0) {
    console.log('  未找到内嵌 JSON');
    continue;
  }
  const text = raw.slice(start).toString('utf8');
  let depth = 0;
  let end = -1;
  for (let i = 0; i < text.length; i++) {
    if (text[i] === '{') depth++;
    else if (text[i] === '}') { depth--; if (depth === 0) { end = i + 1; break; } }
  }
  const json = text.slice(0, end);
  const validity = /"not-before":(\d+)/.exec(json);
  const notAfter = /"not-after":(\d+)/.exec(json);
  const bundle = /"bundle-name":"([^"]*)"/.exec(json);
  const type = /"type":"([^"]*)"/.exec(json);
  const apl = /"apl":"([^"]*)"/.exec(json);
  const devIds = /"device-ids":\[([\s\S]*?)\]/.exec(json);

  const nb = validity ? Number(validity[1]) : 0;
  const na = notAfter ? Number(notAfter[1]) : 0;
  const days = nb && na ? Math.round((na - nb) / 86400) : 0;

  console.log('  类型      :', type ? type[1] : '—', ' apl:', apl ? apl[1] : '—');
  console.log('  包名      :', bundle ? bundle[1] : '—');
  console.log('  生效      :', fmt(nb));
  console.log('  失效      :', fmt(na));
  console.log('  有效天数  :', days, '天 ≈', (days / 365).toFixed(2), '年');
  if (devIds) {
    const ids = devIds[1].split(',').map((s) => s.trim()).filter(Boolean);
    console.log('  绑定设备数:', ids.length);
  }
  const daysLeft = na ? Math.round((na - Date.now() / 1000) / 86400) : 0;
  console.log('  剩余天数  :', daysLeft > 0 ? daysLeft + ' 天' : '已过期');
}
