#!/bin/sh
random() {
tr </dev/urandom -dc A-Za-z0-9 | head -c5
echo
}

gen64() {
array=(1 2 3 4 5 6 7 8 9 0 a b c d e f)
ip64() {
echo "${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}"
}
echo "$1:$(ip64):$(ip64):$(ip64):$(ip64)"
}

gen_limits() {
cat >/etc/security/limits.conf <<-EOF
*           soft    nofile          65535
*           hard    nofile          65535
EOF
cat >/etc/sysctl.conf <<-EOF
net.ipv6.conf.ens33.proxy_ndp=1
net.ipv6.conf.all.proxy_ndp=1
net.ipv6.conf.default.forwarding=1
net.ipv6.conf.all.forwarding=1
net.ipv6.ip_nonlocal_bind=1
EOF
}

gen_remote() {
cat >/etc/pam.d/remote <<-EOF
#%PAM-1.0
#auth       required     pam_securetty.so
auth       substack     password-auth
auth       include      postlogin
account    required     pam_nologin.so
account    include      password-auth
password   include      password-auth
# pam_selinux.so close should be the first session rule
session    required     pam_selinux.so close
session    required     pam_loginuid.so
# pam_selinux.so open should only be followed by sessions to be executed in the user context
session    required     pam_selinux.so open
session    required     pam_namespace.so
session    optional     pam_keyinit.so force revoke
session    include      password-auth
session    include      postlogin
EOF
}

gen_3proxy_service() {
cat <<-EOF
[Unit]
Description=3proxy Proxy Server
After=syslog.target network.target

[Service]
Type=forking
ExecStart=/usr/bin/3proxy /etc/3proxy/3proxy.cfg
LimitNOFILE=65536
LimitNPROC=32768

[Install]
WantedBy=multi-user.target
EOF
}

install_3proxy() {
#git clone https://github.com/z3apa3a/3proxy
#cd 3proxy
#ln -s Makefile.Linux Makefile
#make
#sudo make install
yum install 3proxy -y
gen_3proxy_service >/usr/lib/systemd/system/3proxy.service
chmod +x /usr/lib/systemd/system/3proxy.service
echo "3Proxy Done!"
sleep 5
cd $WORKDIR
}

gen_3proxy() {
cat <<-EOF
daemon
maxconn 2000
nserver 1.1.1.1
nserver [2606:4700:4700::1111]
nserver [2606:4700:4700::1001]
nserver [2001:4860:4860::8888]
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
setgid 65535
setuid 65535
stacksize 6291456
flush
auth none
$(awk -F "/" '{print "proxy -6 -n -a -p" $2 " -i192.168.1.151" " -e" $1 }' ${WORKDATA})
EOF
}

gen_proxy_file() {
cat <<-EOF
$(awk -F "/" '{print "192.168.1.151:" $2 }' ${WORKDATA})
EOF
}

gen_ipv6() {
seq $FIRST_PORT $LAST_PORT | while read port; do
echo "$(gen64 $IP6)/$port"
done
}

gen_iptables() {
cat <<-EOF
$(awk -F "/" '{print "iptables -I INPUT -p tcp -m state --state NEW -m tcp --dport " $2 " -j ACCEPT"}' ${WORKDATA})
EOF
iptables -I INPUT -p tcp -m state --state NEW -m tcp --dport 23 -j ACCEPT
}

gen_ifconfig() {
cat <<-EOF
$(awk -F "/" '{print "ifconfig ens33 inet6 add " $1 "/64"}' ${WORKDATA})
EOF
}

ifcfg_ens33() {
uuid=$(uuidgen)
cat <<-EOF
TYPE=Ethernet
PROXY_METHOD=none
BROWSER_ONLY=no
BOOTPROTO=dhcp
DEFROUTE=yes
IPV4_FAILURE_FATAL=no
IPV6INIT=yes
IPV6_AUTOCONF=yes
IPV6_DEFROUTE=yes
IPV6_FAILURE_FATAL=no
IPV6_ADDR_GEN_MODE=stable-privacy
NAME=ens33
UUID=${uuid}
DEVICE=ens33
ONBOOT=yes
GATEWAY=192.168.1.1
IPADDR=192.168.1.151
NETMASK=255.255.255.0
EOF
}

set_network() {
ifcfg_ens33 >/etc/sysconfig/network-scripts/ifcfg-ens33
chmod +x /etc/sysconfig/network-scripts/ifcfg-ens33
systemctl restart network.service
sleep 5
}

ip_tables() {
yum install iptables-services -y
systemctl restart iptables.service
echo "Iptables Done!"
}

rm -rf /home/*
rm -rf /tmp/*
rm -rf /root/*

echo "Install Apps!"
yum install epel-release -y
yum install wget -y
yum groupinstall "Development Tools" -y
yum install net-tools -y
yum install telnet-server -y
yum clean all -y
yum update -y

set_network
ip_tables
install_3proxy
gen_limits
gen_remote
sysctl -p

echo "Working Folder = /home/Proxy"
WORKDIR="/home/Proxy"
WORKDATA="${WORKDIR}/ipv6.txt"
mkdir $WORKDIR && cd $_

IP4=$(curl -4 -s icanhazip.com)
IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')

echo "Internal IP = ${IP4}. IP6 = ${IP6}"
echo "How many proxy do you want to create? Example 500"
read COUNT
echo "$COUNT" >$WORKDIR/last_port.txt

FIRST_PORT=27081
COUNT_LAST_PORT="${WORKDIR}/last_port.txt"
LAST_PORT=$((($FIRST_PORT-1) + $COUNT_LAST_PORT))
#LAST_PORT=$((($FIRST_PORT-1) + 5))

gen_ipv6 >$WORKDIR/ipv6.txt
gen_proxy_file >$WORKDIR/proxy.txt 
gen_iptables >$WORKDIR/boot_iptables.sh
gen_ifconfig >$WORKDIR/boot_ifconfig.sh
gen_3proxy >/etc/3proxy/3proxy.cfg
wget -O /etc/rc.d/rc.local https://raw.githubusercontent.com/PhoenixPink/proxy_ipv6/main/rc.local && chmod +x /etc/rc.d/rc.local
timedatectl set-timezone Asia/Ho_Chi_Minh

chmod +x ${WORKDIR}/boot_*.sh
chmod +x ${WORKDIR}/*.txt
chmod +x /etc/3proxy/3proxy.cfg
chmod +x /etc/rc.d/rc.local

bash ${WORKDIR}/boot_ifconfig.sh
bash ${WORKDIR}/boot_iptables.sh
ulimit -n 10048
crontab -r
#Xoay Sau 10 Phút
#(crontab -r ; echo "0,10,20,30,40,50 * * * * /usr/sbin/shutdown -r now") | crontab -
systemctl daemon-reload
systemctl start telnet.socket
systemctl restart crond.service
systemctl restart 3proxy.service
systemctl enable telnet.socket
systemctl enable rc-local.service
systemctl status crond.service
systemctl status 3proxy.service
echo "Create Proxy Done!"
exit 0
