# arch-sysclean
It cleans your arch of crap like orphans and unneeded packages

# Here is all the commands to do it manually
pacman -Qdtq  - Scans the system to identify packages that were installed as dependencies but are no longer required by any other package.  
pacman -Rns   - Removes the specified orphaned packages along with their configuration files (-n) and unneeded dependencies (-s).
systemctl list-timers --all   - Lists all active and inactive systemd timers
systemctl disable --now yourtimer.timer
systemctl daemon-reload
paccache -r   - Removes all cached versions of packages from /var/cache/pacman/pkg/ except for the most recent two versions for each package.
journalctl --disk-usage   - Displays the current amount of disk space occupied by systemd journal logs.
journalctl --vacuum-size=200M   - Shrinks the journal log files until the total disk usage is reduced to 200MB.
