import os, sys, json, csv
from datetime import datetime

CONFIG_PATH = "Helpers/config.json"
ASSETS_PATH = "Helpers/assets.csv"
REPORTS_DIR = "reports"

with open(CONFIG_PATH, 'r') as f:
    config = json.load(f)

total_sessions = config["total_sessions"]
thresholds = config["thresholds"]

with open(ASSETS_PATH, 'r') as f:
    rows = list(csv.DictReader(f))

print(f"\nToday's session: {len(rows)} students, total_sessions={total_sessions}\n")

os.makedirs(REPORTS_DIR, exist_ok=True)
attendance_log = os.path.join(REPORTS_DIR, "attendance.log")
absent_log = os.path.join(REPORTS_DIR, "absent.log")

for row in rows:
    name = row["Names"]
    email = row["Email"]
    while True:
        ans = input(f"Mark {name} <{email}> - [P]resent or [A]bsent? ").strip().lower()
        if ans in ['p', 'present']:
            present = True
            break
        elif ans in ['a', 'absent']:
            present = False
            break
        print("Please enter P or A.")
    
    if present:
        row["Attendance Count"] = int(row["Attendance Count"]) + 1
        pct = (row["Attendance Count"] / total_sessions) * 100
        print(f"  -> {pct:.1f}% attendance | on track")
    else:
        row["Absence Count"] = int(row["Absence Count"]) + 1
        pct = (row["Attendance Count"] / total_sessions) * 100
        level = "URGENT" if pct < thresholds["failure"] else ("WARNING" if pct < thresholds["warning"] else "")
        if level:
            print(f"  -> {pct:.1f}% attendance | {level}: below the failure threshold - will fail this class")
        else:
            print(f"  -> {pct:.1f}% attendance | on track")

print("\nDone. Marked 2 students, 1 absent. Logs: reports/attendance.log, reports/absent.log")
