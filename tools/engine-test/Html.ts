/**
 * 轻量 HTML 解析器。
 *
 * 目标不是完整实现 HTML5 规范，而是把漫画站的真实页面稳定变成一棵可查询的树。
 * 针对站点现状做了几处务实取舍：
 *  - script/style/textarea/title 按原样文本吞掉，不参与构建（站点脚本里常含伪标签）；
 *  - 未闭合标签用栈自动补齐，遇到不匹配的结束标签只回退到最近的同类祖先；
 *  - 节点数设上限，防止异常页面把内存打爆。
 */

const VOID_TAGS: string[] = [
  'area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input',
  'link', 'meta', 'param', 'source', 'track', 'wbr'
];

const RAW_TEXT_TAGS: string[] = ['script', 'style', 'textarea', 'title'];

const MAX_NODES: number = 60000;

export class HtmlNode {
  tag: string;
  attrs: Map<string, string>;
  children: HtmlNode[];
  parent: HtmlNode | null;
  /** 文本节点内容；元素节点为空串 */
  text: string;
  isText: boolean;

  constructor(tag: string, isText: boolean) {
    this.tag = tag;
    this.attrs = new Map<string, string>();
    this.children = [];
    this.parent = null;
    this.text = '';
    this.isText = isText;
  }

  attr(name: string): string {
    const value = this.attrs.get(name.toLowerCase());
    return value === undefined ? '' : value;
  }

  hasAttr(name: string): boolean {
    return this.attrs.has(name.toLowerCase());
  }

  className(): string {
    return this.attr('class');
  }

  /** 直接文本（不递归） */
  ownText(): string {
    return this.text;
  }

  /** 递归文本，跳过脚本样式 */
  textContent(): string {
    if (this.isText) {
      return this.text;
    }
    const lower = this.tag.toLowerCase();
    if (lower === 'script' || lower === 'style') {
      return '';
    }
    let out = this.text;
    for (let i = 0; i < this.children.length; i++) {
      out += this.children[i].textContent();
    }
    return out;
  }

  appendChild(child: HtmlNode): void {
    child.parent = this;
    this.children.push(child);
  }

  elementChildren(): HtmlNode[] {
    const out: HtmlNode[] = [];
    for (let i = 0; i < this.children.length; i++) {
      if (!this.children[i].isText) {
        out.push(this.children[i]);
      }
    }
    return out;
  }

  elementIndex(): number {
    const parent = this.parent;
    if (parent === null) {
      return 0;
    }
    let index = 0;
    for (let i = 0; i < parent.children.length; i++) {
      const node = parent.children[i];
      if (node === this) {
        return index;
      }
      if (!node.isText) {
        index++;
      }
    }
    return -1;
  }

  siblingCount(): number {
    const parent = this.parent;
    if (parent === null) {
      return 1;
    }
    return parent.elementChildren().length;
  }
}

/** 文档根：一个虚拟节点，便于统一从根查询 */
export class HtmlDocument {
  root: HtmlNode;
  /** 平铺的全部元素节点，按文档顺序；查询时复用，避免重复遍历 */
  flat: HtmlNode[];

  constructor(root: HtmlNode, flat: HtmlNode[]) {
    this.root = root;
    this.flat = flat;
  }
}

/** 把 HTML 源码解析成文档树 */
export function parseHtml(source: string): HtmlDocument {
  const root = new HtmlNode('#root', false);
  const stack: HtmlNode[] = [root];
  const flat: HtmlNode[] = [];
  let nodeCount = 0;

  const length = source.length;
  let i = 0;

  const pushElement = (node: HtmlNode): void => {
    const parent = stack[stack.length - 1];
    parent.appendChild(node);
    flat.push(node);
    nodeCount++;
  };

  const appendText = (chunk: string): void => {
    if (chunk.length === 0) {
      return;
    }
    const parent = stack[stack.length - 1];
    const last = parent.children.length > 0 ? parent.children[parent.children.length - 1] : null;
    if (last !== null && last.isText) {
      last.text += chunk;
      return;
    }
    const node = new HtmlNode('#text', true);
    node.text = chunk;
    parent.appendChild(node);
  };

  const closeTag = (name: string): void => {
    for (let depth = stack.length - 1; depth >= 1; depth--) {
      if (stack[depth].tag === name) {
        stack.length = depth;
        return;
      }
    }
  };

  while (i < length) {
    if (nodeCount > MAX_NODES) {
      break;
    }
    const lt = source.indexOf('<', i);
    if (lt < 0) {
      appendText(source.substring(i));
      break;
    }
    if (lt > i) {
      appendText(source.substring(i, lt));
    }

    if (source.startsWith('<!--', lt)) {
      const end = source.indexOf('-->', lt + 4);
      i = end < 0 ? length : end + 3;
      continue;
    }
    if (source.startsWith('<!', lt) || source.startsWith('<?', lt)) {
      const end = source.indexOf('>', lt);
      i = end < 0 ? length : end + 1;
      continue;
    }

    const isClose = source.charAt(lt + 1) === '/';
    const nameStart = isClose ? lt + 2 : lt + 1;
    let cursor = nameStart;
    while (cursor < length) {
      const ch = source.charAt(cursor);
      if ((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') ||
        (ch >= '0' && ch <= '9') || ch === '-' || ch === ':' || ch === '_') {
        cursor++;
      } else {
        break;
      }
    }
    if (cursor === nameStart) {
      // 不是合法标签，当普通文本处理
      appendText('<');
      i = lt + 1;
      continue;
    }
    const tagName = source.substring(nameStart, cursor).toLowerCase();

    if (isClose) {
      const gt = source.indexOf('>', cursor);
      i = gt < 0 ? length : gt + 1;
      closeTag(tagName);
      continue;
    }

    // 解析属性
    const node = new HtmlNode(tagName, false);
    let selfClosing = false;
    let attrCursor = cursor;
    while (attrCursor < length) {
      const ch = source.charAt(attrCursor);
      if (ch === '>') {
        attrCursor++;
        break;
      }
      if (ch === '/' && source.charAt(attrCursor + 1) === '>') {
        selfClosing = true;
        attrCursor += 2;
        break;
      }
      if (ch === ' ' || ch === '\n' || ch === '\r' || ch === '\t') {
        attrCursor++;
        continue;
      }
      const nameBegin = attrCursor;
      while (attrCursor < length) {
        const c = source.charAt(attrCursor);
        if (c === '=' || c === '>' || c === ' ' || c === '\n' || c === '\r' ||
          c === '\t' || (c === '/' && source.charAt(attrCursor + 1) === '>')) {
          break;
        }
        attrCursor++;
      }
      const attrName = source.substring(nameBegin, attrCursor).toLowerCase();
      let attrValue = '';
      if (source.charAt(attrCursor) === '=') {
        attrCursor++;
        const quote = source.charAt(attrCursor);
        if (quote === '"' || quote === '\'') {
          attrCursor++;
          const valueEnd = source.indexOf(quote, attrCursor);
          if (valueEnd < 0) {
            attrValue = source.substring(attrCursor);
            attrCursor = length;
          } else {
            attrValue = source.substring(attrCursor, valueEnd);
            attrCursor = valueEnd + 1;
          }
        } else {
          const valueBegin = attrCursor;
          while (attrCursor < length) {
            const c = source.charAt(attrCursor);
            if (c === ' ' || c === '>' || c === '\n' || c === '\r' || c === '\t') {
              break;
            }
            attrCursor++;
          }
          attrValue = source.substring(valueBegin, attrCursor);
        }
      }
      if (attrName.length > 0) {
        node.attrs.set(attrName, attrValue);
      }
    }

    pushElement(node);
    i = attrCursor;

    const isVoid = VOID_TAGS.indexOf(tagName) >= 0;
    if (selfClosing || isVoid) {
      continue;
    }
    if (RAW_TEXT_TAGS.indexOf(tagName) >= 0) {
      const closeSeq = '</' + tagName;
      const rawEnd = source.toLowerCase().indexOf(closeSeq, i);
      if (rawEnd < 0) {
        node.text = source.substring(i);
        i = length;
      } else {
        node.text = source.substring(i, rawEnd);
        const gt = source.indexOf('>', rawEnd);
        i = gt < 0 ? length : gt + 1;
      }
      continue;
    }
    stack.push(node);
  }

  return new HtmlDocument(root, flat);
}
