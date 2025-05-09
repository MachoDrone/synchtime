#!/bin/bash

# Script to check, compare, and sync system time (WSL2 and native Ubuntu)
# Shows before/after results and gives WSL2-specific instructions if time is off.

# Function to display current time settings
show_time_settings() {
    echo -e "\n=== Current Time Settings ==="
    timedatectl | grep --color=never -E "Local time|Universal time|RTC time|Time zone|System clock synchronized|NTP service|RTC in local TZ"
    if [ "$is_wsl2" = "yes" ]; then
        echo -e "\n[WSL2 Note] RTC time is emulated from the Windows host clock."
    fi
}

# Function to detect OS and environment
detect_os() {
    if grep -qi "microsoft" /proc/version; then
        is_wsl2="yes"
        os_env="WSL2"
    else
        is_wsl2="no"
        os_env="Native Ubuntu"
    fi
    . /etc/os-release
    echo -e "\n=== OS Detection ==="
    echo "OS: $PRETTY_NAME"
    echo "Environment: $os_env"
}

# Function to compare system time with external source
compare_time() {
    echo -e "\n=== Time Comparison ==="
    system_time_utc=$(date -u +"%Y-%m-%d %H:%M:%S")
    echo "System UTC Time: $system_time_utc"

    if [ "$is_wsl2" = "yes" ]; then
        # Use WorldTimeAPI for WSL2 (NTP may not work)
        echo "Fetching reference time from WorldTimeAPI..."
        api_time=$(curl -s http://worldtimeapi.org/api/timezone/Etc/UTC | grep -oP '"datetime":".+?"' | cut -d'"' -f4 | cut -d'.' -f1)
        if [ -z "$api_time" ]; then
            echo "Error: Failed to fetch time from WorldTimeAPI. Check internet connection."
            return 1
        fi
        echo "Reference UTC Time (API): $api_time"
        # Calculate difference (seconds)
        diff_seconds=$(( $(date -d "$system_time_utc" +%s) - $(date -d "$api_time" +%s) ))
    else
        # Use chrony or ntpdate for native Ubuntu
        if command -v chronyc >/dev/null; then
            echo "Checking NTP sync via chrony..."
            chrony_output=$(chronyc tracking)
            if echo "$chrony_output" | grep -q "Not synchronised"; then
                echo "Error: chrony is not synchronized."
                return 1
            fi
            ref_time=$(echo "$chrony_offset" | grep "Ref time (UTC)" | awk '{print $4, $5, $6, $7, $8}')
            offset=$(echo "$chrony_offset" | grep "System time" | awk '{print $4}')
            echo "Reference UTC Time (NTP): $ref_time"
            echo "Chrony Offset: $offset seconds"
            diff_seconds=$(echo "$offset" | awk '{printf "%.0f", $1}')
        else
            echo "Checking NTP sync via ntpdate..."
            ntp_output=$(sudo ntpdate -q pool.ntp.org 2>&1)
            if echo "$ntp_output" | grep -q "no server suitable"; then
                echo "Error: NTP server unreachable."
                return 1
            fi
            offset=$(echo "$ntp_output" | grep "offset" | awk '{print $8}' | head -1)
            echo "NTP Offset: $offset seconds"
            diff_seconds=$(echo "$offset" | awk '{printf "%.0f", $1}')
        fi
    fi

    # Evaluate difference
    if [ ${diff_seconds#-} -gt 5 ]; then
        echo "WARNING: Time difference is significant: $diff_seconds seconds."
        return 1
    else
        echo "Time is in sync (difference: $diff_seconds seconds)."
        return 0
    fi
}

# Function to sync time (WSL2 or native)
sync_time() {
    echo -e "\n=== Attempting Time Sync ==="
    if [ "$is_wsl2" = "yes" ]; then
        echo "WSL2 detected: Time is controlled by the Windows host."
        echo "To sync the Windows host clock:"
        echo "  1. Open Windows Command Prompt as Administrator."
        echo "  2. Run: w32tm /resync"
        echo "  3. Restart WSL2 if needed: 'wsl --shutdown' in PowerShell."
        echo "Note: WSL2 will inherit the corrected time automatically."
        return 1  # Script can't directly fix WSL2 time
    else
        echo "Syncing via chrony or ntpdate..."
        if command -v chronyc >/dev/null; then
            sudo chronyc makestep && echo "Success: chrony sync forced."
        else
            sudo ntpdate pool.ntp.org && echo "Success: ntpdate sync completed."
        fi
    fi
}

# Main script
echo -e "\n=== Time Sync Script (WSL2 & Ubuntu) ==="
detect_os
show_time_settings  # Show settings BEFORE sync

# Compare time and sync if needed
if ! compare_time; then
    echo -e "\n[ACTION NEEDED] Time is out of sync!"
    sync_time
    echo -e "\n=== Verifying Changes ==="
    show_time_settings  # Show settings AFTER sync
    compare_time || echo "Warning: Time may still be incorrect. Follow instructions above."
else
    echo -e "\nNo sync needed. Time is accurate."
fi

echo -e "\n=== Script Finished ==="
