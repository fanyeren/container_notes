#!/bin/bash

whoami=$(whoami 2>/dev/null)

if [[ x"$whoami" != "xroot" ]]; then
    echo "Usage: you need to be root!"
    exit 1
fi

which stap >/dev/null 2>&1
if [[ $? != 0 ]]; then
    echo "systemtap not installed."
fi

major=$(lsblk --raw | grep -w sdb | awk -F' |:' '{print $2}')
minor=$(lsblk --raw | grep -w sdb | awk -F' |:' '{print $3}')

hexid=$(perl -e "printf(\"0x%x%05x\n\", ${major}, ${minor})")

# https://buildlogs.centos.org/c7.1511.u/kernel/20161024152721/3.10.0-327.36.3.el7.x86_64/ 从这里下载内核的 debuginfo
cat > /tmp/dev_task_io.stp <<EOF
#! /usr/bin/env stap

global device_of_interest

probe begin {
  device_of_interest = \$1
  printf ("device of interest: 0x%x\\n", device_of_interest)
}

probe kernel.function("submit_bio")
{
  dev = \$bio->bi_bdev->bd_dev
  if (dev == device_of_interest)
    printf ("[%s](%d) dev:0x%x rw:%d size:%d\\n", execname(), pid(), dev, \$rw, \$bio->bi_size)
}
EOF

stap /tmp/dev_task_io.stp $hexid
