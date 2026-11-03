/**
 * 图源注册表。
 *
 * 内置图源以 JSON 文件随包分发（resources/rawfile/sources/），
 * 这里负责加载、解析、持久化启用状态，并对外提供查询。
 * 用户自建图源走同一套规则格式，后续扩展不需要改引擎。
 */

import { util } from '@kit.ArkTS';
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { SourceRule, ruleFromJson } from '../rule/Rules';
import { parseJson } from '../parse/Json';

const STORE_NAME = 'manyu_sources';
const KEY_DISABLED = 'disabled_ids';
const KEY_CURRENT = 'current_source';

export class SourceRegistry {
  private static instance: SourceRegistry | null = null;
  private rules: Map<string, SourceRule> = new Map<string, SourceRule>();
  private order: string[] = [];
  private disabled: Set<string> = new Set<string>();
  private store: preferences.Preferences | null = null;
  private loaded: boolean = false;
  private currentId: string = '';

  static get(): SourceRegistry {
    if (SourceRegistry.instance === null) {
      SourceRegistry.instance = new SourceRegistry();
    }
    return SourceRegistry.instance;
  }

  /** 启动时调用一次 */
  async init(context: common.UIAbilityContext): Promise<void> {
    if (this.loaded) {
      return;
    }
    try {
      this.store = await preferences.getPreferences(context, STORE_NAME);
      const disabledRaw = await this.store.get(KEY_DISABLED, '');
      if (typeof disabledRaw === 'string' && disabledRaw.length > 0) {
        const parts = disabledRaw.split(',');
        for (let i = 0; i < parts.length; i++) {
          if (parts[i].length > 0) {
            this.disabled.add(parts[i]);
          }
        }
      }
      const currentRaw = await this.store.get(KEY_CURRENT, '');
      if (typeof currentRaw === 'string') {
        this.currentId = currentRaw;
      }
    } catch (error) {
      // 偏好读取失败不阻塞启动
    }

    await this.loadBundled(context);
    this.loaded = true;
  }

  private async loadBundled(context: common.UIAbilityContext): Promise<void> {
    const manager = context.resourceManager;
    let indexText = '';
    try {
      const indexData = await manager.getRawFileContent('sources/index.json');
      indexText = util.TextDecoder.create('utf-8').decodeToString(indexData);
    } catch (error) {
      return;
    }
    const indexRoot = parseJson(indexText);
    const list = indexRoot.get('sources');
    if (list === null || list.items.length === 0) {
      return;
    }
    for (let i = 0; i < list.items.length; i++) {
      const fileNode = list.items[i];
      const fileName = fileNode.asString();
      if (fileName.length === 0) {
        continue;
      }
      try {
        const data = await manager.getRawFileContent(`sources/${fileName}`);
        const text = util.TextDecoder.create('utf-8').decodeToString(data);
        const rule = ruleFromJson(parseJson(text));
        if (rule.id.length === 0) {
          continue;
        }
        this.rules.set(rule.id, rule);
        this.order.push(rule.id);
      } catch (error) {
        // 单个图源解析失败不影响其他源
      }
    }
  }

  all(): SourceRule[] {
    const result: SourceRule[] = [];
    for (let i = 0; i < this.order.length; i++) {
      const rule = this.rules.get(this.order[i]);
      if (rule !== undefined) {
        result.push(rule);
      }
    }
    return result;
  }

  enabled(): SourceRule[] {
    const result: SourceRule[] = [];
    for (let i = 0; i < this.order.length; i++) {
      const id = this.order[i];
      if (this.disabled.has(id)) {
        continue;
      }
      const rule = this.rules.get(id);
      if (rule !== undefined) {
        result.push(rule);
      }
    }
    return result;
  }

  find(id: string): SourceRule | null {
    const rule = this.rules.get(id);
    return rule === undefined ? null : rule;
  }

  isEnabled(id: string): boolean {
    return this.rules.has(id) && !this.disabled.has(id);
  }

  async setEnabled(id: string, value: boolean): Promise<void> {
    // 忽略未知 ID，避免无效偏好污染当前源选择。
    if (!this.rules.has(id)) {
      return;
    }
    if (value) {
      this.disabled.delete(id);
    } else {
      this.disabled.add(id);
    }
    // 禁用当前源时同步回退到首个启用源；全部禁用时保存空值。
    this.currentId = this.currentSourceId();
    await this.flush();
  }

  private async flush(): Promise<void> {
    if (this.store === null) {
      return;
    }
    const ids: string[] = [];
    this.disabled.forEach((value: string) => {
      ids.push(value);
    });
    try {
      await this.store.put(KEY_DISABLED, ids.join(','));
      await this.store.put(KEY_CURRENT, this.currentId);
      await this.store.flush();
    } catch (error) {
      // 写入失败只影响下次启动的启用状态，不抛给 UI
    }
  }

  currentSourceId(): string {
    if (this.currentId.length > 0 && this.isEnabled(this.currentId)) {
      return this.currentId;
    }
    const list = this.enabled();
    return list.length > 0 ? list[0].id : '';
  }

  async setCurrent(id: string): Promise<void> {
    // 当前源必须来自已启用的注册规则，不能绕过禁用状态。
    if (!this.isEnabled(id)) {
      return;
    }
    this.currentId = id;
    if (this.store === null) {
      return;
    }
    try {
      await this.store.put(KEY_CURRENT, id);
      await this.store.flush();
    } catch (error) {
      // 忽略
    }
  }

  count(): number {
    return this.order.length;
  }
}
