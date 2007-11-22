# AlarmPlugin by Kevin Deane-Freeman (kevindf@shaw.ca) March 2003
# Adapted from code by Lukas Hinsch
# Updated by Dean Blackketter
# Extended from version included in server code by Kevin Deane-Freeman July 2003
#
# This code is derived from code with the following copyright message:
#
# SlimServer Copyright (C) 2001 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

#****EDIT THIS LINE TO MATCH THE FILENAME***
package Plugins::AlarmPlugin;

my $alarmID = Plugins::AlarmPlugin::getID();

use vars qw($VERSION);
$VERSION = substr(q$Revision: 1.143 $,10);

use Slim::Player::Playlist;
use Slim::Player::Source;
use Slim::Player::Sync;
use Slim::Utils::Misc;
use Slim::Utils::DateTime;
use Slim::Utils::Strings qw (string);

use File::Spec::Functions qw(:ALL);
use File::Spec::Functions qw(updir);
use Scalar::Util qw(blessed);

use Plugins::AlarmPlugin;

my $interval; # check every x seconds
my %menuSelection;
my %searchCursor;
my @browseMenuChoices;


my %countdown;
my %snooze;
my $alarmnum;
my %power;

# edit this to change the snooze length in minutes
my $snoozetime = 10;

sub getDisplayName { return 'PLUGIN_ALARM_'.$alarmID; }

my %functions;
my %alarmActiveFunctions;

sub getID {
	if ($alarmnum) {
		$alarmnum++;
		return pack('c',64+$alarmnum);

	} else {
		$alarmnum++;
		return pack('c',65);
	}
}

# the routines
sub setMode {
	my $client = shift;
	my $method = shift;

	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	if (!defined($menuSelection{$client})) { $menuSelection{$client} = 0; };

	if ($client->prefGet('PLUGIN.alarm.'.$alarmID)) {
		$browseMenuChoices[4] = 'ALARM_ON';
	}
	
	# use INPUT.List to display the list
	my %params = (
			'listRef' 			=> [0..scalar(@browseMenuChoices-1)],
			'externRef' 		=> \@browseMenuChoices,
			'stringExternRef' 	=> 1,
			'header' 			=> sub {
									return ($_[0]->prefGet("PLUGIN.alarmname.".$alarmID) || $_[0]->string('PLUGIN_ALARM_'.$alarmID));
								},
			'headerArgs' 		=> 'C',
			'headerAddCount'	=> 1,
			'callback'			=> \&menuExitHandler,
			'overlayRef'		=> \&overlayFunc,
			'overlayRefArgs' 	=> 'CV',
			'valueRef'			=> \$menuSelection{$client},
		);

	Slim::Buttons::Common::pushModeLeft($client,'INPUT.List',\%params);
};

sub overlayFunc {
	my $client = shift;

	if ($browseMenuChoices[$menuSelection{$client}] =~ /ALARM_O[N|FF]/) {

			return (
				undef,
				Slim::Buttons::Common::checkBoxOverlay(
					$client,
					$client->prefGet('PLUGIN.alarm.'.$alarmID)
				)
			);

	} else {
		return (undef,Slim::Display::Display::symbol('rightarrow'));
	}

};

sub menuExitHandler {
	my ($client,$exittype) = @_;
	$exittype = uc($exittype);

	if ($exittype eq 'LEFT') {
		Slim::Buttons::Common::popModeRight($client);
		
	} elsif ($exittype eq 'RIGHT') {

		if ($browseMenuChoices[$menuSelection{$client}] eq 'ALARM_SET') {
			my $value = $client->prefGet('PLUGIN.alarmtime.'.$alarmID);
			
			# set a default if the pref is undefined
			if (!defined $value) {
				$client->prefSet('PLUGIN.alarmtime.'.$alarmID,0);
				$value = 0;
			}

			my %params = (
				'header'        => $client->string('ALARM_SET')
				,'valueRef'     => \$value,
				,'cursorPos'    => 0
				,'callback'     => \&exitSetHandler
				,'onChange'     => sub { $_[0]->prefSet('PLUGIN.alarmtime.'.$alarmID,$_[1]); }
				,'onChangeArgs' => 'CV'
			);
			Slim::Buttons::Common::pushModeLeft($client, 'INPUT.Time',\%params);
		}
		elsif ($browseMenuChoices[$menuSelection{$client}] eq 'ALARM_SELECT_PLAYLIST') {
			my @playlists = Slim::Schema->rs('Playlist')->getPlaylists;

			push @playlists, $client->string("PLUGIN_ALARM_CURRENT_PLAYLIST");
			
			if ((grep {$_ eq 'RandomPlay::Plugin'} keys %{Slim::Utils::PluginManager::installedPlugins()}) 
				&& !(grep {$_ eq 'RandomPlay::Plugin'} Slim::Utils::Prefs::getArray('disabledplugins'))) {
				push @playlists, $client->string("PLUGIN_RANDOM");
			}
	
			my %params = (
				'listRef'         => \@playlists,
				'externRef'      => sub {
										if ($_[1] eq $client->string('PLUGIN_ALARM_CURRENT_PLAYLIST')) {
											return $client->string('PLUGIN_ALARM_CURRENT_PLAYLIST');

										} elsif ($_[1] eq $client->string('PLUGIN_RANDOM')) {
											return "(".$client->string('PLUGIN_RANDOM').")";

										} else {
											return Slim::Music::Info::standardTitle($_[0],$_[1]->url);
										}
									},
				'externRefArgs'  => 'CV',
				'overlayRef'     => sub {
										if (defined $_[1] && $_[1] ne $client->string('PLUGIN_ALARM_CURRENT_PLAYLIST') && Slim::Music::Info::isDir($_[1])) {

											my @overlay;
											push @overlay,' ';
											push @overlay,$_[0]->symbols('rightarrow');
											return @overlay;

										} else {return undef;};
									},
				'header'         => 'ALARM_SELECT_PLAYLIST',
				'stringHeader'   => 1,
				'headerAddCount' => 1,
				'valueRef'       => undef, #defined later
				'onChange'       => sub {
											return $_[0]->prefSet('PLUGIN.alarmplaylist.'.$alarmID, blessed($_[1]) ? $_[1]->url : $_[1]);
										},
			);
			
			if ($client->prefGet('PLUGIN.alarmplaylist.'.$alarmID)) {
				my $value = $client->prefGet('PLUGIN.alarmplaylist.'.$alarmID);
				$params{'valueRef'} = \$value;
			
			} else {
				$params{'valueRef'} = \$playlists[0];
			}
			
			Slim::Buttons::Common::pushModeLeft($client, 'INPUT.List',\%params);

		} elsif ($browseMenuChoices[$menuSelection{$client}] eq 'ALARM_OFF') {

			$client->prefSet('PLUGIN.alarm.'.$alarmID, 1);

			$browseMenuChoices[$menuSelection{$client}] = 'ALARM_ON';

			setTimer($client);

			$client->update();

		} elsif ($browseMenuChoices[$menuSelection{$client}] eq 'ALARM_ON') {

			$client->prefSet('PLUGIN.alarm.'.$alarmID, 0);

			$browseMenuChoices[$menuSelection{$client}] = 'ALARM_OFF';

			setTimer($client);

			$client->update();

		} elsif ($browseMenuChoices[$menuSelection{$client}] eq 'ALARM_SET_VOLUME') {
			my $value = $client->prefGet('PLUGIN.alarmvolume.'.$alarmID) || 20;

			#Slim::Buttons::Common::pushModeLeft($client, 'PLUGIN.alarmvolume.'.$alarmID);
			my %params = (
				'header'         => 'VOLUME',
				'stringHeader'   => 1,
				'headerValue'    => sub { return $_[0]->volumeString($_[1]) },
				'onChange'       => sub { return $_[0]->prefSet('PLUGIN.alarmvolume.'.$alarmID,$_[1]);},
				'onChangeArgs'   => 'CV',
				'valueRef'       => \$value,
			);

			Slim::Buttons::Common::pushModeLeft($client, 'INPUT.Bar',\%params);

		} elsif ($browseMenuChoices[$menuSelection{$client}] eq 'PLUGIN_ALARM_DAYS') {

			my $value = $client->prefGet('PLUGIN.alarmdays.'.$alarmID) || 0;

			my %params = (
				'listRef'        => [0,1,2,3,4,5,6,7,8,9,10],
				'externRef'      => [$client->string('PLUGIN_ALARM_DAYS_ALL'), $client->string('PLUGIN_ALARM_DAYS_1'), $client->string('PLUGIN_ALARM_DAYS_2'), $client->string('PLUGIN_ALARM_DAYS_3')
										, $client->string('PLUGIN_ALARM_DAYS_4'), $client->string('PLUGIN_ALARM_DAYS_5'), $client->string('PLUGIN_ALARM_DAYS_6')
										, $client->string('PLUGIN_ALARM_DAYS_7'), $client->string('PLUGIN_ALARM_DAYS_WEEK'), $client->string('PLUGIN_ALARM_DAYS_END'), $client->string('PLUGIN_ALARM_DAYS_ONCE')],
				'header'         => $client->string('PLUGIN_ALARM_DAYS'),
				'onChange'       => sub { $_[0]->prefSet('PLUGIN.alarmdays.'.$alarmID,$_[1]); },
				'onChangeArgs'   => 'CV',
				'valueRef'       => \$value,
			);

			Slim::Buttons::Common::pushModeLeft($client, 'INPUT.List',\%params);

		} elsif ($browseMenuChoices[$menuSelection{$client}] eq 'PLUGIN_ALARM_DURATION') {
			my $value = $client->prefGet('PLUGIN.alarmduration.'.$alarmID) || 0;

			my %params = (
				'listRef'        => [0,15,30,60,90,120,150,180],
				'externRef'      => [$client->string('PLUGIN_ALARM_NOEND'), "15", "30", "60", "90", "120", "150", "180"],
				'header'         => $client->string('PLUGIN_ALARM_DURATION'),
				'onChange'       => sub { $_[0]->prefSet('PLUGIN.alarmduration.'.$alarmID,$_[1]); },
				'onChangeArgs'   => 'CV',
				'valueRef'       => \$value,
			);

			Slim::Buttons::Common::pushModeLeft($client, 'INPUT.List',\%params);

		} elsif ($browseMenuChoices[$menuSelection{$client}] eq 'ALARM_FADE') {
			my $value = $client->prefGet('PLUGIN.alarmfadeseconds.'.$alarmID) || 20;

			my %params = (
				'header'         => 'ALARM_FADE',
				'stringHeader'   => 1,
				'headerValue'    =>'unscaled',
				'onChange'       => sub { return $_[0]->prefSet('PLUGIN.alarmfadeseconds.'.$alarmID,$_[1]);},
				'onChangeArgs'   => 'CV',
				'valueRef'       => \$value,
			);

			Slim::Buttons::Common::pushModeLeft($client, 'INPUT.Bar',\%params);		}
	}
};

sub initPlugin {
	
	@browseMenuChoices = qw (ALARM_SET PLUGIN_ALARM_DURATION ALARM_SELECT_PLAYLIST ALARM_SET_VOLUME ALARM_OFF PLUGIN_ALARM_DAYS ALARM_FADE);
	
	# some initialization code, adding modes for this module
	Slim::Buttons::Common::addMode(
		'PLUGIN.alarmactive.'.$alarmID, 
		getAlarmActiveFunctions(), 
		\&setAlarmActiveMode
	);
	
	Slim::Buttons::Common::addSaver(
		'SCREENSAVER.alarmtime.'.$alarmID,
		getScreensaverAlarmtime(),
		\&setScreensaverAlarmTimeMode,
		undef,
		'PLUGIN_SCREENSAVER_ALARMTIME_'.$alarmID,
	);
	
	$::d_plugins && msg("Alarm Plugin $alarmID: Init\n");
	
	%functions = (
		'left' => sub  {
			my $client = shift;
	
			Slim::Buttons::Common::popModeRight($client);
		},
		'play' => sub {
			my $client = shift;

			if ($menuSelection{$client} eq $client->string('ALARM_SELECT_PLAYLIST') 
					&& defined ($client->param('valueRef'))
					&& ( ${$client->param('valueRef')} eq $client->string("PLUGIN_ALARM_CURRENT_PLAYLIST") 
						|| ${$client->param('valueRef')} eq $client->string("PLUGIN_RANDOM") 
						|| Slim::Music::Info::isPlaylist(${$client->param('valueRef')})
					)) {

				my $value = ${$client->param('valueRef')};

				$client->showBriefly({
					'line' => [$client->string('PLUGIN_ALARM_SETTING_PLAYLIST'),(($value eq $client->string("PLUGIN_ALARM_CURRENT_PLAYLIST")) || ($value eq $client->string("PLUGIN_RANDOM"))) 
							? $value 
							: Slim::Music::Info::standardTitle($client,$value)]
					});
				$client->prefSet('PLUGIN.alarmplaylist.'.$alarmID,$value);
			}
		},
	);
	
	%alarmActiveFunctions = (
		'left'             => sub { snooze(shift); },
		'up'               => sub { snooze(shift); },
		'down'             => sub { snooze(shift); },
		'right'            => sub { snooze(shift); },
		'stop'             => sub { killAlarm(shift); },
		'power'            => sub { killAlarm(shift); },
		
		'add'              => sub { shift->bumpRight(); },
		'play'             => sub { shift->bumpRight(); },
		'zap'              => sub { shift->bumpRight(); },
		'muting'           => sub { killAlarm(shift); },
		'pause'            => sub { killAlarm(shift); },
		'menu_now_playing' => sub { shift->bumpRight(); },
		
		'sleep'            => sub { snooze(shift); },
	);

	if ((grep {$_ eq 'TrackStat::Plugin'} keys %{Slim::Utils::PluginManager::installedPlugins()}) 
			&& !(grep {$_ eq 'TrackStat::Plugin'} Slim::Utils::Prefs::getArray('disabledplugins'))) {
		$alarmActiveFunctions{'playFavorite'} = sub { Plugins::TrackStat::Plugin::saveRatingsForCurrentlyPlaying($_[0], undef, $_[2]); };

	} else {
		$alarmActiveFunctions{'numberScroll'} = sub { snooze(shift); };
	}

	setTimer($client);

}

sub setTimer {
	# dont' have more than one.
	Slim::Utils::Timers::killTimers($client, \&checkAlarms);

	#timer to check alarms on an interval
	Slim::Utils::Timers::setTimer(0, Time::HiRes::time() + ($interval || 1), \&checkAlarms);
}

sub checkAlarms
{
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	my $time = $hour * 60 * 60 + $min * 60;

	$::d_plugins && msg("Alarm Plugin $alarmID: Checking timer\n") if defined $interval && $min == 0;
	
	if ($sec == 0) { # once we've reached the beginning of a minute, only check every 60s
		$interval = 60;
	}

	if ($sec >= 50 || ! defined $interval) { # if we end up falling behind, go back to checking each second
		$interval = 60-$sec;
	}

	foreach my $client (Slim::Player::Client::clients()) {

		if ($client->prefGet('PLUGIN.alarm.'.$alarmID)) {

			my $alarmtime =  $client->prefGet('PLUGIN.alarmtime.'.$alarmID);
			if ($alarmtime) {

				if ($time == $alarmtime) {
					#Now Match Days
					my $days = $client->prefGet('PLUGIN.alarmdays.'.$alarmID);
					my $dom = $client->prefGet('PLUGIN.alarmdayofmonth.'.$alarmID);
					my $month = $client->prefGet('PLUGIN.alarmmonth.'.$alarmID);
					
					if (!defined($days)) {$days = 0;}
					
					if (!defined($dom)) {$dom = 0;}
					
					if (!defined($month)) {$month = 0;}
					
					if (($days == $wday) # single day
							|| ($days == 0) # all 7 days
							|| ($days == 10) # once only
							|| (($days == 8) && (($wday > 0) && ($wday < 6))) # weekdays
							|| (($days == 9) && (($wday == 6) || ($wday == 0))) # weekends
							|| (($days == 11) && ($dom == $mday) && (($month-1) == $mon))) {  # exact date
						
						$interval = 60;
						Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + 2, \&alarmTrigger, $client);
					}
				}
			}
		}
	}
	setTimer($client);
}

sub getFunctions() {
	return \%functions;
}

sub exitSetHandler {
	my ($client,$exittype) = @_;
	
	$exittype = uc($exittype);

	if ($exittype eq 'LEFT') {
		
		if ($menuSelection{$client} eq $client->string('ALARM_SET')) {
			$client->prefSet('PLUGIN.alarmtime.'.$alarmID,${$client->param('valueRef')});
		}
		
		Slim::Buttons::Common::popModeRight($client);

	} elsif ($exittype eq 'RIGHT') {
			$client->bumpRight();

	} else {
		return;
	}
}

#################################################################################
# Alarm Active Mode

sub getAlarmActiveFunctions {
	return \%alarmActiveFunctions;
};

sub setAlarmActiveMode {
	my $client = shift;

	Slim::Hardware::IR::setLastIRTime(
		$client,
		Time::HiRes::time() + ($client->prefGet("screensavertimeout") * 5),
	);

	$client->lines(\&alarmActiveLines);

	my $linefunc = $client->lines();
	$client->param('modeUpdateInterval', 1);
};

sub alarmActiveLines {
	my $client = shift;
	my $parts;
	
	Slim::Hardware::IR::setLastIRTime(
		$client,
		Time::HiRes::time() + ($client->prefGet("screensavertimeout") * 5),
		);

	my $playlistlen = Slim::Player::Playlist::count($client);
	$parts->{'line'}[0] = $client->string('PLUGIN_ALARM_NOW_PLAYING');
	
	my $song = Slim::Player::Playlist::song($client);

	if (!$song) {
		$parts->{'line'}[1] = $client->string('NOTHING');

	} elsif (Slim::Music::Info::isRemoteURL($song)) {
		$parts->{'line'}[1] = Slim::Music::Info::getCurrentTitle($client, $song);

	} else {
		$parts->{'line'}[1] = Slim::Music::Info::standardTitle($client, $song);
	}
	
	my $time = Time::HiRes::time();
	
	if ($snooze{$client}) {
		$parts->{'line'}[0] = $client->string('PLUGIN_ALARM_SNOOZE');
		$parts->{'line'}[0] .= "(".int(($countdown{$client} - $time + 50)/60)." ".$client->string('MINUTES').")";
		$parts->{'line'}[1] = "ZzZzzZzzzZzZ..." x4;

	} elsif ($playlistlen < 1) {
		$parts->{'line'}[1] = $client->string('NOTHING');

	} else { 
		$parts->{'line'}[0] = $parts->{'line'}[0] . sprintf " (%d %s %d) ", Slim::Player::Source::playingSongIndex($client) + 1, $client->string('OUT_OF'), $playlistlen;
	}
	$client->nowPlayingModeLines($parts);
	return $parts;
};

sub snooze {
	my $client = shift;
	my $name = $client->prefGet("PLUGIN.alarmname.".$alarmID);
	
	if (!$snooze{$client}) {
		$snooze{$client} = 1;
		$::d_plugins && msg("Alarm Plugin $alarmID: snooze\n");

		$client->execute(['stop']);

		$::d_plugins && msg("Alarm Plugin $alarmID: Alarm $alarmID snoozing...\n");
		$countdown{$client} = Time::HiRes::time() + ($snoozetime * 60);

		$::d_plugins && msgf("Alarm Plugin $alarmID: Coundown: %d\n",$countdown{$client});
		Slim::Utils::Timers::setTimer($client, $countdown{$client}, \&unSnooze, $client);

		$client->showBriefly({
			'line'     => [$name || $client->string(getDisplayName()),$client->string('PLUGIN_ALARM_SNOOZE')],
			'duration' => 3,
			'block'    => 1,
		});
	}
};

sub alarmLoadDone {
	my $client = shift;
	Slim::Buttons::Block::unblock($client);
};

sub killAlarm {
	my $client = shift;
	my $name = $client->prefGet("PLUGIN.alarmname.".$alarmID);
	
	$snooze{$client} = 0;
	$client->execute(['stop']);
	$::d_plugins && msg("Alarm Plugin $alarmID: Alarm $alarmID Has been killed\n");
	Slim::Utils::Timers::killTimers($client, \&unSnooze);
	
	if ($client->prefGet('PLUGIN.alarmdays.'.$alarmID) == 10) {
		#turn off after single trigger
		$client->prefSet('PLUGIN.alarm.'.$alarmID, 0);
	}
	
	if ($power{$client}) {

		while (Slim::Buttons::Common::mode($client) =~ m/PLUGIN.alarmactive/i) {
			Slim::Buttons::Common::popModeRight($client); 
		}

	} else {
		$client->execute(['power',0]);
	}

	$client->execute(["sleep", 0]);

	$client->showBriefly({
		'line'     => [$name || $client->string(getDisplayName()),$client->string('ALARM_TURNING_OFF')],
		'duration' => 3,
		'block'    => 1,
	});
}

sub unSnooze {
	my $client = shift;
	
	$snooze{$client} = 0;
	$::d_plugins && msg("Alarm Plugin $alarmID: Snooze Over\n");
	$client->execute(["playlist", "jump", "+1"]);
	Slim::Player::Playlist::refreshPlaylist($client);

	$client->showBriefly({
		'line'     => [$client->string('PLUGIN_ALARM_NOW_PLAYING'),$client->string('PLUGIN_ALARM_WAKEUP')],
		'duration' => 3,
		'block'    => 1,
	});
};

sub alarmTrigger {
	my $client = shift;
	
	Slim::Hardware::IR::setLastIRTime(
	$client,
	Time::HiRes::time() + ($client->prefGet("screensavertimeout") * 5),
	);
	
	# store power state, for returning after alarm ends.
	$power{$client} = $client->power();

	$client->execute(['stop']);
	my $volume = $client->prefGet('PLUGIN.alarmvolume.'.$alarmID);
	
	$::d_plugins && msg("Alarm Plugin $alarmID: Alarm $alarmID Has Triggered\n");
	
	if ((defined ($volume)) && !$snooze{$client}) {
		$client->execute(["mixer", "volume", $volume]);
	}

	$client->fade_volume($client->prefGet('PLUGIN.alarmfadeseconds.'.$alarmID));
	
	if ((defined $client->prefGet('PLUGIN.alarmplaylist.'.$alarmID)) && !$snooze{$client}) {
		$client->execute(["pause", 0]);
	
	if ((grep {$_ eq 'RandomPlay::Plugin'} keys %{Slim::Utils::PluginManager::installedPlugins()}) 
				&& !(grep {$_ eq 'RandomPlay::Plugin'} Slim::Utils::Prefs::getArray('disabledplugins'))
				&& ($client->prefGet('PLUGIN.alarmplaylist.'.$alarmID) eq $client->string("PLUGIN_RANDOM"))) {
			Plugins::RandomPlay::Plugin::playRandom($client,'track');
	
	} elsif ($client->prefGet('PLUGIN.alarmplaylist.'.$alarmID) ne $client->string("PLUGIN_ALARM_CURRENT_PLAYLIST")) {

			my $playlist = $client->prefGet('PLUGIN.alarmplaylist.'.$alarmID);
			
			my $playlistObj = Slim::Schema->rs('Playlist')->objectForUrl({
				'url' => $playlist,
			});

			if (blessed($playlistObj) && $playlistObj->can('id')) {
				$::d_plugins && msg("Alarm Plugin $alarmID: Loading Playlist - $playlist\n");
				my $autoshuffle = $client->prefGet('PLUGIN.alarmautoshuffle.'.$alarmID);
				
				if ($autoshuffle) {
					$client->execute(["playlist", "loadtracks", "playlist=".$playlistObj->id()]);
					$client->execute(["playlist", "shuffle", $autoshuffle], \&alarmLoadDone, [$client]);
					$::d_plugins && msg ("Alarm Plugin $alarmID: tracks shuffled\n");
				
				} else {
					$client->execute(["playlist", "loadtracks", "playlist=".$playlistObj->id()], \&alarmLoadDone, [$client]);
				}
			
			} else {
				$::d_plugins && msg("Alarm Plugin $alarmID: $playlist not loaded, using Current Playlist instead\n");
				$client->execute(['play']);
			}
		
		} else {
			$::d_plugins && msg("Alarm Plugin $alarmID: Playing Current Playlist\n");
			$client->execute(['play']);
		}
	
	} elsif (!$snooze{$client}) {
		$::d_plugins && msg("Alarm Plugin $alarmID: Playing Alarm $alarmID\n");
		$client->execute(['play']);
	};
	
	my $sleepTime = $client->prefGet('PLUGIN.alarmduration.'.$alarmID);
	$client->execute(["sleep", $sleepTime * 60]) if $sleepTime;
	
	if ($client->prefGet('PLUGIN.alarmdays.'.$alarmID) == 10) {
		#turn off after single trigger
		$client->prefSet('PLUGIN.alarm.'.$alarmID, 0);
	}
	
	Slim::Buttons::Common::pushModeLeft($client, 'PLUGIN.alarmactive.'.$alarmID);

};

sub playlists {
	my $playlists = &Slim::Web::Setup::playlists();
	$playlists->{string("PLUGIN_ALARM_CURRENT_PLAYLIST")} = string("PLUGIN_ALARM_CURRENT_PLAYLIST");
	
	if ((grep {$_ eq 'RandomPlay::Plugin'} keys %{Slim::Utils::PluginManager::installedPlugins()}) 
			&& !(grep {$_ eq 'RandomPlay::Plugin'} Slim::Utils::Prefs::getArray('disabledplugins'))) {
		$playlists->{string("PLUGIN_RANDOM")} = "(".string("PLUGIN_RANDOM").")";
	}
	
	return $playlists;
}

sub addGroup {
	return 'PLUGINS';
}

sub setupGroup {
	my $client = shift;
	my %setupGroup      = (
	'PrefOrder'         => [
						'PLUGIN.alarmname.'.$alarmID,
						'PLUGIN.alarm.'.$alarmID,
						'PLUGIN.alarmtime.'.$alarmID,
						'PLUGIN.alarmduration.'.$alarmID,
						'PLUGIN.alarmvolume.'.$alarmID,
						'PLUGIN.alarmdays.'.$alarmID,
						'PLUGIN.alarmmonth.'.$alarmID,
						'PLUGIN.alarmdayofmonth.'.$alarmID,
						'PLUGIN.alarmplaylist.'.$alarmID,
						'PLUGIN.alarmautoshuffle.'.$alarmID,
						'PLUGIN.alarmfadeseconds.'.$alarmID
					],
	'GroupHead'         => string(getDisplayName()),
	'GroupDesc'         => string('PLUGIN_GROUP_DESC'),
	'GroupLine'         => 1,
	'GroupSub'          => 1,
	'PrefsInTable'      => 1,
	'Suppress_PrefHead' => 1,
	'Suppress_PrefDesc' => 1,
	'Suppress_PrefLine' => 1,
	'Suppress_PrefSub'  => 1,
	);
	my %setupPrefs = (
			'PLUGIN.alarmtime.'.$alarmID => {
				'validate'      => \&Slim::Utils::Validate::isTime,
				'validateArgs' => [0,undef],
				'PrefChoose'   => string('ALARM_SET').string('COLON'),
				'changeIntro'  => string('ALARM_SET').' '.$alarmID.string('COLON'),
				'rejectIntro'  => string('ALARM_SET').' '.$alarmID.string('COLON'),
				'currentValue' => sub {
										my $client = shift;
										
										my $time = $client->prefGet("PLUGIN.alarmtime.".$alarmID);
										my ($h0, $h1, $m0, $m1, $p) = Slim::Buttons::Input::Time::timeDigits($client,$time);
										my $timestring = ((defined($p) && $h0 == 0) ? ' ' : $h0) . $h1 . ":" . $m0 . $m1 . " " . (defined($p) ? $p : '');
										
										return $timestring;
									},
				'onChange'     => sub {
										my ($client,$changeref,$paramref,$pageref) = @_;
										
										my $time = $changeref->{'PLUGIN.alarmtime.'.$alarmID}{'new'};
										
										my $newtime = 0;
										
										$time =~ s{
											^([0\s]?[0-9]|1[0-9]|2[0-4]):([0-5][0-9])\s*(P|PM|A|AM)?$
										}{
											if (defined $3) {
												$newtime = ($1 == 12?0:$1 * 60 * 60) + ($2 * 60) + ($3 =~ /P/?12 * 60 * 60:0);
											} else {
												$newtime = ($1 * 60 * 60) + ($2 * 60);
											}
										}iegsx;
										$client->prefSet('PLUGIN.alarmtime.'.$alarmID,$newtime);
									},
			},
			
			'PLUGIN.alarmduration.'.$alarmID => {
				'validate'      => \&Slim::Utils::Validate::inList,
				'PrefChoose'   => string('PLUGIN_ALARM_DURATION').string('COLON'),
				'validateArgs' => [0,15,30,60,90,120,150,180],
				'changeIntro'  => string('PLUGIN_ALARM_DURATION').' '.$alarmID.string('COLON'),
				'options'      => {
									'0' => string('PLUGIN_ALARM_NOEND'),
									'15' => "15",
									'30' => "30",
									'60' => "60",
									'90' => "90",
									'120' => "120",
									'150' => "150",
									'180' => "180",
								},
			},
			
			'PLUGIN.alarmname.'.$alarmID => {
				'validate'     => \&Slim::Utils::Validate::acceptAll,
				'PrefChoose'  => string('PLUGIN_ALARM_NAME').string('COLON'),
				'changeIntro' => string('PLUGIN_ALARM_NAME').' '.$alarmID.string('COLON'),
			},
			
			'PLUGIN.alarmvolume.'.$alarmID	=> {
				'validate'      => \&Slim::Utils::Validate::number,
				'currentValue' => sub {
						my $client = shift;
						
						my $val = $client->prefGet("PLUGIN.alarmvolume.".$alarmID);
						
						if (!defined $val) {
							$client->prefSet("PLUGIN.alarmvolume.".$alarmID,50);
						}
						
						return $val;
					},
				'PrefChoose'   => string('SETUP_ALARMVOLUME').string('COLON'),
				'changeIntro'  => string('SETUP_ALARMVOLUME').' '.$alarmID.string('COLON'),
				'validateArgs' => [0,$Slim::Player::Client::maxVolume,1,1],
			},
			
			'PLUGIN.alarmplaylist.'.$alarmID => {
				'validate'      => \&Slim::Utils::Validate::inHash,
				'PrefChoose'   => string('ALARM_SELECT_PLAYLIST').string('COLON'),
				'changeIntro'  => string('SETUP_ALARMPLAYLIST').' '.$alarmID.string('COLON'),
				'validateArgs' => [&playlists()], #[\&playlists]
				'options'      => &playlists(), #{playlists()}
			},
			
			'PLUGIN.alarmdays.'.$alarmID => {
				'validate'      => \&Slim::Utils::Validate::inList
				,'PrefChoose'   => string('PLUGIN_ALARM_DAYS').string('COLON')
				,'validateArgs' => [0,1,2,3,4,5,6,7,8,9,10,11]
				,'changeIntro'  => string('PLUGIN_ALARM_DAYS').' '.$alarmID.string('COLON')
				,'optionSort'   => NK
				,'options'      => {
									'0' => string('PLUGIN_ALARM_DAYS_ALL'),
									'1' => string('PLUGIN_ALARM_DAYS_1'),
									'2' => string('PLUGIN_ALARM_DAYS_2'),
									'3' => string('PLUGIN_ALARM_DAYS_3'),
									'4' => string('PLUGIN_ALARM_DAYS_4'),
									'5' => string('PLUGIN_ALARM_DAYS_5'),
									'6' => string('PLUGIN_ALARM_DAYS_6'),
									'7' => string('PLUGIN_ALARM_DAYS_7'),
									'8' => string('PLUGIN_ALARM_DAYS_WEEK'),
									'9' => string('PLUGIN_ALARM_DAYS_END'),
									'10' => string('PLUGIN_ALARM_DAYS_ONCE'),
									'11' => string('PLUGIN_ALARM_DAYS_DATE'),
								}
			},
			
			'PLUGIN.alarmdayofmonth.'.$alarmID => {
				# Use AcceptAll since it can allow a blank, and the date range of 31 doesn't fit every month anyway
				'validate' => \&Slim::Utils::Validate::acceptAll,
				'PrefChoose' => string('PLUGIN_ALARM_DAYOFMONTH').string('COLON'),
				#,'validateArgs' => [1,31,1,1],
				'changeIntro' => string('PLUGIN_ALARM_DAYOFMONTH').' '.$alarmID.string('COLON'),
			},
			
			'PLUGIN.alarmmonth.'.$alarmID => {
				'validate'      => \&Slim::Utils::Validate::inList,
				'PrefChoose'   => string('PLUGIN_ALARM_MONTH').string('COLON'),
				'validateArgs' => [1,2,3,4,5,6,7,8,9,10,11,12],
				'changeIntro'  => string('PLUGIN_ALARM_MONTH').' '.$alarmID.string('COLON'),
				'optionSort'   => NK,
				'options'      => {
									'1' => string('PLUGIN_ALARM_MONTH_1'),
									'2' => string('PLUGIN_ALARM_MONTH_2'),
									'3' => string('PLUGIN_ALARM_MONTH_3'),
									'4' => string('PLUGIN_ALARM_MONTH_4'),
									'5' => string('PLUGIN_ALARM_MONTH_5'),
									'6' => string('PLUGIN_ALARM_MONTH_6'),
									'7' => string('PLUGIN_ALARM_MONTH_7'),
									'8' => string('PLUGIN_ALARM_MONTH_8'),
									'9' => string('PLUGIN_ALARM_MONTH_9'),
									'10' => string('PLUGIN_ALARM_MONTH_10'),
									'11' => string('PLUGIN_ALARM_MONTH_11'),
									'12' => string('PLUGIN_ALARM_MONTH_12'),
								},
			},
			
			'PLUGIN.alarm.'.$alarmID => {
				'validate' => \&Slim::Utils::Validate::trueFalse,
				'currentValue' => sub {
						my $client = shift;
						
						my $val = $client->prefGet("PLUGIN.alarm.".$alarmID);
						
						if (!defined $val) {
							$client->prefSet("PLUGIN.alarm.".$alarmID,0);
						}
						
						return $val;
					},
				'PrefHead'    => ' ',
				'PrefChoose'  => string('SETUP_ALARM').string('COLON'),
				'changeIntro' => string('SETUP_ALARM').' '.$alarmID.string('COLON'),
				'options'     => {
								'1'  => string('ON'),
								'0' => string('OFF'),
					},
			},
			
			'PLUGIN.alarmautoshuffle.'.$alarmID => {
				'validate'      => \&Slim::Utils::Validate::inList,
				'validateArgs'  => [0,1,2],
				'currentValue'  => sub {
									my $client = shift;
									
									my $val = $client->prefGet("PLUGIN.alarmautoshuffle.".$alarmID);
									
									if (!defined $val) {
										$client->prefSet("PLUGIN.alarmautoshuffle.".$alarmID,0);
									}
									
									return $val
								},
				'PrefHead'      => ' ',
				'PrefChoose'    => string('PLUGIN_ALARM_AUTOSHUFFLE').string('COLON'),
				'changeIntro'   => string('PLUGIN_ALARM_AUTOSHUFFLE').' '.$alarmID.string('COLON'),
				'options'       => {
								'2'  => string('ALBUMS'),
								'1'  => string('SONGS'),
								'0'  => string('OFF')
				},
			},
			
			'PLUGIN.alarmfadeseconds.'.$alarmID	=> {
				'validate'      => \&Slim::Utils::Validate::number
				,'currentValue' => sub {
						my $client = shift;
						my $val = $client->prefGet("PLUGIN.alarmfadeseconds.".$alarmID);
						
						if (!defined $val) {
							$client->prefSet("PLUGIN.alarmfadeseconds.".$alarmID,20);
						}
						
						return $val;
					}
				,'PrefChoose'   => string('PLUGIN_ALARM_FADESECONDS').string('COLON')
				,'changeIntro'  => string('PLUGIN_ALARM_FADESECONDS').' '.$alarmID.string('COLON')
				,'validateArgs' => [0,90,1,1]
			}
	);
	return (\%setupGroup,\%setupPrefs,1);
}


# First, Register the screensaver mode here.  Must make the call to addStrings in order to have plugin
# localization available at this point.
#sub screenSaver {
#}

our %screensaverAlarmTimeFunctions = (
	'done' => sub  {
		my ($client ,$funct ,$functarg) = @_;

		Slim::Buttons::Common::popMode($client);
		$client->update();

		# pass along ir code to new mode if requested
		if (defined $functarg && $functarg eq 'passback') {
			Slim::Hardware::IR::resendButton($client);
		}
	},
);

sub getScreensaverAlarmtime {
	return \%screensaverAlarmTimeFunctions;
}

sub setScreensaverAlarmTimeMode() {
	my $client = shift;
	$client->lines(\&screensaverAlarmTimelines);

	# setting this param will call client->update() frequently
	$client->param('modeUpdateInterval', 1); # seconds
}

sub screensaverAlarmTimelines {
	my $client = shift;

	my @line = (Slim::Utils::DateTime::longDateF(), Slim::Utils::DateTime::timeF());
	if ($client->prefGet("PLUGIN.alarm.".$alarmID)) {
		my $alarmtime = $client->prefGet("PLUGIN.alarmtime.".$alarmID);
		
		my $hour = int($alarmtime / 3600);
		
		my $minute = int(($alarmtime - $hour * 3600) / 60);
		
		if ($hour < 10) { $hour = '0' . $hour; }
		
		if ($minute < 10) { $minute = '0' . $minute; }
		
		if ($client->prefGet('offDisplaySize')) {
		
			# for large size, display in the format:    hh:mm   m xx:yy
			# with:  hh = current hour, mm = current minute, m = alarm_mode, xx = alarm hour, yy = alarm minute
			my $sec = int(substr($line[1],6,2));
			my $even = $sec - (int($sec / 2) * 2);     # blink of separator
			my $sep = ".";
			
			if ($even) {$sep = ":";}
			
			my @alarmModes = ('*', '1','2','3','4','5','6','7','w', ,'s');
			
			$line[1] = substr($line[1],0,2).$sep.substr($line[1],3,2)."   ";
			$line[1] = $line[1].$alarmModes[$client->prefGet("PLUGIN.alarmdays.".$alarmID)];
			$line[1] = $line[1]." ".substr($hour,0,2).":".substr($minute,0,2);
		
		} else {
			# for small size display verbose information
			# upper line:  centered date (default style)
			# lower line:  Time  hh:mm:ss   Alarm  hh:mm  mode
		
			my @alarmModes = ('7day', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun', 'Week', ,'SaSo');
			$line[1] = "Time   ".$line[1]."       Alarm   ".substr($hour,0,2).":".substr($minute,0,2);
			$line[1] = $line[1]." ".$alarmModes[$client->prefGet("PLUGIN.alarmdays.".$alarmID)];
		}
	
	} else {
	# if the alarm is off, default display
	}
	
	return {
		'center' => \@line,
		'overlay'=> [ ($alarmOn ? $client->symbols('bell') : undef) ],
	};
}

#Set common text strings.  can be placed in strings.txt for language templates.
sub strings { 
	return '
PLUGIN_GROUP_DESC
	EN	This player can have as many alarms as you like: simply add an additional AlarmPlugin#.pm file. You may also choose to have the alarm fade in over x seconds or have the selected playlist auto-shuffled.

PLUGIN_ALARM_'.$alarmID.'
	DE	Wecker '.$alarmID.'
	EN	Alarm Plugin '.$alarmID.'
	FR	Reveil '.$alarmID.'

PLUGIN_SCREENSAVER_ALARMTIME_'.$alarmID.'
	DE	AlarmTime Bildschirmschoner '.$alarmID.'
	EN	AlarmTime Screensaver '.$alarmID.'
	FR	Ecran de veille Lecture '.$alarmID.'

PLUGIN_ALARM_NAME
	DE	Wecker Name
	EN	Alarm Name
	FR	Nom de Lecture

PLUGIN_ALARM_NOW_PLAYING
	DE	Der Wecker spielt gerade
	EN	Alarm Playing
	FR	Lecture (réveil)

PLUGIN_ALARM_DAYS
	DE	Tage für Wecker wählen
	EN	Choose Days for Alarm
	FR	Choisir les jours pour le réveil

PLUGIN_ALARM_DAYS_ALL
	DE	Jeden Tag
	EN	All 7 Days
	FR	Tous les jours

PLUGIN_ALARM_DAYS_1
	DE	Montag
	EN	Monday
	FR	Lundi

PLUGIN_ALARM_DAYS_2
	DE	Dienstag
	EN	Tuesday
	FR	Mardi

PLUGIN_ALARM_DAYS_3
	DE	Mittwoch
	EN	Wednesday
	FR	Mercredi

PLUGIN_ALARM_DAYS_4
	DE	Donnerstag
	EN	Thursday
	FR	Jeudi

PLUGIN_ALARM_DAYS_5
	DE	Freitag
	EN	Friday
	FR	Vendredi

PLUGIN_ALARM_DAYS_6
	DE	Samstag
	EN	Saturday
	FR	Samedi

PLUGIN_ALARM_DAYS_7
	DE	Sonntag
	EN	Sunday
	FR	Dimanche

PLUGIN_ALARM_DAYS_ONCE
	DE	Nur ein Mal
	EN	One Time Only
	FR	Une fois seulement

PLUGIN_ALARM_DAYS_WEEK
	DE	Nur wochentags
	EN	Weekdays Only
	FR	Jours de semaine

PLUGIN_ALARM_DAYS_END
	DE	Nur an Wochenenden
	EN	Weekends Only
	FR	Week-end

PLUGIN_ALARM_SNOOZE
	DE	Schlummern...
	EN	Snoozing...
	FR	Sommeiller...

PLUGIN_ALARM_WAKEUP
	DE	Zeit, aufzustehen...
	EN	Time to wake up...
	FR	C\'est le temps de se lever...

PLUGIN_ALARM_CURRENT_PLAYLIST
	DE	(die aktuelle)
	EN	(current)
	FR	(actuelle)

PLUGIN_ALARM_SETTING_PLAYLIST
	DE	Benutze Playlist...
	EN	Setting Playlist to...

PLUGIN_ALARM_DURATION
	DE	Dauer des Weckers (Minuten)
	EN	Alarm Duration (minutes)
	FR	Dureé\'alarme (en minutes)
	
PLUGIN_ALARM_NOEND
	DE	Manuell
	EN	Manual
	FR	Manuel

PLUGIN_ALARM_DAYS_DATE
	DE	Exaktes Datum
	EN	Exact Date
	FR	Jour spéfique

PLUGIN_ALARM_DAYOFMONTH
	DE	Tag des Monats
	EN	Day of month
	FR	Jour de mois

PLUGIN_ALARM_MONTH
	DE	Monat
	EN	Month
	FR	Mois

PLUGIN_ALARM_MONTH_1
	DE	Januar
	EN	January
	FR	Janvier

PLUGIN_ALARM_MONTH_2
	DE	Februar
	EN	February
	FR	Février

PLUGIN_ALARM_MONTH_3
	DE	März
	EN	March
	FR	Mars

PLUGIN_ALARM_MONTH_4
	EN	April
	FR	Avril

PLUGIN_ALARM_MONTH_5
	DE	Mai
	EN	May
	FR	Mai

PLUGIN_ALARM_MONTH_6
	DE	Juni
	EN	June
	FR	Juin

PLUGIN_ALARM_MONTH_7
	DE	Juli
	EN	July
	FR	Juillet

PLUGIN_ALARM_MONTH_8
	EN	August
	FR	Août
	
PLUGIN_ALARM_MONTH_9
	EN	September
	FR	Septembre

PLUGIN_ALARM_MONTH_10
	DE	Oktober
	EN	October
	FR	Octobre

PLUGIN_ALARM_MONTH_11
	EN	November
	FR	Novembre

PLUGIN_ALARM_MONTH_12
	DE	Dezember
	EN	December
	FR	Décembre

PLUGIN_ALARM_AUTOSHUFFLE
	DE	Wiedergabeliste zufällig mischen
	EN	Auto shuffle playlist

PLUGIN_ALARM_FADESECONDS
	DE	Einblende-Dauer (Sekunden)
	EN	Fade-in seconds
'};

1;

__END__

