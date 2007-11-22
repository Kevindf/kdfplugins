package Plugins::Scanner;

# $Id: Scanner.pm,v 1.8 2007-10-24 03:02:03 fishbone Exp $
# by Kevin Deane-Freeman August 2004

# This code is derived from code with the following copyright message:
#
# SliMP3 Server Copyright (C) 2001 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
use strict;

###########################################
### Section 1. Change these as required ###
###########################################

use Slim::Utils::Strings qw (string);
use File::Spec::Functions qw(:ALL);

use vars qw($VERSION);
$VERSION = substr(q$Revision: 1.8 $,10);

my $offset    = 0;
my $jumptomode = 0;

sub getDisplayName {return 'PLUGIN_SCANNER'}

sub strings { return '
PLUGIN_SCANNER
	EN	Song Scanner

PLUGIN_SCANNER_SET
	EN	Scan to:

PLUGIN_SCANNER_PLAY
	EN	 (press PLAY)
'};

##################################################
### Section 2. Your variables and code go here ###
##################################################

my %current;

my %menuParams = (
	'scanner' => {
				'header' => 'PLUGIN_SCANNER_SET'
				,'stringHeader' => 1
				,'headerValue' => sub {
					my $client = shift;
					my $val = shift;
					my $pos = int($val);
					my $dur = int(Slim::Player::Source::playingSongDuration($client));#$_[0]->songduration());
					my $txtPos = sprintf("%02d:%02d", $pos / 60, $pos % 60);
					my $txtDur = sprintf("%02d:%02d", $dur / 60, $dur % 60);
					return ' ('.$txtPos.'/'.$txtDur.') '.$client->string('PLUGIN_SCANNER_PLAY');
					}
				,'headerArgs' => 'CV'
				,'max' => undef
				,'increment' => undef
				,'onChange' => sub { $offset = $_[1];
								$_[0]->param('max',Slim::Player::Source::playingSongDuration($_[0]));
								$_[0]->param('increment',Slim::Player::Source::playingSongDuration($_[0])/100);
							}
				,'onChangeArgs' => 'CV'
				,'callback' => \&scannerExitHandler
				,'valueRef' => \$offset
		}
);

sub scannerExitHandler {
	my ($client,$exittype) = @_;
	$exittype = uc($exittype);
	if ($exittype eq 'LEFT') {
		Slim::Buttons::Common::popModeRight($client);
		#Slim::Player::Source::gototime($client, $offset, 1);
	} elsif ($exittype eq 'RIGHT') {
			Slim::Display::Animation::bumpRight($client);
	} else {
		return;
	}
}

my %functions = (
	'right' => sub  {
		my ($client,$funct,$functarg) = @_;
		scannerExitHandler($client,'RIGHT');
	},
	'left' => sub {
		my $client = shift;
		scannerExitHandler($client,'LEFT');
	},
	'play' => sub {
		my $client = shift;
		Slim::Player::Source::playmode($client,"play");
		Slim::Player::Source::gototime($client, $offset, 1);
		$client->showBriefly($client->currentSongLines());
		if ($jumptomode) {
			Slim::Buttons::Common::popMode($client);
			$jumptomode = 0;
		}
	},
	'jumptoscanner' => sub {
		my $client = shift;
		Slim::Buttons::Common::pushModeLeft( $client, 'PLUGIN.Scanner');
		$jumptomode = 1;
	},
);

sub getFunctions {
	return \%functions;
}

sub lines {
	my $line1 = string('PLUGIN_SCANNER');
	my $line2 = '';
	
	return {'line'    => [$line1, $line2],}
}

sub setMode {
	my $client = shift;
	my $method = shift;
	if ($method eq 'pop') {
		Slim::Buttons::Common::popModeRight($client);
		return;
	}
	#$client->lines(\&lines);
	my %params = %{$menuParams{'scanner'}};
	$params{'max'} = Slim::Player::Source::playingSongDuration($client) || 100;
	$params{'increment'} = $params{'max'}/100;
	$offset = Slim::Player::Source::songTime($client);
	Slim::Buttons::Common::pushMode($client,'INPUT.Bar',\%params);
	$client->update();
}