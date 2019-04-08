#!/bin/bash
# Author: whymaths@gmail.com
# 以前我一直用的是 lxc，在发现最新版的 systemd 里的 systemd-nspawn 已经很强大以后，就正式放弃 lxc，投入 systemd 的怀抱

sudo yum -y install debootstrap
sudo debootstrap --arch=amd64 stretch /home/devops/debian/ http://mirrors.sohu.com/debian/

# 下面两个文件是编译自新版本的 systemd，CentOS7/RHEL7 上自带的 systemd 版本太旧，跑不起来。
sudo cp -f libsystemd-shared-239.so /usr/lib64/
sudo chmod +x my-systemd-nspawn
sudo cp -f my-systemd-nspawn /usr/bin

sudo /bin/my-systemd-nspawn -D /home/devops/debian/

# sudo chown root:root /bin/hmnsjump.ns
# sudo chmod 4755 /bin/hmnsjump.ns

cat | sudo tee /lib/systemd/system/debian.service <<EOF
[Unit]
Description=Debian Container
After=network.target rc-local.service

[Service]
ExecStart=/bin/my-systemd-nspawn -D /home/devops/debian "--property=DeviceAllow=char-pts rwm" "--property=DeviceAllow=char-tty rwm" -b
KillMode=process
Restart=always
RestartSec=42s
# systemd.resource-control
# DeviceAllow

LimitNOFILE=infinity
LimitNPROC=infinity

User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl start debian
sudo systemctl status debian

# .... 后略，为容器环境初始化和个性化设置，包括配置网络，安装 ssh server，配置认证方式（需要支持 LDAP 和 Kerberos）等。
