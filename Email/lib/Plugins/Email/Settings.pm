#line 1 "Plugins/Email/Settings.pm"
package Plugins::Email::Settings;

# SlimServer Copyright (C) 2001-2006 Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.email',
	'defaultLevel' => 'WARN',
	'description'  => 'PLUGIN_EMAIL_BROWSER',
});

sub name {
	return 'PLUGIN_EMAIL_BROWSER';
}

sub page {
	return 'plugins/Email/settings/basic.html';
}

sub handler {
	my ($class, $client, $params) = @_;

	# These are lame preference names.
	my @prefs = qw(
		checkwhen
		display
		audio
		servers
		users
		passwords
	);

	if ($params->{'submit'}) {
	
		my @changed = ();

		for my $pref (@prefs) {
	
			Slim::Utils::Prefs::set("plugin-Email-".$pref, $params->{$pref});
		}
		
	}

	for my $pref (@prefs) {

		$params->{'prefs'}->{$pref} = Slim::Utils::Prefs::get("plugin-Email-".$pref);

	}

	return $class->SUPER::handler($client, $params);
}

1;

__END__
