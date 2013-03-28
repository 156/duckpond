#!/usr/bin/perl

use Getopt::Std;

use POE;
use POE::Component::IRC;

my %options=();

getopts("hdc:", \%options);

my $option_length = 9; #ammount of options split by : in config file

my ($configfile, $debug, $max_proc, $pm, @ircs);

# check options

if (defined $options{h})
{
	print "-h help (this command)\n";
	die;
}

if (defined $options{d})
{
	$debug=1;
}

if (defined $options{c})
{
	$configfile = $options{c};
	delete $options{c};
} else { die("need -c <config>"); }

if (!-e $configfile) { die("can't open config"); }

open_config($configfile);

$poe_kernel->run();
exit 0;

sub open_config
{
	($file) = @_;

	open FD, "$file";

	if ($debug) { print "open_config: $file\n"; }

	my @configlines = <FD>;

	close (FD);

	$max_proc = @configlines;

	if ($debug) { print "open_config max_proc: $max_proc\n"; }

	foreach (@configlines)
	{

		parse_config ($_);

	}

}

sub parse_config
{
	($line) = @_;
	
	chomp($line);

	my @option_values = split(/:/, $line);

	if (@option_values ne $option_length) { return 0; }

	my ($l, $n, $cs, $i, $u, $s, $p, $rx, $tx) = @option_values;

	my $irc = POE::Component::IRC->spawn();

	my @c = split(/,/, $cs);

	POE::Session->create(
		inline_states => {
			_start => sub {
				$_[HEAP]->{irc}->yield(register => 'all');
				$_[HEAP]->{irc}->yield(
					connect => {
						Nick     => $n,
						Username => $u,
						Ircname  => $i,
						Server   => $s,
						Port     => $p,
					});
			},

			irc_255 => sub {
				foreach($_[HEAP]->{channels})
				{
					$_[HEAP]->{irc}->yield(join => $_);
				}
			},

			irc_public => \&on_public,
		},
		heap => {
			irc => $irc,
			label => $l,
			nickname => $n,
			channels => @c,
			username => $u,
			ircname => $i,
			server => $s,
			port => $p,
			rx => $rx,
			tx => $tx
			}
		);

	if ($debug) {
		print "parse_config: $line got values: " . @option_values . "\n";
		print "parse_config nickname: $n\n";
		print "parse_config channels: " . @c . " - \"$cs\"\n";
		print "parse_config username: $u\n";
		print "parse_config ircname: $i\n";
		print "parse_config server: $s\n";
		print "parse_config port: $p\n";
		print "parse_config rx: $rx\n";
		print "parse_config tx: $tx\n";
	}

	if ($rx) { push (@ircs, ({irc => $irc, server => $s, rx => $rx, channels => $cs})); }
}


# irc events

sub on_public
{
	my ($kernel, $heap, $who, $where, $msg) = @_[KERNEL, HEAP, ARG0, ARG1, ARG2];

	my $nick    = (split /!/, $who)[0];
	my $channel = $where->[0];



	my $output = "<" . $nick . ":" . $channel . ":" . $heap->{label} . "> $msg";
	#my $output = "<" . $nick . ":" . $channel . "> $msg";

	tx_send($heap, $heap->{irc}->{server}, $output);

}

sub tx_send
{
	($heap, $server, $output) = @_;

	foreach $ircobj (@ircs) {
		if ($server ne $ircobj->{server})
		{
			my @cc = split(/,/,$ircobj->{channels});
			my $irc = $ircobj->{irc};

			print $server . ":" . $ircobj->{server} . "\n";

			foreach $channel (@cc)
			{
				$irc->yield(privmsg => $channel, $output);
			}
		}
	}

}