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

atf_init_test_cases()
{
	atf_add_test_case "max"
}
