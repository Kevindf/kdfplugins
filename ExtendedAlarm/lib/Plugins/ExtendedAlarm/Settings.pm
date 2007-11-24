#line 1 "Plugins/ExtendedAlarm/Settings.pm"
package Plugins::ExtendedAlarm::Settings;

# SlimServer Copyright (C) 2001-2006 Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Prefs;

my $alarmID = 'A';

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.extendedalarm',
	'defaultLevel' => 'WARN',
	'description'  => 'PLUGIN_ALARM',
});

my $prefs = preferences('plugin.extendedalarm');

$prefs->migrate(1, sub {

	$prefs->set('count', Slim::Utils::Prefs::OldPrefs->get('PLUGIN.alarmcount'));
	1;
});

$prefs->migrateClient(1, sub {
	my ($clientprefs, $client) = @_;
	
	for my $count (1.. $prefs->get('count')) {
		my $alarmID = pack('c',64+$count);
		
		$clientprefs->set('name.'.$alarmID,        Slim::Utils::Prefs::OldPrefs->clientGet($client, 'PLUGIN.alarmname.'.$alarmID));
		$clientprefs->set('active.'.$alarmID,      Slim::Utils::Prefs::OldPrefs->clientGet($client, 'PLUGIN.alarm.'.$alarmID));
		$clientprefs->set('time.'.$alarmID,        Slim::Utils::Prefs::OldPrefs->clientGet($client, 'PLUGIN.alarmtime.'.$alarmID));
		$clientprefs->set('duration.'.$alarmID,    Slim::Utils::Prefs::OldPrefs->clientGet($client, 'PLUGIN.alarmduration.'.$alarmID));
		$clientprefs->set('volume.'.$alarmID,      Slim::Utils::Prefs::OldPrefs->clientGet($client, 'PLUGIN.alarmvolume.'.$alarmID));
		$clientprefs->set('days.'.$alarmID,        Slim::Utils::Prefs::OldPrefs->clientGet($client, 'PLUGIN.alarmdays.'.$alarmID));
		$clientprefs->set('month.'.$alarmID,       Slim::Utils::Prefs::OldPrefs->clientGet($client, 'PLUGIN.alarmmonth.'.$alarmID));
		$clientprefs->set('dayofmonth.'.$alarmID,  Slim::Utils::Prefs::OldPrefs->clientGet($client, 'PLUGIN.alarmdayofmonth.'.$alarmID));
		$clientprefs->set('playlist.'.$alarmID,    Slim::Utils::Prefs::OldPrefs->clientGet($client, 'PLUGIN.alarmplaylist.'.$alarmID));
		$clientprefs->set('autoshuffle.'.$alarmID, Slim::Utils::Prefs::OldPrefs->clientGet($client, 'PLUGIN.alarmautoshuffle.'.$alarmID));
		$clientprefs->set('fadeseconds.'.$alarmID, Slim::Utils::Prefs::OldPrefs->clientGet($client, 'PLUGIN.alarmfadeseconds.'.$alarmID));
	};
	1;
});

sub prefstest {
	my ($class, $client) = @_;
	
	my @prefs;
	
	for my $count (1..$prefs->get('count')) {
		my $alarmID = pack('c',64+$count);
		
		push @prefs,
			'name.'.$alarmID,
			'active.'.$alarmID,
			'duration.'.$alarmID,
			'volume.'.$alarmID,
			'days.'.$alarmID,
			'month.'.$alarmID,
			'dayofmonth.'.$alarmID,
			'playlist.'.$alarmID,
			'autoshuffle.'.$alarmID,
			'fadeseconds.'.$alarmID;
		
		if ($client->display->isa('Slim::Display::Transporter')) {
			push @prefs,'showclock.'.$alarmID;
		}
	}
	
	return ($prefs, @prefs);
}

sub name {
	return 'PLUGIN_ALARM';
}

sub page {
	return 'plugins/ExtendedAlarm/settings/basic.html';
}

sub needsClient {
	return 1;
}

sub handler {
	my ($class, $client, $paramRef) = @_;

	# These are lame preference names.
	my @prefs = qw(
		name
		time
		duration
		volume
		days
		month
		dayofmonth
		playlist
		fadeseconds
	);
	
	if ($client->display->isa('Slim::Display::Transporter')) {
		push @prefs,'showclock';
	}

	if ($paramRef->{'AddAlarm'}) {
		$prefs->set('count', $prefs->get('count')+1);
		Plugins::ExtendedAlarm::Plugin->initPlugin();
	}
	if ($paramRef->{'RemoveLast'}) {
		$prefs->set('count', $prefs->get('count')-1)
	}

	if ($paramRef->{'saveSettings'}) {
	
		for my $count (1..$prefs->get('count')) {
			my $alarmID = pack('c',64+$count);
		
			for my $pref (@prefs) {
				
				if (defined $paramRef->{$pref.$count}) {
	
					if ($pref eq 'time') {
						my $newTime = Slim::Utils::DateTime::prettyTimeToSecs($paramRef->{"time".$count});
						my $oldTime = $prefs->client($client)->get('time.'.$alarmID);
						
						if (!defined $oldTime || $newTime != $oldTime) {
		
							my (undef, $ok) = $prefs->client($client)->set($pref.'.'.$alarmID, $newTime);
							
							if (!$ok) {
								$paramRef->{'warning'} .= sprintf(Slim::Utils::Strings::string('SETTINGS_INVALIDVALUE'),
									$paramRef->{$pref}, $pref);
							}
						}
					} else {
			
						my (undef, $ok) = $prefs->client($client)->set($pref.'.'.$alarmID, $paramRef->{$pref.$count});
						
						if (!$ok) {
							$paramRef->{'warning'} .= sprintf(Slim::Utils::Strings::string('SETTINGS_INVALIDVALUE'),
								$paramRef->{$pref}, $pref);
						}
					}
				}
				
				# alternative Now Playing display
				#if ($client->prefGet('PLUGIN.alarmShowClock.'.$alarmID)) {
				#	$client->customPlaylistLines(\&Plugins::ExtendedAlarm::Plugin::specialAlarmLines);
				#	$client->suppressStatus(1);
				#} else {
				#	$client->customPlaylistLines(undef);
				#	$client->suppressStatus(undef);
				#}
			}
			
			$prefs->client($client)->set('active.'.$alarmID, $paramRef->{'active'.$count} eq 'on' ? 1: 0);
			$prefs->client($client)->set('autoshuffle.'.$alarmID, $paramRef->{'autoshuffle'.$count} eq 'on' ? 1: 0);
		}
		Plugins::ExtendedAlarm::Plugin::resetSchedule($client);
	}

	for my $count (1..$prefs->get('count')) {
		my $alarmID = pack('c',64+$count);
	
		for my $pref (@prefs) {
			
			if ($pref eq 'time') {
	
				my $time = Slim::Utils::DateTime::secsToPrettyTime(
					$prefs->client($client)->get($pref.'.'.$alarmID)
				);
				
				$paramRef->{'prefs'}->{$pref}->{$count} = $time;
	
			} else {
			
				$paramRef->{'prefs'}->{$pref}->{$count} = $prefs->client($client)->get($pref.'.'.$alarmID);
			}
			
			$paramRef->{'alarmid'}->{$count} = $alarmID;
		}
		
		$paramRef->{'prefs'}->{'active'}->{$count} = $prefs->client($client)->get('active.'.$alarmID);
	}
	
	$paramRef->{'max'} = $prefs->get('count');

	# Load any option lists for dynamic options.
	my $playlists = {
		'' => undef,
	};

	for my $playlist (Slim::Schema->rs('Playlist')->getPlaylists) {

		$playlists->{$playlist->url} = Slim::Music::Info::standardTitle(undef, $playlist);
	}

	my $specialPlaylists = \%Slim::Buttons::AlarmClock::specialPlaylists;

	for my $key (keys %{$specialPlaylists}) {

		$playlists->{$key} = string($key);
	}

	$paramRef->{'playlistOptions'} = $playlists;

	return $class->SUPER::handler($client, $paramRef);
}

1;

__END__
