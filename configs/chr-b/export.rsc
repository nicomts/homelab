# 2026-10-10 19:04:17 by RouterOS 7.24.5
#
/interface bridge
add comment="branch B LAN" name=branch-lan
/interface ethernet
set [ find default-name=ether1 ] disable-running-check=no
/interface wireguard
add comment="tunnel to chr-a" listen-port=13231 mtu=1420 name=wg-site-to-site
/interface wireguard peers
add allowed-address=10.255.255.1/32,10.20.1.0/24 comment=chr-a \
    endpoint-address=10.10.10.21 endpoint-port=13231 interface=\
    wg-site-to-site name=peer1 persistent-keepalive=25s public-key=\
    "hboNHJ8fTQ1t/IFM9OZu8dG2Cqy/u7iOhusmOYK+WQ4="
/ip address
add address=10.10.10.22/24 comment="lab network" interface=ether1 network=\
    10.10.10.0
add address=10.20.2.1/24 interface=branch-lan network=10.20.2.0
add address=10.255.255.2/30 interface=wg-site-to-site network=10.255.255.0
/ip dns
set servers=10.10.10.1
/ip route
add comment="default via fw-01" dst-address=0.0.0.0/0 gateway=10.10.10.1
add comment="branch A via tunnel" dst-address=10.20.1.0/24 gateway=\
    wg-site-to-site
/ip service
set ftp disabled=yes
set telnet disabled=yes
set www disabled=yes
set api disabled=yes
set api-ssl disabled=yes
/system identity
set name=chr-b
