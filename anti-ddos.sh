#!/bin/sh
#------------------------------------------------------------------------------
# Que:		Simple Anti-DDoS sysconfig and iptables rules set     
# Por:		Stephen Horner
# Correo:	treeherder arroba protonmail punto com

#------------------------------------------------------------------------------
# For debugging use iptables -v.
#
IPT="/sbin/iptables"
IP6="/sbin/ip6tables"
MP="/sbin/modprobe"
RMM="/sbin/rmmod"
ARP="/usr/sbin/arp"

#------------------------------------------------------------------------------
# Logging options.
#
LOG="LOG --log-level debug --log-tcp-sequence --log-tcp-options"
LOG="$LOG --log-ip-options"

#------------------------------------------------------------------------------
# Defaults for rate limiting
#
RLIMIT="-m limit --limit 3/s --limit-burst 8"

#------------------------------------------------------------------------------
# Unprivileged ports.
#
PORTSHIGH="1024:65535"
PORTSSSH="11337:11339"

#------------------------------------------------------------------------------
# Load required kernel modules
#
$MP ip_conntrack_ftp
$MP ip_conntrack_irc

#------------------------------------------------------------------------------
# Mitigate ARP spoofing/poisoning and similar attacks.
#
# Hardcode static ARP cache entries here
# $ARP -s IP-ADDRESS MAC-ADDRESS

#------------------------------------------------------------------------------
# Kernel configuration.

#------------------------------------------------------------------------------
# Disable IP forwarding.
# On => Off = (reset)
#
echo 1 > /proc/sys/net/ipv4/ip_forward
echo 0 > /proc/sys/net/ipv4/ip_forward

#------------------------------------------------------------------------------
# Enable IP spoofing protection
#
for i in /proc/sys/net/ipv4/conf/*/rp_filter; do echo 1 > $i; done

#------------------------------------------------------------------------------
# Protect against SYN flood attacks
#
echo 1 > /proc/sys/net/ipv4/tcp_syncookies

#------------------------------------------------------------------------------
# Ignore all incoming ICMP echo requests
#
echo 0 > /proc/sys/net/ipv4/icmp_echo_ignore_all

#------------------------------------------------------------------------------
# Ignore ICMP echo requests to broadcast
#
echo 1 > /proc/sys/net/ipv4/icmp_echo_ignore_broadcasts

#------------------------------------------------------------------------------
# Log packets with impossible addresses.
#
for i in /proc/sys/net/ipv4/conf/*/log_martians; do echo 1 > $i; done

#------------------------------------------------------------------------------
# Don't log invalid responses to broadcast
#
echo 1 > /proc/sys/net/ipv4/icmp_ignore_bogus_error_responses

#------------------------------------------------------------------------------
# Don't accept or send ICMP redirects.
#
for i in /proc/sys/net/ipv4/conf/*/accept_redirects; do echo 0 > $i; done
for i in /proc/sys/net/ipv4/conf/*/send_redirects; do echo 0 > $i; done

#------------------------------------------------------------------------------
# Don't accept source routed packets.
#
for i in /proc/sys/net/ipv4/conf/*/accept_source_route; do echo 0 > $i; done

#------------------------------------------------------------------------------
# Disable multicast routing
#
for i in /proc/sys/net/ipv4/conf/*/mc_forwarding; do echo 0 > $i; done

#------------------------------------------------------------------------------
# Disable proxy_arp.
#
for i in /proc/sys/net/ipv4/conf/*/proxy_arp; do echo 0 > $i; done

#------------------------------------------------------------------------------
# Enable secure redirects, i.e. only accept ICMP redirects for gateways
# Helps against MITM attacks.
#
for i in /proc/sys/net/ipv4/conf/*/secure_redirects; do echo 1 > $i; done

#------------------------------------------------------------------------------
# Disable bootp_relay
#
for i in /proc/sys/net/ipv4/conf/*/bootp_relay; do echo 0 > $i; done


#------------------------------------------------------------------------------
# Default policies
#
# Drop everything by default.
#
$IPT -P INPUT DROP
$IPT -P FORWARD DROP
$IPT -P OUTPUT DROP

#------------------------------------------------------------------------------
# Set the nat/mangle/raw tables' chains to ACCEPT
#
$IPT -t nat -P PREROUTING ACCEPT
$IPT -t nat -P OUTPUT ACCEPT
$IPT -t nat -P POSTROUTING ACCEPT

$IPT -t mangle -P PREROUTING ACCEPT
$IPT -t mangle -P INPUT ACCEPT
$IPT -t mangle -P FORWARD ACCEPT
$IPT -t mangle -P OUTPUT ACCEPT
$IPT -t mangle -P POSTROUTING ACCEPT

#------------------------------------------------------------------------------
# Cleanup.
#

# Delete all
#
$IPT -F
$IPT -t nat -F
$IPT -t mangle -F

# Delete all
#
$IPT -X
$IPT -t nat -X
$IPT -t mangle -X

# Zero all packets and counters.
#
$IPT -Z
$IPT -t nat -Z
$IPT -t mangle -Z


#------------------------------------------------------------------------------
# Completely disable IPv6.


# If the ip6tables command is available, try to block all IPv6 traffic.
#
if test -x $IP6; then

	# Set the default policies
	# drop everything
	#
	$IP6 -P INPUT DROP 2>/dev/null
	$IP6 -P FORWARD DROP 2>/dev/null
	$IP6 -P OUTPUT DROP 2>/dev/null
	
	# The mangle table can pass everything
	#
	$IP6 -t mangle -P PREROUTING ACCEPT 2>/dev/null
	$IP6 -t mangle -P INPUT ACCEPT 2>/dev/null
	$IP6 -t mangle -P FORWARD ACCEPT 2>/dev/null
	$IP6 -t mangle -P OUTPUT ACCEPT 2>/dev/null
	$IP6 -t mangle -P POSTROUTING ACCEPT 2>/dev/null

	# Delete all rules.
	#
	$IP6 -F 2>/dev/null
	$IP6 -t mangle -F 2>/dev/null

	# Delete all chains.
	#
	$IP6 -X 2>/dev/null
	$IP6 -t mangle -X 2>/dev/null

	# Zero all packets and counters.
	#
	$IP6 -Z 2>/dev/null
	$IP6 -t mangle -Z 2>/dev/null

fi

#------------------------------------------------------------------------------
# Custom user-defined chains.

# LOG packets, then ACCEPT.
#
$IPT -N ACCEPTLOG
$IPT -A ACCEPTLOG -j $LOG $RLIMIT --log-prefix "ACCEPT "
$IPT -A ACCEPTLOG -j ACCEPT

# LOG packets, then DROP.
#
$IPT -N DROPLOG
$IPT -A DROPLOG -j $LOG $RLIMIT --log-prefix "DROP "
$IPT -A DROPLOG -j DROP

# LOG packets, then REJECT.
# TCP packets are rejected with a TCP reset.
#
$IPT -N REJECTLOG
$IPT -A REJECTLOG -j $LOG $RLIMIT --log-prefix "REJECT "
$IPT -A REJECTLOG -p tcp -j REJECT --reject-with tcp-reset
$IPT -A REJECTLOG -j REJECT

# Only allows RELATED ICMP types
# (destination-unreachable, time-exceeded, and parameter-problem).
# TODO: Rate-limit this traffic?
# TODO: Allowing fragmentation?
#
$IPT -N RELATED_ICMP
$IPT -A RELATED_ICMP -p icmp --icmp-type destination-unreachable -j ACCEPT
$IPT -A RELATED_ICMP -p icmp --icmp-type time-exceeded -j ACCEPT
$IPT -A RELATED_ICMP -p icmp --icmp-type parameter-problem -j ACCEPT
$IPT -A RELATED_ICMP -j DROPLOG

# Make It Even Harder To Multi-PING
#
$IPT  -A INPUT -p icmp -m limit --limit 1/s --limit-burst 2 -j ACCEPT
$IPT  -A INPUT -p icmp -m limit --limit 1/s --limit-burst 2 -j LOG --log-prefix PING-DROP:
$IPT  -A INPUT -p icmp -j DROP
$IPT  -A OUTPUT -p icmp -j ACCEPT

#------------------------------------------------------------------------------
# Only allow the minimally required/recommended parts of ICMP. Block the rest.

# TODO: This section needs a lot of testing!

# First, drop all fragmented ICMP packets (almost always malicious).
#
$IPT -A INPUT -p icmp --fragment -j DROPLOG
$IPT -A OUTPUT -p icmp --fragment -j DROPLOG
$IPT -A FORWARD -p icmp --fragment -j DROPLOG

# Allow all ESTABLISHED ICMP traffic.
#
$IPT -A INPUT -p icmp -m state --state ESTABLISHED -j ACCEPT $RLIMIT
$LES -A OUTPUT -p icmp -m state --state ESTABLISHED -j ACCEPT $RLIMIT

# Allow some parts of the RELATED ICMP traffic, block the rest.
#
$IPT -A INPUT -p icmp -m state --state RELATED -j RELATED_ICMP $RLIMIT
$IPT -A OUTPUT -p icmp -m state --state RELATED -j RELATED_ICMP $RLIMIT

# Allow incoming ICMP echo requests (ping), but only rate-limited.
#
$IPT -A INPUT -p icmp --icmp-type echo-request -j ACCEPT $RLIMIT

# Allow outgoing ICMP echo requests (ping), but only rate-limited.
#
$IPT -A OUTPUT -p icmp --icmp-type echo-request -j ACCEPT $RLIMIT

# Drop any other ICMP traffic.
#
$IPT -A INPUT -p icmp -j DROPLOG
$IPT -A OUTPUT -p icmp -j DROPLOG
$IPT -A FORWARD -p icmp -j DROPLOG

#------------------------------------------------------------------------------
# Selectively allow certain special types of traffic.

# Allow loopback interface to do anything.
#
$IPT -A INPUT -i lo -j ACCEPT
$IPT -A OUTPUT -o lo -j ACCEPT

# Allow incoming connections related to existing allowed connections.
#
$IPT -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow outgoing connections EXCEPT invalid
#
$IPT -A OUTPUT -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT

#------------------------------------------------------------------------------
# Miscellaneous.

# Micro$oft can eat a bowl of dicks
#
$IPT -A INPUT -p tcp -m multiport --dports 135,137,138,139,445,1433,1434 -j DROP
$IPT -A INPUT -p udp -m multiport --dports 135,137,138,139,445,1433,1434 -j DROP

# Explicitly drop invalid incoming traffic
#
$IPT -A INPUT -m state --state INVALID -j DROP

# Drop invalid outgoing traffic, too.
#
$IPT -A OUTPUT -m state --state INVALID -j DROP

# If we would use NAT, INVALID packets would pass - BLOCK them anyways
#
$IPT -A FORWARD -m state --state INVALID -j DROP

# PORT Scanners (stealth also)
#
$IPT -A INPUT -m state --state NEW -p tcp --tcp-flags ALL ALL -j DROP
$IPT -A INPUT -m state --state NEW -p tcp --tcp-flags ALL NONE -j DROP

# TODO: Some more anti-spoofing rules? For example:
#
# $IPT -A INPUT -p tcp --tcp-flags ALL FIN,URG,PSH -j DROP
# $IPT -A INPUT -p tcp --tcp-flags SYN,RST SYN,RST -j DROP
# $IPT -A INPUT -p tcp --tcp-flags SYN,FIN SYN,FIN -j DROP

$IPT -N SYN_FLOOD
$IPT -A INPUT -p tcp --syn -j SYN_FLOOD
$IPT -A SYN_FLOOD -m limit --limit 2/s --limit-burst 6 -j RETURN
$IPT -A SYN_FLOOD -j DROP

# TODO: Block known-bad IPs (see http://www.dshield.org/top10.php).
#
# $IPT -A INPUT -s INSERT-BAD-IP-HERE -j DROPLOG

#------------------------------------------------------------------------------
# Drop any traffic from IANA-reserved IPs.

$IPT -A INPUT -s 0.0.0.0/7 -j DROP
$IPT -A INPUT -s 2.0.0.0/8 -j DROP
$IPT -A INPUT -s 5.0.0.0/8 -j DROP
$IPT -A INPUT -s 7.0.0.0/8 -j DROP
$IPT -A INPUT -s 10.0.0.0/8 -j DROP
$IPT -A INPUT -s 23.0.0.0/8 -j DROP
$IPT -A INPUT -s 27.0.0.0/8 -j DROP
$IPT -A INPUT -s 31.0.0.0/8 -j DROP
$IPT -A INPUT -s 36.0.0.0/7 -j DROP
$IPT -A INPUT -s 39.0.0.0/8 -j DROP
$IPT -A INPUT -s 42.0.0.0/8 -j DROP
$IPT -A INPUT -s 49.0.0.0/8 -j DROP
$IPT -A INPUT -s 50.0.0.0/8 -j DROP
$IPT -A INPUT -s 77.0.0.0/8 -j DROP
$IPT -A INPUT -s 78.0.0.0/7 -j DROP
$IPT -A INPUT -s 92.0.0.0/6 -j DROP
$IPT -A INPUT -s 96.0.0.0/4 -j DROP
$IPT -A INPUT -s 112.0.0.0/5 -j DROP
$IPT -A INPUT -s 120.0.0.0/8 -j DROP
$IPT -A INPUT -s 169.254.0.0/16 -j DROP
$IPT -A INPUT -s 172.16.0.0/12 -j DROP
$IPT -A INPUT -s 173.0.0.0/8 -j DROP
$IPT -A INPUT -s 174.0.0.0/7 -j DROP
$IPT -A INPUT -s 176.0.0.0/5 -j DROP
$IPT -A INPUT -s 184.0.0.0/6 -j DROP
$IPT -A INPUT -s 192.0.2.0/24 -j DROP
$IPT -A INPUT -s 197.0.0.0/8 -j DROP
$IPT -A INPUT -s 198.18.0.0/15 -j DROP
$IPT -A INPUT -s 223.0.0.0/8 -j DROP
$IPT -A INPUT -s 224.0.0.0/3 -j DROP

#------------------------------------------------------------------------------
# Selectively allow certain outbound connections, block the rest.

# Allow outgoing DNS requests. Few things will work without this.
#
$IPT -A OUTPUT -m state --state NEW -p udp --dport 53 -j ACCEPT
$IPT -A OUTPUT -m state --state NEW -p tcp --dport 53 -j ACCEPT

# Allow outgoing HTTP requests. Unencrypted, use with care.
#
$IPT -A OUTPUT -m state --state NEW -p tcp --dport 80 -j ACCEPT

# Allow outgoing HTTPS requests.
#
$IPT -A OUTPUT -m state --state NEW -p tcp --dport 443 -j ACCEPT

# Allow outgoing SMTPS requests. Do NOT allow unencrypted SMTP!
#
# $IPT -A OUTPUT -m state --state NEW -p tcp --dport 465 -j ACCEPT

# Allow outgoing "submission" (RFC 2476) requests.
#
$IPT -A OUTPUT -m state --state NEW -p tcp --dport 587 -j ACCEPT

# Allow outgoing POP3S requests.
#
$IPT -A OUTPUT -m state --state NEW -p tcp --dport 995 -j ACCEPT

# Allow outgoing SSH requests.
#
$IPT -A OUTPUT -m state --state NEW -p tcp --dport 22 -j ACCEPT

# Allow outgoing FTP requests. Unencrypted, use with care.
#
$IPT -A OUTPUT -m state --state NEW -p tcp --dport 21 -j ACCEPT

# Allow outgoing NNTP requests. Unencrypted, use with care.
#
# $IPT -A OUTPUT -m state --state NEW -p tcp --dport 119 -j ACCEPT

# Allow outgoing NTP requests. Unencrypted, use with care.
#
# $IPT -A OUTPUT -m state --state NEW -p udp --dport 123 -j ACCEPT

# Allow outgoing IRC requests. Unencrypted, use with care.
#
# Note: This usually needs the ip_conntrack_irc kernel module.
#
# $IPT -A OUTPUT -m state --state NEW -p tcp --dport 6667 -j ACCEPT

# Allow outgoing requests to various proxies. Unencrypted, use with care.
#
# $IPT -A OUTPUT -m state --state NEW -p tcp --dport 8080 -j ACCEPT
# $IPT -A OUTPUT -m state --state NEW -p tcp --dport 8090 -j ACCEPT

# Allow outgoing DHCP requests. Unencrypted, use with care.
#
# TODO: This is completely untested, I have no idea whether it works!
# TODO: I think this can be tightened a bit more.
#
$IPT -A OUTPUT -m state --state NEW -p udp --sport 67:68 --dport 67:68 -j ACCEPT

# Allow outgoing CVS requests. Unencrypted, use with care.
#
# $IPT -A OUTPUT -m state --state NEW -p tcp --dport 2401 -j ACCEPT

# Allow outgoing MySQL requests. Unencrypted, use with care.
#
# $IPT -A OUTPUT -m state --state NEW -p tcp --dport 3306 -j ACCEPT

# Allow outgoing SVN requests. Unencrypted, use with care.
#
# $IPT -A OUTPUT -m state --state NEW -p tcp --dport 3690 -j ACCEPT

# Allow outgoing PLESK requests. Unencrypted, use with care.
#
# $IPT -A OUTPUT -m state --state NEW -p tcp --dport 8443 -j ACCEPT

# Allow outgoing Tor (http://tor.eff.org) requests.
#
# Note: Do _not_ use unencrypted protocols over Tor (sniffing is possible)!
#
# $IPT -A OUTPUT -m state --state NEW -p tcp --dport 9001 -j ACCEPT
# $IPT -A OUTPUT -m state --state NEW -p tcp --dport 9002 -j ACCEPT
# $IPT -A OUTPUT -m state --state NEW -p tcp --dport 9030 -j ACCEPT
# $IPT -A OUTPUT -m state --state NEW -p tcp --dport 9031 -j ACCEPT
# $IPT -A OUTPUT -m state --state NEW -p tcp --dport 9090 -j ACCEPT
# $IPT -A OUTPUT -m state --state NEW -p tcp --dport 9091 -j ACCEPT

# Allow outgoing OpenVPN requests.
#
$IPT -A OUTPUT -m state --state NEW -p udp --dport 1194 -j ACCEPT

# TODO: ICQ, MSN, GTalk, Skype, Yahoo, etc...

#------------------------------------------------------------------------------
# Selectively allow certain inbound connections, block the rest.

# Allow incoming DNS requests.
#
$IPT -A INPUT -m state --state NEW -p udp --dport 53 -j ACCEPT
$IPT -A INPUT -m state --state NEW -p tcp --dport 53 -j ACCEPT

# Allow incoming HTTP requests.
#
$IPT -A INPUT -m state --state NEW -p tcp --dport 80 -j ACCEPT

# Allow incoming HTTPS requests.
#
$IPT -A INPUT -m state --state NEW -p tcp --dport 443 -j ACCEPT

# Allow incoming POP3 requests.
#
$IPT -A INPUT -m state --state NEW -p tcp --dport 110 -j ACCEPT

# Allow incoming IMAP4 requests.
#
$IPT -A INPUT -m state --state NEW -p tcp --dport 143 -j ACCEPT

# Allow incoming POP3S requests.
#
$IPT -A INPUT -m state --state NEW -p tcp --dport 995 -j ACCEPT

#------------------------------------------------------------------------------
# Allow incoming SMTP requests.
#
$IPT -A INPUT -m state --state NEW -p tcp --dport 25 -j ACCEPT

#------------------------------------------------------------------------------
# Allow incoming SSH requests.
#
$IPT -A INPUT -m state --state NEW -p tcp --dport 22 -j ACCEPT

#------------------------------------------------------------------------------
# Allow incoming FTP requests.
#
$IPT -A INPUT -m state --state NEW -p tcp --dport 21 -j ACCEPT

#------------------------------------------------------------------------------
# Allow incoming NNTP requests.
#
# $IPT -A INPUT -m state --state NEW -p tcp --dport 119 -j ACCEPT

#------------------------------------------------------------------------------
# Allow incoming MySQL requests.
#
# $IPT -A INPUT -m state --state NEW -p tcp --dport 3306 -j ACCEPT

#------------------------------------------------------------------------------
# Allow incoming PLESK requests.
#
# $IPT -A INPUT -m state --state NEW -p tcp --dport 8843 -j ACCEPT

#------------------------------------------------------------------------------
# Allow incoming BitTorrent requests.
#
# TODO: Are these already handled by ACCEPTing established/related traffic?
#
# $IPT -A INPUT -m state --state NEW -p tcp --dport 6881 -j ACCEPT
# $IPT -A INPUT -m state --state NEW -p udp --dport 6881 -j ACCEPT

#------------------------------------------------------------------------------
# Allow incoming nc requests.
#
# $IPT -A INPUT -m state --state NEW -p tcp --dport 2030 -j ACCEPT
# $IPT -A INPUT -m state --state NEW -p udp --dport 2030 -j ACCEPT

#------------------------------------------------------------------------------
# Explicitly log and reject everything else.

# Use REJECT instead of REJECTLOG if you don't need/want logging.
#
$IPT -A INPUT -j REJECTLOG
$IPT -A OUTPUT -j REJECTLOG
$IPT -A FORWARD -j REJECTLOG

# tests to run 
# iptables -vnL, nmap, ping, telnet, ...

exit 0
