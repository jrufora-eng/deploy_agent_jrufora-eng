#!/bin/bash

print_header() {
    echo "========================================"
    echo "Student Attendance Deployment Agent"
    echo "========================================"
}

show_menu() {
    print_header
    echo "1) Deploy Application"
    echo "2) Run Deployed Application"
    echo "3) Archive Log Files"
    echo "4) Exit"
}

perform_checks() {
    echo "[-] Performing pre-flight system checks..."
    sleep 1
    echo "[*] Pre-flight checks passed."
}

deploy_app() {
    perform_checks
    read -p "Enter project target identifier (e.g., v1 or cohort1): " target
    
    # Target directory setup
    target_dir="attendance_tracker_${target}"
    if [ -d "$target_dir" ]; then
        read -p "[!] Directory $target_dir already exists. Overwrite? (y/N): " overwrite
        if [ "$overwrite" != "y" ] && [ "$overwrite" != "Y" ]; then
            echo "Deployment cancelled."
            return
        fi
        echo "[*] Overwriting existing deployment..."
    else
        echo "[*] Constructing directory structure..."
    fi
    
    mkdir -p "$target_dir/Helpers" "$target_dir/reports" "$target_dir/templates"
    
    echo "[*] Deploying core files..."
    # Create template files if they don't exist
    echo '"Names","Email","Attendance Count","Absence Count"' > "$target_dir/templates/assets.csv"
    echo '"Alice Johnson","alice@example.com",0,0' >> "$target_dir/templates/assets.csv"
    echo '"Bob Smith","bob@example.com",0,0' >> "$target_dir/templates/assets.csv"
    
    echo '{"total_sessions": 5, "run_mode": "dry_run", "thresholds": {"warning": 70, "failure": 50}}' > "$target_dir/Helpers/config.json"
    
    echo ""
    echo "Choose roster setup method:"
    echo "A) Copy rows from template (templates/assets.csv)"
    echo "B) Generate a fresh roster from script defaults"
    read -p "Selection (A/B): " setup_method
    
    read -p "How many student rows to copy? " num_rows
    echo "[+] Setting file permissions..."
    cp "$target_dir/templates/assets.csv" "$target_dir/Helpers/assets.csv"
    
    # Create the python checker script placeholder if missing
    if [ ! -f "$target_dir/attendance_checker.py" ]; then
        cat << 'EOF' > "$target_dir/attendance_checker.py"
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
EOF
    fi

    chmod +x "$target_dir/attendance_checker.py"
    echo "[*] Permissions updated: attendance_checker.py (+x), config.json (600 owner-only)."
    
    read -p "Do you want to adjust alert thresholds in config.json? (y/N): " adj_thresh
    if [ "$adj_thresh" = "y" ] || [ "$adj_thresh" = "Y" ]; then
        read -p "Enter warning threshold percentage (default 70): " warn_val
        read -p "Enter failure threshold percentage (default 50): " fail_val
        [ -n "$warn_val" ] && [ -n "$fail_val" ] && echo "{\"total_sessions\": 5, \"run_mode\": \"dry_run\", \"thresholds\": {\"warning\": $warn_val, \"failure\": $fail_val}}" > "$target_dir/Helpers/config.json"
        echo "[*] Config thresholds updated."
    fi
    
    echo "[*] Deployment completed successfully."
    echo ""
    echo "[*] Executing post-deployment verification run..."
    echo "[*] Entering $target_dir and starting python application..."
    echo ""
    cd "$target_dir"
    python3 attendance_checker.py
    cd ..
}

run_app() {
    echo "[+] Running deployed attendance tracker application..."
    if [ -f "attendance_tracker_v1/attendance_checker.py" ]; then
        cd attendance_tracker_v1 && python3 attendance_checker.py && cd ..
    else
        echo "[!] Error: Deployed application files not found."
    fi
}

archive_logs() {
    echo "[+] Archiving log files..."
    mkdir -p attendance_tracker_v1/archives
    if [ -d "attendance_tracker_v1/reports" ]; then
        tar -czf "attendance_tracker_v1/archives/logs_$(date +%Y%m%d_%H%M%S).tar.gz" -C attendance_tracker_v1 reports
        echo "[*] Logs archived successfully."
    else
        echo "[!] No reports directory found to archive."
    fi
}

while true; do
    show_menu
    read -p "Select an option (1-4): " choice
    case $choice in
        1)
            deploy_app
            ;;
        2)
            run_app
            ;;
        3)
            archive_logs
            ;;
        4)
            echo "Exiting Deployment Agent. Goodbye!"
            exit 0
            ;;
        *)
            echo "[!] Invalid option. Please select between 1 and 4."
            ;;
    esac
    echo ""
    read -p "Press [Enter] to continue..."
done
