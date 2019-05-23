#!/bin/bash

set -ex
set -o pipefail

export LC_ALL="C.UTF-8"


echo
echo "### Running $0 on the provisioned system"
echo

if [ -f boot-speed-measurement-taken-here ]; then
    echo "Device is dirty (boot-speed-measurement-taken-here)!"
    # We want to be extra sure not to re-download a past measurement.
    ls -la
    rm -rfv artifacts
    exit 1
fi

rm -rf artifacts
mkdir -v artifacts
cd artifacts

# Run the script with the `pipefail` option to retain the exit code
date --utc --rfc-3339=ns | tee date-rfc-3339
hostname | tee hostname
arch | tee arch
uname -a | tee uname-a
id | tee id
w | tee w
pwd | tee pwd
ip addr | tee ip-addr
free -m | tee free-m
mount | tee mount
df -h | tee df-h
sudo journalctl --list-boots | tee journalctl_list-boots

cat /proc/cpuinfo | tee cpuinfo
cat /etc/os-release | tee os-release
cat /proc/sys/kernel/random/boot_id | tee boot_id

if ! command -v cloud-init >/dev/null; then
    touch NO-CLOUD-INIT
elif ! timeout 20m cloud-init status --wait; then
    # Wait for `cloud-init status --wait` to exit (with a timeout)
    touch CLOUDINIT-DID-NOT-FINISH-IN-TIME
    exit 1
fi

if [ -f /var/log/cloud-init.log ]; then
    cp -v /var/log/cloud-init.log .
fi

# Wait for systemd-analyze to exit with status 0 (success)
# https://github.com/systemd/systemd/blob/1cae151/src/analyze/analyze.c#L279
if timeout 20m sh -c "until systemd-analyze time; do sleep 20; done"; then
    # Gather the actual data
    systemd-analyze time > systemd-analyze_time
    systemd-analyze blame > systemd-analyze_blame
    systemd-analyze critical-chain > systemd-analyze_critical-chain
    systemd-analyze plot > systemd-analyze_plot.svg
else
    touch SYSTEM-DID-NOT-BOOT-IN-TIME
    exit 1
fi

# There should be no jobs running once boot is finished.
# This is mostly useful to debug boot timeouts.
systemctl list-jobs > systemctl_list-jobs

# Gather additional data
cp -v /etc/fstab .

. /etc/os-release

if [ "$NAME" != "Ubuntu Core" ]; then
    sudo apt -y install pciutils usbutils
    dpkg-query --list > dpkg-query.out 2>&1 || true
    sudo lspci -vvv > lspci.out 2>&1 || true
    sudo lsusb -v > lsusb.out 2>&1 || true
fi

snap list > snap_list
ls -l > directory-listing

echo
echo "### End of $0"
echo