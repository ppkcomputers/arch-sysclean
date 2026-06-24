#!/usr/bin/env bash

# Color codes for clean terminal output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}==================================================${NC}"
echo -e "${GREEN}      SecretArch System Maintenance & Cleanup     ${NC}"
echo -e "${BLUE}==================================================${NC}"

# Check for root privileges up front
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script needs to run with sudo to handle system maintenance.${NC}"
    exit 1
fi

# Get the actual user behind sudo for home directory cleanups
REAL_USER=${SUDO_USER:-$USER}
REAL_HOME=$(eval echo "~$REAL_USER")

# ---------------------------------------------------------------------
# 1. ORPHANS SECTION
# ---------------------------------------------------------------------
echo -e "\n${YELLOW}[1/6] Scanning for Orphan Packages (-Qdt)...${NC}"
ORPHANS=$(pacman -Qdtq)

if [ -n "$ORPHANS" ]; then
    echo -e "${BLUE}Found unneeded dependencies / debug symbols:${NC}"
    echo "$ORPHANS" | sed 's/^/  - /'
    echo -e "\n${YELLOW}Description:${NC} These are lingering build tools, debug packages, or old dependencies no longer attached to active software."

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
        echo -e "${YELLOW}Description:${NC} ${description}"

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
    "Provides XRDP server environments and Hyper-V guest interactions. Safe to remove if you don't remote into this desktop via RDP." \
    xrdp xorgxrdp pipewire-module-xrdp-git hyperv

check_and_remove_block "Leftover Development Tools" \
    "Compilers and modules (like LDC/D-lang and extra CMake extensions) that are typically only needed for custom builds." \
    ldc gtkd extra-cmake-modules

check_and_remove_block "Redundant Mirroring Utilities" \
    "Standard Arch Reflector setup. Safe to drop since you use cachyos-rate-mirrors." \
    reflector

check_and_remove_block "Network & Sharing Services" \
    "Samba (Windows file sharing) hooks, local network discovery protocols, and ARP scanners." \
    samba gvfs-smb gvfs-dnssd arp-scan

# ---------------------------------------------------------------------
# 3. DANGLING SYSTEMD TIMERS
# ---------------------------------------------------------------------
echo -e "\n${YELLOW}[3/6] Auditing Dead Systemd Timers...${NC}"
if systemctl list-timers --all | grep -q "reflector.timer"; then
    echo -e "${BLUE}Found lingering reflector.timer (package was previously removed).${NC}"
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
    echo -e "${YELLOW}Description:${NC} Clears old installer archives while keeping the current and previous versions for emergency rollbacks."

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
echo -e "${YELLOW}Description:${NC} Shrinks accumulated systemd boot and service logs down to a lightweight size limit."

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

echo -e "\n${GREEN}==================================================${NC}"
echo -e "${GREEN}         Maintenance Script Executed Successfully  ${NC}"
echo -e "${GREEN}==================================================${NC}\n"
