# GUI background-job watchdog, started by hsp_gui_start_job (hsp_gui.pro).
# Ends the background worker (and its child processes) when the GUI process that started it exits,
# e.g. when the GUI is ended from Task Manager. Exits as soon as the worker finishes.
# Process objects hold handles, so a reused PID can never make it kill an unrelated process.
param([Parameter(Mandatory = $true)][int]$WorkerPid)
try {
  $worker = Get-Process -Id $WorkerPid -ErrorAction Stop
  $guiPid = (Get-CimInstance Win32_Process -Filter "ProcessId = $WorkerPid").ParentProcessId
  $gui = Get-Process -Id $guiPid -ErrorAction Stop
} catch { exit 0 }
while (-not $worker.HasExited) {
  if ($gui.HasExited) {
    & taskkill.exe /pid $WorkerPid /t /f | Out-Null
    break
  }
  Start-Sleep -Seconds 1
}
