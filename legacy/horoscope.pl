#!/usr/bin/perl

use File::Spec::Functions qw(catfile);
use LWP::UserAgent;
use FindBin qw($Bin);
use strict;

my $remote_uri = 'http://astrology.yahoo.com/astrology/general/dailyoverview/';
my $out_location = catfile($Bin,'horoscope.txt');
my $VERSION = substr(q$Revision: 1.4 $,10);
#
#	if you need to use a proxy server then specify it here
#
# my $proxy = 'http://proxy.yourdomain.com:8080/';
#
my $proxy;#
#	timeout HTTP GET requests after this many seconds
#
my $timeout = 30;

my @out;
my @signs = (
	 [ 'aries',	[] ],
	 [ 'taurus',	[] ],
	 [ 'gemini',		[]	],
    [ 'cancer',		[] ],
    [ 'leo',		[] ],
    [ 'virgo',			[] ],
    [ 'libra',		[] ],
    [ 'scorpio',		[] ],
    [ 'sagittarius',		[] ],
    [ 'capricorn',		[] ],
    [ 'aquarius',		[] ],
    [ 'pisces',		[] ],
);

my $ua = new LWP::UserAgent(
    timeout => $timeout,
    keepalive => 1,
);
$ua->agent("news_mirror/$VERSION");
$ua->proxy('http',$proxy) if $proxy;
foreach (@signs) {
	my $uri = "$remote_uri$_->[0]";
	my $response = $ua->request(HTTP::Request->new('GET',$uri));
	unless ($response->is_success()) {
		warn "Failed to GET from $uri";
		next;
	}
	my $buf = $response->content();
	#
	#	parse the raw news blocks out of the rest of the HTML
	#
		$buf =~ s{
			Overview:\<\/b\>\<br\>(.*?)\n
		}{	
			#print $1;
				push(@{$_->[1]},$1);
		}iegsx;
}

#
#	just send the news to the stdout for now
#
open(FILE,">$out_location") or die "Cannot open $out_location for writing: $!";
foreach (@signs) {
    print FILE uc($_->[0]).":\n";
    print FILE join("\n",@{$_->[1]}) . "\n\n";
}
close FILE;

exit 0;
