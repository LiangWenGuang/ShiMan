/**
 * 自研 JSON 解析与 JSON Path 取值。
 *
 * 为什么不用 JSON.parse：ArkTS 严格模式下 JSON.parse 返回 Object，
 * 动态键访问需要反复强转，既容易崩也不好读。这里直接产出强类型节点树，
 * 顺带支持站点的 JSONP 包裹（`callback({...})`）。
 */

export enum JsonKind {
  Object = 0,
  Array = 1,
  String = 2,
  Number = 3,
  Bool = 4,
  Null = 5
}

export class JsonNode {
  kind: JsonKind;
  members: Map<string, JsonNode>;
  items: JsonNode[];
  text: string;
  number: number;
  flag: boolean;

  constructor(kind: JsonKind) {
    this.kind = kind;
    this.members = new Map<string, JsonNode>();
    this.items = [];
    this.text = '';
    this.number = 0;
    this.flag = false;
  }

  static ofString(value: string): JsonNode {
    const node = new JsonNode(JsonKind.String);
    node.text = value;
    return node;
  }

  static ofNumber(value: number): JsonNode {
    const node = new JsonNode(JsonKind.Number);
    node.number = value;
    return node;
  }

  asString(): string {
    if (this.kind === JsonKind.String) {
      return this.text;
    }
    if (this.kind === JsonKind.Number) {
      return String(this.number);
    }
    if (this.kind === JsonKind.Bool) {
      return this.flag ? 'true' : 'false';
    }
    return '';
  }

  asNumber(): number {
    if (this.kind === JsonKind.Number) {
      return this.number;
    }
    if (this.kind === JsonKind.String) {
      const parsed = parseFloat(this.text);
      return isNaN(parsed) ? 0 : parsed;
    }
    return 0;
  }

  get(key: string): JsonNode | null {
    const found = this.members.get(key);
    return found === undefined ? null : found;
  }

  isContainer(): boolean {
    return this.kind === JsonKind.Object || this.kind === JsonKind.Array;
  }
}

class JsonReader {
  private source: string;
  private index: number = 0;

  constructor(source: string) {
    this.source = source;
  }

  parse(): JsonNode {
    this.skipWhitespace();
    const value = this.readValue();
    return value;
  }

  private skipWhitespace(): void {
    while (this.index < this.source.length) {
      const ch = this.source.charAt(this.index);
      if (ch === ' ' || ch === '\n' || ch === '\r' || ch === '\t') {
        this.index++;
      } else {
        break;
      }
    }
  }

  private readValue(): JsonNode {
    this.skipWhitespace();
    if (this.index >= this.source.length) {
      return new JsonNode(JsonKind.Null);
    }
    const ch = this.source.charAt(this.index);
    if (ch === '{') {
      return this.readObject();
    }
    if (ch === '[') {
      return this.readArray();
    }
    if (ch === '"' || ch === '\'') {
      return JsonNode.ofString(this.readString());
    }
    if (ch === 't' || ch === 'f') {
      return this.readBool();
    }
    if (ch === 'n') {
      this.index += 4;
      return new JsonNode(JsonKind.Null);
    }
    return this.readNumber();
  }

  private readObject(): JsonNode {
    const node = new JsonNode(JsonKind.Object);
    this.index++; // {
    let guard = 0;
    while (this.index < this.source.length) {
      guard++;
      if (guard > 200000) {
        break;
      }
      this.skipWhitespace();
      const ch = this.source.charAt(this.index);
      if (ch === '}') {
        this.index++;
        break;
      }
      if (ch === ',') {
        this.index++;
        continue;
      }
      if (ch === '"' || ch === '\'') {
        const key = this.readString();
        this.skipWhitespace();
        if (this.source.charAt(this.index) === ':') {
          this.index++;
        }
        const value = this.readValue();
        node.members.set(key, value);
      } else {
        // 非标准写法：跳到下一个逗号，避免死循环
        const next = this.source.indexOf(',', this.index);
        const end = this.source.indexOf('}', this.index);
        if (next < 0 && end < 0) {
          this.index = this.source.length;
        } else if (next < 0) {
          this.index = end;
        } else {
          this.index = next;
        }
      }
    }
    return node;
  }

  private readArray(): JsonNode {
    const node = new JsonNode(JsonKind.Array);
    this.index++; // [
    let guard = 0;
    while (this.index < this.source.length) {
      // 防御性上限：即使解析逻辑出意外，也不能变成无限循环
      guard++;
      if (guard > 200000) {
        break;
      }
      this.skipWhitespace();
      const ch = this.source.charAt(this.index);
      if (ch === ']') {
        this.index++;
        break;
      }
      if (ch === ',') {
        this.index++;
        continue;
      }
      node.items.push(this.readValue());
    }
    return node;
  }

  private readString(): string {
    const quote = this.source.charAt(this.index);
    this.index++;
    let out = '';
    while (this.index < this.source.length) {
      const ch = this.source.charAt(this.index);
      if (ch === quote) {
        this.index++;
        break;
      }
      if (ch === '\\') {
        this.index++;
        const esc = this.source.charAt(this.index);
        if (esc === 'n') {
          out += '\n';
        } else if (esc === 't') {
          out += '\t';
        } else if (esc === 'r') {
          out += '\r';
        } else if (esc === 'b') {
          out += '\b';
        } else if (esc === 'f') {
          out += '\f';
        } else if (esc === 'u') {
          const hex = this.source.substring(this.index + 1, this.index + 5);
          const code = parseInt(hex, 16);
          out += isNaN(code) ? '' : String.fromCharCode(code);
          this.index += 4;
        } else if (esc === '/') {
          out += '/';
        } else {
          out += esc;
        }
        this.index++;
        continue;
      }
      out += ch;
      this.index++;
    }
    // 站点常见：字符串里塞转义的 \/，上面已处理；这里再统一还原一次
    return out;
  }

  private readBool(): JsonNode {
    const node = new JsonNode(JsonKind.Bool);
    if (this.source.charAt(this.index) === 't') {
      node.flag = true;
      this.index += 4;
    } else {
      node.flag = false;
      this.index += 5;
    }
    return node;
  }

  private readNumber(): JsonNode {
    const begin = this.index;
    while (this.index < this.source.length) {
      const ch = this.source.charAt(this.index);
      const isDigit = (ch >= '0' && ch <= '9') || ch === '-' || ch === '+' || ch === '.' ||
        ch === 'e' || ch === 'E';
      if (!isDigit) {
        break;
      }
      this.index++;
    }
    if (this.index === begin) {
      // 遇到无法识别的字符（例如被整体 JSON 编码后残留的反斜杠）：
      // 必须吞掉一个字符，否则外层循环原地打转会把内存吃光。
      this.index++;
      return new JsonNode(JsonKind.Null);
    }
    const raw = this.source.substring(begin, this.index);
    const parsed = parseFloat(raw);
    return JsonNode.ofNumber(isNaN(parsed) ? 0 : parsed);
  }
}

/** 解析 JSON 文本；自动跳过 JSONP 外壳 */
export function parseJson(source: string): JsonNode {
  let text = source.trim();
  const brace = text.indexOf('{');
  const bracket = text.indexOf('[');
  let start = -1;
  if (brace >= 0 && bracket >= 0) {
    start = brace < bracket ? brace : bracket;
  } else if (brace >= 0) {
    start = brace;
  } else if (bracket >= 0) {
    start = bracket;
  }
  if (start > 0) {
    text = text.substring(start);
  }
  let node = new JsonReader(text).parse();
  // runJavaScript 取回字符串时可能被整体再编码一层（"[\"https://...\"]"），
  // 这里解开一次，否则外层会当成普通字符串而取不到数组元素。
  if (node.kind === JsonKind.String) {
    const inner = node.text.trim();
    if (inner.startsWith('[') || inner.startsWith('{')) {
      node = new JsonReader(inner).parse();
    }
  }
  return node;
}

/**
 * JSON Path 取值。支持 `$.a.b`、`a.b`、`$.list[0].x`，
 * 若末段命中数组则铺平返回，便于「列表 → 字段」两层写法。
 */
export function selectPath(root: JsonNode, path: string): JsonNode[] {
  let expr = path.trim();
  if (expr.startsWith('$')) {
    expr = expr.substring(1);
  }
  if (expr.startsWith('.')) {
    expr = expr.substring(1);
  }
  if (expr.length === 0) {
    return [root];
  }

  let current: JsonNode[] = [root];
  const segments = expr.split('.');
  for (let s = 0; s < segments.length; s++) {
    const segment = segments[s];
    if (segment.length === 0) {
      continue;
    }
    const bracketIndex = segment.indexOf('[');
    const key = bracketIndex >= 0 ? segment.substring(0, bracketIndex) : segment;
    let indices: number[] = [];
    if (bracketIndex >= 0) {
      const tail = segment.substring(bracketIndex);
      const matches = tail.match(new RegExp('\\[(\\d+)\\]', 'g'));
      if (matches !== null) {
        for (let m = 0; m < matches.length; m++) {
          const digits = matches[m].replace('[', '').replace(']', '');
          indices.push(parseInt(digits, 10));
        }
      }
    }

    const next: JsonNode[] = [];
    for (let c = 0; c < current.length; c++) {
      let node: JsonNode | null = current[c];
      if (node === null) {
        continue;
      }
      if (key.length > 0) {
        if (node.kind === JsonKind.Array) {
          for (let i = 0; i < node.items.length; i++) {
            const child = node.items[i].get(key);
            if (child !== null) {
              next.push(child);
            }
          }
          node = null;
        } else if (node.kind === JsonKind.Object) {
          node = node.get(key);
          if (node !== null) {
            next.push(node);
          }
        } else {
          node = null;
        }
      } else {
        next.push(node);
      }
    }

    if (indices.length === 0) {
      current = next;
      continue;
    }

    const indexed: JsonNode[] = [];
    for (let n = 0; n < next.length; n++) {
      let node: JsonNode | null = next[n];
      for (let k = 0; k < indices.length; k++) {
        if (node === null || node.kind !== JsonKind.Array) {
          node = null;
          break;
        }
        const idx = indices[k];
        node = idx >= 0 && idx < node.items.length ? node.items[idx] : null;
      }
      if (node !== null) {
        indexed.push(node);
      }
    }
    current = indexed;
  }
  return current;
}
