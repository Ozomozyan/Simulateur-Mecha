import time
from datetime import datetime, timedelta, timezone
import random
import paho.mqtt.client as mqtt

BROKER_HOST = "localhost"
BROKER_PORT = 1883

# PoC scope (from your docs)
MACHINES = [
    ("PLANT_FR_TLS", "LINE_FR_A_PM", "CNC-01"),
    ("PLANT_FR_TLS", "LINE_FR_A_PM", "CNC-02"),
    ("PLANT_FR_TLS", "LINE_FR_A_PM", "QC-01"),
    ("PLANT_ES_ZAZ", "LINE_ES_B_PM", "CNC-01"),
    ("PLANT_ES_ZAZ", "LINE_ES_B_PM", "CNC-02"),
    ("PLANT_ES_ZAZ", "LINE_ES_B_PM", "QC-01"),
]

def ns(dt: datetime) -> int:
    return int(dt.timestamp() * 1_000_000_000)

def clamp(x, lo, hi):
    return max(lo, min(hi, x))

def make_point(plant, line, machine, dt):
    # Base “healthy” signals
    temperature = 30.0 + random.uniform(-1.0, 1.0)
    vibration = 0.10 + random.uniform(-0.02, 0.02)
    power_kw = 5.0 + random.uniform(-0.5, 0.5)
    state = 1  # 1=RUN, 0=STOP, 2=IDLE (simple numeric)

    # Scenario hooks (you’ll enrich later):
    # - FR1/CNC-01: gradual drift signs (slightly higher vibration/heat)
    if plant == "PLANT_FR_TLS" and machine == "CNC-01":
        day_index = (dt.date() - START.date()).days
        drift = day_index / 7.0
        vibration += 0.05 * drift
        temperature += 2.0 * drift

    # - ES1/CNC-02: pre-failure spikes (vibration + power) at certain hours
    if plant == "PLANT_ES_ZAZ" and machine == "CNC-02" and dt.hour in (9, 15, 20):
        vibration += 0.20
        power_kw += 2.0

    temperature = clamp(temperature, 20, 90)
    vibration = clamp(vibration, 0.0, 5.0)
    power_kw = clamp(power_kw, 0.0, 50.0)

    # Influx line protocol
    measurement = "telemetry"
    tags = f"plant={plant},line={line},machine={machine}"
    fields = f"temperature_c={temperature:.2f},vibration_rms={vibration:.3f},power_kw={power_kw:.2f},state={state}i"
    return f"{measurement},{tags} {fields} {ns(dt)}"

if __name__ == "__main__":
    client = mqtt.Client()
    client.connect(BROKER_HOST, BROKER_PORT, 60)

    # Backfill: 7 days, 1 point/min/machine
    START = datetime.now(timezone.utc) - timedelta(days=7)
    END = datetime.now(timezone.utc)

    dt = START
    sent = 0

    while dt <= END:
        for plant, line, machine in MACHINES:
            topic = f"mecha/{plant}/{line}/{machine}/telemetry"
            payload = make_point(plant, line, machine, dt)
            client.publish(topic, payload, qos=0)
            sent += 1

        # 1 minute step in “simulated time”
        dt += timedelta(minutes=1)

        # tiny sleep so you don’t nuke your laptop
        if sent % 6000 == 0:
            time.sleep(0.2)

    client.disconnect()
    print(f"Done. Published {sent} telemetry points.")