# 2026-10-10 19:04:10 by RouterOS 7.24.5
#
/interface bridge
add comment="branch A LAN" name=branch-lan
/interface ethernet
set [ find default-name=ether1 ] disable-running-check=no
/interface wireguard
add comment="tunnel to chr-b" listen-port=13231 mtu=1420 name=wg-site-to-site
/interface wireguard peers
add allowed-address=10.255.255.2/32,10.20.2.0/24 comment=chr-b \
    endpoint-address=10.10.10.22 endpoint-port=13231 interface=\
    wg-site-to-site name=peer1 persistent-keepalive=25s public-key=\
    "muOo7m1X4GP9i/S+mVK9A1F9tvxXukAEnOc7hvmPyUo="
/ip address
add address=10.10.10.21/24 comment="lab network" interface=ether1 network=\
    10.10.10.0
add address=10.20.1.1/24 interface=branch-lan network=10.20.1.0
add address=10.255.255.1/30 interface=wg-site-to-site network=10.255.255.0
/ip dns
set servers=10.10.10.1
/ip route
add comment="default via fw-01" dst-address=0.0.0.0/0 gateway=10.10.10.1
add comment="branch B via tunnel" dst-address=10.20.2.0/24 gateway=\
    wg-site-to-site
/ip service
set ftp disabled=yes
set telnet disabled=yes
set www disabled=yes
set api disabled=yes
set api-ssl disabled=yes
/system identity
set name=chr-a
