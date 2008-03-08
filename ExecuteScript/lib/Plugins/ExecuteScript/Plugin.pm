# Execute plugin by Kevin Deane-Freeman (kevindf@shaw.ca) April 2003
#
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
$VERSION = substr(q$Revision: 2.1 $,10);

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
	my $scriptPath = catfile((Slim::Utils::Prefs::dir() || Slim::Utils::OSDetect::dirsFor('prefs')),'scripts');
	
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
	
	my $prefs = preferences('plugin.executescript');
	
	@browseMenuChoices = qw(
		PLUGIN_EXECUTE_OPEN
		PLUGIN_EXECUTE_PLAY
		PLUGIN_EXECUTE_STOP
		PLUGIN_EXECUTE_POWER_ON
		PLUGIN_EXECUTE_POWER_OFF
		PLUGIN_EXECUTE_ON_DEMAND
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
			my $selection = $menuSelection{$client};
			
			my %params = (
				'name'           => sub {return $_[1] },
				'header'         => '{PLUGIN_SELECT_SCRIPT} {count}',
				'pref'           => sub { my $scripts = $prefs->client($_[0])->get('script'); return $scripts->[ $selection ] || '(server)' },
				'onRight'        => sub { 
							my ( $client, $item ) = @_;
							
							my $scripts = $prefs->client($client)->get('script');
							$scripts->[ $selection ] = $item eq '(server)' ? '' : $item ;
							$prefs->client($client)->set('script', $scripts);
							$client->update();
				},
				'onAdd'          => sub { 
							my ( $client, $item ) = @_;
							
							my $scripts = $prefs->client($client)->get('script');
							$scripts->[ $selection  ] = $item  eq '(server)' ? '' : $item ;
							$prefs->client($client)->set('script', $scripts);
							$client->update();
				},
				'onPlay'         => sub { 
							my ( $client, $item ) = @_;
							
							my $scripts = $prefs->client($client)->get('script');
							$scripts->[ $selection  ] = $item  eq '(server)' ? '' : $item ;
							$prefs->client($client)->set('script', $scripts);
							$client->update();
							
							return unless $scripts->[ $selection  ];
							
							if (my $runScript = catfile(scriptPath(),$item)) {
								$log->info("Execute: path: ".scriptPath());
								$log->info("Execute: file: ".$runScript);
								$log->info("Execute: Executing: ".$runScript);
								$client->showBriefly({'line'=>[string('PLUGIN_EXECUTE_GO'),$runScript],'duration'=>2});
								if (Slim::Utils::OSDetect::OS ne 'win') { $runScript =~ s/ /\\ /g };
								system $runScript;
							}
				},
				'valueRef'       => sub { my $scripts = $prefs->client($_[0])->get('script'); return $scripts->[ $selection ] || '(server)'  },
				'initialValue'   => sub { my $scripts = $prefs->client($_[0])->get('script'); return $scripts->[ $selection ] || '(server)'  },
			);

			my %scripts = scriptlist();
			$params{'listRef'} = ['(server)',keys %scripts];
			
			Slim::Buttons::Common::pushModeLeft($client, 'INPUT.Choice',\%params);
		},
		'execute_on_demand' => sub {
			my $client = shift;
			doThisScript('on_demand');
			$client->showBriefly({'line'=>[$client->string('PLUGIN_EXECUTE_GO'),$client->string('PLUGIN_EXECUTE_ON_DEMAND')]});
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

sub doThisScript {
	my $client = shift;
	my $script = shift;
	
	my %scriptChoices = {
		'open'    => 0,
		play      => 1,
		stop      => 2,
		power_on  => 3,
		power_off => 4,
		on_demand => 5,
	};

	my $scriptPath = scriptPath();
	
	my $runScript;
	if (my $scripts = $prefs->client($client)->get('script')) {
		$runScript = $scripts ->[$scriptChoices{$script}];
	}
	if ((!defined($runScript)) || ($runScript eq '')) {
		$log->info("Execute: using server pref");
		$runScript = $prefs->get($script);
	}
	if (defined($runScript) && ($runScript ne "(none)")) {
		my $runScriptPath = catfile($scriptPath,$runScript);
		$log->info("Execute: Executing $runScriptPath");
		$client->showBriefly({'line'=>[string('PLUGIN_EXECUTE_GO'),$runScript]});
		if (Slim::Utils::OSDetect::OS ne 'win') { $runScriptPath =~ s/ /\\ /g };
		system $runScriptPath;
	} else {
		$log->warn("Execute: No Script Selected");
	}
}

sub commandCallbackStop {
	my $request = shift;

	my $client = $request->client();
	return unless $client;
	
	my $code   = $request->getParam('_buttoncode');

	$log->info("Execute: Play Stopped");
	doThisScript($client,"stop");
};
	
sub commandCallbackPlay {
	my $request = shift;

	my $client = $request->client();
	return unless $client;
	
	if ($request->getParam('_buttoncode')) {
		return unless $request->getParam('_buttoncode') eq 'play';
	}
	
	$log->info("Execute: Play Started");
	doThisScript($client,"play");
};
	
sub commandCallbackOpen {
	my $request = shift;

	my $client = $request->client();
	return unless $client;

	$log->info("Execute: File Open");
	doThisScript($client,"open");

};
	
sub commandCallbackPower {
	my $request = shift;

	my $client = $request->client();
	return unless $client; 
	
	my $code   = $request->getParam('_buttoncode');

	 if ($client->power) {
		$log->info("Execute: Power On");
		doThisScript($client,"power_on");
	} else {
		$log->info("Execute: Power Off");
		doThisScript($client,"power_off");
	}

};

1;

__END__

