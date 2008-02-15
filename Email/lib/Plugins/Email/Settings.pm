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


use Slim::Utils::Prefs;

my $prefs = preferences('plugin.email');


sub name {
	return 'PLUGIN_EMAIL_BROWSER';
}

sub page {
	return 'plugins/Email/settings/basic.html';
}

sub prefs {
	return qw(
		checkwhen
		display
		audio
		servers
		users
		passwords
		UseSSL
	);
}

sub handler {
	my ($class, $client, $params) = @_;

	return $class->SUPER::handler($client, $params);
}

1;

__END__
