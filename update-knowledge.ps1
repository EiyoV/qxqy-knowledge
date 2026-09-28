# update-knowledge.ps1
# 千星奇域开发知识手册 自动更新检查器（完整包模式）
# 作用：对比上游版本（GitHub commit / npm version）与本地 knowledge-state.json，
#       有更新则下载【完整包】到 _upstream/<源名>/（含 README/AGENTS.md 与
#       API 定义文件 dist/src/definitions/*.d.ts），写标记并更新版本记录。
# 用法：双击运行（或 PowerShell 执行）。结果输出在窗口 / 可加日志。
$ErrorActionPreference = 'Stop'

$base = Split-Path -Parent $MyInvocation.MyCommand.Path
$stateFile = Join-Path $base 'knowledge-state.json'
$upstreamDir = Join-Path $base '_upstream'
$markFile = Join-Path $base 'handbook-update-needed.txt'
$log = Join-Path $base 'knowledge-update.log'

function Write-Log($msg) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
    Add-Content -LiteralPath $log -Value $line -Encoding UTF8
    Write-Host $msg
}

# 读取或初始化状态（统一转成 hashtable，支持新增/修改键）
$state = @{}
if (Test-Path $stateFile) {
    try {
        $raw = Get-Content $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($prop in $raw.PSObject.Properties) { $state[$prop.Name] = $prop.Value }
    } catch { $state = @{} }
}

$changed = @()
$anyUpdate = $false

# ---- 1. miliastra-toolbox（GitHub commit）----
try {
    $r = curl.exe -s --ssl-no-revoke -m 20 "https://api.github.com/repos/1475505/dsh-plugin-miliastra-toolbox/commits?per_page=1"
    $j = $r | ConvertFrom-Json
    $sha = $j[0].sha
    if ($state.'miliastra-plugin'.'sha' -ne $sha) {
        if ($null -ne $state.'miliastra-plugin'.'sha') {
            $anyUpdate = $true
            $changed += "miliastra-toolbox: $($state.'miliastra-plugin'.'sha') -> $sha"
        }
        $dest = Join-Path $upstreamDir 'miliastra-plugin'
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
        $files = @(
            @{ url = "https://raw.githubusercontent.com/1475505/dsh-plugin-miliastra-toolbox/master/skill.md"; name = "skill.md" },
            @{ url = "https://raw.githubusercontent.com/1475505/dsh-plugin-miliastra-toolbox/master/README.md"; name = "README.md" },
            @{ url = "https://raw.githubusercontent.com/1475505/Miliastra-toolbox/main/skills/miliastra-knowledge/references/tools.md"; name = "references-tools.md" }
        )
        foreach ($f in $files) {
            $c = curl.exe -s --ssl-no-revoke -m 30 $f.url
            if ($c -and $c.Length -gt 50) { [IO.File]::WriteAllText((Join-Path $dest $f.name), $c, (New-Object Text.UTF8Encoding $false)) }
        }
        $state.'miliastra-plugin' = @{ sha = $sha; checked = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') }
    }
} catch { Write-Log "miliastra-plugin check failed: $($_.Exception.Message)" }

# ---- 2. beyond-simulator（npm version + GitHub commit）----
try {
    $v = (& npm.cmd view dsh-plugin-beyond-simulator version --registry=https://registry.npmmirror.com 2>$null)
    if ($state.'beyond-simulator'.'npm' -ne $v) {
        if ($null -ne $state.'beyond-simulator'.'npm') {
            $anyUpdate = $true
            $changed += "beyond-simulator: npm $($state.'beyond-simulator'.'npm') -> $v"
        }
        $dest = Join-Path $upstreamDir 'beyond-simulator'
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
        $tmp = Join-Path $env:TEMP "beyond-pack"
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        & npm.cmd pack dsh-plugin-beyond-simulator@$v --pack-destination $tmp --registry=https://registry.npmmirror.com | Out-Null
        $tgz = Get-ChildItem $tmp -Filter "*.tgz" | Select-Object -First 1
        if ($tgz) { tar -xzf $tgz.FullName -C $dest; Remove-Item $tgz.FullName -Force }
        $state.'beyond-simulator' = @{ npm = $v; checked = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') }
    }
} catch { Write-Log "beyond-simulator check failed: $($_.Exception.Message)" }

# ---- 3. genshin-ts（npm version + GitHub AGENTS.md）----
try {
    $v2 = (& npm.cmd view genshin-ts version --registry=https://registry.npmmirror.com 2>$null)
    if ($state.'genshin-ts'.'npm' -ne $v2) {
        if ($null -ne $state.'genshin-ts'.'npm') {
            $anyUpdate = $true
            $changed += "genshin-ts: npm $($state.'genshin-ts'.'npm') -> $v2"
        }
        $dest = Join-Path $upstreamDir 'genshin-ts'
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
        $tmp = Join-Path $env:TEMP "gsts-pack"
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        & npm.cmd pack genshin-ts@$v2 --pack-destination $tmp --registry=https://registry.npmmirror.com | Out-Null
        $tgz2 = Get-ChildItem $tmp -Filter "*.tgz" | Select-Object -First 1
        if ($tgz2) { tar -xzf $tgz2.FullName -C $dest; Remove-Item $tgz2.FullName -Force }
        $state.'genshin-ts' = @{ npm = $v2; checked = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') }
    }
} catch { Write-Log "genshin-ts check failed: $($_.Exception.Message)" }

# 保存状态
[IO.File]::WriteAllText($stateFile, (ConvertTo-Json $state -Depth 5), (New-Object Text.UTF8Encoding $false))

if ($anyUpdate) {
    $mark = "知识上游已更新（{0}）：`n{1}`n`n请让 AI 读取 _upstream/ 下的最新快照，重新学习后更新《千星奇域开发知识手册》正文。" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), ($changed -join "`n")
    [IO.File]::WriteAllText($markFile, $mark, (New-Object Text.UTF8Encoding $false))
    Write-Log "发现更新: $($changed -join '; ')"
    Write-Host "`n[更新] 上游有新版本，快照已下载到 _upstream/，并写入 handbook-update-needed.txt"
    Write-Host "下次让豆包读手册时，它会先看 _upstream/ 学习新内容。"
} else {
    Write-Host "[OK] 所有知识源已是最新（miliastra 知识库为实时 API，无需检查）。"
    if (Test-Path $markFile) { Remove-Item $markFile -Force }
}
