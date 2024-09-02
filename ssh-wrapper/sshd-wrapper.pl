#!/usr/bin/perl -w

# run this from inetd or something similar

$allowusers='AllowUsers ';
@ssh_command = ('/usr/sbin/sshd','-i','-u0','-o',\$allowusers);
$timeout=300;

use Socket;
use FileHandle;
use Email::MessageID;
use Net::Domain qw(hostfqdn);
use Digest::MD5 md5_hex;

STDOUT->autoflush(1);

umask(0133);

alarm($timeout);

my $user;

$user=<>||'';
$user=~s/[\x0d\x0a]+$//;

if($user=~/^GET\s.*\sHTTP\/\d+\.\d+$/i){
#	print "Content-Type: text/plain\n\n";
	exec('/bin/cat','/usr/bin/ssh-wrapper') || die "exec(/bin/cat): $!";
}

$mid=Email::MessageID->new(host => 
	sprintf("%8.8x.".hostfqdn(),rand(4294967295)));

print $mid,"\n";
my ($name,$passwd,$uid,$gid,
	$quota,$comment,$gcos,$dir,$shell,$expire)
	= getpwnam($user);

if (!defined $uid
||  !$shell
||   $shell =~ m,/false,){exit 1}

#print "$name,$dir,",join(':',@perms),",$shell\n";

$allowusers .= $user;

if(!open(F,'<',"$dir/.config/ssh-passwd2")){exit 1};
($passwd=readline(F))=~s/[\x0d\x0a]+$//;
close(F);

if(!$passwd){exit 1};
$digest=md5_hex("$mid$passwd");

my $digest_in=<>||'';
$digest_in=~s/[\x0d\x0a]+$//;;

if($digest ne $digest_in){
	print STDERR "Password mismatch for user $user\n";
	exit 1
}

map {if(defined ${$_}){$_=${$_}}} @ssh_command;

alarm(0);

exec {$ssh_command[0]} @ssh_command;
