#!/usr/bin/env bash
# 把 App 里的 ArkTS 引擎源码同步成 Node 能直接跑的 .ts 副本。
#
# 为什么需要：Engine/Selector 是纯逻辑，可以脱离鸿蒙在 Node 上做回归
# （node --experimental-transform-types xxx.ts）。但 app 里是 .ets、且
# Engine 引了 @kit.* 这类只有设备上才有的模块，所以这里做两件事：
#   1) 把相对 import 补上 .ts 后缀；
#   2) 把 @kit.* 换成本地 kitshim.ts 的桩实现。
# 手改 tools/engine-test/*.ts 会被这个脚本覆盖，要改就改 app 里的 .ets。
set -euo pipefail

ROOT="F:/AI/QoderCN-Data/output/harmony-comic-origin"
OUT="$ROOT/tools/engine-test"

copy() {
  local src="$1"
  local dst="$2"
  sed -E \
    -e "s#from '\.\./(parse|util|model|rule)/([A-Za-z]+)'#from './\2.ts'#g" \
    -e "s#from '\./([A-Za-z]+)'#from './\1.ts'#g" \
    -e "s#from '@kit\.[A-Za-z]+'#from './kitshim.ts'#g" \
    "$src" > "$dst"
}

copy "$ROOT/app/entry/src/main/ets/parse/Html.ets"     "$OUT/Html.ts"
copy "$ROOT/app/entry/src/main/ets/parse/Selector.ets" "$OUT/Selector.ts"
copy "$ROOT/app/entry/src/main/ets/parse/Json.ets"     "$OUT/Json.ts"
copy "$ROOT/app/entry/src/main/ets/util/Text.ets"      "$OUT/Text.ts"
copy "$ROOT/app/entry/src/main/ets/model/Models.ets"   "$OUT/Models.ts"
copy "$ROOT/app/entry/src/main/ets/rule/Rules.ets"     "$OUT/Rules.ts"
copy "$ROOT/app/entry/src/main/ets/rule/Engine.ets"    "$OUT/Engine.ts"

echo "引擎副本已同步 -> $OUT"
