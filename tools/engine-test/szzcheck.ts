import { fetchFollow } from '../http.mjs';
import { parseJson } from './Json.ts';
import { ruleFromJson } from './Rules.ts';
import { parseImagesFromRegex, parseListItems } from './Engine.ts';
import fs from 'node:fs';

const SRC = 'F:/AI/QoderCN-Data/output/harmony-comic-origin/app/entry/src/main/resources/rawfile/sources/songzi.json';
const rule = ruleFromJson(parseJson(fs.readFileSync(SRC, 'utf8')));
const headers = { Referer: rule.baseUrl + '/' };

// 1) 章节图片是否串章
const ch = await fetchFollow('https://www.songzimanhua.com/read/1633214/', { headers, timeout: 25000 });
const imgs = parseImagesFromRegex(ch.text, rule, 'https://www.songzimanhua.com/read/1633214/');
const dirs = [...new Set(imgs.map((i) => (i.url.match(/chapters\/\d+\/\d+\//) || ['?'])[0]))];
console.log(`图片 ${imgs.length} 张，来自 ${dirs.length} 个目录: ${dirs.join(', ')}`);
console.log('首图:', imgs[0]?.url);
console.log('末图:', imgs[imgs.length - 1]?.url);
const nums = imgs.map((i) => Number((i.url.match(/\/(\d+)_\d+\.webp$/) || [0, 0])[1]));
const seq = nums.every((n, k) => k === 0 || n >= nums[k - 1]);
console.log('序号是否单调递增:', seq, '  首序号', nums[0], '末序号', nums[nums.length - 1]);

// 2) 排行榜做分类页是否可用
const br = rule.browse[0];
const r = await fetchFollow(rule.baseUrl + br.url, { headers, timeout: 25000 });
const items = parseListItems(r.text, br.listSelector, rule.id, rule.baseUrl + br.url,
  br.title, br.cover, br.link, br.id, br.author, br.latest);
console.log(`\n分类页 ${br.name}: status=${r.status} 条数=${items.length}`);
if (items.length) console.log('  首条:', items[0].title, items[0].url);
