#!/usr/bin/env bash
set -euo pipefail
IFS=':' read -ra steps <<< "${STEPS}"
total=${#steps[@]}

chvt 2

for i in "${!steps[@]}"; do
    step="${steps[$i]}"
    current=$((i + 1))
    clear
    width=$(tput cols)
    divider=$(printf '─%.0s' $(seq 1 $width))
    # White on blue for header
    tput setaf 7; tput setab 4
    tput cup 0 0
    printf "%-${width}s" "$divider"
    printf "%-${width}s" " $current/$total: $step"
    printf "%-${width}s" "$divider"
    # Black on light grey for scroll area
    tput setaf 0
    tput setab 7
    # Clear rest of screen with new colors
    tput ed
    # Set scrolling region from line 4 to bottom
    tput csr 3 $(tput lines)
    # Move cursor to scroll region
    tput cup 3 0
    "$step" 2>&1
    # Reset scroll region and colors
    tput csr 0 $(tput lines)
    tput sgr0
    tput cup $(tput lines) 0
done
tput sgr0

chvt 1

systemctl poweroff --no-block --force
