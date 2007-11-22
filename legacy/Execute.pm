# Execute.pm by Kevin Deane-Freeman (kevindf@shaw.ca) April 2003
# Bug fixed by Christopher Johnson (chris@dirigo.net) January 2007
#
# This code is derived from code with the following copyright message:
#
# SliMP3 Server Copyright (C) 2001 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

package Plugins::Execute;

use strict;

use Slim::Player::Playlist;
use Slim::Player::Source;
use Slim::Player::Sync;
use Slim::Utils::Strings qw (string);
use File::Spec::Functions qw(:ALL);
use POSIX qw(strftime);
use FindBin qw($Bin);
use Slim::Utils::Misc;

use vars qw($VERSION);
$VERSION = substr(q$Revision: 1.19 $,10);

my $interval = 1; # check every x seconds
my @browseMenuChoices;
my %menuSelection;
my %functions;

#  NOTE: Default script folder /usr/local/slimserver/scripts must be created.
sub scriptPath {
	my $scriptPath = $Bin.'/scripts';

	if (Slim::Utils::OSDetect::OS() eq 'mac') {
		$scriptPath = catfile(Slim::Utils::Prefs::preferencesPath(),'scripts');
	}
	return $scriptPath;
}
my @events;
#Set to 1 for Debugging new commands.
my $debug=1;

sub getDisplayName { 'PLUGIN_EXECUTE_SCRIPT'; }

#Set common text strings.  can be placed in strings.txt for language templates.
sub strings() { return '
PLUGIN_EXECUTE_SCRIPT
	EN	Execute Script

PLUGIN_GROUP_EXECUTE
	EN	Execute Script On Event

PLUGIN_GROUP_EXECUTE_DESC
	EN	Select scripts or system commands to execute on certain server events. Any individual player settings will override unless left undefined or set to "(server)"

PLUGIN_EXECUTE_PLAY
	EN	Execute On Play File

PLUGIN_EXECUTE_OPEN
	EN	Execute On Open File

PLUGIN_EXECUTE_STOP
	EN	Execute On Stop

PLUGIN_EXECUTE_POWER_ON
	EN	Execute On Power On

PLUGIN_EXECUTE_POWER_OFF
	EN	Execute On Power Off

PLUGIN_SELECT_SCRIPT
	EN	Select Script

PLUGIN_EXECUTE_GO
	EN	Running Script...

SETUP_PLUGIN-EXECUTE-OPEN
	EN	On Open

SETUP_PLUGIN-EXECUTE-OPEN_DESC
	EN	Run when a file is opened by the server

SETUP_PLUGIN-EXECUTE-PLAY
	EN	On Play

SETUP_PLUGIN-EXECUTE-PLAY_DESC
	EN	Run when a file is played by the server

SETUP_PLUGIN-EXECUTE-STOP
	EN	On Stop

SETUP_PLUGIN-EXECUTE-STOP_DESC
	EN	Run when playback is stopped on server.

SETUP_PLUGIN-EXECUTE-POWER_ON
	EN	On Power On

SETUP_PLUGIN-EXECUTE-POWER_ON_DESC
	EN	Run when a player is turned on.

SETUP_PLUGIN-EXECUTE-POWER_OFF
	EN	On Power Off

SETUP_PLUGIN-EXECUTE-POWER_OFF_DESC
	EN	Run when a player is turned off.
'};

# the routines
sub setMode {
	my $client = shift;
	checkDefaults();
	@browseMenuChoices = (
		string('PLUGIN_EXECUTE_OPEN'),
		string('PLUGIN_EXECUTE_PLAY'),
		string('PLUGIN_EXECUTE_STOP'),
		string('PLUGIN_EXECUTE_POWER_ON'),
		string('PLUGIN_EXECUTE_POWER_OFF'),
	);
	if (!defined($menuSelection{$client})) { $menuSelection{$client} = 0; };
	$client->lines(\&lines);
}

sub initPlugin {
	%functions = (
		'up' => sub  {
			my $client = shift;
			my $newposition = Slim::Buttons::Common::scroll($client, -1, ($#browseMenuChoices + 1), $menuSelection{$client});
	
			$menuSelection{$client} =$newposition;
			$client->update();
		},
		'down' => sub  {
			my $client = shift;
			my $newposition = Slim::Buttons::Common::scroll($client, +1, ($#browseMenuChoices + 1), $menuSelection{$client});
	
			$menuSelection{$client} =$newposition;
			$client->update();
		},
		'left' => sub  {
			my $client = shift;
	
			Slim::Buttons::Common::popModeRight($client);
		},
		'right' => sub  {
			my $client = shift;
#			my @oldlines = Slim::Display::Display::curLines($client);

			my $value = $client->prefGet('script',$menuSelection{$client});
			my %scripts = scriptlist();
			
			if ($debug) {
				use Data::Dumper;
				print Data::Dumper::Dumper(keys %scripts, $value);
			}
			
			my %params = (
				'listRef'        => ['(server)',keys %scripts],
				'header'         => $client->string('PLUGIN_SELECT_SCRIPT'),
				'onChange'       => sub { $_[0]->prefSet('script'.$menuSelection{$client},$_[1] eq '(server)' ? '' : $_[1]); },
				'onChangeArgs'   => 'CV',
				'valueRef'       => \$value,
			);
			Slim::Buttons::Common::pushModeLeft($client, 'INPUT.List',\%params);

			#Slim::Buttons::Common::pushModeLeft($client, 'selectscripts');
		},
		'play' => sub {
			my $client = shift;
			if (my $runScript = catfile(scriptPath(),${$client->param('valueRef')})) {
				$::d_plugins && msg("Execute: path: ".scriptPath()."\n");
				$::d_plugins && msg("Execute: file: ".$runScript."\n");
				$::d_plugins && msg("Execute: Executing: ".$runScript."\n");
				$client->showBriefly({'line'=>[string('PLUGIN_EXECUTE_GO'),$runScript]});
				system $runScript;
			}
		},
	);
	Slim::Control::Request::subscribe(\&Plugins::Execute::commandCallbackStop, [['stop']]);
	Slim::Control::Request::subscribe(\&Plugins::Execute::commandCallbackOpen, [['playlist'], ['newsong']]);
	Slim::Control::Request::subscribe(\&Plugins::Execute::commandCallbackPlay, [['play']]);
	Slim::Control::Request::subscribe(\&Plugins::Execute::commandCallbackPlay, [['button']]);
	Slim::Control::Request::subscribe(\&Plugins::Execute::commandCallbackPower, [['power']]);
}

sub lines {
	my $client = shift;
	my ($line1, $line2, $overlay);

	$line1 = string('PLUGIN_EXECUTE_SCRIPT');

	$line2 = $browseMenuChoices[$menuSelection{$client}];

	return {'line'    => [$line1, $line2],
		    'overlay' => [undef, $client->symbols('rightarrow')]};
}


sub getFunctions {
	return \%functions;
}

#########################
# Setup Routines for Web Interface
#########################
sub setupGroup {
	my %setupGroup = (
	PrefOrder =>
	['plugin-Execute-open','plugin-Execute-play','plugin-Execute-stop','plugin-Execute-power_on','plugin-Execute-power_off']
	,GroupHead => 'PLUGIN_GROUP_EXECUTE'
	,GroupDesc => 'PLUGIN_GROUP_EXECUTE_DESC'
	,GroupLine => 1
	,GroupSub => 1
	,Suppress_PrefSub => 1
	,Suppress_PrefLine => 1
	);
	my %setupPrefs = (
	'plugin-Execute-open' => {
		'validate' => \&Slim::Utils::Validate::inHash
		,'validateArgs' => [\&scriptlist]
		,'options' => {scriptlist()}
	},
	'plugin-Execute-play' => {
		'validate' => \&Slim::Utils::Validate::inHash
		,'validateArgs' => [\&scriptlist]
		,'options' => {scriptlist()}
	},
	'plugin-Execute-stop' => {
		'validate' => \&Slim::Utils::Validate::inHash
		,'validateArgs' => [\&scriptlist]
		,'options' => {scriptlist()}
	},
	'plugin-Execute-power_on' => {
		'validate' => \&Slim::Utils::Validate::inHash
		,'validateArgs' => [\&scriptlist]
		,'options' => {scriptlist()}
	},
	'plugin-Execute-power_off' => {
		'validate' => \&Slim::Utils::Validate::inHash
		,'validateArgs' => [\&scriptlist]
		,'options' => {scriptlist()}
	},
	);
	checkDefaults();
	return (\%setupGroup,\%setupPrefs);
}

sub checkDefaults {
	if (!Slim::Utils::Prefs::isDefined('plugin-Execute-open')) {
		Slim::Utils::Prefs::set('plugin-Execute-open','(none)')
	}
	if (!Slim::Utils::Prefs::isDefined('plugin-Execute-play')) {
			Slim::Utils::Prefs::set('plugin-Execute-play','(none)')
	}
	if (!Slim::Utils::Prefs::isDefined('plugin-Execute-stop')) {
			Slim::Utils::Prefs::set('plugin-Execute-stop','(none)')
	}
	if (!Slim::Utils::Prefs::isDefined('plugin-Execute-power_on')) {
			Slim::Utils::Prefs::set('plugin-Execute-power_on','(none)')
	}
	if (!Slim::Utils::Prefs::isDefined('plugin-Execute-power_off')) {
			Slim::Utils::Prefs::set('plugin-Execute-power_off','(none)')
	}
}

sub scriptlist {

	my %scriptList = ();
	$::d_plugins && msgf("Execute: loading scripts from %s\n",scriptPath());
	
	my @dirItems = Slim::Utils::Misc::readDirectory( scriptPath(), qr((\w+?)|\.(?:bat|cmd|pl|sh|exe|com)));
	push @dirItems,"(none)";
	foreach my $script ( @dirItems ) {
		# reject CVS and html directories
		next if $script =~ /^(?:cvs|html)$/i;
		if ($script eq "(none)") {
			$scriptList{$script} = $script;
			next
		}
		$::d_plugins && msg("Execute:	  found $script\n");
		$scriptList{$script} = Slim::Utils::Misc::unescape($script);
	}
	return %scriptList;
}

sub commandCallbackStop {
	my $request = shift;

	my $client = $request->client();
	return unless $client;
	
	my $code   = $request->getParam('_buttoncode');

	$::d_plugins && msg("Execute: Playback Stopped\n");
	my $scriptPath = scriptPath();
	my $runScript = $client->prefGet('script',2);
	if ((!defined($runScript)) || ($runScript eq '')) {
		$::d_plugins && msg("Execute: using server pref\n");
		$runScript = Slim::Utils::Prefs::get('plugin-Execute-stop');
	}
	if (defined($runScript) && ($runScript ne "(none)")) {
		my $runScriptPath = catfile($scriptPath,$runScript);
		$::d_plugins && msg("Execute: Executing $runScript\n");
		$client->showBriefly({'line'=>[string('PLUGIN_EXECUTE_GO'),$runScript]});
		system $runScriptPath;
	} else {
		$::d_plugins && msg("Execute: No Script Selected \n");
	}
};
	
sub commandCallbackPlay {
	my $request = shift;

	my $client = $request->client();
	return unless $client;
	if (defined $request->getParam('_buttoncode')) {
		return unless $request->getParam('_buttoncode') eq 'play';
	}
	
	$::d_plugins && msg("Execute: Playback Started\n");
	
	my $scriptPath = scriptPath();
	my $runScript = $client->prefGet('script',1);
	if ((!defined($runScript)) || ($runScript eq '')) {
		$::d_plugins && msg("Execute: using server pref\n");
		$runScript = Slim::Utils::Prefs::get('plugin-Execute-play');
	}
	if (defined($runScript) && ($runScript ne "(none)")) {
		my $runScriptPath = catfile($scriptPath,$runScript);
		$::d_plugins && msg("Execute: Executing $runScript\n");
		$client->showBriefly({'line'=>[string('PLUGIN_EXECUTE_GO'),$runScript]});
		system $runScriptPath;
	} else {
		$::d_plugins && msg("Execute: No Script Selected \n");
	}
};
	
sub commandCallbackOpen {
	my $request = shift;

	my $client = $request->client();
	return unless $client;

	$::d_plugins && msg("Execute: File Open\n");
	my $scriptPath = scriptPath();
	my $runScript = $client->prefGet('script',0);
	if ((!defined($runScript)) || ($runScript eq '')) {
		$::d_plugins && msg("Execute: using server pref\n");
		$runScript = Slim::Utils::Prefs::get('plugin-Execute-open');
	}
	if (defined($runScript) && ($runScript ne "(none)")) {
		my $runScriptPath = catfile($scriptPath,$runScript);
		$::d_plugins && msg("Execute: Executing $runScript\n");
		$client->showBriefly({'line'=>[string('PLUGIN_EXECUTE_GO'),$runScript]});
		system $runScriptPath;
	} else {
		$::d_plugins && msg("Execute: No Script Selected \n");
	}

};
	
sub commandCallbackPower {
	my $request = shift;

	my $client = $request->client();
	return unless $client; 
	
	my $code   = $request->getParam('_buttoncode');

	my $scriptPath = scriptPath();
	my $runScript;
	if ($client->power) {
		$::d_plugins && msg("Execute: Power On\n");
		$runScript = $client->prefGet('script',3);
	} else {
		$::d_plugins && msg("Execute: Power Off\n");
		$runScript = $client->prefGet('script',4);
	}
	if ((!defined($runScript)) || ($runScript eq '')) {
		$::d_plugins && msg("Execute: using server pref\n");
		if ($client->power) {
			$runScript = Slim::Utils::Prefs::get('plugin-Execute-power_on');
		} else {
			$runScript = Slim::Utils::Prefs::get('plugin-Execute-power_off');
		}
	}
	if (defined($runScript) && ($runScript ne "(none)")) {
		my $runScriptPath = catfile($scriptPath,$runScript);
		$::d_plugins && msg("Execute: Executing $runScript\n");
		$client->showBriefly({'line'=>[string('PLUGIN_EXECUTE_GO'),$runScript]});
		system $runScriptPath;
	} else {
		$::d_plugins && msg("Execute: No Script Selected \n");
	}
};

1;

__END__

