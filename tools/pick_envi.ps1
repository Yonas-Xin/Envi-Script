# 未自动找到 ENVI 时由 tools\find_idl.bat 调用：弹出文件夹选择框，让用户选择 ENVI 安装目录，
# 校验其中有 idlrt.exe 与 taskengine.exe 后把目录写入 tools\idl_path.txt（ANSI 编码，供批处理读取）。
# 用法：pick_envi.ps1 <idl_path.txt> [目录]   给出目录时只校验并写入，不弹窗。
# 退出码：0 已写入；1 用户取消或目录无效。
param([Parameter(Mandatory=$true)][string]$Out, [string]$Path)

function Find-IdlBin([string]$p) {
  if (-not $p -or -not (Test-Path -LiteralPath $p -PathType Container)) { return $null }
  $cands = @($p, (Join-Path $p 'bin\bin.x86_64'))
  $cands += @(Get-ChildItem -LiteralPath $p -Directory -Filter 'IDL*' -ErrorAction SilentlyContinue |
              ForEach-Object { Join-Path $_.FullName 'bin\bin.x86_64' })
  foreach ($c in $cands) {
    if ((Test-Path -LiteralPath (Join-Path $c 'idlrt.exe')) -and (Test-Path -LiteralPath (Join-Path $c 'taskengine.exe'))) {
      return (Resolve-Path -LiteralPath $c).Path
    }
  }
  return $null
}

function Save-Bin([string]$bin) {
  [IO.File]::WriteAllText($Out, $bin, [Text.Encoding]::Default)
}

if ($Path) {
  $bin = Find-IdlBin $Path
  if ($bin) { Save-Bin $bin; exit 0 } else { exit 1 }
}

Add-Type -AssemblyName System.Windows.Forms
$owner = New-Object System.Windows.Forms.Form -Property @{ TopMost = $true; ShowInTaskbar = $false }
while ($true) {
  $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
  $dlg.Description = "没有自动找到 ENVI。请选择 ENVI 的安装目录，例如 D:\Program Files\Harris\ENVI56（也可以选其中的 IDL88 目录）。"
  $dlg.ShowNewFolderButton = $false
  if ($dlg.ShowDialog($owner) -ne [System.Windows.Forms.DialogResult]::OK) { exit 1 }
  $bin = Find-IdlBin $dlg.SelectedPath
  if ($bin) { Save-Bin $bin; exit 0 }
  [System.Windows.Forms.MessageBox]::Show($owner,
    "所选目录中没有找到 idlrt.exe 和 taskengine.exe：`n$($dlg.SelectedPath)`n`n请选择 ENVI 的安装目录（其中有 IDLxx 子目录）。",
    "未找到 ENVI", 'OK', 'Warning') | Out-Null
}
