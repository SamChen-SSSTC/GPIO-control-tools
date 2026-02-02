#! /bin/bash

echo "$1 Download $2 FW slot 1..."
sudo nvme fw-download $1 --fw=$2 --xfer=0x20000
sleep 1
sudo nvme fw-commit $1 --slot=1 --action=3
echo "$1 Download $2 FW slot 2..."
sleep 3
sudo nvme fw-download $1 --fw=$2 --xfer=0x20000
sleep 1
sudo nvme fw-commit $1 --slot=2 --action=3
echo "Pass "
