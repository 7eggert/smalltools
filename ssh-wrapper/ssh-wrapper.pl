#!/usr/bin/perl -w

$ssh='/usr/bin/ssh';
$ssh_wrapper='/usr/bin/ssh-wrapper';

use Socket;
use FileHandle;
use Digest::MD5 md5_hex;
use IO::Select;
use IO::Handle;
$|=1;

if($ARGV[0] eq '--internal-callback'){
	my ($user,$host,$port)=@ARGV[1..3];
	
	my $iaddr   = inet_aton($host) || die "can't get IP for $host";
	my $proto   = getprotobyname('tcp');
	my $paddr   = sockaddr_in($port, $iaddr);
	socket(SOCK, PF_INET, SOCK_STREAM, $proto)  || die "socket: $!";
	connect(SOCK, $paddr)    || die "connect to $host:$port: $!";
	SOCK->autoflush(1);

	open(TTY,'+<','/dev/tty');
	print TTY "Password: ";
	print SOCK $user,"\n";
	system("stty -F /dev/tty -echo");
	$passwd=<TTY>;
	system("stty -F /dev/tty echo");
	print TTY "\n";
	chomp($passwd);
	$mid=<SOCK>;
	chomp($mid);

	$digest=md5_hex("$mid$passwd");
	print SOCK $digest,"\n";
	binmode(SOCK);
	
	my $sto  = IO::Handle->new_from_fd(fileno(STDOUT),"w");
	my $sti  = IO::Handle->new_from_fd(fileno(STDIN), "r");
	my $pxy  = IO::Handle->new_from_fd(fileno(SOCK), "r+");
	my $rsel = IO::Select->new($pxy,$sti);
	my $wsel = IO::Select->new($pxy,$sto);
	
	$$pxy->{'wbuf'} = "";
	$$sto->{'wbuf'} = "";
	
	sub finished { die "$0: Connection closed.\n"; }
	
	$$pxy->{'can_write'} = sub {
		my $bw = $pxy->syswrite($$pxy->{'wbuf'},length $$pxy->{'wbuf'});
		substr($$pxy->{'wbuf'},0,$bw,'');
		$wsel->remove($pxy) unless length $$pxy->{'wbuf'};
	};
	
	$$sto->{'can_write'} = sub {
		my $bw = $sto->syswrite($$sto->{'wbuf'},length $$sto->{'wbuf'});
		substr($$sto->{'wbuf'},0,$bw,'');
		$wsel->remove($sto) unless length $$sto->{'wbuf'};
	};
	
	$$sti->{'can_read'} = sub {
		$sti->sysread($$pxy->{'wbuf'},1024,length $$pxy->{'wbuf'}) || finished;
		$wsel->add($pxy);
	};
	
    $$pxy->{'can_read'} = sub { # Redefine for 2nd time
    	$pxy->sysread($$sto->{'wbuf'},1024,length $$sto->{'wbuf'}) || finished;
    	$wsel->add($sto);
	};
	# Loop forever
	while (my ($r,$w) = IO::Select::select($rsel,$wsel)) {
		foreach my $i (@$r) { $$i->{'can_read'}->()  }
		foreach my $o (@$w) { $$o->{'can_write'}->() }
	}

} else {
	my $user;
	my $a;
	for (@ARGV){if(!(/^-/)){$a=$_;last}}
	if($a=~/^-/){exit 1}
	(my $host=$a)=~s/.*@//;
	$a=~/^(\S+)@\S+$/;
	if(!($user=$1)
	&& !defined ($user=$ENV{'USER'})
	&& !defined ($user=(getpwuid($<))[0])){exit 1}
	
	($prg=$ssh_wrapper)=~s/'/'\\''/; #'
	($user2=$user)=~s/'/'\\''/; #'
	exec {$ssh} ($ssh,'-o', "User=$user", '-o', "ProxyCommand '$prg' --internal-callback '$user2' %h %p", @ARGV);
}
