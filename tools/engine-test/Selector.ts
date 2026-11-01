/**
 * CSS 选择器引擎（自研，够用即止）。
 *
 * 支持：标签 / #id / .class / [attr] / [attr=v] / [attr*=v] / [attr^=v] / [attr$=v]
 *      后代(空格) / 子代(>) / 相邻(+) / 兄弟(~) / 逗号分组
 *      伪类 :first-child :last-child :nth-child(n) :eq(n) :contains(文本)
 * 不支持伪元素与动态伪类（站点页面里用不到，且实现成本高）。
 */

import { HtmlNode, HtmlDocument } from './Html.ts';
import { decodeEntities } from './Text.ts';

class AttrCond {
  name: string;
  op: string; // '' | '=' | '*=' | '^=' | '$='
  value: string;

  constructor(name: string, op: string, value: string) {
    this.name = name;
    this.op = op;
    this.value = value;
  }
}

class PseudoCond {
  name: string;
  number: number;
  text: string;

  constructor(name: string, number: number, text: string) {
    this.name = name;
    this.number = number;
    this.text = text;
  }
}

class Compound {
  tag: string = '';
  id: string = '';
  classes: string[] = [];
  attrs: AttrCond[] = [];
  pseudos: PseudoCond[] = [];
}

class SeqItem {
  combinator: string; // '' | ' ' | '>' | '+' | '~'
  compound: Compound;

  constructor(combinator: string, compound: Compound) {
    this.combinator = combinator;
    this.compound = compound;
  }
}

function parseCompound(raw: string): Compound {
  const compound = new Compound();
  let i = 0;
  const length = raw.length;

  // 开头可能是标签名或通配
  if (i < length) {
    const first = raw.charAt(i);
    if (first === '*') {
      i++;
    } else if ((first >= 'a' && first <= 'z') || (first >= 'A' && first <= 'Z')) {
      const begin = i;
      while (i < length) {
        const ch = raw.charAt(i);
        if ((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') ||
          (ch >= '0' && ch <= '9') || ch === '-' || ch === '_' || ch === ':') {
          i++;
        } else {
          break;
        }
      }
      compound.tag = raw.substring(begin, i).toLowerCase();
    }
  }

  while (i < length) {
    const ch = raw.charAt(i);
    if (ch === '.') {
      i++;
      const begin = i;
      while (i < length) {
        const c = raw.charAt(i);
        if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
          (c >= '0' && c <= '9') || c === '-' || c === '_') {
          i++;
        } else {
          break;
        }
      }
      const cls = raw.substring(begin, i);
      if (cls.length > 0) {
        compound.classes.push(cls);
      }
    } else if (ch === '#') {
      i++;
      const begin = i;
      while (i < length) {
        const c = raw.charAt(i);
        if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
          (c >= '0' && c <= '9') || c === '-' || c === '_') {
          i++;
        } else {
          break;
        }
      }
      compound.id = raw.substring(begin, i);
    } else if (ch === '[') {
      const close = raw.indexOf(']', i);
      if (close < 0) {
        break;
      }
      const inner = raw.substring(i + 1, close);
      compound.attrs.push(parseAttr(inner));
      i = close + 1;
    } else if (ch === ':') {
      i++;
      const begin = i;
      while (i < length) {
        const c = raw.charAt(i);
        if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c === '-') {
          i++;
        } else {
          break;
        }
      }
      const name = raw.substring(begin, i).toLowerCase();
      let argText = '';
      if (raw.charAt(i) === '(') {
        const close = findBalanced(raw, i);
        argText = raw.substring(i + 1, close);
        i = close + 1;
      }
      let numeric = -1;
      if (argText.length > 0) {
        const parsed = parseInt(argText, 10);
        if (!isNaN(parsed)) {
          numeric = parsed;
        }
      }
      compound.pseudos.push(new PseudoCond(name, numeric, argText));
    } else {
      i++;
    }
  }
  return compound;
}

function findBalanced(raw: string, openIndex: number): number {
  let depth = 0;
  for (let i = openIndex; i < raw.length; i++) {
    const ch = raw.charAt(i);
    if (ch === '(') {
      depth++;
    } else if (ch === ')') {
      depth--;
      if (depth === 0) {
        return i;
      }
    }
  }
  return raw.length - 1;
}

function parseAttr(inner: string): AttrCond {
  const operators: string[] = ['*=', '^=', '$=', '='];
  for (let o = 0; o < operators.length; o++) {
    const op = operators[o];
    const index = inner.indexOf(op);
    if (index > 0) {
      const name = inner.substring(0, index).trim().toLowerCase();
      let value = inner.substring(index + op.length).trim();
      if ((value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith('\'') && value.endsWith('\''))) {
        value = value.substring(1, value.length - 1);
      }
      return new AttrCond(name, op, value);
    }
  }
  return new AttrCond(inner.trim().toLowerCase(), '', '');
}

function parseSelectorText(text: string): SeqItem[][] {
  const groups: SeqItem[][] = [];
  const rawGroups = splitTopLevel(text, ',');
  for (let g = 0; g < rawGroups.length; g++) {
    const raw = rawGroups[g].trim();
    if (raw.length === 0) {
      continue;
    }
    const items: SeqItem[] = [];
    let i = 0;
    let pendingCombinator = '';
    const length = raw.length;
    while (i < length) {
      const ch = raw.charAt(i);
      if (ch === ' ' || ch === '\n' || ch === '\t' || ch === '\r') {
        if (items.length > 0 && pendingCombinator.length === 0) {
          pendingCombinator = ' ';
        }
        i++;
        continue;
      }
      if (ch === '>' || ch === '+' || ch === '~') {
        pendingCombinator = ch;
        i++;
        continue;
      }
      const begin = i;
      let depth = 0;
      while (i < length) {
        const c = raw.charAt(i);
        if (c === '(') {
          depth++;
        } else if (c === ')') {
          depth--;
        } else if (depth === 0 && (c === ' ' || c === '>' || c === '+' || c === '~' || c === '\t' || c === '\n')) {
          break;
        }
        i++;
      }
      const token = raw.substring(begin, i);
      if (token.length === 0) {
        continue;
      }
      const combinator = items.length === 0 ? '' : (pendingCombinator.length === 0 ? ' ' : pendingCombinator);
      items.push(new SeqItem(combinator, parseCompound(token)));
      pendingCombinator = '';
    }
    if (items.length > 0) {
      groups.push(items);
    }
  }
  return groups;
}

function splitTopLevel(text: string, separator: string): string[] {
  const out: string[] = [];
  let depth = 0;
  let current = '';
  for (let i = 0; i < text.length; i++) {
    const ch = text.charAt(i);
    if (ch === '(' || ch === '[') {
      depth++;
    } else if (ch === ')' || ch === ']') {
      depth--;
    }
    if (ch === separator && depth === 0) {
      out.push(current);
      current = '';
      continue;
    }
    current += ch;
  }
  out.push(current);
  return out;
}

function matchesCompound(node: HtmlNode, compound: Compound): boolean {
  if (node.isText) {
    return false;
  }
  if (compound.tag.length > 0 && node.tag !== compound.tag) {
    return false;
  }
  if (compound.id.length > 0 && node.attr('id') !== compound.id) {
    return false;
  }
  if (compound.classes.length > 0) {
    // 手工按空白切分类名，避免正则开销
    const classes = node.className();
    for (let i = 0; i < compound.classes.length; i++) {
      const target = compound.classes[i];
      let found = false;
      let start = 0;
      while (start <= classes.length) {
        let end = classes.indexOf(' ', start);
        if (end < 0) {
          end = classes.length;
        }
        if (classes.substring(start, end) === target) {
          found = true;
          break;
        }
        if (end === classes.length) {
          break;
        }
        start = end + 1;
      }
      if (!found) {
        return false;
      }
    }
  }
  for (let i = 0; i < compound.attrs.length; i++) {
    const cond = compound.attrs[i];
    if (!node.hasAttr(cond.name)) {
      return false;
    }
    if (cond.op.length === 0) {
      continue;
    }
    const actual = node.attr(cond.name);
    if (cond.op === '=') {
      if (actual !== cond.value) {
        return false;
      }
    } else if (cond.op === '*=') {
      if (actual.indexOf(cond.value) < 0) {
        return false;
      }
    } else if (cond.op === '^=') {
      if (!actual.startsWith(cond.value)) {
        return false;
      }
    } else if (cond.op === '$=') {
      if (!actual.endsWith(cond.value)) {
        return false;
      }
    }
  }
  for (let i = 0; i < compound.pseudos.length; i++) {
    const pseudo = compound.pseudos[i];
    if (pseudo.name === 'first-child') {
      if (node.elementIndex() !== 0) {
        return false;
      }
    } else if (pseudo.name === 'last-child') {
      if (node.elementIndex() !== node.siblingCount() - 1) {
        return false;
      }
    } else if (pseudo.name === 'nth-child') {
      if (pseudo.number < 0 || node.elementIndex() !== pseudo.number) {
        return false;
      }
    } else if (pseudo.name === 'eq') {
      if (pseudo.number < 0) {
        return false;
      }
    } else if (pseudo.name === 'contains') {
      const target = decodeEntities(pseudo.text).replace(new RegExp('^["\']|["\']$', 'g'), '');
      if (node.textContent().indexOf(target) < 0) {
        return false;
      }
    }
  }
  return true;
}

function previousElement(node: HtmlNode): HtmlNode | null {
  const parent = node.parent;
  if (parent === null) {
    return null;
  }
  let previous: HtmlNode | null = null;
  for (let i = 0; i < parent.children.length; i++) {
    const current = parent.children[i];
    if (current === node) {
      return previous;
    }
    if (!current.isText) {
      previous = current;
    }
  }
  return null;
}

function matchesSequence(node: HtmlNode, seq: SeqItem[], index: number): boolean {
  if (!matchesCompound(node, seq[index].compound)) {
    return false;
  }
  if (index === 0) {
    return true;
  }
  const combinator = seq[index].combinator;
  if (combinator === '>') {
    const parent = node.parent;
    return parent !== null && matchesSequence(parent, seq, index - 1);
  }
  if (combinator === '+') {
    const previous = previousElement(node);
    return previous !== null && matchesSequence(previous, seq, index - 1);
  }
  if (combinator === '~') {
    let cursor = previousElement(node);
    while (cursor !== null) {
      if (matchesSequence(cursor, seq, index - 1)) {
        return true;
      }
      cursor = previousElement(cursor);
    }
    return false;
  }
  // 后代
  let parent = node.parent;
  while (parent !== null) {
    if (!parent.isText && matchesSequence(parent, seq, index - 1)) {
      return true;
    }
    parent = parent.parent;
  }
  return false;
}

/** 查询所有匹配节点，保持文档顺序 */
export function queryAll(root: HtmlDocument, selector: string): HtmlNode[] {
  const groups = parseSelectorText(selector);
  if (groups.length === 0) {
    return [];
  }
  const result: HtmlNode[] = [];
  const flat = root.flat;
  for (let i = 0; i < flat.length; i++) {
    const node = flat[i];
    for (let g = 0; g < groups.length; g++) {
      const seq = groups[g];
      if (matchesSequence(node, seq, seq.length - 1)) {
        result.push(node);
        break;
      }
    }
  }
  // :eq() 是位置语义，需要在结果集上再裁剪一次
  return applyEq(result, selector);
}

/** 查询第一个匹配节点 */
export function queryOne(root: HtmlDocument, selector: string): HtmlNode | null {
  const all = queryAll(root, selector);
  return all.length > 0 ? all[0] : null;
}

function applyEq(nodes: HtmlNode[], selector: string): HtmlNode[] {
  if (selector.indexOf(':eq(') < 0) {
    return nodes;
  }
  const all = parseSelectorText(selector);
  const wanted: number[] = [];
  let hasEq = false;
  for (let g = 0; g < all.length; g++) {
    const seq = all[g];
    const last = seq[seq.length - 1];
    for (let p = 0; p < last.compound.pseudos.length; p++) {
      const pseudo = last.compound.pseudos[p];
      if (pseudo.name === 'eq' && pseudo.number >= 0) {
        wanted.push(pseudo.number);
        hasEq = true;
      }
    }
  }
  if (!hasEq) {
    return nodes;
  }
  const out: HtmlNode[] = [];
  for (let i = 0; i < nodes.length; i++) {
    if (wanted.indexOf(i) >= 0) {
      out.push(nodes[i]);
    }
  }
  return out;
}

/** 在给定节点集合内继续筛选（用于作用域内二次查询） */
export function queryWithin(nodes: HtmlNode[], selector: string): HtmlNode[] {
  const groups = parseSelectorText(selector);
  if (groups.length === 0) {
    return [];
  }
  const out: HtmlNode[] = [];
  for (let n = 0; n < nodes.length; n++) {
    const scope = nodes[n];
    for (let g = 0; g < groups.length; g++) {
      const seq = groups[g];
      if (matchesSequence(scope, seq, seq.length - 1)) {
        out.push(scope);
        break;
      }
    }
    // 后代
    collectDescendants(scope, groups, out);
  }
  return out;
}

function collectDescendants(scope: HtmlNode, groups: SeqItem[][], out: HtmlNode[]): void {
  const stack: HtmlNode[] = [scope];
  while (stack.length > 0) {
    const node = stack.pop() as HtmlNode;
    for (let i = 0; i < node.children.length; i++) {
      const child = node.children[i];
      if (child.isText) {
        continue;
      }
      for (let g = 0; g < groups.length; g++) {
        const seq = groups[g];
        if (matchesSequence(child, seq, seq.length - 1)) {
          if (out.indexOf(child) < 0) {
            out.push(child);
          }
          break;
        }
      }
      stack.push(child);
    }
  }
}

/** 判断单个节点是否匹配选择器 */
export function matches(node: HtmlNode, selector: string): boolean {
  const groups = parseSelectorText(selector);
  for (let g = 0; g < groups.length; g++) {
    const seq = groups[g];
    if (matchesSequence(node, seq, seq.length - 1)) {
      return true;
    }
  }
  return false;
}
