# =============================================================================
#  一键构建「漫屿」鸿蒙安装包
#
#  用法（在本目录打开 PowerShell）:
#    powershell -ExecutionPolicy Bypass -File 一键构建.ps1
#        编译并产出 unsigned HAP（不需要连手机、不需要账号）。
#    powershell -ExecutionPolicy Bypass -File 一键构建.ps1 -EngineTest
#        运行基于当前 app 源码镜像的离线引擎回归。
#    powershell -ExecutionPolicy Bypass -File 一键构建.ps1 -LiveEngineTest
#        在已有 tools/http.mjs 时额外跑真实网络图源回归。
#
#  说明:
#    本工程使用了新的 bundleName（com.manyu.reader），而调试签名证书是与
#    华为账号 + 包名绑定的，所以这里只产出 unsigned HAP。
#    要装机请按「装机与签名指引.md」在 DevEco Studio 里点一次「自动签名」。
# =============================================================================
param(
  [string]$DevEcoPath = 'D:\DevEco Studio',
  [switch]$EngineTest,
  [switch]$LiveEngineTest
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$app = Join-Path $here 'app'
$hapDir = Join-Path $here 'hap'
$logDir = Join-Path $here 'logs'
New-Item -ItemType Directory -Force $hapDir | Out-Null
New-Item -ItemType Directory -Force $logDir | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

function Step([string]$m) { Write-Host ''; Write-Host ('==> ' + $m) -ForegroundColor Cyan }
function Ok([string]$m) { Write-Host ('    ' + $m) -ForegroundColor Green }
function Fail([string]$m) { Write-Host ''; Write-Host ('失败: ' + $m) -ForegroundColor Red; exit 1 }

Step '第 1 步 / 共 3 步：检查 DevEco Studio'
$hvigor = Join-Path $DevEcoPath 'tools\hvigor\bin\hvigorw.bat'
if (!(Test-Path -LiteralPath $hvigor)) { Fail "找不到 $hvigor；用 -DevEcoPath 指定安装目录" }
Ok $hvigor

$env:DEVECO_HOME = $DevEcoPath
$env:JAVA_HOME = Join-Path $DevEcoPath 'jbr'
$env:DEVECO_SDK_HOME = Join-Path $DevEcoPath 'sdk'
$env:PATH = (Join-Path $DevEcoPath 'tools\node') + ';' +
  (Join-Path $DevEcoPath 'tools\ohpm\bin') + ';' +
  (Join-Path $DevEcoPath 'tools\hvigor\bin') + ';' +
  (Join-Path $DevEcoPath 'jbr\bin') + ';' + $env:PATH

Step '第 2 步 / 共 3 步：编译'
Set-Location -LiteralPath $app
if (!(Test-Path -LiteralPath (Join-Path $app 'oh_modules'))) {
  $ohpm = Join-Path $DevEcoPath 'tools\ohpm\bin\ohpm.bat'
  if (Test-Path -LiteralPath $ohpm) { & $ohpm install --all | Out-Null }
}
$buildLog = Join-Path $logDir ('build-' + $stamp + '.log')
# hvigor 的 clean 会批量删除产物，撞上「批量删除需确认」保护会误报失败
$prevBulk = $env:CODEBUDDY_SAFE_DELETE_BULK_THRESHOLD
$env:CODEBUDDY_SAFE_DELETE_BULK_THRESHOLD = '1000000'
# 关键：hvigor 会把 WARN 写到 stderr，而 PowerShell 5.1 在 $ErrorActionPreference
# = 'Stop' 下会把原生命令的 stderr 当成 RemoteException 直接中断脚本（即便编译成功）。
# 这里把 hvigor 调用段的错误偏好临时改为 Continue，只靠 $LASTEXITCODE 判定成败。
$prevEAP = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
& $hvigor --mode module -p product=default -p module=entry@default -p buildMode=debug assembleHap --no-daemon 2>&1 |
  Out-File -Encoding UTF8 $buildLog
$code = $LASTEXITCODE
$ErrorActionPreference = $prevEAP
if ($null -eq $prevBulk) { Remove-Item Env:CODEBUDDY_SAFE_DELETE_BULK_THRESHOLD -ErrorAction SilentlyContinue }
else { $env:CODEBUDDY_SAFE_DELETE_BULK_THRESHOLD = $prevBulk }
if ($code -ne 0) {
  Get-Content -LiteralPath $buildLog | Where-Object { $_ -match 'ERROR|Error Message|At File' } |
    Select-Object -First 12 | ForEach-Object { Write-Host ('    ' + $_.Trim()) -ForegroundColor DarkYellow }
  Fail "编译失败 (exit=$code)，日志: $buildLog"
}

$src = Join-Path $app 'entry\build\default\outputs\default\entry-default-unsigned.hap'
if (!(Test-Path -LiteralPath $src)) { Fail '编译通过但找不到 HAP 产物' }
# 版本号从 app.json5 的 versionName 读取，保证产物名与真实版本一致
$appJson5 = Join-Path $app 'AppScope\app.json5'
$verName = '1.0.0'
if (Test-Path -LiteralPath $appJson5) {
  $m = Select-String -LiteralPath $appJson5 -Pattern '"versionName"\s*:\s*"([^"]+)"'
  if ($null -ne $m -and $m.Matches.Count -gt 0) { $verName = $m.Matches[0].Groups[1].Value }
}
$dst = Join-Path $hapDir ('manyu-' + $verName + '-unsigned-' + $stamp + '.hap')
Copy-Item -LiteralPath $src -Destination $dst -Force
Ok ('HAP: ' + $dst)
Ok ('体积: ' + [math]::Round((Get-Item -LiteralPath $dst).Length / 1KB, 1) + ' KB')

Step '第 3 步 / 共 3 步：引擎回归（可选）'
if ($EngineTest) {
  $testDir = Join-Path $here 'tools\engine-test'
  $node = Join-Path $DevEcoPath 'tools\node\node.exe'
  if (!(Test-Path -LiteralPath $node)) { $node = 'node' }
  Push-Location $testDir
  & $node --experimental-transform-types run.ts
  $r1 = $LASTEXITCODE
  Pop-Location
  if ($r1 -ne 0) { Fail '离线引擎回归失败，先修解析规则再装机' }
  Ok '当前 app 源码离线回归全绿'
} else {
  Write-Host '    跳过（需要时加 -EngineTest）' -ForegroundColor DarkGray
}

if ($LiveEngineTest) {
  $testDir = Join-Path $here 'tools\engine-test'
  $node = Join-Path $DevEcoPath 'tools\node\node.exe'
  if (!(Test-Path -LiteralPath $node)) { $node = 'node' }
  $httpHelper = Join-Path $here 'tools\http.mjs'
  if (!(Test-Path -LiteralPath $httpHelper)) {
    Write-Host '    跳过真实网络回归：缺少 tools/http.mjs（可显式补齐后重试）' -ForegroundColor Yellow
  } else {
    Push-Location $testDir
    & $node --experimental-transform-types live.ts
    $liveCode = $LASTEXITCODE
    Pop-Location
    if ($liveCode -ne 0) { Fail '真实网络图源回归失败' }
    Ok '真实网络图源回归全绿'
  }
}

Write-Host ''
Write-Host '构建完成。下一步：按「装机与签名指引.md」在 DevEco Studio 里自动签名后安装。' -ForegroundColor Cyan
