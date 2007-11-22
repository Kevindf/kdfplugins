#
# $Id: CanadaCom.pm,v 1.7 2006-04-29 09:02:10 fishbone Exp $
# Built on BBCNews.pm from Kevin Walsh
use vars qw($VERSION);
$VERSION = substr(q$Revision: 1.7 $,10);
#
#
package Plugins::CanadaCom;
use File::Spec::Functions qw(catfile);
use Slim::Utils::Strings qw(string);
use FindBin qw($Bin);
use strict;

# Choose http: if you want online access
# Choose file if you use the companion script.
my $news_location = 'http://www.canada.com/vancouver/';
#my $news_location = catfile($Bin,'Plugins','canadacom.txt');


# Display order, and menu position control. Remove elements or shuffle as you wish
my @display_order = (0,1,2,3,4,5,6,7,8);

#
#	end of configurable variables
#

my $last_check;
my $last_update;
my @news_list = ();
my %context;

#
#
my @news = (
	 [ 'TOPSTORIES',	'Top Stories',	[] ],#0
	 [ 'SPECIAL',		'Special',		[]	],#1
    [ 'LOCALNEWS',		'Local',		[] ],#2
    [ 'NATIONAL',		'National',		[] ],#3
    [ 'WORLD',			'World',			[] ],#4
    [ 'BUSINESS',		'Business',		[] ],#5
    [ 'SPORTS',			'Sports',		[] ],#6
    [ 'HEALTHANDLIFESTYLE',	'Health and Lifestyle',	[] ],#7
    [ 'ENTERTAINMENT',		'Entertainment',	[] ],#8
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
		#
		#	refresh the news from the text file
		#	note that the [add] key is labeled as [rec] on the Sony remotes
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
		getDisplayName() .
		' (' .
		(($context{$client} || 0) + 1) .
		' ' .
		string('OF') .
		' ' .
		($#display_order + 1) .
		') ' .
		$news[$display_order[$context{$client}]][1]
   	 );

    if (exists($news_list[$display_order[$context{$client}]])) {
	$lines[1] = $news_list[$display_order[$context{$client}]];
    }
    else {
	$lines[1] = string('PLUGIN_CANADANEWS_NO_NEWS');
    }
    @lines;
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
		Slim::Buttons::Block::block($client,string('PLUGIN_CANADANEWS_MODULE_NAME'),string('PLUGIN_CANADANEWS_UPDATING'));

	#
	#	the location is a HTTP URI so open a socket to the remote
	#	webpage and collect the data
	#
	my $sock = Slim::Web::RemoteStream::openRemoteStream($news_location,$client) or return undef;
	print $_;
	$buf .= $_ while (<$sock>);
	$sock->close();
	
	foreach (@news) {
    $buf =~ s{
    	<!--START:$_->[0]-->
		(.*?)
		<!--END:$_->[0]-->
    }{
	 	my $tmp = $1;
	 	if ($_->[0] eq 'TOPSTORIES') {
			$tmp =~ s{
		    	<FONT .*?topstory.*?>
		    	(.*?)
		    	</FONT>
			}{
		    	push(@{$_->[2]},$1);
			}iegsx;	
		} elsif ($_->[0] eq 'SPECIAL') {
			$tmp =~ s{
		    	<FONT .*?boxtitle.*?>
		    	(.*?)
		    	<
			}{
		    	push(@{$_->[2]},$1);
			}iegsx;
			$tmp =~ s{
		    	<FONT .*?plain.*?>
		    	(.*?)
		    	<
			}{
		    	push(@{$_->[2]},$1);
			}iegsx;
		} else {
			$tmp =~ s{
		    	<a .*?href="story.asp.*?>
		    	(.*?)
		    	</a>
			}{
		    	push(@{$_->[2]},$1);
			}iegsx;
		}
    }iegsx;
	}

#
#	just send the news to the stdout for now
#
		foreach (@news) {
 		   push(@text, "$_->[1]:\n");
 		   #my $line = join("\n",@{$_->[2]}) . "\n\n";
 		   #print "$line\n";
   		push(@text,@{$_->[2]});
   		push(@text,"\n");
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
		if (/$news[$cur_story][1]\:/) {
			next;
		} elsif ($_ eq "") {
			$cur_story++;
		} else {
			$news_list[$cur_story] .= "$_ $divider ";
		}
    }

    #
    #	make some minor modifications to the "finance" string
    #	(put the +- change in parenthesis)
    #
    #$news_list[8] =~ s/\s([+\-][\d.,]+)\s/ ($1) /g;

    #
    #	go through the @news_list removing unnecessary whitespace and
    #	appending a long gap to the end of the news item
    #
    foreach (@news_list) {
	s/\s\s+/ /g;
	s/\s+$divider\s+$/                              /;
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
	'PLUGIN_CANADANEWS_MODULE_NAME';
}

1;

__DATA__

PLUGIN_CANADANEWS_MODULE_NAME
	EN	Canada.com News

PLUGIN_CANADANEWS_UPDATING
	EN	updating...

PLUGIN_CANADANEWS_NO_NEWS
	EN	No news at this time.  Press ADD to retry

