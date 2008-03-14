# Updated by Kevin Deane-Freeman (kevin@deane-freeman.com) May 2003
#
# This code is derived from code with the following copyright message:
#
# SliMP3 Server Copyright (C) 2001 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

package Plugins::MythRemote::Plugin;

use Slim::Utils::Prefs;
use base qw(Slim::Plugin::Base);
use strict;
use Slim::Utils::Strings qw (string);

use File::Spec::Functions qw(catfile);

my $prefs = preferences('plugin.mythtv');
my $prefsServer = preferences('server');

my %menuItems;
my %numOfMenuItems;
my %menuSelection;
my %functions;

my $mythremote = 'http://phobos/mythweb/remote/';
my $mythremotekey = $mythremote.'keys?command=';

my $http;

my $log          = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.mythremote',
	'defaultLevel' => 'WARN',
	'description'  => getDisplayName(),
});

sub initPlugin {
	my $class = shift;

	%functions = (
		'up' => sub  {
			my $client = shift;
			
			$http->get($mythremotekey.'up');
		},
		
		'down' => sub  {
			my $client = shift;
			
			$http->get($mythremotekey.'down');
		},
		
		'left' => sub  {
			my $client = shift;
			
			$http->get($mythremotekey.'left');
		},
		
		'right' => sub  {
			my $client = shift;
			
			$http->get($mythremotekey.'right');
		},
		
		'play' => sub  {
			my $client = shift;

			$http->get($mythremotekey.'enter');
		},
		
		'pause' => sub  {
			my $client = shift;

			$http->get($mythremotekey.'p');
		},
		
		'jump_fwd' => sub  {
			my $client = shift;

			$http->get($mythremotekey.'z');
		},

		'jump_rew' => sub  {
			my $client = shift;

			$http->get($mythremotekey.'escape');
		},

		'add' => sub  {
			my $client = shift;

			$http->get($mythremotekey.'a');
		},

 
		'power_toggle' => sub  {
			my $client = shift;
			
			$http->get($mythremote.'?unping=pegasus');
			Slim::Buttons::Common::popModeRight($client);
		},

	);

	$class->SUPER::initPlugin();
}

sub getDisplayName {return 'PLUGIN_MYTHREMOTE';}

sub setMode() {
	my $class = shift;
	my $client = shift;
	my $push = shift;

	$client->lines(\&lines);

	$http = Slim::Networking::SimpleAsyncHTTP->new(
		sub {
			my $http = shift;
		},
		sub {
			my $http = shift;
			$log->error("Remote Frontend not responding\n" . $http->error);
		},
		{
			timeout => 5
		}
	);
	
	$http->get($mythremote.'?ping=pegasus');
}

sub lines {
	my $client = shift;
	
	my ($line1, $line2);

	$line1 = $client->string('PLUGIN_MYTHREMOTE');
	$line2 = $client->string('PLUGIN_MYTHREMOTE_INSTRUCTIONS');

	return {'line'    => [$line1, $line2],
			'overlay' => [undef,undef]};
}

sub getFunctions() {
	return \%functions;
}

# ----------------------------------------------------------------------------
# some initialization code, adding modes for this module
#Slim::Buttons::Common::addMode('bookmarkmode', getRemoteControlFunctions(), \&enterRemoteControl, \&leaveRemoteControl);

1;
