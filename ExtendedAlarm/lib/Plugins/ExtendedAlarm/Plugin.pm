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

package Plugins::ExtendedAlarm::Plugin;

use base qw(Slim::Plugin::Base);

use vars qw($VERSION);
$VERSION = substr(q$Revision: 1.1 $,10);

use Slim::Utils::Misc;
use Slim::Utils::DateTime;
use Slim::Utils::Strings qw (string);

use File::Spec::Functions qw(:ALL);
use Scalar::Util qw(blessed);
use Slim::Utils::Prefs;

use Plugins::ExtendedAlarm::Settings;

my $interval; # check every x seconds
my %menuSelection;

my @browseMenuChoices;
my %nextAlarm = ();
my %schedule = ();
my $lastFillday = undef;

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.extendedalarm',
	'defaultLevel' => 'ERROR',
	'description'  => 'PLUGIN_ALARM',
});

my $prefs = preferences('plugin.extendedalarm');

my %snooze;
my %power;

# edit this to change the snooze length in minutes
my $snoozetime = 10;

sub getDisplayName { return 'PLUGIN_ALARM' };

my %functions;
my %alarmActiveFunctions;
my %customPlaylists;

sub setMode {
	my $class  = shift;
	my $client = shift;
	my $method = shift;

	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	if (!defined($menuSelection{$client})) { $menuSelection{$client} = 0; };

	my $count = $prefs->get('count') || 1;
	
	if ($count == 1) {
		alarmSelectHandler($client,'RIGHT');
	} else {
		
		my %params = (
			'listRef'		=> [1..$count],
			'externRef'		=> sub {
							my $alarmID = pack('c',64+$_[1]);
							return (
								$_[0]->string('PLUGIN_ALARM').
								(
									$prefs->client($_[0])->get("name.".$alarmID) 
									? " ".$prefs->client($_[0])->get("name.".$alarmID) 
									: " $alarmID"
								)
							)
						},
			'header'		=> sub {
							my $alarmID = pack('c',64+$_[1]);
							return ($_[0]->string('PLUGIN_ALARM')." ".$alarmID);
						},
			'headerArgs'		=> 'CV',
			'headerAddCount'	=> 1,
			'callback'		=> \&alarmSelectHandler,
			'overlayRef'		=> \&overlayAlarmsFunc,
			'overlayRefArgs'	=> 'CV',
			'valueRef'		=> \$value,
			);
			
		Slim::Buttons::Common::pushModeLeft($client,'INPUT.List',\%params);
	}
	
}

sub overlayAlarmsFunc {
	my $client = shift;
	my $value  = shift;
	
	my $alarmID = pack('c',64+$value);
	
	my $timestring = $client->string("OFF");
	
	if ($prefs->client($client)->get('active.'.$alarmID)) {
		$timestring = Slim::Buttons::Input::Time::timeString( 
			$client,
			Slim::Utils::DateTime::timeDigits(
				$prefs->client($client)->get('time.'.$alarmID)
			),
			-1  # hide the cursor
		);
	}
	
	return (undef,$timestring.' '.$client->symbols('rightarrow'));
}

sub addCustomPlaylist {
	my $class        = shift;
	my $name         = shift; # friendly name for playlist title
	my $callback     = shift; # function to call when the playlist is used for the alarm
	my $callbackargs = shift; # any extra args (beyond the $client) required for the callback

	$customPlaylists{$name} = $callback;
}

sub alarmSelectHandler {
	my ($client,$exittype) = @_;
	$exittype = uc($exittype);

	if ($exittype eq 'LEFT') {
		Slim::Buttons::Common::popModeRight($client);
		
	} elsif ($exittype eq 'RIGHT') {
		my $value = $client->modeParam('listIndex') + 1;
		my $alarmID = pack('c',64+$value);
		
		if (!defined($menuSelection{$client}{$alarmID})) { $menuSelection{$client}{$alarmID} = 0; };
		
		my @menuChoices = @browseMenuChoices;
		if ($prefs->client($client)->get('active.'.$alarmID)) {
			$menuChoices[4] = 'ALARM_ON';
		}
		
		my %params = (
			'listRef'	  => [0..scalar(@menuChoices-1)],
			'externRef'	  => \@menuChoices,
			'stringExternRef' => 1,
			'header'	  => sub {
							return ($prefs->client($_[0])->get("name.".$alarmID) || $_[0]->string('PLUGIN_ALARM') . " ".$alarmID);
						},
			'headerArgs'	  => 'C',
			'headerAddCount'  => 1,
			'callback'	  => \&menuExitHandler,
			'overlayRef'	  => \&overlayFunc,
			'overlayRefArgs'  => 'CV',
			'valueRef'	  => \$menuSelection{$client}{$alarmID},
			'alarmID'	  => $alarmID,
		);
	
		Slim::Buttons::Common::pushModeLeft($client,'INPUT.List',\%params);
	}
};

# the routines
sub setAlarmMode {
	my $client = shift;
	my $method = shift;

	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}
	
	my $alarmID = $client->modeParam('alarmID') || 'A';
	
	if (!defined($menuSelection{$client}{$alarmID})) { $menuSelection{$client}{$alarmID} = 0; };

	my @menuChoices = @browseMenuChoices;
	if ($prefs->client($client)->get('active.'.$alarmID)) {
		$menuChoices[4] = 'ALARM_ON';
	}
	
	# use INPUT.List to display the list
	my %params = (
			'listRef' 	  => [0..scalar(@menuChoices-1)],
			'externRef' 	  => \@menuChoices,
			'stringExternRef' => 1,
			'header' 	  => sub {
							return ($prefs->client($_[0])->get("name.".$alarmID) || 
								$_[0]->string('PLUGIN_ALARM_'.$alarmID));
						},
			'headerArgs' 	  => 'C',
			'headerAddCount'  => 1,
			'callback'	  => \&menuExitHandler,
			'overlayRef'	  => \&overlayFunc,
			'overlayRefArgs'  => 'CV',
			'valueRef'	  => \$menuSelection{$client}{$alarmID},
		);

	Slim::Buttons::Common::pushModeLeft($client,'INPUT.List',\%params);
};

sub overlayFunc {
	my $client = shift;

	my $alarmID = $client->modeParam('alarmID') || 'A';

	if ($browseMenuChoices[shift] =~ /ALARM_O[N|FF]/) {

			return (
				undef,
				Slim::Buttons::Common::checkBoxOverlay(
					$client,
					$prefs->client($client)->get('active.'.$alarmID)
				)
			);

	} else {
		return (undef,$client->symbols('rightarrow'));
	}

};

sub menuExitHandler {
	my ($client,$exittype) = @_;
	$exittype = uc($exittype);

	if ($exittype eq 'LEFT') {
		Slim::Buttons::Common::popModeRight($client);
		
	} elsif ($exittype eq 'RIGHT') {

		my $alarmID = $client->modeParam('alarmID') || 'A';
		
		my $selection = $client->modeParam('externRef')->[$client->modeParam('listIndex')];
		
		if ($selection eq 'ALARM_SET') {
			my $value = $prefs->client($client)->get('time.'.$alarmID);
			
			# set a default if the pref is undefined
			if (!defined $value) {
				$prefs->client($client)->set('time.'.$alarmID,0);
				$value = 0;
			}

			my %params = (
				'header'       => 'ALARM_SET',
				'stringHeader' => 1,
				'valueRef'     => \$value,
				'cursorPos'    => 0,
				'callback'     => \&exitSetHandler,
				#'onChange'     => sub { 
				#				$prefs->client($_[0])->set('time.'.$alarmID,$_[1]); 
				#			},
				'onChangeArgs' => 'CV',
				'alarmID'      => $alarmID,
			);
			Slim::Buttons::Common::pushModeLeft($client, 'INPUT.Time',\%params);
		
		} elsif ($selection eq 'ALARM_SELECT_PLAYLIST') {

			my %params = (
				'name'      => sub { Slim::Buttons::AlarmClock::playlistName(@_) },
				'header'         => '{ALARM_SELECT_PLAYLIST} {count}',
				'pref'           => sub { return $prefs->client($_[0])->get('playlist.'.$alarmID) },
				'onRight'        => sub { 
							my ( $client, $item ) = @_;
							
							$prefs->client($client)->set(
								'playlist.'.$alarmID, 
								exists $Slim::Buttons::AlarmClock::specialPlaylists{$item} || exists $customPlaylists{$name} ? $item : $item->url);
							$client->update();
				},
				'onAdd'          => sub { 
							my ( $client, $item ) = @_;
							
							$prefs->client($client)->set(
								'playlist.'.$alarmID, 
								exists $Slim::Buttons::AlarmClock::specialPlaylists{$item} || exists $customPlaylists{$name} ? $item : $item->url);
							$client->update();
				},
				'onPlay'         => sub { 
							my ( $client, $item ) = @_;
							
							$prefs->client($client)->set(
								'playlist.'.$alarmID, 
								exists $Slim::Buttons::AlarmClock::specialPlaylists{$item} || exists $customPlaylists{$name} ? $item : $item->url);
							$client->update();
				},
				'valueRef'       => sub { return $prefs->client($_[0])->get('playlist.'.$alarmID) },
				'initialValue'   => sub { return $prefs->client($_[0])->get('playlist.'.$alarmID) },
				'alarmID'        => $alarmID,
			);

			my @playlists = Slim::Schema->rs('Playlist')->getPlaylists;
			
			# This is ugly, add a value item to each playlist object so INPUT.Choice remembers selection
			for my $playlist (@playlists) {
				$playlist->{'value'} = $playlist->url;
			}

			$params{'listRef'} = [ @playlists, keys %Slim::Buttons::AlarmClock::specialPlaylists, keys %customPlaylists];
			
			Slim::Buttons::Common::pushModeLeft($client, 'INPUT.Choice',\%params);

		} elsif ($selection =~ /ALARM_O[N|FF]/) {

			if ($prefs->client($client)->get('active.'.$alarmID)) {
				$prefs->client($client)->set('active.'.$alarmID, 0);
				$client->modeParam('externRef')->[4] = 'ALARM_OFF';
			} else {
				$prefs->client($client)->set('active.'.$alarmID, 1);
				$client->modeParam('externRef')->[4] = 'ALARM_ON';
			}

			#$browseMenuChoices[$menuSelection{$client}{$alarmID}] = 'ALARM_OFF';
			#$client->modeParam('externRef')->[$client->modeParam('listIndex')] = 'ALARM_OFF';

			setTimer($client);
			resetSchedule($client);

			$client->update();

		} elsif ($selection eq 'ALARM_SET_VOLUME') {
			my $value = $prefs->client($client)->get('volume.'.$alarmID) || 20;

			#Slim::Buttons::Common::pushModeLeft($client, 'volume.'.$alarmID);
			my %params = (
				'header'         => 'VOLUME',
				'stringHeader'   => 1,
				'headerValue'    => sub { return $_[0]->volumeString($_[1]) },
				'onChange'       => sub { return $prefs->client($_[0])->set('volume.'.$alarmID,$_[1]);},
				'onChangeArgs'   => 'CV',
				'valueRef'       => \$value,
				'alarmID'        => $alarmID,
			);

			Slim::Buttons::Common::pushModeLeft($client, 'INPUT.Bar',\%params);

		} elsif ($selection eq 'PLUGIN_ALARM_DAYS') {

			#my $value = $prefs->client($client)->get('days.'.$alarmID) || 0;

			my %params = (
				'listRef'      => [
						{
							name   => '{PLUGIN_ALARM_DAYS_ALL}',
							value  => 0,
						},
						{
							name   => '{PLUGIN_ALARM_DAYS_1}',
							value  => 1,
						},
						{
							name   => '{PLUGIN_ALARM_DAYS_2}',
							value  => 2,
						},
						{
							name   => '{PLUGIN_ALARM_DAYS_3}',
							value  => 3,
						},
						{
							name   => '{PLUGIN_ALARM_DAYS_4}',
							value  => 4,
						},
						{
							name   => '{PLUGIN_ALARM_DAYS_5}',
							value  => 5,
						},
						{
							name   => '{PLUGIN_ALARM_DAYS_6}',
							value  => 6,
						},
						{
							name   => '{PLUGIN_ALARM_DAYS_7}',
							value  => 7,
						},
						{
							name   => '{PLUGIN_ALARM_DAYS_WEEK}',
							value  => 8,
						},
						{
							name   => '{PLUGIN_ALARM_DAYS_END}',
							value  => 9,
						},
						{
							name   => '{PLUGIN_ALARM_DAYS_ONCE}',
							value  => 10,
						},
					],
				'header'       => '{PLUGIN_ALARM_DAYS} {count}',
				'pref'         => sub { return $prefs->client($_[0])->get('days.'.$alarmID) },
				'onRight'      => sub { 
							my ( $client, $item ) = @_;
							
							$prefs->client($client)->set('days.'.$alarmID, $item->{'value'});
							$client->update();
							resetSchedule($client);
				},
				'onPlay'       => sub { 
							my ( $client, $item ) = @_;
							
							$prefs->client($client)->set('days.'.$alarmID, $item->{'value'});
							$client->update();
							resetSchedule($client);
				},
				'onAdd'        => sub { 
							my ( $client, $item ) = @_;
							
							$prefs->client($client)->set('days.'.$alarmID, $item->{'value'});
							$client->update();
							resetSchedule($client);
				},
				'alarmID'      => $alarmID,
				'valueRef'     => sub { return $prefs->client($_[0])->get('days.'.$alarmID) },
				'initialValue' => sub { return $prefs->client($_[0])->get('days.'.$alarmID) },
			);

			Slim::Buttons::Common::pushModeLeft($client, 'INPUT.Choice',\%params);

		} elsif ($selection eq 'PLUGIN_ALARM_DURATION') {
			my $value = $prefs->client($client)->get('duration.'.$alarmID) || 0;

			my %params = (
				'listRef'        => [0,15,30,60,90,120,150,180],
				'externRef'      => [$client->string('PLUGIN_ALARM_NOEND'), "15", "30", "60", "90", "120", "150", "180"],
				'header'         => $client->string('PLUGIN_ALARM_DURATION'),
				'onChange'       => sub { $prefs->client($_[0])->set('duration.'.$alarmID,$_[1]); },
				'onChangeArgs'   => 'CV',
				'valueRef'       => \$value,
				'alarmID'        => $alarmID,
			);

			Slim::Buttons::Common::pushModeLeft($client, 'INPUT.List',\%params);

		} elsif ($selection eq 'ALARM_FADE') {
			my $value = $prefs->client($client)->get('fadeseconds.'.$alarmID) || 20;

			my %params = (
				'header'         => 'ALARM_FADE',
				'stringHeader'   => 1,
				'headerValue'    =>'unscaled',
				'onChange'       => sub { return $prefs->client($_[0])->set('fadeseconds.'.$alarmID,$_[1]);},
				'onChangeArgs'   => 'CV',
				'valueRef'       => \$value,
				'alarmID'        => $alarmID,
			);

			Slim::Buttons::Common::pushModeLeft($client, 'INPUT.Bar',\%params);
		}
	}
};

sub initPlugin {
	my $class = shift;
	
	@browseMenuChoices = qw (ALARM_SET
				PLUGIN_ALARM_DURATION
				ALARM_SELECT_PLAYLIST
				ALARM_SET_VOLUME
				ALARM_OFF
				PLUGIN_ALARM_DAYS
				ALARM_FADE
			);
	
	if (!$prefs->get('count')) {
		$prefs->set('count',1)
	}
	
	Slim::Control::Request::subscribe( \&clientConnectCallback, [['client']]);
	
	# some initialization code, adding modes for this module
	for my $count (1..$prefs->get('count')) {
		my $alarmID = pack('c',64+$count);
		
		Slim::Buttons::Common::addMode(
			'PLUGIN.alarmactive.'.$alarmID, 
			getAlarmActiveFunctions(), 
			\&setAlarmActiveMode,
			\&leaveAlarmActiveMode,
		);
		
		$log->info("Alarm Plugin $alarmID: Init");
	}

		Slim::Buttons::Common::addSaver(
			'SCREENSAVER.alarmtime.',
			getScreensaverAlarmtime(),
			\&setScreensaverAlarmTimeMode,
			undef,
			'PLUGIN_SCREENSAVER_ALARM',
		);
	
	%functions = ();
	
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

	if (Slim::Utils::PluginManager->isEnabled('Plugins::TrackStat::Plugin')) {
		$alarmActiveFunctions{'playFavorite'} = sub { Plugins::TrackStat::Plugin::saveRatingsForCurrentlyPlaying($_[0], undef, $_[2]); };

	} else {
		$alarmActiveFunctions{'numberScroll'} = sub { snooze(shift); };
	}

	setTimer();
	#addGroups();
	
	%week = (
		'0' => {map {$_ => 1} (0,7,9,10,11)},
		'1' => {map {$_ => 1} (0,1,8,10,11)},
		'2' => {map {$_ => 1} (0,2,8,10,11)},
		'3' => {map {$_ => 1} (0,3,8,10,11)},
		'4' => {map {$_ => 1} (0,4,8,10,11)},
		'5' => {map {$_ => 1} (0,5,8,10,11)},
		'6' => {map {$_ => 1} (0,6,9,10,11)},
	); 
	
	Plugins::ExtendedAlarm::Settings->new;
	
	$class->SUPER::initPlugin();
}

sub setTimer {
	my $client = shift;
	
	# dont' have more than one.
	Slim::Utils::Timers::killTimers($client, \&checkAlarms);
	
	#timer to check alarms on an interval
	Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + ($interval || 1), \&checkAlarms);
}

sub clientConnectCallback {
	my $request = shift;

	my $client = $request->client();
	
	if( $request->isCommand([['client'], ['new']]) || $request->isCommand([['client'], ['reconnect']])) {
		fill24HScheduler($client);
	}
}

sub resetSchedule {
	my $client = shift;
	
	$log->info("settings changed, reset alarm scheduler.\n");
	$nextAlarm{$client} = undef;
	fill24HScheduler($client);
}

sub fill24HScheduler {
	my $thisclient = shift;
	
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	my $currenttime = $hour * 60 * 60 + $min * 60;
	
	for my $client ($thisclient || Slim::Player::Client::clients()) {
	
		$schedule{$client} = undef;
		
		if ( $log->is_debug ) {
				$log->debug("Fill scheduler for ".$client->name);
				$log->debug("Current time is ".$currenttime);
				$log->debug("Today is ".$wday);
		};
		
		for my $count (1..$prefs->get('count')) {
			my $alarmID = pack('c',64+$count);
			#$log->debug(sprintf("count is %s.",$count));
			#$log->debug(sprintf("state is %s.",$prefs->client($client)->get('active.'.$alarmID)));
			if ($prefs->client($client)->get('active.'.$alarmID)) {

				my $time      =  $prefs->client($client)->get('time.'.$alarmID);
				my $alarmdays =  $prefs->client($client)->get('days.'.$alarmID);
				my $tomorrow  = $wday < 6 ? $wday +1 : 1;
				#$log->debug($time." ".$alarmdays." ".$tomorrow);
				if ($alarmdays == 11) {
					my $dom = $prefs->client($client)->get('dayofmonth.'.$alarmID);
					my $month = $prefs->client($client)->get('month.'.$alarmID);
					
					# bypass specific date alarm if not within a day.
					if ($month != $mon || ($mday != $dom && $mday+1 != $dom)) {
						next;
					}
				}
				
				# today's alarms
				#$log->debug($wday." ".$alarmdays." ".$week{$wday}{$alarmdays});
				if ($time && $week{$wday}{$alarmdays} && $time > $currenttime) {
					$schedule{$client}{$time} = $alarmID;
					$log->debug("Found alarm $alarmID for ".$client->name." at $time");
				
				#tomorrow's alarms
				} elsif($time && $week{$tomorrow}{$alarmdays} && $time < $currenttime) {
					$schedule{$client}{$time} = $alarmID;
					$log->debug("Found next day alarm $alarmID for ".$client->name." at ". $time);
				}
			}
		}
	}
	
	if ($log->is_debug) {
		$log->info("alarms pending:");
		for my $alrmclient (Slim::Player::Client::clients()) {
			$log->info(sub {return $alrmclient->name." - ".Data::Dump::dump($schedule{$alrmclient})}) if $schedule{$alrmclient};
		}
	}
}

sub getFuzzyTimeF {
	my ($client, $time, $format) = @_;
	
	if( Slim::Utils::PluginManager->isEnabled('Plugins::FuzzyTime::Plugin')) {
		return Plugins::FuzzyTime::Public::timeF($client,$time,$format);
	}
	
	return Slim::Utils::DateTime::timeF($time,$format);
}

sub getFuzzyTime {
	my ($client, $time, $format) = @_;
	
	if( Slim::Utils::PluginManager->isEnabled('Plugins::FuzzyTime::Plugin')) {
		return int(Plugins::FuzzyTime::Public::getClientTime($client));
	}
	
	return time();
}

sub checkAlarms {
	my $client = shift;
	
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(&getFuzzyTime($client));
	my $time = $hour * 60 * 60 + $min * 60;
	
	# fill the scheduler is it's empty or it's midnight.
	if (($time < 3600 && defined $lastFillDay && $lastFillDay != $wday )) {
		$log->info("repopulating 24 hour schedule.\n");
		fill24HScheduler();
		$lastFillDay = $wday;
	}
	
	if ($sec == 0) { # once we've reached the beginning of a minute, only check every 60s
		$interval = 60;
	}

	if ($sec >= 50 || ! defined $interval) { # if we end up falling behind, go back to checking each second
		$interval = 60-$sec;
		$log->info("resync timer in $interval seconds.\n");
	}

	for my $count (1..$prefs->get('count')) {
		my $alarmID = pack('c',64+$count);
	
		$log->info("Checking status of Alarm $alarmID") if defined $interval && $min == 0;

		foreach my $client (Slim::Player::Client::clients()) {
	
			if (!exists $schedule{$client}) {
				fill24HScheduler($client);
			}
	
			# do we have an alarm for this time
			if ($schedule{$client}{$time} && $schedule{$client}{$time} eq $alarmID) {
			
					$log->debug(sprintf("%s has an alarm now, but checking days to be safe",$client->name));
					#Now double check as a sanity check
					my $days = $prefs->client($client)->get('days.'.$alarmID);
					my $dom = $prefs->client($client)->get('dayofmonth.'.$alarmID);
					my $month = $prefs->client($client)->get('month.'.$alarmID);
					
					if (!defined($days)) {$days = 0;}
					
					if (!defined($dom)) {$dom = 0;}
					
					if (!defined($month)) {$month = 0;}
					
					if ((($wday && $days == $wday) || ($wday == 0 && $days == 7)) # single day
							|| ($days == 0) # all 7 days
							|| ($days == 10) # once only
							|| (($days == 8) && (($wday > 0) && ($wday < 6))) # weekdays
							|| (($days == 9) && (($wday == 6) || ($wday == 0))) # weekends
							|| (($days == 11) && ($dom == $mday) && (($month-1) == $mon))) {  # exact date
					
			
						$log->warn(sprintf("%s triggering $alarmID",$client->name));
						Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + 2, \&alarmTrigger, $alarmID);
					}
			}
		}
	}
	setTimer($client);
}

sub findNextAlarm {
	my $client = shift;
	
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	my $time = $hour * 60 * 60 + $min * 60;
	
	my $next = undef;
	
	# send back the ID of the next alarm
	if (defined $schedule{$client}) {
	
		my @sorted = sort { $a <=> $b } keys %{$schedule{$client}};
	
		for my $a (@sorted) {
			
			if ($time < $a) {
				$next = $schedule{$client}{$a};
				last;
			}
		}
		
		if (!defined $next) {
			$next = $schedule{$client}{$sorted[0]};
		}
	
		if ($next) {
			$log->info("next alarm is ID: $next\n");
			$nextAlarm{$client} = $next;
		} else {
			$log->warn("next alarm is out of range");
			$nextAlarm{$client} = 0;
		}
	} else {
		fill24HScheduler($client);
	}
}

sub getFunctions() {
	return \%functions;
}

sub exitSetHandler {
	my ($client,$exittype) = @_;
	
	my $alarmID = $client->modeParam('alarmID') || 'A';
	
	$exittype = uc($exittype);

	if ($exittype eq 'LEFT') {
		
		if ($browseMenuChoices[$menuSelection{$client}] eq 'ALARM_SET') {
			$prefs->client($client)->set('time.'.$alarmID,${$client->modeParam('valueRef')});
			resetSchedule($client);
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
		Time::HiRes::time() + (preferences('server')->client($client)->get("screensavertimeout") * 5),
	);

	$client->lines(\&alarmActiveLines);

	my $linefunc = $client->lines();
	
	$client->modeParam('modeUpdateInterval', 1);
	
	$client->modeParam('alarmID', substr(Slim::Buttons::Common::mode($client),-1));
	
	if ($prefs->client($client)->get('showclock.'.$client->modeParam('alarmID')) && $client->display->isa('Slim::Display::Transporter')) {
		$oldVisualizer{$client} = $client->modeParam('visu');
	}
};

sub leaveAlarmActiveMode {
	my $client = shift;

	$client->modeParam('visu', $oldVisualizer{$client});
	$client->update({'screen2' => {}});
}

sub alarmActiveLines {
	my $client = shift;
	
	my $parts;

	Slim::Hardware::IR::setLastIRTime(
		$client,
		Time::HiRes::time() + (preferences('server')->client($client)->get("screensavertimeout") * 5),
	);

	my $playlistlen = Slim::Player::Playlist::count($client);
	
	my $alarmID = $client->modeParam('alarmID') || 'A';
	
	if (my $name = $prefs->client($client)->get("name.".$alarmID)) {
		$parts->{'line'}[0] = $name.' '.$client->string('NOW_PLAYING')
	} else {
		$parts->{'line'}[0] = $client->string('PLUGIN_ALARM_NOW_PLAYING');
	}
	
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
		$parts->{'line'}[0] .= "(".int(($snooze{$client} - $time + 50)/60)." ".$client->string('MINUTES').")";
		$parts->{'line'}[1] = "ZzZzzZzzzZzZ..." x4;

	} elsif ($playlistlen < 1) {
		$parts->{'line'}[1] = $client->string('NOTHING');

	} else { 
		$parts->{'line'}[0] = $parts->{'line'}[0] . sprintf " (%d %s %d) ", 
			Slim::Player::Source::playingSongIndex($client) + 1, 
			$client->string('OUT_OF'), $playlistlen;
	}
	
	$client->nowPlayingModeLines($parts);
	
	if ($prefs->client($client)->get('showclock.'.$alarmID) && $client->display->isa('Slim::Display::Transporter')) {
		$parts->{'screen2'} = {
			'center' => [ '',getFuzzyTimeF($client,undef,Slim::Utils::Prefs::get('screensaverTimeFormat')) ],
			'fonts'  => { 
					'graphic-320x32' => 'full',
					'graphic-280x16' => 'large',
					'text'           => 1,
				},
		};
	}
	
	return $parts;
};

sub snooze {
	my $client = shift;
	
	my $alarmID = $client->modeParam('alarmID') || 'A';
	
	my $name = $prefs->client($client)->get("name.".$alarmID);
	
	if (!$snooze{$client}) {
		$log->info("Alarm Plugin $alarmID: snooze");

		$client->execute(['stop']);

		$log->info("Alarm Plugin $alarmID: Alarm $alarmID snoozing...");
		$snooze{$client} = Time::HiRes::time() + ($snoozetime * 60);

		$log->info(sprintf("Alarm Plugin $alarmID: Coundown: %d",$snooze{$client}));
		Slim::Utils::Timers::setTimer($client, $snooze{$client}, \&unSnooze, $client);

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
	
	my $alarmID = $client->modeParam('alarmID') || 'A';
	
	my $name = $prefs->client($client)->get("name.".$alarmID);
	
	$snooze{$client} = 0;
	
	$client->execute(['stop']);
	
	$log->info("Alarm Plugin $alarmID: Alarm $alarmID Has been killed");
	
	Slim::Utils::Timers::killTimers($client, \&unSnooze);
	Slim::Utils::Timers::killTimers($client, \&killAlarm);
	
	if ($prefs->client($client)->get('days.'.$alarmID) == 10) {
		#turn off after single trigger
		$prefs->client($client)->set('active.'.$alarmID, 0);
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
	
	my $alarmID = $client->modeParam('alarmID') || 'A';
	
	$snooze{$client} = 0;
	$log->info("Alarm Plugin $alarmID: Snooze Over");
	$client->execute(["playlist", "jump", "+1"]);
	Slim::Player::Playlist::refreshPlaylist($client);

	$client->showBriefly({
		'line'     => [$client->string('PLUGIN_ALARM_NOW_PLAYING'),$client->string('PLUGIN_ALARM_WAKEUP')],
		'duration' => 3,
		'block'    => 1,
	});
};

sub alarmTrigger {
	my $client  = shift;
	my $alarmID = shift;
	
	$log->warn("triggering $alarmID");
	
	Slim::Hardware::IR::setLastIRTime(
		$client,
		Time::HiRes::time() + (preferences('server')->client($client)->get("screensavertimeout") * 5),
	);
	
	# store power state, for returning after alarm ends.
	$power{$client} = $client->power();

	# wipe the next alarm record, since we've now triggered on it. allows findNext to grab the next one.
	$nextAlarm{$client} = undef;

	$client->execute(['stop']);
	my $volume = $prefs->client($client)->get('volume.'.$alarmID);
	
	$log->info("Alarm Plugin $alarmID: Alarm $alarmID Has Triggered");
	
	if ((defined ($volume)) && !$snooze{$client}) {
		$client->execute(["mixer", "volume", $volume]);
	}

	$client->fade_volume($prefs->client($client)->get('fadeseconds.'.$alarmID));
	
	my $playlist = $prefs->client($client)->get('playlist.'.$alarmID);
	
	if (defined $playlist && !$snooze{$client}) {
		$client->execute(["pause", 0]);
	
	if ($Slim::Buttons::AlarmClock::specialPlaylists{$playlist}) {
			Slim::Plugin::RandomPlay::Plugin::playRandom($client,$Slim::Buttons::AlarmClock::specialPlaylists{$playlist});
	
	} elsif ($customPlaylists{$playlist}) {
			&{$customPlaylists{$playlist}}($client);
	
	} elsif (defined $playlist && $playlist ne 'CURRENT_PLAYLIST') {

			my $playlistObj = Slim::Schema->rs('Playlist')->objectForUrl({
				'url' => $playlist,
			});

			if (blessed($playlistObj) && $playlistObj->can('id')) {

				$log->info("Alarm Plugin $alarmID: Loading Playlist - $playlist");
				my $autoshuffle = $prefs->client($client)->get('autoshuffle.'.$alarmID);
				
				if ($autoshuffle) {

					$client->execute(["playlist", "loadtracks", "playlist=".$playlistObj->id()]);
					$client->execute(["playlist", "shuffle", $autoshuffle], \&alarmLoadDone, [$client]);
					$log->info ("Alarm Plugin $alarmID: tracks shuffled");
				
				} else {
					$client->execute(["playlist", "loadtracks", "playlist=".$playlistObj->id()], \&alarmLoadDone, [$client]);
				}
			
			} else {
				$log->error("Alarm Plugin $alarmID: $playlist not loaded, using Current Playlist instead");
				$client->execute(['play']);
			}
		
		} else {
			$log->info("Alarm Plugin $alarmID: Playing Current Playlist");
			$client->execute(['play']);
		}
	
	} elsif (!$snooze{$client}) {
		$log->info("Alarm Plugin $alarmID: Playing Alarm $alarmID");
		$client->execute(['play']);
	};
	
	my $sleepTime = $prefs->client($client)->get('duration.'.$alarmID);
	$client->execute(["sleep", $sleepTime * 60]) if $sleepTime;
	
	if ($prefs->client($client)->get('days.'.$alarmID) == 10) {
		#turn off after single trigger
		$prefs->client($client)->set('active.'.$alarmID, 0);
	}
	
	$log->debug("pushing to active alarm mode");
	Slim::Buttons::Common::pushModeLeft($client, 'PLUGIN.alarmactive.'.$alarmID);
	#Slim::Buttons::Common::pushModeLeft($client, 'playlist');
};

sub playlists {
	my $playlists = {
		'' => undef,
	};

	for my $playlist (Slim::Schema->rs('Playlist')->getPlaylists) {

		$playlists->{$playlist->url} = Slim::Music::Info::standardTitle(undef, $playlist);
	}

	for my $key (keys %Slim::Buttons::AlarmClock::specialPlaylists) {
		$playlists->{$key} = $key;
	}

	for my $key (keys %customPlaylists) {
		$playlists->{$key} = $key;
	}
	
	return $playlists;
}

sub addGroup {
	return 'PLUGINS';
}

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

sub setScreensaverAlarmTimeMode {
	my $client = shift;
	$client->lines(\&screensaverAlarmTimelines);

	# setting this param will call client->update() frequently
	$client->modeParam('modeUpdateInterval', 1); # seconds
	
	# grab alarm id from the current mode name
	$client->modeParam('saverID', 1);
}

sub screensaverAlarmTimelines {
	my $client = shift;

	my @line = (Slim::Utils::DateTime::longDateF(), getFuzzyTimeF());
	
	my $alarmID = defined $nextAlarm{$client} ? $nextAlarm{$client} : findNextAlarm($client);
	
	if ($alarmID) {
		
		my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
		
		my $time = $prefs->client($client)->get('time.'.$alarmID);
		
		my ($h0, $h1, $m0, $m1, $p) = Slim::Utils::DateTime::timeDigits($time);
		my $timestring = ((defined($p) && $h0 == 0) ? ' ' : $h0) . $h1 . ":" . $m0 . $m1 . " " . (defined($p) ? $p : '');
		
		if ($prefs->client($client)->get('offDisplaySize')) {
		
			# for large size, display in the format:    hh:mm   m xx:yy
			# with:  hh = current hour, mm = current minute, m = alarm_mode, xx = alarm hour, yy = alarm minute
			my $sec = int(substr($line[1],6,2));
			my $even = $sec - (int($sec / 2) * 2);     # blink of separator
			my $sep = ".";
			
			if ($even) {$sep = ":";}
			
			my @alarmModes = ('*', '1','2','3','4','5','6','7','w', 'e' ,'o', 'd');
			
			$line[1] = substr($line[1],0,2).$sep.substr($line[1],3,2)."   ";
			$line[1] .= $alarmModes[$prefs->client($client)->get("days.".$alarmID)];
			$line[1] .= " $timestring";
		
		} else {
			# for small size display verbose information
			# upper line:  centered date (default style)
			# lower line:  Time  hh:mm:ss   Alarm  hh:mm  mode
		
			my @alarmModes = ('7d', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun', 'Week', ,'SaSo', 'Next', 'Today');
			$line[1] .= " ".$client->string("PLUGIN_ALARM_WAKE")." $timestring";
			$line[1] .= " ".$alarmModes[$prefs->client($client)->get("days.".$alarmID)];
		}
	}
	
	return {
		'center' => \@line,
		'overlay'=> [ ($nextAlarm{$client} ? $client->symbols('bell') : undef) ],
	};
}

1;

__END__

