#!/bin/bash
# =============================================================================
# mount_pixel_ssd.sh - Production-Grade ext4 Mount & Samba Starter for WSL2
# =============================================================================
# Features:
#   1. Performance optimization: noatime, nodiratime (eliminates access write-wear)
#   2. Hardware disconnect safety: errors=remount-ro (prevents dirty corruption)
#   3. Automatic journal playback & safe fsck preen on unclean disconnections
#   4. Bind-mounts /mnt/wsl/PHYSICALDRIVE*p1 or block device /dev/sd[b-z]1
#   5. Ensures Samba daemon (smbd) is running
# =============================================================================

MOUNT_POINT="${1:-/mnt/pixel_ssd}"
mkdir -p "$MOUNT_POINT"

MOUNT_OPTS="noatime,nodiratime,errors=remount-ro"

# 1. Check if already mounted by WSL at /mnt/wsl/PHYSICALDRIVE*p1
W_MOUNT=$(grep -E '/mnt/wsl/PHYSICALDRIVE[0-9]+p[0-9]+' /proc/mounts | awk '{print $2}' | tail -n 1)
if [ -n "$W_MOUNT" ] && [ -d "$W_MOUNT" ]; then
    grep -qs "$MOUNT_POINT" /proc/mounts || mount --bind "$W_MOUNT" "$MOUNT_POINT"
    # Apply noatime to the bind mount
    mount -o "remount,$MOUNT_OPTS" "$MOUNT_POINT" 2>/dev/null
fi

# 2. If still not mounted, find the ext4 partition and mount directly
if ! grep -qs "$MOUNT_POINT" /proc/mounts; then
    for dev in $(lsblk -rno NAME,TYPE,FSTYPE | awk '$2=="part" && $3=="ext4" {print $1}'); do
        if ! mount -o "$MOUNT_OPTS" "/dev/$dev" "$MOUNT_POINT" 2>/dev/null; then
            # If mount failed (e.g. dirty journal), run safe fsck preen repair
            /sbin/fsck.ext4 -p "/dev/$dev" >/dev/null 2>&1
            mount -o "$MOUNT_OPTS" "/dev/$dev" "$MOUNT_POINT" 2>/dev/null && break
        else
            break
        fi
    done
fi

# 3. Ensure Samba is running
/usr/sbin/service smbd status >/dev/null 2>&1 || /usr/sbin/service smbd start