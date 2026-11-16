#!/bin/bash
# Mount the USB test ESP (root required on this install).
set -x
diskutil repairVolume disk4s1
diskutil mount disk4s1
ls -la /Volumes
