#
# SPDX-License-Identifier: BSD-2-Clause
#
# Copyright (c) 2024 Deciso B.V.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.

. $(atf_get_srcdir)/utils.subr

common_dir=$(atf_get_srcdir)/../common

atf_test_case "max" "cleanup"
max_head()
{
	atf_set descr 'Test the pflog output on max keyword'
	atf_set require.user root
}

max_body()
{
	pflog_init

	epair=$(vnet_mkepair)

	vnet_mkjail alcatraz ${epair}a
	jexec alcatraz ifconfig ${epair}a 192.0.2.1/24 up
	jexec alcatraz ifconfig ${epair}a alias 192.0.2.3/24

	ifconfig ${epair}b 192.0.2.2/24 up

	# Sanity check
	atf_check -s exit:0 -o ignore \
	    ping -c 1 192.0.2.1

	jexec alcatraz pfctl -e
	jexec alcatraz ifconfig pflog0 up
	pft_set_rules alcatraz "pass log inet keep state (max 1)"

	jexec alcatraz tcpdump -n -e -ttt --immediate-mode -l -U -i pflog0 >> ${PWD}/pflog.txt &
	sleep 1 # Wait for tcpdump to start

	atf_check -s exit:0 -o ignore \
	    ping -c 1 192.0.2.1

	atf_check -s exit:2 -o ignore \
	    ping -c 1 192.0.2.1

	echo "Rules"
	jexec alcatraz pfctl -sr -vv
	echo "States"
	jexec alcatraz pfctl -ss -vv
	echo "Log"
	cat ${PWD}/pflog.txt

	# first ping passes
	atf_check -o match:".*rule 0/0\(match\): pass in on ${epair}a: 192.0.2.2 > 192.0.2.1: ICMP echo request.*" \
	    cat pflog.txt

	# second ping is blocked
	atf_check -o match:".*rule 0/0\(match\): block in on ${epair}a: 192.0.2.2 > 192.0.2.1: ICMP echo request.*" \
	    cat pflog.txt

	# only two log lines shall be written
	atf_check -o match:2 grep -c . pflog.txt
}

max_cleanup()
{
	pft_cleanup
}

atf_test_case "rdr" "cleanup"
rdr_head()
{
        atf_set descr 'Test RDR rule logging'
        atf_set require.user root
}

rdr_body()
{
	j="pflog:rdr"
	epair_c=$(vnet_mkepair)
	epair_srv=$(vnet_mkepair)

	vnet_mkjail ${j}srv ${epair_srv}a
	vnet_mkjail ${j}gw ${epair_srv}b ${epair_c}a
	vnet_mkjail ${j}c ${epair_c}b

	jexec ${j}srv ifconfig ${epair_srv}a 198.51.100.1/24 up
	# No default route in srv jail, to ensure we're NAT-ing
	jexec ${j}gw ifconfig ${epair_srv}b 198.51.100.2/24 up
	jexec ${j}gw ifconfig ${epair_c}a 192.0.2.1/24 up
	jexec ${j}gw sysctl net.inet.ip.forwarding=1
	jexec ${j}c ifconfig ${epair_c}b 192.0.2.2/24 up
	jexec ${j}c route add default 192.0.2.1

	jexec ${j}gw pfctl -e
        jexec ${j}gw ifconfig pflog0 up
	pft_set_rules ${j}gw \
		"rdr log on ${epair_srv}b proto tcp from 198.51.100.0/24 to any port 1234 -> 192.0.2.2 port 1234" \
		"block quick inet6" \
		"pass in log"

        jexec ${j}gw tcpdump -n -e -ttt --immediate-mode -l -U -i pflog0 >> ${PWD}/pflog.txt &
        sleep 1 # Wait for tcpdump to start

	# send a SYN to catch in the log
        jexec ${j}srv nc -N -w 0 198.51.100.2 1234

        echo "Log"
        cat ${PWD}/pflog.txt

	# log line generated for rdr hit (pre-NAT)
	atf_check -o match:".*.*rule 0/0\(match\): rdr in on ${epair_srv}b: 198.51.100.1.[0-9]* > 198.51.100.2.1234: Flags \[S\].*" \
	    cat pflog.txt

	# log line generated for pass hit (post-NAT)
	atf_check -o match:".*.*rule 1/0\(match\): pass in on ${epair_srv}b: 198.51.100.1.[0-9]* > 192.0.2.2.1234: Flags \[S\].*" \
	    cat pflog.txt

	# only two log lines shall be written
	atf_check -o match:2 grep -c . pflog.txt
}

rdr_cleanup()
{
        pft_cleanup
}

atf_init_test_cases()
{
	atf_add_test_case "max"
	atf_add_test_case "rdr"
}
