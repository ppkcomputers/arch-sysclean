#!/usr/bin/env bash

# Color codes for clean terminal output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}==================================================${NC}"
echo -e "${GREEN}             Arch System Maintenance & Cleanup    ${NC}"
echo -e "${BLUE}==================================================${NC}"

# Echo the commands being used block directly to the terminal
echo -e "${BLUE}=====================================================================${NC}"
echo -e "${YELLOW} Commands being used${NC}"
echo -e "${BLUE}=====================================================================${NC}"
echo -e " This script utilizes the following core system commands:"
echo -e "   - pacman -Qdtq                  : Scans for orphan dependencies"
echo -e "   - pacman -Rns <pkgs>            : Purges packages and their unneeded dependencies"
echo -e "   - pacman -Qq <pkg>              : Checks if a specific package is installed"
echo -e "   - systemctl list-timers --all  : Lists all active and inactive systemd timers"
echo -e "   - systemctl disable --now <srv> : Stops and disables a systemd service/timer immediately"
echo -e "   - systemctl daemon-reload       : Reloads the systemd manager configuration"
echo -e "   - du -sh <dir>                  : Checks disk usage of a directory in human-readable format"
echo -e "   - paccache -r                   : Trims cached packages to the current and previous versions"
echo -e "   - paccache -rk1                 : Removes cached files for uninstalled packages"
echo -e "   - journalctl --disk-usage       : Checks total disk space used by systemd journal logs"
echo -e "   - journalctl --vacuum-size=200M : Shrinks systemd journal logs down to 200MB"
echo -e "${BLUE}=====================================================================${NC}"

# Check for root privileges up front
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script needs to run with sudo to handle system maintenance.${NC}"
    exit 1
fi

# Get the actual user behind sudo for home directory cleanups
REAL_USER=${SUDO_USER:-$USER}
REAL_HOME=$(eval echo "~$REAL_USER")

# Capture starting disk space (Available space on root '/' in 1024-byte blocks)
START_SPACE=$(df / | awk 'NR==2 {print $4}')

# ---------------------------------------------------------------------
# 1. ORPHANS SECTION
# ---------------------------------------------------------------------
echo -e "\n${YELLOW}[1/6] Scanning for Orphan Packages (-Qdt)...${NC}"
ORPHANS=$(pacman -Qdtq)

if [ -n "$ORPHANS" ]; then
    echo -e "${BLUE}Found unneeded dependencies / debug symbols:${NC}"
    echo "$ORPHANS" | sed 's/^/  - /'
    echo -e "\n${YELLOW}Description & What Happens Next:${NC}"
    echo -e "  These are packages that were originally installed automatically as dependencies"
    echo -e "  for other applications, but the main applications have since been uninstalled."
    echo -e "  If you choose YES (y): The command 'pacman -Rns' will run. This will completely"
    echo -e "  purge these packages along with any of THEIR unneeded sub-dependencies and global"
    echo -e "  configuration files. It is highly recommended and safe to remove them."
    echo -e "  If you choose NO (n): They will remain on your system taking up disk space."

    read -p "Would you like to purge these orphans? (y/N): " choice
    if [[ "$choice" =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}Removing orphans...${NC}"
        pacman -Rns $ORPHANS
    else
        echo -e "Skipping orphan removal."
    fi
else
    echo -e "${GREEN}No orphan packages found.${NC}"
fi

# ---------------------------------------------------------------------
# 2. TARGETED EXPLICIT PACKAGES
# ---------------------------------------------------------------------
echo -e "\n${YELLOW}[2/6] Checking for specific redundant software blocks...${NC}"

# Function to safely check and offer package block removal
check_and_remove_block() {
    local block_name="$1"
    local description="$2"
    shift 2
    local pkgs_to_check=("$@")
    local found_pkgs=()

    for pkg in "${pkgs_to_check[@]}"; do
        if pacman -Qq "$pkg" &>/dev/null; then
            found_pkgs+=("$pkg")
        fi
    done

    if [ ${#found_pkgs[@]} -gt 0 ]; then
        echo -e "\n${BLUE}Found ${block_name} Packages:${NC}"
        for p in "${found_pkgs[@]}"; do echo "  - $p"; done
        echo -e "${YELLOW}Description & What Happens Next:${NC}"

        # Print the description (handling multi-line layout nicely)
        echo -e "${description}"

        echo -e "  If you choose YES (y): The command 'pacman -Rns' will explicitly strip out"
        echo -e "  this pre-defined structural group of applications, freeing up system storage."
        echo -e "  If you choose NO (n): This software block will remain completely untouched."

        read -p "Remove this entire block? (y/N): " choice
        if [[ "$choice" =~ ^[Yy]$ ]]; then
            echo -e "${GREEN}Removing ${block_name} stack...${NC}"
            pacman -Rns "${found_pkgs[@]}"
        else
            echo -e "Keeping ${block_name} stack."
        fi
    fi
}

# Scan individual structural blocks
check_and_remove_block "Remote Desktop / VM Integration" \
    "  Provides XRDP server environments and Hyper-V guest interactions. Safe to remove if you don't remote into this desktop via RDP." \
    xrdp xorgxrdp pipewire-module-xrdp-git hyperv

check_and_remove_block "Leftover Development Tools" \
    "  Compilers and modules (like LDC/D-lang and extra CMake extensions) that are typically only needed for custom builds." \
    ldc gtkd extra-cmake-modules

check_and_remove_block "Redundant Mirroring Utilities" \
    "  Standard Arch Reflector setup. Safe to drop since you use cachyos-rate-mirrors." \
    reflector

# Dynamic Network & Sharing breakdown
NETWORK_TARGETS=(samba gvfs-smb gvfs-dnssd arp-scan tcpdump wireshark-cli nmap)
FOUND_NET=()

for pkg in "${NETWORK_TARGETS[@]}"; do
    if pacman -Qq "$pkg" &>/dev/null; then
        FOUND_NET+=("$pkg")
    fi
done

if [ ${#FOUND_NET[@]} -gt 0 ]; then
    echo -e "\n${BLUE}Found Network & Sharing Services Packages:${NC}"
    for p in "${FOUND_NET[@]}"; do
        # Dynamically query local descriptions and trim extra formatting spaces
        PKG_DESC=$(pacman -Qi "$p" 2>/dev/null | grep -E "^Description" | cut -d':' -f2- | xargs)
        echo -e "  - ${GREEN}$p${NC} : $PKG_DESC"
    done

    echo -e "${YELLOW}Description & What Happens Next:${NC}"
    echo -e "  This block handles local network discovery, file sharing, and analysis toolsets."
    echo -e "  If you choose YES (y): The command 'pacman -Rns' will explicitly strip out"
    echo -e "  this pre-defined structural group of applications, freeing up system storage."
    echo -e "  If you choose NO (n): This software block will remain completely untouched."

    read -p "Remove this entire block? (y/N): " choice
    if [[ "$choice" =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}Removing Network & Sharing Services stack...${NC}"
        pacman -Rns "${FOUND_NET[@]}"
    else
        echo -e "Keeping Network & Sharing Services stack."
    fi
fi

# ---------------------------------------------------------------------
# 3. DANGLING SYSTEMD TIMERS
# ---------------------------------------------------------------------
echo -e "\n${YELLOW}[3/6] Auditing Dead Systemd Timers...${NC}"
if systemctl list-timers --all | grep -q "reflector.timer"; then
    echo -e "${BLUE}Found lingering reflector.timer (package was previously removed).${NC}"
    echo -e "\n${YELLOW}Description & What Happens Next:${NC}"
    echo -e "  The main package was uninstalled, but its systemd automation timer is still checking"
    echo -e "  in the background, triggering useless system log failures."
    echo -e "  If you choose YES (y): The command 'systemctl disable --now' will freeze and stop"
    echo -e "  the timer instantly, and prevent it from ever starting up on future system boots."
    echo -e "  If you choose NO (n): The dead timer remains loaded in the system background."

    read -p "Disable and stop this dead timer? (y/N): " choice
    if [[ "$choice" =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}Disabling reflector.timer...${NC}"
        systemctl disable --now reflector.timer
        systemctl daemon-reload
    fi
else
    echo -e "${GREEN}No dangling reflector timers active.${NC}"
fi

# ---------------------------------------------------------------------
# 4. PACMAN PACKAGES CACHE
# ---------------------------------------------------------------------
echo -e "\n${YELLOW}[4/6] Optimizing Pacman Package Cache...${NC}"
if command -v paccache &>/dev/null; then
    CURRENT_CACHE=$(du -sh /var/cache/pacman/pkg/ | cut -f1)
    echo -e "${BLUE}Current Pacman Cache Size:${NC} $CURRENT_CACHE"
    echo -e "\n${YELLOW}Description & What Happens Next:${NC}"
    echo -e "  Arch preserves download archives of all installed software in case you need an emergency rollback."
    echo -e "  If you choose YES (y): The script runs 'paccache -r' and 'paccache -rk1'. This safely trims"
    echo -e "  the cache down to only the current version and one previous version for active software,"
    echo -e "  while completely purging old install files for apps you have fully uninstalled."
    echo -e "  If you choose NO (n): Your package storage cache remains completely un-optimized."

    read -p "Trim cache down to last 2 versions? (y/N): " choice
    if [[ "$choice" =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}Running paccache...${NC}"
        paccache -r
        echo -e "${GREEN}Removing cached files for uninstalled packages...${NC}"
        paccache -rk1
    fi
else
    echo -e "${RED}paccache utility (pacman-contrib) not found. Skipping.${NC}"
fi

# ---------------------------------------------------------------------
# 5. SYSTEMD JOURNAL VACUUMING
# ---------------------------------------------------------------------
echo -e "\n${YELLOW}[5/6] Checking Systemd Journal Log Size...${NC}"
CURRENT_LOGS=$(journalctl --disk-usage | awk '{print $NF}')
echo -e "${BLUE}Current System Logs Size:${NC} $CURRENT_LOGS"
echo -e "\n${YELLOW}Description & What Happens Next:${NC}"
echo -e "  Systemd constantly logs kernel operations and errors, growing relentlessly over months of uptime."
echo -e "  If you choose YES (y): The command 'journalctl --vacuum-size=200M' will aggressively shrink"
echo -e "  historical system logs down to a lightweight 200MB maximum ceiling, freeing up active root space."
echo -e "  If you choose NO (n): All old boots and system debug logs will remain stored on your drive."

read -p "Vacuum logs down to a max of 200MB? (y/N): " choice
if [[ "$choice" =~ ^[Yy]$ ]]; then
    echo -e "${GREEN}Vacuuming logs...${NC}"
    journalctl --vacuum-size=200M
fi

# ---------------------------------------------------------------------
# 6. CONFIG LEFT-OVERS ENCOURAGEMENT
# ---------------------------------------------------------------------
echo -e "\n${YELLOW}[6/6] Local Configuration Cleanups${NC}"
echo -e "System-level purging complete! Keep an eye on your local user home directories."
echo -e "You can manually audit and drop orphaned app files here if they exist:"
echo -e "  - ${BLUE}$REAL_HOME/.config/${NC}"
echo -e "  - ${BLUE}$REAL_HOME/.cache/${NC}"

# Calculate ending space and total spared disk storage
END_SPACE=$(df / | awk 'NR==2 {print $4}')
SPARED_KB=$((END_SPACE - START_SPACE))

echo -e "\n${GREEN}==================================================${NC}"
echo -e "${GREEN}         Maintenance Script Executed Successfully  ${NC}"

# Display spared disk space summary at the bottom
if [ "$SPARED_KB" -gt 0 ]; then
    # Format the calculated output into human-readable MB or GB metrics
    if [ "$SPARED_KB" -ge 1048576 ]; then
        SPARED_HUMAN=$(awk "BEGIN {printf \"%.2f GB\", $SPARED_KB/1048576}")
    else
        SPARED_HUMAN=$(awk "BEGIN {printf \"%.2f MB\", $SPARED_KB/1024}")
    fi
    echo -e "${YELLOW}         Total Disk Space Recovered: $SPARED_HUMAN${NC}"
else
    echo -e "${GREEN}         No disk space was modified during this run.${NC}"
fi

echo -e "${GREEN}==================================================${NC}\n"
