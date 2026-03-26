param(
  [int]$DurationMinutes = 5,
  [int]$IntervalSeconds = 5
)

$ErrorActionPreference = "Stop"

$endTime = (Get-Date).ToUniversalTime().AddMinutes($DurationMinutes)

# Full capacity demo: 5 plants x 3 machines = 15 live streams
$machines = @(
  @{plant="PLANT_FR_TLS"; line="LINE_FR_A_PM"; machine="CNC-01"; basePkw=5.8; baseTemp=33.4; baseVib=0.145; state=1},
  @{plant="PLANT_FR_TLS"; line="LINE_FR_A_PM"; machine="CNC-02"; basePkw=5.0; baseTemp=31.8; baseVib=0.100; state=1},
  @{plant="PLANT_FR_TLS"; line="LINE_FR_A_PM"; machine="QC-01";  basePkw=1.2; baseTemp=28.5; baseVib=0.050; state=1},

  @{plant="PLANT_ES_ZAZ"; line="LINE_ES_B_PM"; machine="CNC-01"; basePkw=5.6; baseTemp=33.0; baseVib=0.130; state=1},
  @{plant="PLANT_ES_ZAZ"; line="LINE_ES_B_PM"; machine="CNC-02"; basePkw=6.3; baseTemp=34.2; baseVib=0.185; state=1},
  @{plant="PLANT_ES_ZAZ"; line="LINE_ES_B_PM"; machine="QC-01";  basePkw=1.3; baseTemp=29.0; baseVib=0.060; state=1},

  @{plant="PLANT_FR_LYO"; line="LINE_FR_C_PM"; machine="CNC-01"; basePkw=5.2; baseTemp=32.0; baseVib=0.110; state=1},
  @{plant="PLANT_FR_LYO"; line="LINE_FR_C_PM"; machine="CNC-02"; basePkw=5.1; baseTemp=31.7; baseVib=0.100; state=1},
  @{plant="PLANT_FR_LYO"; line="LINE_FR_C_PM"; machine="QC-01";  basePkw=1.2; baseTemp=28.4; baseVib=0.050; state=1},

  @{plant="PLANT_FR_LIL"; line="LINE_FR_D_PM"; machine="CNC-01"; basePkw=5.3; baseTemp=32.2; baseVib=0.110; state=1},
  @{plant="PLANT_FR_LIL"; line="LINE_FR_D_PM"; machine="CNC-02"; basePkw=5.1; baseTemp=31.9; baseVib=0.100; state=1},
  @{plant="PLANT_FR_LIL"; line="LINE_FR_D_PM"; machine="QC-01";  basePkw=1.2; baseTemp=28.6; baseVib=0.050; state=1},

  @{plant="PLANT_ES_VLC"; line="LINE_ES_E_PM"; machine="CNC-01"; basePkw=5.5; baseTemp=32.8; baseVib=0.120; state=1},
  @{plant="PLANT_ES_VLC"; line="LINE_ES_E_PM"; machine="CNC-02"; basePkw=5.7; baseTemp=33.3; baseVib=0.140; state=1},
  @{plant="PLANT_ES_VLC"; line="LINE_ES_E_PM"; machine="QC-01";  basePkw=1.3; baseTemp=28.9; baseVib=0.060; state=1}
)

Write-Host "Streaming FULL live telemetry for $DurationMinutes minute(s) across 5 plants / 15 machines..."

while ((Get-Date).ToUniversalTime() -lt $endTime) {
  $now = [DateTimeOffset]::UtcNow
  $ns  = [int64]($now.ToUnixTimeSeconds()) * 1000000000

  $sb = New-Object System.Text.StringBuilder

  foreach ($m in $machines) {
    $sec = $now.Second
    $min = $now.Minute
    $hour = $now.Hour

    # deterministic oscillation
    $wave1 = [Math]::Sin(($sec / 60.0) * 2.0 * [Math]::PI) * 0.08
    $wave2 = [Math]::Cos(($min / 60.0) * 2.0 * [Math]::PI) * 0.05
    $wave3 = [Math]::Sin(($hour / 24.0) * 2.0 * [Math]::PI) * 0.03

    $pkw  = $m.basePkw  + $wave1 + $wave2 + $wave3
    $temp = $m.baseTemp + ($wave1 * 1.5) + ($wave2 * 0.8) + ($wave3 * 0.5)
    $vib  = $m.baseVib  + ($wave1 / 10.0) + ($wave3 / 20.0)

    # Pilot anomaly 1: FR_TLS / CNC-01 gradual drift
    if ($m.plant -eq "PLANT_FR_TLS" -and $m.machine -eq "CNC-01") {
      $elapsedRatio = 1.0 - (($endTime - (Get-Date).ToUniversalTime()).TotalSeconds / ($DurationMinutes * 60.0))
      $temp += 0.8 * $elapsedRatio
      $vib  += 0.02 * $elapsedRatio
    }

    # Pilot anomaly 2: ES_ZAZ / CNC-02 recurring spikes
    if ($m.plant -eq "PLANT_ES_ZAZ" -and $m.machine -eq "CNC-02") {
      if (($sec -ge 20) -and ($sec -le 35)) {
        $pkw += 0.6
        $vib += 0.03
        $temp += 0.2
      }
    }

    # QC machines stay calmer
    if ($m.machine -eq "QC-01") {
      $pkw *= 0.95
      $temp *= 0.995
      $vib *= 0.90
    }

    $pkw  = [Math]::Round($pkw, 2)
    $temp = [Math]::Round($temp, 2)
    $vib  = [Math]::Round($vib, 3)

    $line = "telemetry,plant=$($m.plant),line=$($m.line),machine=$($m.machine) temperature_c=$temp,vibration_rms=$vib,power_kw=$pkw,state=$($m.state)i $ns"
    [void]$sb.Append($line).Append("`n")
  }

  $lpPath = Join-Path $PSScriptRoot "telemetry_live.lp"
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($lpPath, $sb.ToString(), $utf8NoBom)

  $cmd = "mosquitto_pub -h localhost -t mecha/live/live/live/telemetry -l"
  Get-Content -Raw $lpPath | docker compose exec -T mosquitto sh -lc "$cmd" | Out-Null

  Remove-Item $lpPath -Force

  Write-Host ("Sent live batch at " + $now.ToString("u"))
  Start-Sleep -Seconds $IntervalSeconds
}

Write-Host "Full live stream finished."