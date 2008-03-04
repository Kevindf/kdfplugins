# 
# This code is derived from code with the following copyright message:
#
# SlimServer Copyright (C) 2001 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

package Plugins::StationPlaylist;

use vars qw($VERSION);
$VERSION = substr(q$Revision: 0.5 $,10);


use File::Spec::Functions qw(:ALL);
use File::Spec::Functions qw(updir);
use Scalar::Util qw(blessed);

use Slim::Player::Playlist;
use Slim::Player::Source;
use Slim::Player::Sync;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw (string);

our $interval; # check every x seconds
our %playlist;
our %current;
our %monthNames;
our %active;

sub getDisplayName { return 'PLUGIN_STATIONPLAYLIST'; }

my %functions;

sub initPlugin {
	
	setTimer();
	
	@monthNames = ('January','February','March','April','May','June','July','August','September','October','November','December');
	
	%functions = (
		'play' => sub  {
			my $client = shift;
			
			if ($active{$client}) {
				$active{$client} = 0;
				$client->prefSet("PLUGIN.stationplaylist_active",0);
				$client->update;
			
			} else {
				$active{$client} = 1;
				$client->prefSet("PLUGIN.stationplaylist_active",1);
				$client->update;
			}
		},
		'left' => sub  {
			my $client = shift;
			
			Slim::Buttons::Common::popModeRight($client);
		},
		'right' => sub  {
			my $client = shift;
			
			if ($active{$client}) {
				$active{$client} = 0;
				$client->prefSet("PLUGIN.stationplaylist_active",0);
				$client->update;
			
			} else {
				$active{$client} = 1;
				$client->prefSet("PLUGIN.stationplaylist_active",1);
				$client->update;
			}
		},
	);
};

sub setTimer {
	my $interval = shift;
	my $secs     = shift;
	
	# dont' have more than one.
	Slim::Utils::Timers::killTimers($client, \&checkAlarms);
	
	$::d_plugins && msg("StationPlaylist: setting timer to $interval minutes.\n");
	
	#timer to check alarms on an interval
	Slim::Utils::Timers::setTimer(0, Time::HiRes::time() + ($interval*60 || 60) - $secs, \&checkTime);
}

sub checkTime
{
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	my $time = $hour * 60 * 60 + $min * 60;
	
	#increment month to convert from index to number
	$mon++;
	
	#use double digit month and days
	$mon  = '0'.$mon  if $mon  <= 9;
	$mday = '0'.$mday if $mday <= 9;
	
	$::d_plugins && msg("StationPlaylist: checking timer\n");
	$interval = 60-$min;

	foreach my $client (Slim::Player::Client::clients()) {
		$active{$client} = $client->prefGet("PLUGIN.stationplaylist_active") || 0;
		
		#skip inactive players
		next unless $active{$client};
		
		#only work if a playlist folder is set for use
		if ($client->prefGet('PLUGIN.stationplaylist_location')) {
			
			#create the full path
			$playlist{$client} = catdir($client->prefGet('PLUGIN.stationplaylist_location'),$mon.$mday."-".$hour.".m3u");
			
			#check vs current playlist and only reload if it is a new one
			$::d_plugins && msg("StationPlaylist: checking for $playlist{$client}, current is: $current{$client}\n");
			
			if (-e $playlist{$client}) {
				
				if ($playlist{$client} ne $current{$client}) {
				
					$interval = 60;
					Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + 2, \&trigger, $client);
			
				} else {
					$::d_plugins && msg("StationPlaylist: required playlist already loaded.\n");
				}
			
			} else {
				$::d_plugins && msg("StationPlaylist: required playlist not found.\n");
			}
		}
	}

	setTimer($interval,$sec);
}

sub getFunctions {
	return \%functions;
}

sub lines {
	my $client = shift;
	
	return {
		'line'    => [
						$client->string("PLUGIN_STATIONPLAYLIST_TURN_".($active{$client}?"OFF":"ON")),
						$client->string(getDisplayName()),
					],
		'overlay' => [
						undef,
						Slim::Buttons::Common::checkBoxOverlay($client, $active{$client}),
					],
	};
}

sub setMode {
	my $client = shift;
	
	$active{$client} = $client->prefGet("PLUGIN.stationplaylist_active") || 0;
	$client->lines(\&lines);
}

sub trigger {
	my $client = shift;
	
	Slim::Hardware::IR::setLastIRTime(
		$client,
		Time::HiRes::time() + ($client->prefGet("screensavertimeout") * 5),
	);

	$client->execute(['stop']);
	
	$::d_plugins && msg("StationPlaylist: Loading Playlist - $playlist{$client}\n");
	$client->execute(["playlist", "play",$playlist{$client}], \&loadDone, [$client]);

	Slim::Buttons::Common::pushModeLeft($client, 'playlist');
};

sub loadDone {
	my $client = shift;
	
	$current{$client} = $playlist{$client};
	Slim::Buttons::Block::unblock($client);
};

sub setupGroup {
	my $client = shift;
	
	my %setupGroup = (
	'PrefOrder'          => ["PLUGIN.stationplaylist_location"]
	,'GroupHead'         => string(getDisplayName())
	,'GroupDesc'         => string('SETUP_GROUP_STATIONPLAYLIST_DESC')
	,'GroupLine'         => 1
	,'GroupSub'          => 1
	,'PrefsInTable'      => 1
	,'Suppress_PrefHead' => 1
	,'Suppress_PrefDesc' => 1
	,'Suppress_PrefLine' => 1
	,'Suppress_PrefSub'  => 1
	);
	
	my %setupPrefs = (
			'PLUGIN.stationplaylist_location' => {
				'validate'     => \&Slim::Utils::Validate::isDir,
				'validateArgs' => [1],
				'changeIntro'  => string('PLUGIN_STATIONPLAYLIST_NEWDIR_OK'),
				'rejectMsg'    => string('SETUP_BAD_DIRECTORY'),
				'PrefSize'     => 'large',
			},
	);
	
	return (\%setupGroup,\%setupPrefs,1);
}


#Set common text strings.  can be placed in strings.txt for language templates.
sub strings { 
	return '
PLUGIN_STATIONPLAYLIST
	EN	Station Playlist
	
SETUP_GROUP_STATIONPLAYLIST_DESC
	EN	Enter the location of your Station Playlist Creator playlists:
	
PLUGIN_STATIONPLAYLIST_TURN_ON
	EN	Press PLAY/RIGHT to turn ON

PLUGIN_STATIONPLAYLIST_TURN_OFF
	EN	Press PLAY/RIGHT to turn OFF

PLUGIN_STATIONPLAYLIST_NEWDIR_OK
	EN	Using the following directory for playlists:
'};

1;

__END__

