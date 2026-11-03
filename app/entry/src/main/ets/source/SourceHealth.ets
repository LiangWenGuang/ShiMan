/**
 * 图源请求健康度：只记录真实业务请求的结果，不主动探测全部图源。
 * 搜索无结果仍算请求成功，避免把“没有匹配”误显示成源故障。
 */
export class SourceHealthState {
  sourceId: string = '';
  ok: boolean = false;
  message: string = '';
  at: number = 0;
  /** 最近一次成功请求时间；失败记录不会覆盖，便于判断源是否曾经可用。 */
  lastSuccessAt: number = 0;
}

export class SourceHealth {
  private static states: Map<string, SourceHealthState> = new Map<string, SourceHealthState>();

  static record(sourceId: string, ok: boolean, message: string): void {
    if (sourceId.length === 0) return;
    const state = new SourceHealthState();
    const previous = SourceHealth.states.get(sourceId);
    state.sourceId = sourceId;
    state.ok = ok;
    state.message = message.length > 0 ? message : (ok ? '请求成功' : '请求失败');
    state.at = Date.now();
    state.lastSuccessAt = ok ? state.at : (previous === undefined ? 0 : previous.lastSuccessAt);
    SourceHealth.states.set(sourceId, state);
  }

  static get(sourceId: string): SourceHealthState | null {
    const state = SourceHealth.states.get(sourceId);
    return state === undefined ? null : state;
  }

  static all(): SourceHealthState[] {
    const result: SourceHealthState[] = [];
    SourceHealth.states.forEach((state: SourceHealthState) => result.push(state));
    return result;
  }
}
