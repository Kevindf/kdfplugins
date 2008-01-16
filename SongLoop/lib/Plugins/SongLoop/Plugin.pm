package Plugins::SongLoop::Plugin;

# $Id: Plugin.pm,v 1.1 2007-11-07 07:43:09 fishbone Exp $
# by Kevin Deane-Freeman August 2004

# This code is derived from code with the following copyright message:
#
# SliMP3 Server Copyright (C) 2001 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
use strict;

use Slim::Utils::Prefs;

use base qw(Slim::Plugin::Base);

###########################################
### Section 1. Change these as required ###
###########################################

use Slim::Utils::Strings qw (string);
use File::Spec::Functions qw(:ALL);

use vars qw($VERSION);
$VERSION = substr(q$Revision: 1.2 $,10);

my $offset=0;
my %functions;

sub getDisplayName {return 'PLUGIN_SONGLOOP'};


##################################################
### Section 2. Your variables and code go here ###
##################################################

my $log          = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.songloop',
	'defaultLevel' => 'ERROR',
	'description'  => getDisplayName(),
});

my $prefs = preferences('plugin.songloop');

my %current;

my %menuParams = (
	'songloop' => {
				'header' => sub {
					my $client = shift;
					if ($prefs->client($client)->get('songloopStartTime')) {
						return 'PLUGIN_SONGLOOP_SET_END';
					} else {
						return 'PLUGIN_SONGLOOP_SET_START';
					}
				}
				,'stringHeader' => 1
				,'headerValue' => sub {
					my $client = shift;
					my $val = shift;
					my $pos = int($val);
					my $dur = int(Slim::Player::Source::playingSongDuration($client));#$_[0]->songduration());
					my $txtPos = sprintf("%02d:%02d", $pos / 60, $pos % 60);
					my $txtDur = sprintf("%02d:%02d", $dur / 60, $dur % 60);
					return ' ('.$txtPos.'/'.$txtDur.') '.$client->string('PLUGIN_SONGLOOP_PLAY');
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
			$client->bumpRight($client);
	} else {
		return;
	}
}

sub setTimer {
	my $client = shift;
	# dont' have more than one.
	Slim::Utils::Timers::killTimers($client, \&checkLoop);

	#timer to check alarms on an interval
	Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + 1, \&checkLoop, $client);
}

sub checkLoop {
	my $client = shift;
	
	unless ($prefs->client($client)->get('songloopStartTime') && $prefs->client($client)->get('songloopEndTime')) {
		Slim::Utils::Timers::killTimers($client, \&checkLoop);
		return;
	}
	
	if (Slim::Player::Source::songTime($client) >= $prefs->client($client)->get('songloopEndTime')) {
		Slim::Player::Source::gototime($client, $prefs->client($client)->get('songloopStartTime'), 1);
		
	}
	setTimer($client);
}

sub getFunctions {
	return \%functions;
}

sub lines {
	my $line1 = string('PLUGIN_SONGLOOP');
	my $line2 = '';
	
	return {'line'    => [$line1, $line2],}
}

sub setMode {
	my $class  = shift;
	my $client = shift;
	my $method = shift;
	
	if ($method eq 'pop') {
		Slim::Buttons::Common::popModeRight($client);
		return;
	}
	
	#$client->lines(\&lines);
	$prefs->client($client)->remove('songloopStartTime');
	$prefs->client($client)->remove('songloopEndTime');
	
	my %params = %{$menuParams{'songloop'}};
	
	$params{'max'} = Slim::Player::Source::playingSongDuration($client) || 100;
	$params{'increment'} = $params{'max'}/100;
	
	$offset = Slim::Player::Source::songTime($client);
	
	Slim::Buttons::Common::pushMode($client,'INPUT.Bar',\%params);
	$client->update();
}

sub initPlugin {
	my $class = shift;
	
	%functions = (
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
			
			if ($prefs->client($client)->get('songloopStartTime')) {
				$prefs->client($client)->set('songloopEndTime',$offset);
				Slim::Player::Source::playmode($client,"play");
				Slim::Player::Source::gototime($client,$prefs->client($client)->get('songloopStartTime'), 1);
				setTimer($client);
			} else {
				$prefs->client($client)->set('songloopStartTime',$offset);
			}
			$client->update();
		},
	);

	$class->SUPER::initPlugin();
}