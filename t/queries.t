#! /usr/bin/perl
use 5.006;
use strict;
use warnings;

use Data::MessagePack;
use IO::Socket::INET;
use Data::Dump qw(dd pp);
use Time::HiRes;
use FindBin;
use Socket ':all';
use Test::More;
use Sys::Hostname;

use constant RT_SETOPT    => 1;
use constant RT_GETOPT    => 2;
use constant RT_INFO      => 3;
use constant RT_GET       => 4;
use constant RT_GETTABLE  => 5;
use constant RT_DEST_INFO => 6;
use constant RT_REPLY     => 0x10;
use constant RT_ERROR     => 0x20;

sub THERE () { return bless \my $dummy, 't::Present' }
our $NUMBER = qr/^\d+$/;
our $NON_ZERO = qr/^[1-9]\d*$/;

my @GLOBAL_STATS = qw(
active_cid_infos
active_client_connections
active_cr_infos
active_oid_infos
active_sid_infos
active_timers_sec
active_timers_usec
bad_snmp_responses
client_requests
destination_ignores
destination_throttles
get_requests
getopt_requests
gettable_requests
global_throttles
good_snmp_responses
info_requests
invalid_requests
max_packets_on_the_wire
oids_ignored
oids_non_increasing
oids_requested
oids_returned_from_snmp
oids_returned_to_client
octets_received
octets_sent
packets_on_the_wire
setopt_requests
snmp_retries
snmp_sends
snmp_timeouts
snmp_v1_sends
snmp_v2c_sends
total_cid_infos
total_client_connections
total_cr_infos
total_oid_infos
total_sid_infos
total_timers_sec
total_timers_usec
udp_receive_buffer_size
udp_send_buffer_size
udp_send_buffer_overflow
udp_timeouts
uptime
program_version
);

my @CLIENT_STATS = qw(
active_cid_infos
active_cr_infos
active_sid_infos
client_requests
get_requests
getopt_requests
gettable_requests
good_snmp_responses
info_requests
invalid_requests
oids_non_increasing
oids_requested
oids_returned_from_snmp
oids_returned_to_client
setopt_requests
snmp_retries
snmp_sends
snmp_timeouts
snmp_v1_sends
snmp_v2c_sends
total_cid_infos
total_cr_infos
total_sid_infos
udp_timeouts
uptime
);
my %CLIENT_STATS = map { $_ => $NUMBER } @CLIENT_STATS;
my %GLOBAL_STATS = map { $_ => $NUMBER } @GLOBAL_STATS;
$CLIENT_STATS{oids_non_increasing} = 0;
$GLOBAL_STATS{oids_non_increasing} = 0;

my $daemon_pid;
if (!($daemon_pid = fork)) {
	exec("$FindBin::Bin/../snmp-query-engine", "-p7668", "-q");
	exit;  # unreach
}

Time::HiRes::sleep(0.2);
our $mp = Data::MessagePack->new()->prefer_integer;
our $conn = IO::Socket::INET->new(PeerAddr => "127.0.0.1:7668", Proto => "tcp")
	or die "cannot connect to snmp-query-engine daemon: $!\n";

$mp->utf8(1);
request_match("defaults via getopt", [RT_GETOPT,2000,"127.0.0.1",161], [RT_GETOPT|RT_REPLY,2000,
	{ip=>"127.0.0.1", port=>161, community=>"public", version=>2, max_packets => 3, max_req_size => 1400, timeout => 2000, retries => 3, min_interval => 10, max_repetitions => 10, ignore_threshold => 0, ignore_duration => 300000, max_reply_size => 1472, estimated_value_size => 9, max_oids_per_request => 64 }]);
$mp->utf8(0);
request_match("defaults via setopt", [RT_SETOPT,2001,"127.0.0.1",161, {}], [RT_SETOPT|RT_REPLY,2001,
	{ip=>"127.0.0.1", port=>161, community=>"public", version=>2, max_packets => 3, max_req_size => 1400, timeout => 2000, retries => 3, min_interval => 10, max_repetitions => 10, ignore_threshold => 0, ignore_duration => 300000, max_reply_size => 1472, estimated_value_size => 9, max_oids_per_request => 64 }]);
request_match("setopt bad length", [RT_SETOPT,2002,"127.0.0.1",161], [RT_SETOPT|RT_ERROR,2002,qr/bad request length/]);
request_match("setopt bad port 1", [RT_SETOPT,2003,"127.0.0.1","x",{}], [RT_SETOPT|RT_ERROR,2003,qr/bad port number/]);
request_match("setopt bad port 2", [RT_SETOPT,2004,"127.0.0.1",80000,{}], [RT_SETOPT|RT_ERROR,2004,qr/bad port number/]);
request_match("setopt bad IP", [RT_SETOPT,2005,"127.260.0.1",161,{}], [RT_SETOPT|RT_ERROR,2005,qr/bad IP/]);
request_match("setopt opt not map 1", [RT_SETOPT,2006,"127.0.0.1",161,[]], [RT_SETOPT|RT_ERROR,2006,qr/not a map/]);
request_match("setopt opt not map 2", [RT_SETOPT,2007,"127.0.0.1",161,42], [RT_SETOPT|RT_ERROR,2007,qr/not a map/]);
request_match("setopt bad option key", [RT_SETOPT,2008,"127.0.0.1",161,{meow=>1}], [RT_SETOPT|RT_ERROR,2008,qr/bad option key/]);
request_match("setopt bad version 1", [RT_SETOPT,2009,"127.0.0.1",161,{version=>42}], [RT_SETOPT|RT_ERROR,2009,qr/invalid SNMP version/]);
request_match("setopt bad version 2", [RT_SETOPT,2010,"127.0.0.1",161,{version=>"x"}], [RT_SETOPT|RT_ERROR,2010,qr/invalid SNMP version/]);
request_match("setopt bad community", [RT_SETOPT,2011,"127.0.0.1",161,{community=>[]}], [RT_SETOPT|RT_ERROR,2011,qr/invalid SNMP community/]);
request_match("setopt bad max_packets 1", [RT_SETOPT,2012,"127.0.0.1",161,{max_packets=>"meow"}], [RT_SETOPT|RT_ERROR,2012,qr/invalid max packets/]);
request_match("setopt bad max_packets 2", [RT_SETOPT,2013,"127.0.0.1",161,{max_packets=>0}], [RT_SETOPT|RT_ERROR,2013,qr/invalid max packets/]);
request_match("setopt bad max_packets 3", [RT_SETOPT,2014,"127.0.0.1",161,{max_packets=>30000}], [RT_SETOPT|RT_ERROR,2014,qr/invalid max packets/]);
request_match("setopt bad global_max_packets 1", [RT_SETOPT,42012,"127.0.0.1",161,{global_max_packets=>"meow"}], [RT_SETOPT|RT_ERROR,42012,qr/invalid global max packets/]);
request_match("setopt bad global_max_packets 2", [RT_SETOPT,42013,"127.0.0.1",161,{global_max_packets=>0}], [RT_SETOPT|RT_ERROR,42013,qr/invalid global max packets/]);
request_match("setopt bad global_max_packets 3", [RT_SETOPT,42014,"127.0.0.1",161,{global_max_packets=>3000000}], [RT_SETOPT|RT_ERROR,42014,qr/invalid global max packets/]);
request_match("setopt bad max req size 1", [RT_SETOPT,2015,"127.0.0.1",161,{max_req_size=>"foo"}], [RT_SETOPT|RT_ERROR,2015,qr/invalid max request size/]);
request_match("setopt bad max req size 2", [RT_SETOPT,2016,"127.0.0.1",161,{max_req_size=>480}], [RT_SETOPT|RT_ERROR,2016,qr/invalid max request size/]);
request_match("setopt bad max req size 3", [RT_SETOPT,2017,"127.0.0.1",161,{max_req_size=>52000}], [RT_SETOPT|RT_ERROR,2017,qr/invalid max request size/]);
request_match("setopt bad timeout 1", [RT_SETOPT,2018,"127.0.0.1",161,{timeout=>"st"}], [RT_SETOPT|RT_ERROR,2018,qr/invalid timeout/]);
request_match("setopt bad timeout 2", [RT_SETOPT,2019,"127.0.0.1",161,{timeout=>31000}], [RT_SETOPT|RT_ERROR,2019,qr/invalid timeout/]);
request_match("setopt bad retries 1", [RT_SETOPT,2020,"127.0.0.1",161,{retries=>"foo"}], [RT_SETOPT|RT_ERROR,2020,qr/invalid retries/]);
request_match("setopt bad retries 2", [RT_SETOPT,2021,"127.0.0.1",161,{retries=>0}], [RT_SETOPT|RT_ERROR,2021,qr/invalid retries/]);
request_match("setopt bad retries 3", [RT_SETOPT,2022,"127.0.0.1",161,{retries=>12}], [RT_SETOPT|RT_ERROR,2022,qr/invalid retries/]);
request_match("setopt bad min interval 1", [RT_SETOPT,2120,"127.0.0.1",161,{min_interval=>"foo"}], [RT_SETOPT|RT_ERROR,2120,qr/invalid min interval/]);
request_match("setopt bad min interval 2", [RT_SETOPT,2122,"127.0.0.1",161,{min_interval=>10002}], [RT_SETOPT|RT_ERROR,2122,qr/invalid min interval/]);
request_match("setopt bad max repetitions 1", [RT_SETOPT,2220,"127.0.0.1",161,{max_repetitions=>"foo"}], [RT_SETOPT|RT_ERROR,2220,qr/invalid max repetitions/]);
request_match("setopt bad max repetitions 2", [RT_SETOPT,2221,"127.0.0.1",161,{max_repetitions=>0}], [RT_SETOPT|RT_ERROR,2221,qr/invalid max repetitions/]);
request_match("setopt bad max repetitions 3", [RT_SETOPT,2222,"127.0.0.1",161,{max_repetitions=>256}], [RT_SETOPT|RT_ERROR,2222,qr/invalid max repetitions/]);
request_match("defaults unchanged", [RT_SETOPT,2023,"127.0.0.1",161, {}], [RT_SETOPT|RT_REPLY,2023,
	{ip=>"127.0.0.1", port=>161, community=>"public", version=>2, max_packets => 3, max_req_size => 1400, timeout => 2000, retries => 3, min_interval => 10, max_repetitions => 10, }]);
request_match("change timeout", [RT_SETOPT,2024,"127.0.0.1",161, {timeout=>1500}], [RT_SETOPT|RT_REPLY,2024,
	{ip=>"127.0.0.1", port=>161, community=>"public", version=>2, max_packets => 3, max_req_size => 1400, timeout => 1500, retries => 3, min_interval => 10, max_repetitions => 10, }]);
request_match("correct timeout via getopt", [RT_GETOPT,2025,"127.0.0.1",161], [RT_GETOPT|RT_REPLY,2025,
	{ip=>"127.0.0.1", port=>161, community=>"public", version=>2, max_packets => 3, max_req_size => 1400, timeout => 1500, retries => 3, min_interval => 10, max_repetitions => 10, }]);

request_match("bad request: not an array 1", {x=>1}, [RT_ERROR,0,qr/not an array/]);
request_match("bad request: not an array 2", 55, [RT_ERROR,0,qr/not an array/]);
request_match("bad request: not an array 3", "hello", [RT_ERROR,0,qr/not an array/]);
request_match("bad request: empty array", [], [RT_ERROR,0,qr/empty array/]);
request_match("bad request: no id", [RT_GET], [RT_ERROR,0,qr/without an id/]);
request_match("bad request: bad id 1", [RT_GET,-1], [RT_ERROR,0,qr/id is not a positive integer/]);
request_match("bad request: bad id 2", [RT_GET,"heps"], [RT_ERROR,0,qr/id is not a positive integer/]);
request_match("bad request: bad type 1", [-1,12], [RT_ERROR,12,qr/type is not a positive integer/]);
request_match("bad request: bad type 2", ["heps",13], [RT_ERROR,13,qr/type is not a positive integer/]);
request_match("bad request: unknown type", [9,14], [RT_ERROR|9,14,qr/unknown request type/i]);
request_match("bad request length 1", [RT_GET,15,"127.0.0.1",161, 2, "public"], [RT_GET|RT_ERROR,15,qr/bad request length/i]);
request_match("bad request length 2", [RT_GET,16,"127.0.0.1",161, 2, "public", ["1.3.6.1.2.1.1.5.0"], "heh", "heh"],
			  [RT_GET|RT_ERROR,16,qr/bad request length/i]);
request_match("bad port number #1", [RT_GET,17,"127.0.0.1",-2, ["1.3.6.1.2.1.1.5.0"]], [RT_GET|RT_ERROR,17,qr/bad port number/i]);
request_match("bad port number #2", [RT_GET,18,"127.0.0.1",[], ["1.3.6.1.2.1.1.5.0"]], [RT_GET|RT_ERROR,18,qr/bad port number/i]);
request_match("bad port number #3", [RT_GET,19,"127.0.0.1",66666, ["1.3.6.1.2.1.1.5.0"]], [RT_GET|RT_ERROR,19,qr/bad port number/i]);
request_match("bad IP 1", [RT_GET,21,666,161, ["1.3.6.1.2.1.1.5.0"]], [RT_GET|RT_ERROR,21,qr/bad IP/i]);
request_match("bad IP 2", [RT_GET,22,[],161, ["1.3.6.1.2.1.1.5.0"]], [RT_GET|RT_ERROR,22,qr/bad IP/i]);
request_match("bad IP 3", [RT_GET,23,"257.12.22.13",161, ["1.3.6.1.2.1.1.5.0"]], [RT_GET|RT_ERROR,23,qr/bad IP/i]);
request_match("oids is not an array 1", [RT_GET,24,"127.0.0.1",161, 42], [RT_GET|RT_ERROR,24,qr/oids must be an array/i]);
request_match("oids is not an array 2", [RT_GET,25,"127.0.0.1",161, {}], [RT_GET|RT_ERROR,25,qr/oids must be an array/i]);
request_match("oids is not an array 3", [RT_GET,26,"127.0.0.1",161, "oids"], [RT_GET|RT_ERROR,26,qr/oids must be an array/i]);
request_match("oids is an empty array", [RT_GET,27,"127.0.0.1",161, []], [RT_GET|RT_ERROR,27,qr/oids is an empty array/i]);

request_match("destinfo length 1", [RT_DEST_INFO,6600], [RT_DEST_INFO|RT_ERROR, 6600, qr/bad request length/i]);
request_match("destinfo length 2", [RT_DEST_INFO,6600,"127.0.0.1"], [RT_DEST_INFO|RT_ERROR, 6600, qr/bad request length/i]);
request_match("destinfo port 1", [RT_DEST_INFO,6601,"127.0.0.1",-2], [RT_DEST_INFO|RT_ERROR, 6601, qr/bad port number/i]);
request_match("destinfo port 2", [RT_DEST_INFO,6602,"127.0.0.1",[]], [RT_DEST_INFO|RT_ERROR, 6602, qr/bad port number/i]);
request_match("destinfo port 3", [RT_DEST_INFO,6603,"127.0.0.1",66666], [RT_DEST_INFO|RT_ERROR, 6603, qr/bad port number/i]);
request_match("destinfo ip 1", [RT_DEST_INFO,6611,666,161], [RT_DEST_INFO|RT_ERROR, 6611, qr/bad IP/i]);
request_match("destinfo ip 2", [RT_DEST_INFO,6612,[],161], [RT_DEST_INFO|RT_ERROR, 6612, qr/bad IP/i]);
request_match("destinfo ip 3", [RT_DEST_INFO,6613,"257.12.22.13",161], [RT_DEST_INFO|RT_ERROR, 6613, qr/bad IP/i]);

request_match("destinfo zero", [RT_DEST_INFO,6620,"127.0.0.1",161], [RT_DEST_INFO|RT_REPLY, 6620,
			  { octets_received => 0, octets_sent => 0}]);

my $target   = "127.0.0.1";
my $hostname = hostname;
my $uptime   = qr/^\d+$/;
my $r;

$r = request([RT_GET,33,$target,161, ["1.3.6.1.2.1.1.5.0"]]);
if ($r->[0] != (RT_GET|RT_REPLY) || ref $r->[2][0][1]) {
	print STDERR "\n\n=====\n=====\n";
	print STDERR "=====> Skipping remaining tests, need running local snmpd on port 161\n";
	print STDERR "=====> with \"public\" community.\n";
	print STDERR "=====\n=====\n\n";
	goto bailout;
}

$r = request_match("change community to a bad one", [RT_SETOPT,3000,$target,161, {community=>1234, ignore_threshold => 1, timeout => 1500, retries => 2, ignore_duration => 2000}], [RT_SETOPT|RT_REPLY,3000,
	{ip=>$target, port=>161, community=>1234, version=>2, max_packets => 3, max_req_size => 1400, timeout => 1500, retries => 2, min_interval => 10, max_repetitions => 10, ignore_threshold => 1, ignore_duration => 2000 }]);

$r = request([RT_INFO,2252]);
is($r->[2]{global}{destination_ignores}, 0, "ignored destinations 0");
is($r->[2]{global}{oids_ignored}, 0, "ignored oids 0");
is($r->[2]{global}{max_packets_on_the_wire}, 1_000_000, "default global max packets");

$r = request([RT_SETOPT,42016,"127.0.0.1",161,{global_max_packets=>100_000}]);

request_match("times out", [RT_GET,41,$target,161, ["1.3.6.1.2.1.1.5.0"]],
			  [RT_GET|RT_REPLY,41,[["1.3.6.1.2.1.1.5.0",["timeout"]]]]);
for my $id (2241..2250) {
	$mp->utf8(!$mp->get_utf8);
	request_match("ignored $id", [RT_GET,$id,$target,161, ["1.3.6.1.2.1.1.5.0"]],
				  [RT_GET|RT_REPLY,$id,[["1.3.6.1.2.1.1.5.0",["ignored"]]]]);
}
$mp->utf8(0);
$r = request([RT_INFO,2251]);
is($r->[2]{global}{destination_ignores}, 1, "ignored destinations");
is($r->[2]{global}{oids_ignored}, 10, "ignored oids");
is($r->[2]{global}{max_packets_on_the_wire}, 100_000, "global max packets changed ok");

request_match("change community to a good one", [RT_SETOPT,2253,$target,161, {community=>"public"}], [RT_SETOPT|RT_REPLY,2253,
	{ip=>$target, port=>161, community=>"public", version=>2, max_packets => 3, max_req_size => 1400, timeout => 1500, retries => 2, min_interval => 10, max_repetitions => 10, ignore_threshold => 1, ignore_duration => 2000}]);

sleep 2;

request_match("past ignore interval", [RT_GET,2254,$target,161, ["1.3.6.1.2.1.1.5.0", ".1.3.6.1.2.1.25.1.1.0", "1.3.66"]],
			  [RT_GET|RT_REPLY,2254,[
			  ["1.3.6.1.2.1.1.5.0",$hostname],
			  ["1.3.6.1.2.1.25.1.1.0",$uptime],
			  ["1.3.66",["no-such-object"]]]]);

$r = request([RT_INFO,2255]);
is($r->[2]{global}{destination_ignores}, 1, "ignored destinations did not change");
is($r->[2]{global}{oids_ignored}, 10, "ignored oids did not change");

request_match("switch off ignoring", [RT_SETOPT,3001,$target,161, {ignore_threshold => 0}], [RT_SETOPT|RT_REPLY,3001,
	{ip=>$target, port=>161, community=>"public", version=>2, max_packets => 3, max_req_size => 1400, timeout => 1500, retries => 2, min_interval => 10, max_repetitions => 10, ignore_threshold => 0, ignore_duration => 2000}]);

request_match("all is good", [RT_GET,42,$target,161, ["1.3.6.1.2.1.1.5.0", ".1.3.6.1.2.1.25.1.1.0", "1.3.66"]],
			  [RT_GET|RT_REPLY,42,[
			  ["1.3.6.1.2.1.1.5.0",$hostname],
			  ["1.3.6.1.2.1.25.1.1.0",$uptime],
			  ["1.3.66",["no-such-object"]]]]);

request_match("3rd time lucky", [RT_GET,110,$target,161, ["1.3.6.1.2.1.1.5.0", "1.3.6.1.2.1.1.5.0", "1.3.6.1.2.1.1.5.0"]],
			  [RT_GET|RT_REPLY,110,[
			  ["1.3.6.1.2.1.1.5.0",$hostname],
			  ["1.3.6.1.2.1.1.5.0",$hostname],
			  ["1.3.6.1.2.1.1.5.0",$hostname],
			  ]]);

request_match("change version to SNMP v1", [RT_SETOPT,3002,$target,161, {version=>1}], [RT_SETOPT|RT_REPLY,3002,
	{ip=>$target, port=>161, community=>"public", version=>1, max_packets => 3, max_req_size => 1400, timeout => 1500, retries => 2, min_interval => 10, max_repetitions => 10, }]);

$r = request_match("try request SNMP v1", [RT_GET,43,$target,161, ["1.3.6.1.2.1.1.5.0", ".1.3.6.1.2.1.25.1.1.0", "1.3.66"]],
			  [RT_GET|RT_REPLY,43,[
			  ["1.3.6.1.2.1.1.5.0",["noSuchName"]],
			  ["1.3.6.1.2.1.25.1.1.0",["noSuchName"]],
			  ["1.3.66",["noSuchName"]]]]);

$r = request_match("ifDescr SNMPv1 table", [RT_GETTABLE,555,$target,161,"1.3.6.1.2.1.2.2.1.2"], [RT_GETTABLE|RT_REPLY,555,THERE]);

request_match("change version back to SNMP v2", [RT_SETOPT,3003,$target,161, {version=>2}], [RT_SETOPT|RT_REPLY,3003,
	{ip=>$target, port=>161, community=>"public", version=>2, max_packets => 3, max_req_size => 1400, timeout => 1500, retries => 2, min_interval => 10, max_repetitions => 10, }]);

$r = request_match("ifDescr SNMPv2c table", [RT_GETTABLE,3200,$target,161,"1.3.6.1.2.1.2.2.1.2"], [RT_GETTABLE|RT_REPLY,3200,THERE]);
my $first_ifindex = $r->[2][0][0];  $first_ifindex =~ s/.*\.(\d+)$/$1/;

my $rr = request_match("ifDescr table small reps", [RT_GETTABLE,3201,$target,161,"1.3.6.1.2.1.2.2.1.2",4], [RT_GETTABLE|RT_REPLY,3201,THERE]);
match("small reps same", $r->[2], $rr->[2]);
$rr = request_match("ifDescr table large reps", [RT_GETTABLE,3202,$target,161,"1.3.6.1.2.1.2.2.1.2",20], [RT_GETTABLE|RT_REPLY,3202,THERE]);
match("large reps same", $r->[2], $rr->[2]);

lone_request([RT_GET,3500,$target,161, ["1.3.6.1.2.1.1.5.0"]]);
lone_request([RT_GET,3501,$target,161, [".1.3.6.1.2.1.25.1.1.0"]]);
Time::HiRes::sleep(0.5);
my ($r1,$r2) = bulk_response();
if ($r1->[1] == 3501) {
	($r1, $r2) = ($r2, $r1);
}
match("combined req1", $r1, [RT_GET|RT_REPLY,3500,[["1.3.6.1.2.1.1.5.0",$hostname]]]);
match("combined req2", $r2, [RT_GET|RT_REPLY,3501,[["1.3.6.1.2.1.25.1.1.0",$uptime]]]);

$r = request([RT_INFO,3555]);
my $snmp_sends = $r->[2]{global}{snmp_sends};
multi_request(
	[RT_GET,3502,$target,161, ["1.3.6.1.2.1.1.5.0"]],
	[RT_GET,3503,$target,161, [".1.3.6.1.2.1.25.1.1.0"]],
	[RT_GET,3504,$target,161, ["1.3.6.1.2.1.2.1.0"]],
	[RT_GET,3505,$target,161, ["1.3.6.1.2.1.2.2.1.1.$first_ifindex"]],
);
Time::HiRes::sleep(0.5);
my @r = sort { $a->[1] <=> $b->[1] } bulk_response();
match("multi combined req1", $r[0], [RT_GET|RT_REPLY,3502,[["1.3.6.1.2.1.1.5.0",$hostname]]]);
match("multi combined req2", $r[1], [RT_GET|RT_REPLY,3503,[["1.3.6.1.2.1.25.1.1.0",$uptime]]]);
match("multi combined req3", $r[2], [RT_GET|RT_REPLY,3504,[["1.3.6.1.2.1.2.1.0",$NUMBER]]]);
match("multi combined req4", $r[3], [RT_GET|RT_REPLY,3505,[["1.3.6.1.2.1.2.2.1.1.$first_ifindex",$first_ifindex]]]);
$r = request([RT_INFO,3556]);
#print STDERR ">>>> SENDS 4 clients, ", $r->[2]{global}{snmp_sends}-$snmp_sends, " SNMP, $r->[2]{global}{udp_timeouts}($r->[2]{global}{snmp_timeouts}) timeouts in total\n";
# TODO is($r->[2]{global}{snmp_sends}-$snmp_sends, 2, "4 client requests in 2 SNMP requests");

$r = request_match("stats", [RT_INFO,5000], [RT_INFO|RT_REPLY,5000,
	{ connection => \%CLIENT_STATS,
	  global => \%GLOBAL_STATS}]);
#print STDERR "OIDS requested: $r->[2]{connection}{oids_requested}\n";

request_match("destinfo non-zero", [RT_DEST_INFO,6630,"127.0.0.1",161], [RT_DEST_INFO|RT_REPLY, 6630,
			  { octets_received => $NON_ZERO, octets_sent => $NON_ZERO}]);

bailout:
Time::HiRes::sleep(0.2);
close $conn;
Time::HiRes::sleep(0.2);
END { kill 15, $daemon_pid if $daemon_pid };

done_testing;

sub request_match
{
	my ($t, $req, $mat) = @_;
	my $res = request($req);
	match($t, $res, $mat);
	return $res;
}

sub request
{
	my $d = shift;
	my $p = $mp->pack($d);
	$conn->syswrite($p);
	my $reply = "";
	$conn->sysread($reply, 65536);
	$mp->unpack($reply);
}

sub lone_request
{
	my $d = shift;
	my $p = $mp->pack($d);
	$conn->syswrite($p);
}

sub multi_request
{
	my @d = @_;
	my $p = "";
	for my $d (@d) {
		$p .= $mp->pack($d);
	}
	$conn->syswrite($p);
}

sub bulk_response
{
	my $reply;
	$conn->sysread($reply, 65536);
	my $up = Data::MessagePack::Unpacker->new;
	my $offset = 0;
	my @r;
	while( $offset < length($reply) ) {
		$offset = $up->execute($reply, $offset);
		push @r, $up->data;
		$up->reset;
		$reply = substr($reply, $offset);
		$offset = 0;
	}
	return @r;
}

sub match
{
	my ($t, $result, $template) = @_;
	if (!ref $result && !ref $template) {
		is($result, $template, "$t: matches");
		return;
	}
	if (ref $template && ref $template eq "Regexp") {
		like($result, $template, "$t: matches");
		return;
	}
	if (ref $template && ref $template eq "Test::Deep::Regexp") {
		like($result, $template->{val}, "$t: matches");
		return;
	}
	if (ref $template && ref $template eq "t::Present") {
		# ok if we got that far
		return;
	}
	unless (ref $result && ref $template) {
		fail("$t: apples to oranges");
		return;
	}
	my $tt = $t;
	$tt .= ": " unless $tt =~ /[\]}]$/;
	if (is(ref($result), ref($template), "$t: same reftype")) {
		if (UNIVERSAL::isa($result, "HASH")) {
			for my $k (keys %$template) {
				if (ok(exists $result->{$k}, "$t: \"$k\" exists")) {
					match("$tt\{$k}", $result->{$k}, $template->{$k});
				}
			}
		} elsif (UNIVERSAL::isa($result, "ARRAY")) {
			if (ok(@$result == @$template, "$t: array size matches")) {
				for my $i (0..$#$result) {
					match("$tt\[$i]", $result->[$i], $template->[$i]);
				}
			}
		}
	}
}
