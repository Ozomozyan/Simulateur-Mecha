param(
  [switch]$ResetVolumes,
  [int]$TelemetryBackfillHours = 48
)

$ErrorActionPreference = "Stop"

# ---------------------------
# Helpers
# ---------------------------
function Wait-ForPostgres {
  Write-Host "Waiting for Postgres..."
  for ($i=0; $i -lt 45; $i++) {
    docker compose exec -T postgres pg_isready -U mecha -d mecha 1>$null 2>$null
    if ($LASTEXITCODE -eq 0) { return }
    Start-Sleep -Seconds 1
  }
  throw "Postgres not ready"
}

function Wait-ForInflux {
  Write-Host "Waiting for InfluxDB..."
  for ($i=0; $i -lt 45; $i++) {
    docker compose exec -T influxdb influx ping 1>$null 2>$null
    if ($LASTEXITCODE -eq 0) { return }
    Start-Sleep -Seconds 1
  }
  throw "InfluxDB not ready"
}

function Backfill-TelemetryMQTT([int]$hours) {
  Write-Host "Backfilling telemetry for last $hours hour(s) via MQTT -> Telegraf -> Influx..."

  $end   = [DateTimeOffset]::UtcNow
  $start = $end.AddHours(-$hours)

  # 6 machines (2 plants x 3 machines) - enough for plant grouping + energy charts
  $machines = @(
    @{plant="PLANT_FR_TLS"; line="LINE_FR_A_PM"; machine="CNC-01"; pkw=5.3; temp=32.1; vib=0.12; state=1},
    @{plant="PLANT_FR_TLS"; line="LINE_FR_A_PM"; machine="CNC-02"; pkw=5.0; temp=31.8; vib=0.10; state=1},
    @{plant="PLANT_FR_TLS"; line="LINE_FR_A_PM"; machine="QC-01";  pkw=1.2; temp=28.5; vib=0.05; state=1},
    @{plant="PLANT_ES_ZAZ"; line="LINE_ES_B_PM"; machine="CNC-01"; pkw=5.6; temp=33.0; vib=0.13; state=1},
    @{plant="PLANT_ES_ZAZ"; line="LINE_ES_B_PM"; machine="CNC-02"; pkw=5.8; temp=33.5; vib=0.16; state=1},
    @{plant="PLANT_ES_ZAZ"; line="LINE_ES_B_PM"; machine="QC-01";  pkw=1.3; temp=29.0; vib=0.06; state=1}
  )

  # Build line protocol with LF-only newlines (important!)
  $sb = New-Object System.Text.StringBuilder
  for ($t = $start; $t -le $end; $t = $t.AddMinutes(1)) {
    $ns = [int64]($t.ToUnixTimeSeconds()) * 1000000000

    foreach ($m in $machines) {
      # small deterministic jitter so graphs look alive (no random dependency)
      $minute = $t.Minute
      $j = (($minute % 5) - 2) * 0.02

      $pkw  = [Math]::Round(($m.pkw  + $j), 2)
      $temp = [Math]::Round(($m.temp + $j), 2)
      $vib  = [Math]::Round(($m.vib  + $j/10), 3)

      $line = "telemetry,plant=$($m.plant),line=$($m.line),machine=$($m.machine) temperature_c=$temp,vibration_rms=$vib,power_kw=$pkw,state=$($m.state)i $ns"
      [void]$sb.Append($line).Append("`n")
    }
  }

  $lpPath = Join-Path $PSScriptRoot "telemetry_backfill.lp"
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($lpPath, $sb.ToString(), $utf8NoBom)

  # Publish all lines to ONE topic that matches telegraf subscription (mecha/+/+/+/telemetry)
  # Topic tags are not critical because we already tag plant/line/machine inside the line protocol.
  $cmd = "mosquitto_pub -h localhost -t mecha/seed/seed/seed/telemetry -l"

  Get-Content -Raw $lpPath | docker compose exec -T mosquitto sh -lc "$cmd" | Out-Host

  Remove-Item $lpPath -Force

  # Give Telegraf time to flush to Influx
  Start-Sleep -Seconds 6
}

# ---------------------------
# Main
# ---------------------------
if ($ResetVolumes) {
  docker compose down -v
}

docker compose up -d
Wait-ForPostgres
Wait-ForInflux

Write-Host "Loading demo events into Postgres (Phase 6.2)..."
Get-Content .\postgres\demo\02_generate_events.sql -Raw | docker compose exec -T postgres psql -U mecha -d mecha | Out-Host

Write-Host "Creating KPI views (Phase 7)..."
Get-Content .\postgres\kpi\03_kpi_views.sql -Raw | docker compose exec -T postgres psql -U mecha -d mecha | Out-Host

Backfill-TelemetryMQTT -hours $TelemetryBackfillHours

Write-Host "Smoke test Postgres:"
docker compose exec -T postgres psql -U mecha -d mecha -c "
SELECT 'production_events' AS t, COUNT(*) AS n FROM production_events
UNION ALL SELECT 'downtime_events', COUNT(*) FROM downtime_events
UNION ALL SELECT 'maintenance_events', COUNT(*) FROM maintenance_events;
SELECT * FROM kpi_plant_daily ORDER BY day, plant_code;" | Out-Host

Write-Host "Smoke test Influx (should return rows):"
$flux = @'
from(bucket:"telemetry")
  |> range(start: -6h)
  |> filter(fn:(r)=> r._measurement == "telemetry" and r._field == "power_kw")
  |> limit(n: 5)
'@
$flux | docker compose exec -T influxdb influx query --org mecha --token mecha-super-token - | Out-Host

Write-Host "Done. Grafana: http://localhost:3000"