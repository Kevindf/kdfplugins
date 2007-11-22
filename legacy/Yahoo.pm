#
#	$Id: Yahoo.pm,v 1.1 2006-04-29 08:39:27 fishbone Exp $
# Built on BBCNews.pm from Kevin Walsh
#
#
package Plugins::Yahoo;
use File::Spec::Functions qw(catfile);
use Slim::Utils::Strings qw(string);
use FindBin qw($Bin);
use strict;

#my $news_location = 'http://ca.my.yahoo.com/';
my $news_location = catfile($Bin,'Plugins','yahoo.txt');

use vars qw($VERSION);
$VERSION = substr(q$Revision: 1.1 $,10);
#
#
#	specify the catagories you want and their display order
#	(see the @news_description array, below)
#
my @cats = ();

#
#	end of configurable variables
#

my $last_check;
my $last_update;
my @news_list = ();
my %context;


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
	    scalar(@cats),
	    $context{$client} || 0,
	);
	$client->update();
    },
    'down' => sub {
	my $client = shift;

	$context{$client} = Slim::Buttons::Common::scroll(
	    $client,
	    1,
	    scalar(@cats),
	    $context{$client} || 0,
	);
	$client->update();
    },
    'add' => sub {
	#
	#	refresh the news from the text file
	#
	#	note that the [add] key is labeled as [rec] on the Sony remotes
	#
	$last_update = $last_check = undef;
	Slim::Display::Display::update(shift);
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
		Time::HiRes::time() + (Slim::Utils::Prefs::get("screensavertimeout") * 5),
    );

    #
    #	check whether we need to re-read the news text file
    #
    if ($news_location =~ m|^http://|i) {
	#
	#	HTTP mode: only update the news if we don't have
	#	any extsting text
	#
		unless ($last_update) {
		    $last_update = time();
		    update_news($client);
		}
   } else {
	#
	#	file mode: check the news file's last update time
	#	every 60 seconds
	#
	if (!$last_check || (time() - $last_check) > 60) {
	    $last_check = time();
	    my $mtime = (stat($news_location))[9] || 0;

	    #
	    #	update the news if the file has been modified
	    #	since we last read it
	    #
	    if (!$last_update || $mtime > $last_update) {
			$last_update = $mtime;
			update_news($client) if $mtime;
	    }
		}
   }

   $context{$client} ||= 0;

   $lines[0] = (
		string('PLUGIN_YAHOO_LOGO')." ".$cats[$context{$client}]
	);

    if (exists($news_list[$context{$client}])) {
	$lines[1] = $news_list[$context{$client}];
    }
    else {
	$lines[1] = string('PLUGIN_YAHOO_NO_NEWS');
    }
    my $overlay = "(".(($context{$client} || 0) + 1)." ".string('OF')." ".(scalar(@cats)).")";
    return ($lines[0], $lines[1],$overlay,undef);
}

#
#	update_news()
#	-------------
#	Overwrites the @news_list with data collected from either the
#	remote HTTP URI or a text file, depending upon what is configured
#	into the $bbcnews_location variable.
#
sub update_news {
    my $client = shift;
    my $divider = Slim::Hardware::VFD::symbol('rightarrow') x 2;
    my $cur_story = 0;
    my $cur_desc = '';
    my $buf;
    my @text = ();

    if ($news_location =~ m|^http://|i) {
	#
	#	the location is a HTTP URI so open a socket to the remote
	#	webpage and collect the data
	#
	Slim::Buttons::Block::block($client,string('PLUGIN_YAHOO_MODULE_NAME'),string('PLUGIN_YAHOO_UPDATING'));
	
	my $sock = Slim::Web::RemoteStream::openRemoteStream($news_location,$client) or return undef;
	$buf .= $_ while (<$sock>);
	$sock->close();
	
	my @news_lines =split(/\n/,$buf);
		foreach (@news_lines) {
			my $tmp = $_;
    		$_ =~ s{
  				<tr><td .*? bgcolor="999999".*?colspan.*?<font.*?>
				(.*?)
				</font>
    		}{
			    	push(@text,"CATEGORY:$1<>");
  	 		}iegsx;
  	 		$_ =~ s{
    			<li>.*?href.*?>
				(.*?)
				</a>
    		}{
    			if (m/no longer available/i) {
    				push(@text,"");
    			} else {
			    	push(@text,"HEADLINE:$1<>");
			   }
  	 		}iegsx;
		}
		if (Slim::Buttons::Common::mode($client) eq 'block') {
  				Slim::Buttons::Block::unblock($client);
  		};
   } else {
   	Slim::Display::Animation::showBriefly(
	   	$client,
	    	getDisplayName() . ' ' . string('PLUGIN_CANADANEWS_UPDATING')
		);
	#
	#	the location is not a HTTP URI so strip any leading
	#	protocol specification, such as "file://" from the location
	#	and treat the resulting string as a path to a text file
	#
	$news_location =~ s|^\w+://||i;
	open(FILE,$news_location) or return undef;
	push(@text,$_) while (<FILE>);
	close FILE;
   }

    @news_list = ();

    #
    #	parse the data gathered in one of the above collection operations
    #	to create the @news_list array
    #
    foreach (@text) {
		chomp;
		$_ =~ s{
			CATEGORY: .*?
			(.*?)
			<>
		} {
			$cats[$cur_story] .= $1;
			$cur_story++;
		}iegsx;
		 
		$_ =~ s{HEADLINE: .*?
			(.*?)
			<>
		} {
			$news_list[$cur_story-1] .= "$1 $divider ";
		}iegsx;
		if ($_ eq "") {
			$cur_story--;
		}
    }
#
    #	go through the @news_list removing unnecessary whitespace and
    #	appending a long gap to the end of the news item
    #
    foreach (@news_list) {
    	if (defined($_)) {
			s/\s\s+/ /g;
			s/\s+$divider\s+$/                              /;
		}
    }
    undef;
}

#
#	strings()
#	---------
#	Read the string localisation data.
#
sub strings {
    local $/ = undef;
    <DATA>;
}

sub setMode {
    my $client = shift;

    update_news($client) unless $news_location =~ m|^http://|i;
    $client->lines(\&lines);
    $client->update();
}

sub getFunctions {
    \%functions;
}

sub getDisplayName {
    string('PLUGIN_YAHOO_MODULE_NAME');
}

1;

__DATA__

PLUGIN_YAHOO_MODULE_NAME
	EN	Yahoo! News

PLUGIN_YAHOO_LOGO
	EN	Yahoo!

PLUGIN_YAHOO_UPDATING
	EN	updating...

PLUGIN_YAHOO_NO_NEWS
	EN	No news at this time.  Press ADD to retry

