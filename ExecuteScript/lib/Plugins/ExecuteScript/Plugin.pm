# Execute.pm by Kevin Deane-Freeman (kevindf@shaw.ca) April 2003
#
# This code is derived from code with the following copyright message:
#
# SliMP3 Server Copyright (C) 2001 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

package Plugins::ExecuteScript::Plugin;

use base qw(Slim::Plugin::Base);

use strict;

use Slim::Player::Playlist;
use Slim::Player::Source;
use Slim::Player::Sync;
use Slim::Utils::Strings qw (string);
use File::Spec::Functions qw(:ALL);
use POSIX qw(strftime);
use FindBin qw($Bin);
use Slim::Utils::Misc;
use Slim::Utils::Prefs;

use vars qw($VERSION);
$VERSION = substr(q$Revision: 1.18 $,10);

use Plugins::ExecuteScript::Settings;

my $interval = 1; # check every x seconds
my @browseMenuChoices;
my %menuSelection;
my %functions;

my $log          = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.executescript',
	'defaultLevel' => 'WARN',
	'description'  => getDisplayName(),
});

my $prefs = preferences('plugin.executescript');

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

# the routines
sub setMode {
	my $class = shift;
	my $client = shift;
	
	if (!defined($menuSelection{$client})) { $menuSelection{$client} = 0; };
	$client->lines(\&lines);
}

sub initPlugin {
	my $class = shift;
	
	@browseMenuChoices = qw(
		PLUGIN_EXECUTE_OPEN
		PLUGIN_EXECUTE_PLAY
		PLUGIN_EXECUTE_STOP
		PLUGIN_EXECUTE_POWER_ON
		PLUGIN_EXECUTE_POWER_OFF
	);
	
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

			my $value;
			if (my $scripts = $prefs->client($client)->get('script')) {
				$value = $scripts ->[$menuSelection{$client}];
			}
			my %scripts = scriptlist();
			#print Data::Dumper::Dumper(keys %scripts);
			my %params = (
				'listRef'        => ['(server)',keys %scripts],
				'header'         => $client->string('PLUGIN_SELECT_SCRIPT'),
				'onChange'       => sub {
					my $client = shift;
					my $scripts = $prefs->client($client)->get('script');
					$scripts->[ $menuSelection{$client} ] = $_[1] eq '(server)' ? '' : $_[1];
					$prefs->client($client)->set('script', $scripts);
				},
				'onChangeArgs'   => 'CV',
				'scriptnum'      => $menuSelection{$client},
				'valueRef'       => \$value,
			);
			Slim::Buttons::Common::pushModeLeft($client, 'INPUT.List',\%params);

			#Slim::Buttons::Common::pushModeLeft($client, 'selectscripts');
		},
		'play' => sub {
			my $client = shift;
			if (my $runScript = catfile(scriptPath(),${$client->param('valueRef')})) {
				$log->info("Execute: path: ".scriptPath());
				$log->info("Execute: file: ".$runScript);
				$log->info("Execute: Executing: ".$runScript);
				$client->showBriefly({'line'=>[string('PLUGIN_EXECUTE_GO'),$runScript]});
				system $runScript;
			}
		},
	);
	Slim::Control::Request::subscribe(\&commandCallbackStop, [['stop']]);
	Slim::Control::Request::subscribe(\&commandCallbackOpen, [['playlist'], ['newsong']]);
	Slim::Control::Request::subscribe(\&commandCallbackPlay, [['play']]);
	Slim::Control::Request::subscribe(\&commandCallbackPlay, [['button']]);
	Slim::Control::Request::subscribe(\&commandCallbackPower, [['power']]);
	
	Plugins::ExecuteScript::Settings->new;
	
	$class->SUPER::initPlugin();
}

sub lines {
	my $client = shift;
	my ($line1, $line2, $overlay);

	$line1 = string('PLUGIN_EXECUTE_SCRIPT');

	$line2 = $client->string($browseMenuChoices[$menuSelection{$client}]);

	return {'line'    => [$line1, $line2],
		'overlay' => [undef, $client->symbols('rightarrow')]};
}


sub getFunctions {
	return \%functions;
}

sub scriptlist {

	my %scriptList = ();
	$log->info(sprintf("Execute: loading scripts from %s",scriptPath()));
	
	my @dirItems = Slim::Utils::Misc::readDirectory( scriptPath(), qr((\w+?)|\.(?:bat|cmd|pl|sh|exe|com)));
	push @dirItems,"(none)";
	foreach my $script ( @dirItems ) {
		# reject CVS and html directories
		next if $script =~ /^(?:cvs|html)$/i;
		if ($script eq "(none)") {
			$scriptList{$script} = $script;
			next
		}
		$log->info("Execute:	  found $script");
		$scriptList{$script} = Slim::Utils::Misc::unescape($script);
	}
	return %scriptList;
}

sub commandCallbackStop {
	my $request = shift;

	my $client = $request->client();
	return unless $client;
	
	my $code   = $request->getParam('_buttoncode');

	$log->info("Execute: Play Stopped");
	my $scriptPath = scriptPath();
	
	my $runScript;
	if (my $scripts = $prefs->client($client)->get('script')) {
		$runScript = $scripts ->[2];
	}
	if ((!defined($runScript)) || ($runScript eq '')) {
		$log->info("Execute: using server pref");
		$runScript = $prefs->get('plugin-Execute-stop');
	}
	if (defined($runScript) && ($runScript ne "(none)")) {
		my $runScriptPath = catfile($scriptPath,$runScript);
		$log->info("Execute: Executing $runScript");
		$client->showBriefly({'line'=>[string('PLUGIN_EXECUTE_GO'),$runScript]});
		system $runScriptPath;
	} else {
		$log->warn("Execute: No Script Selected");
	}
};
	
sub commandCallbackPlay {
	my $request = shift;

	my $client = $request->client();
	return unless $client;
	
	if ($request->getParam('_buttoncode')) {
		return unless $request->getParam('_buttoncode') eq 'play';
	}
	
	$log->info("Execute: Play Started");
	my $scriptPath = scriptPath();
	
	my $runScript;
	if (my $scripts = $prefs->client($client)->get('script')) {
		$runScript = $scripts ->[1];
	}

	if ((!defined($runScript)) || ($runScript eq '')) {
		$log->info("Execute: using server pref");
		$runScript = $prefs->get('plugin-Execute-play');
	}
	if (defined($runScript) && ($runScript ne "(none)")) {
		my $runScriptPath = catfile($scriptPath,$runScript);
		$log->info("Executing $runScript");
		$client->showBriefly({'line'=>[string('PLUGIN_EXECUTE_GO'),$runScript]});
		system $runScriptPath;
	} else {
		$log->warn("Execute: No Script Selected");
	}
};
	
sub commandCallbackOpen {
	my $request = shift;

	my $client = $request->client();
	return unless $client;

	$log->info("Execute: File Open");
	my $scriptPath = scriptPath();
	
	my $runScript;
	if (my $scripts = $prefs->client($client)->get('script')) {
		$runScript = $scripts ->[0];
	}
	
	if ((!defined($runScript)) || ($runScript eq '')) {
		$log->info("using server pref");
		$runScript = $prefs->get('plugin-Execute-open');
	}
	if (defined($runScript) && ($runScript ne "(none)")) {
		my $runScriptPath = catfile($scriptPath,$runScript);
		$log->info("Execute: Executing $runScript");
		$client->showBriefly({'line'=>[string('PLUGIN_EXECUTE_GO'),$runScript]});
		system $runScriptPath;
	} else {
		$log->warn("Execute: No Script Selected");
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
		$log->info("Execute: Power On");
		if (my $scripts = $prefs->client($client)->get('script')) {
			$runScript = $scripts ->[3];
		}
	} else {
		$log->info("Execute: Power Off");
		if (my $scripts = $prefs->client($client)->get('script')) {
			$runScript = $scripts ->[4];
		}
	}
	if ((!defined($runScript)) || ($runScript eq '')) {
		$log->info("Execute: using server pref");
		if ($client->power) {
			$runScript = $prefs->get('plugin-Execute-power_on');
		} else {
			$runScript = $prefs->get('plugin-Execute-power_off');
		}
	}
	if (defined($runScript) && ($runScript ne "(none)")) {
		my $runScriptPath = catfile($scriptPath,$runScript);
		$log->info("Execute: Executing $runScript\n");
		$client->showBriefly({'line'=>[string('PLUGIN_EXECUTE_GO'),$runScript]});
		system $runScriptPath;
	} else {
		$log->warn("Execute: No Script Selected");
	}
};

1;

__END__

