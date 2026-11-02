/**
 * App 自身的版本信息。
 *
 * 界面上原来写死 `拾漫 1.0.2`，升版本时必然漏改（1.0.3 时就漏了）。
 * 这里从 bundle 信息里读真实的 versionName，和 app.json5 永远保持一致。
 */

import { bundleManager } from '@kit.AbilityKit';

/** 读一次就缓存，界面多处调用不用反复查系统 */
let cachedVersion: string = '';

export function appVersion(): string {
  if (cachedVersion.length > 0) {
    return cachedVersion;
  }
  try {
    const info = bundleManager.getBundleInfoForSelfSync(
      bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT
    );
    cachedVersion = info.versionName;
  } catch (error) {
    cachedVersion = '';
  }
  return cachedVersion;
}

/** 带产品名的版本标题，如「拾漫 1.0.4」；取不到版本就只显示产品名 */
export function appVersionLabel(): string {
  const version = appVersion();
  return version.length > 0 ? `拾漫 ${version}` : '拾漫';
}
