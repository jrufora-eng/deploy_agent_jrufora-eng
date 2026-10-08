#!/usr/bin/env bash

CURRENT_TARGET_DIR=""

cleanup_on_interrupt() {
    echo -e "\n\n[!] Interruption signal caught! Deployment interrupted."
    
    if [ -n "$CURRENT_TARGET_DIR" ] && [ -d "$CURRENT_TARGET_DIR" ]; then
        ZIP_NAME="${CURRENT_TARGET_DIR}_archive.zip"
        echo "[*] Archiving incomplete setup to ${ZIP_NAME}..."
        
        zip -r "$ZIP_NAME" "$CURRENT_TARGET_DIR" >/dev/null 2>&1
        
        echo "[*] Cleaning up incomplete directory: ${CURRENT_TARGET_DIR}"
        rm -rf "$CURRENT_TARGET_DIR"
        
        echo "[✓] Incomplete state archived to ${ZIP_NAME} and working directory cleaned."
    fi
    
    exit 1
}

trap 'cleanup_on_interrupt' SIGINT SIGTSTP

run_preflight_checks() {
    echo "[*] Performing pre-flight system checks..."
    
    for cmd in python3 zip; do
        if ! command -v "$cmd" &> /dev/null; then
            echo "[X] Error: Required tool '$cmd' is not installed or not in PATH."
            exit 1
        fi
    done
    
    if [ ! -d "templates" ]; then
        echo "[X] Error: 'templates/' directory missing in current working path."
        exit 1
    fi
    
    echo "[✓] Pre-flight checks passed."
}

deploy_application() {
    run_preflight_checks

    echo -n "Enter project target identifier (e.g., v1 or cohort1): "
    read -r user_input
    
    if [ -z "$user_input" ]; then
        echo "[X] Input cannot be empty."
        return 1
    fi

    TARGET_DIR="attendance_tracker_${user_input}"
    CURRENT_TARGET_DIR="$TARGET_DIR"

    if [ -d "$TARGET_DIR" ]; then
        echo -n "[!] Directory $TARGET_DIR already exists. Overwrite? (y/N): "
        read -r choice
        case "$choice" in
            [yY][eE][sS]|[yY])
                echo "[*] Overwriting existing deployment..."
                rm -rf "$TARGET_DIR"
                ;;
            *)
                echo "[*] Deployment aborted by user."
                CURRENT_TARGET_DIR=""
                return 0
                ;;
        esac
    fi

    echo "[*] Constructing directory structure..."
    mkdir -p "$TARGET_DIR/Helpers"
    mkdir -p "$TARGET_DIR/reports"

    echo "[*] Deploying core files..."
    cp templates/attendance_checker.py "$TARGET_DIR/"
    cp templates/config.json "$TARGET_DIR/Helpers/"

    echo -e "\nChoose roster setup method:"
    echo "  A) Copy rows from template (templates/assets.csv)"
    echo "  B) Generate a fresh roster from script defaults"
    echo -n "Selection (A/B): "
    read -r roster_option

    case "$roster_option" in
        [aA])
            echo -n "How many student rows to copy? "
            read -r num_rows
            
            head -n 1 templates/assets.csv > "$TARGET_DIR/Helpers/assets.csv"
            tail -n +2 templates/assets.csv | head -n "$num_rows" >> "$TARGET_DIR/Helpers/assets.csv"
            
            sed -i 's/"total_sessions": [0-9]*/"total_sessions": 5/' "$TARGET_DIR/Helpers/config.json"
            ;;
        [bB])
            echo -n "How many fresh students to generate? "
            read -r num_students
            
            echo "Email,Names,Attendance Count,Absence Count" > "$TARGET_DIR/Helpers/assets.csv"
            
            names=("Alice_Smith" "Bob_Jones" "Charlie_Brown" "Diana_Prince" "Evan_Wright")
            
            for (( i=1; i<=num_students; i++ )); do
                idx=$(( (i - 1) % ${#names[@]} ))
                name="${names[$idx]}_$i"
                email="student${i}@example.com"
                echo "${email},${name},0,0" >> "$TARGET_DIR/Helpers/assets.csv"
            done
            
            sed -i 's/"total_sessions": [0-9]*/"total_sessions": 1/' "$TARGET_DIR/Helpers/config.json"
            ;;
        *)
            echo "[X] Invalid selection. Aborting deployment."
            rm -rf "$TARGET_DIR"
            CURRENT_TARGET_DIR=""
            return 1
            ;;
    esac

    echo "[*] Setting file permissions..."
    chmod +x "$TARGET_DIR/attendance_checker.py"
    chmod 600 "$TARGET_DIR/Helpers/config.json"
    echo "[✓] Permissions updated: attendance_checker.py (+x), config.json (600 owner-only)."

    echo -n "Do you want to adjust alert thresholds in config.json? (y/N): "
    read -r update_thresholds
    if [[ "$update_thresholds" =~ ^[yY]$ ]]; then
        echo -n "Enter warning threshold percentage (default 75): "
        read -r warn_val
        echo -n "Enter failure threshold percentage (default 50): "
        read -r fail_val

      [[ "$warn_val" =~ ^[0-9]+$ ]] || warn_val=75
        [[ "$fail_val" =~ ^[0-9]+$ ]] || fail_val=50

        sed -i "s/\"warning\": [0-9]*/\"warning\": $warn_val/" "$TARGET_DIR/Helpers/config.json"
        sed -i "s/\"failure\": [0-9]*/\"failure\": $fail_val/" "$TARGET_DIR/Helpers/config.json"
        echo "[✓] Config thresholds updated."
       
    fi

    CURRENT_TARGET_DIR=""
    echo "[✓] Deployment completed successfully."
    
    echo -e "\n[*] Executing post-deployment verification run..."
    run_application "$TARGET_DIR"
}

run_application() {
    TARGET_DIR="$1"
    if [ -z "$TARGET_DIR" ]; then
        echo -n "Enter deployed project directory name to run: "
        read -r TARGET_DIR
    fi

    if [ ! -d "$TARGET_DIR" ]; then
        echo "[X] Target directory '$TARGET_DIR' does not exist."
        return 1
    fi

    echo "[*] Entering $TARGET_DIR and starting python application..."
    (
        cd "$TARGET_DIR" || exit
        python3 attendance_checker.py
    )
}

archive_logs() {
    echo -n "Enter deployed project directory name to archive logs for: "
    read -r TARGET_DIR

    if [ ! -d "$TARGET_DIR" ]; then
        echo "[X] Directory '$TARGET_DIR' not found."
        return 1
    fi

    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    
    mkdir -p "$TARGET_DIR/archives/attendance"
    mkdir -p "$TARGET_DIR/archives/absent"

    LOG_FOUND=0

    if [ -f "$TARGET_DIR/reports/attendance.log" ]; then
        ARCH_NAME="attendance_${TIMESTAMP}.log"
        cp "$TARGET_DIR/reports/attendance.log" "$TARGET_DIR/archives/attendance/${ARCH_NAME}"
        echo "[✓] Archived attendance.log to archives/attendance/${ARCH_NAME}"
        LOG_FOUND=1
    else
        echo "[i] No attendance.log found in reports/ directory."
    fi

    if [ -f "$TARGET_DIR/reports/absent.log" ]; then
        ARCH_NAME="absent_${TIMESTAMP}.log"
        cp "$TARGET_DIR/reports/absent.log" "$TARGET_DIR/archives/absent/${ARCH_NAME}"
        echo "[✓] Archived absent.log to archives/absent/${ARCH_NAME}"
        LOG_FOUND=1
    else
        echo "[i] No absent.log found in reports/ directory."
    fi

    if [ $LOG_FOUND -eq 0 ]; then
        echo "[!] No logs were present to archive. Handled cleanly."
    fi
}

show_menu() {
    while true; do
        echo -e "\n=========================================="
        echo "   Student Attendance Deployment Agent    "
        echo "=========================================="
        echo "1) Deploy Application"
        echo "2) Run Deployed Application"
        echo "3) Archive Log Files"
        echo "4) Exit"
        echo -n "Select an option [1-4]: "
        read -r option

        case "$option" in
            1) deploy_application ;;
            2) run_application ;;
            3) archive_logs ;;
            4) echo "Exiting script."; exit 0 ;;
            *) echo "[X] Invalid selection. Try again." ;;
        esac
    done
}

show_menu
