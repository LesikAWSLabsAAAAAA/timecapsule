"""Render the CloudWatch API's one-minute maximum datapoints from CSV."""
import csv
from pathlib import Path

import matplotlib.pyplot as plt

root = Path(__file__).resolve().parent
with (root / "07-mail-metrics.csv").open(newline="", encoding="utf-8") as f:
    rows = list(csv.DictReader(f))

fig, ax = plt.subplots(figsize=(10, 4))
ax.step([r["minute_utc"] for r in rows], [int(r["mail_in_flight"]) for r in rows],
        where="mid", marker="o", label="Mail: не видны (в обработке)")
ax.step([r["minute_utc"] for r in rows], [int(r["dlq_visible"]) for r in rows],
        where="mid", marker="o", label="DLQ: видимые сообщения")
ax.set(title="CloudWatch SQS · сбой mailer · 26.11.2026",
       xlabel="Время, UTC", ylabel="Максимум за минуту")
ax.set_yticks([0, 1, 2])
ax.grid(alpha=0.25)
ax.legend()
fig.tight_layout()
fig.savefig(root / "07-mail-metrics.png", dpi=160)
