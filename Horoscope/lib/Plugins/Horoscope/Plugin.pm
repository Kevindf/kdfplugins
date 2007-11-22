#
#	$Id: Plugin.pm,v 1.1 2007-11-07 07:45:51 fishbone Exp $
# Built on BBCNews.pm from Kevin Walsh
#
#
package Plugins::Horoscope::Plugin;
use File::Spec::Functions qw(catfile);
use Slim::Utils::Strings qw(string);
use FindBin qw($Bin);
use strict;

my $location = 'http://astrology.yahoo.com/astrology/general/dailyoverview/';
#my $location = catfile($Bin,'Plugins','horoscope.txt');

use vars qw($VERSION);
$VERSION = substr(q$Revision: 1.1 $,10);
#
#	specify the catagories you want and their display order
#	(see the @news_description array, below)
#
my @display_order = (0,1,2,3,4,5,6,7,8,9,10,11);

#
#	end of configurable variables
#

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugins',
	'defaultLevel' => 'WARN',
	'description'  => 'PLUGINs',
});


my $last_check;
my $last_update;
my @stars = ();
my %context;

my @signs = (
	[ 'aries',	[] ],
	[ 'taurus',	[] ],
	[ 'gemini',	[] ],
	[ 'cancer',	[] ],
	[ 'leo',	[] ],
	[ 'virgo',	[] ],
	[ 'libra',	[] ],
	[ 'scorpio',	[] ],
	[ 'sagittarius',[] ],
	[ 'capricorn',	[] ],
	[ 'aquarius',	[] ],
	[ 'pisces',	[] ],
);

my %functions = (
	'left' => sub {
		Slim::Buttons::Common::popModeRight(shift);
	},
	'right' => sub {
		Slim::Display::Animation::bumpRight(shift);
	},
	'up' => sub {
		my $client = shift;
	
		$context{$client} = Slim::Buttons::Common::scroll(
			$client,
			-1,
			$#display_order + 1,
			$context{$client} || 0,
		);
		$client->update();
	},
	'down' => sub {
		my $client = shift;
	
		$context{$client} = Slim::Buttons::Common::scroll(
			$client,
			1,
			$#display_order + 1,
			$context{$client} || 0,
		);
		$client->update();
	},
	'add' => sub {
		my $client = shift;
		$last_update = $last_check = undef;
		update($client);
	},
);

#
#	lines()
#	-------
#	Create and return the two-line display.  Also "fake" the IR time so
#	that the "screen saver" doesn't take over.
#
sub lines {
	my $client = shift;
	my @lines;

	#
	#	"Fake" the last remote control keypress time so the "screen saver"
	#	doesn't take over
	#
	Slim::Hardware::IR::setLastIRTime(
		$client,
		Time::HiRes::time() + (Slim::Utils::Prefs::clientGet($client, "screensavertimeout") * 5),
	);

	#
	#	check whether we need to re-read the news text file
	#
	if ($location =~ m|^http://|i) {
	#
	#	HTTP mode: only update the news if we don't have
	#	any extsting text
	#
		unless ($last_update) {
			$last_update = time();
			update($client);
		}
	} else {
	#
	#	file mode: check the news file's last update time
	#	every 60 seconds
	#
		if (!$last_check || (time() - $last_check) > 60) {

			$last_check = time();

			my $mtime = (stat($location))[9] || 0;
	
			#
			#	update the news if the file has been modified
			#	since we last read it
			#

			if (!$last_update || $mtime > $last_update) {
				$last_update = $mtime;
				update($client) if $mtime;
			}
		}
	}

	$context{$client} ||= 0;

	$lines[0] = (
		$client->string(getDisplayName()) .
		' (' .
		(($context{$client} || 0) + 1) .
		' ' .string('OF').' ' .
		($#display_order + 1) .
		') ' .
		uc($signs[$display_order[$context{$client}]][0])
	);
	
	if (exists($stars[$display_order[$context{$client}]])) {
		$lines[1] = $stars[$display_order[$context{$client}]];
	
	} else {
		$lines[1] = $client->string('PLUGIN_HOROSCOPE_NONE');
	}
	
	@lines;
}

#
#	update()
#	-------------
#	Overwrites the @stars with data collected from either the
#	remote HTTP URI or a text file, depending upon what is configured
#	into the $bbcnews_location variable.
#
sub update {
	my $client = shift;
	my $divider = $client->symbols('rightarrow') x 2;
	my $cur_sign = 0;
	my $cur_desc = '';
	my $buf;
	my @text = ();

	if ($location =~ m|^http://|i) {
		#
		Slim::Buttons::Block::block($client,$client->string('PLUGIN_HOROSCOPE_MODULE_NAME'),$client->string('PLUGIN_HOROSCOPE_UPDATING'));
	
		#	the location is a HTTP URI so open a socket to the remote
		#	webpage and collect the data
		for my $sign (@signs) {
			$log->info(sprintf("Grabbing %s",$sign->[0]));

			my $sock = Slim::Player::Protocols::HTTP->new({
				'url'     => "$location$sign->[0]",
				'create'  => 0,
				'timeout' => 5,
			});
			
			$buf = $sock ? $sock->content() : "";
			
			$sock->close();
			#	parse the raw news blocks out of the rest of the HTML
			$buf =~ s{
				Overview:\<\/b\>\<br\>(.*?)\n
			}{
				push(@{$sign->[1]},$1);
			}iegsx;
		}	
#
#	just send the news to the stdout for now
#
		for my $sign (@signs) {
			push(@text,uc($sign->[0]).":\n");
			push(@text,join("\n",@{$sign->[1]}) . "\n\n");
		}
		
		if (Slim::Buttons::Common::mode($client) eq 'block') {
			Slim::Buttons::Block::unblock($client);
		};
	} else {
		Slim::Display::Animation::showBriefly(
			$client,
			getDisplayName() . ' ' . $client->string('PLUGIN_HOROSCOPE_UPDATING')
		);
		#
		#	the location is not a HTTP URI so strip any leading
		#	protocol specification, such as "file://" from the location
		#	and treat the resulting string as a path to a text file
		#
		$location =~ s|^\w+://||i;
		
		open(FILE,$location) or return undef;
		push(@text,$_) while (<FILE>);
		close FILE;
	}
	
	@stars = ();
	
	#
	#	parse the data gathered in one of the above collection operations
	#	to create the @stars array
	#
	foreach (@text) {
		chomp;
		my $tmp = uc($signs[$cur_sign][0]);
		
		if (/$tmp\:/) {
			if ($cur_sign < 12) {$cur_sign++;}; #don't go past the end.
			next;
		} elsif ($_ eq "") {
			next
		} else {
			$stars[$cur_sign-1] .= "$_                                ";
		}
	}

	#	go through the @stars removing unnecessary whitespace and
	#	appending a long gap to the end of the news item
	#

	undef;
}


sub setMode {
	my $client = shift;

	update($client) unless $location =~ m|^http://|i;
	$client->lines(\&lines);
	$client->update();
}

sub getFunctions {
	\%functions;
}

sub getDisplayName {
	return 'PLUGIN_HOROSCOPE_MODULE_NAME';
}

1;


