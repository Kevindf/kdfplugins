package Plugins::ExecuteScript::Settings;

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

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.executescript',
	'defaultLevel' => 'WARN',
	'description'  => 'PLUGIN_EXECUTE_SCRIPT',
});

my $prefs = preferences('plugin.executescript');

$prefs->migrate(1, sub {
	$prefs->set('open', Slim::Utils::Prefs::OldPrefs->get('plugin-Execute-open'));
	$prefs->set('play', Slim::Utils::Prefs::OldPrefs->get('plugin-Execute-play'));
	$prefs->set('stop', Slim::Utils::Prefs::OldPrefs->get('plugin-Execute-stop'));
	$prefs->set('power_on', Slim::Utils::Prefs::OldPrefs->get('plugin-Execute-power_on'));
	$prefs->set('p0wer_off', Slim::Utils::Prefs::OldPrefs->get('plugin-Execute-power_off'));
	1;
});

$prefs->migrateClient(1, sub {
	my ($clientprefs, $client) = @_;
	
	$clientprefs->set('script',        Slim::Utils::Prefs::OldPrefs->clientGet($client, 'script'));
	1;
});
sub name {
	return 'PLUGIN_EXECUTE_SCRIPT';
}

sub page {
	return 'plugins/ExecuteScript/settings/basic.html';
}

sub prefs {
	return ($prefs, qw(
		open
		play
		stop
		power_on
		power_off
	) );
}

sub handler {
	my ($class, $client, $paramRef) = @_;
	
	my %scripts = Plugins::ExecuteScript::Plugin::scriptlist();
	$paramRef->{'scriptOptions'} = \%scripts;
	
	return $class->SUPER::handler($client, $paramRef);
}


1;

__END__
