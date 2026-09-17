#!/bin/sh
# Run inside the host mount namespace, only on kubernetes6 or kubernetes7.
# Uses existing free LVM extents: no formatting, shrinking, reboot or eviction.
# Growing is not automatically reversible. Keep remaining VG space unallocated.
set -eu
mode=${1:---check}
[ "$mode" = --check ] || [ "$mode" = --apply ] || exit 2
lv=/dev/ubuntu-vg/ubuntu-lv
target=322122547200 # 300 GiB total, not an increment
[ "$(findmnt -n -o FSTYPE /)" = ext4 ]
[ "$(readlink -f "$(findmnt -n -o SOURCE /)")" = "$(readlink -f "$lv")" ]
[ "$(findmnt -n -o SOURCE -T /var/lib/longhorn)" = "$(findmnt -n -o SOURCE /)" ]
size=$(lvs --units b --nosuffix --noheadings -o lv_size "$lv" | awk '{printf "%.0f", $1}')
free=$(vgs --units b --nosuffix --noheadings -o vg_free ubuntu-vg | awk '{printf "%.0f", $1}')
[ "$size" -le "$target" ]
needed=$((target - size))
[ "$free" -ge "$needed" ]
printf 'LV bytes=%s; target=%s; free VG bytes=%s; mode=%s\n' "$size" "$target" "$free" "$mode"
if [ "$mode" = --apply ]; then
  if [ "$size" -lt "$target" ]; then lvextend --size 300G "$lv"; fi
  resize2fs "$lv"
  df -h /var/lib/longhorn
fi
