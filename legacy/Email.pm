# $Id: Email.pm,v 1.45 2006-12-12 02:43:18 fishbone Exp $
# Email.pm by Andrew Hedges (andrew@hedges.me.uk) October 2002
# Updated by Kevin Deane-Freeman (kevin@deane-freeman.com) May 2003
#
# This code is derived from code with the following copyright message:
#
# SliMP3 Server Copyright (C) 2001 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

package Plugins::Email;

sub getDisplayName { return 'PLUGIN_EMAIL_BROWSER';}

use Slim::Utils::Strings qw (string);

use vars qw($VERSION);
$VERSION = substr(q$Revision: 1.45 $,10);

sub strings() { return '
PLUGIN_EMAIL_BROWSER
	DE	POP3 eMail Browser
	EN	POP3 email browser

PLUGIN_EMAIL_NO_CONNECT
	DE	Konnte zu keinem POP3 Server verbinden.
	EN	Could not connect to any POP3 servers.

PLUGIN_EMAIL_CONNECT
	DE	Verbinde zu POP3 Server...
	EN	Connecting to POP3 servers

PLUGIN_EMAIL_NO_MESSAGES
	DE	Keine Nachrichten
	EN	No Messages

PLUGIN_EMAIL_RETRY
	DE	Drücke Rec für erneuten Versuch.
	EN	Press Rec to retry.

PLUGIN_EMAIL_WAIT
	DE	Bitte warten...
	EN	Please Wait...

PLUGIN_EMAIL_UHAVE
	DE	Sie haben
	EN	You Have

PLUGIN_EMAIL_MESSAGES
	DE	Nachrichten
	EN	Messages

PLUGIN_EMAIL_NEW
	DE	*neue*
	EN	*NEW* 

SETUP_GROUP_PLUGIN_EMAIL
	DE	POP3 eMail Browser
	EN	POP3 email browser

SETUP_GROUP_PLUGIN_EMAIL_DESC
	DE	Ermöglicht das Checken von POP3 Mail und Lesen der Titelzeilen.
	EN	Check Pop3 Email and browse headers.

PLUGIN_EMAIL_PASSWORD_CHANGED
	DE	Ermöglicht das Checken von POP3 Mail und Lesen der Titelzeilen.
	EN	Email password changed

SETUP_PLUGIN-EMAIL-CHECK-WHEN
	DE	eMail Überprüf-Intervall
	EN	Email Check Timing

SETUP_PLUGIN-EMAIL-CHECK-WHEN_DESC
	DE	Wie oft auf Mail überprüfen? (in Minuten, Vorgabe 5)
	EN	How often to check email, in minutes.  Default is 5.

SETUP_PLUGIN-EMAIL-DISPLAY
	DE	Länge der Benachrichtigung
	EN	Message Alert length

SETUP_PLUGIN-EMAIL-DISPLAY_DESC
	DE	Anzahl Sekunden, die die Benachrichtigung angezeigt werden soll.
	EN	The number of seconds to display the new message alert.

SETUP_PLUGIN-EMAIL-AUDIO
	DE	Hörbare Benachrichtigung bei Mail-Eingang
	EN	Audible Email Alerts

SETUP_PLUGIN-EMAIL_NO_AUDIO
	DE	Keine hörbare Benachrichtigung bei Mail-Eingang
	EN	Silent Email Alert

SETUP_PLUGIN-EMAIL-AUDIO_DESC
	DE	Sie haben die Möglichkeit, neue Mail akustisch anzukündigen (unterbricht Musik!).
	EN	You can have the option of have your audio stream interrupted with an audible alert for new mail.

SETUP_PLUGIN-EMAIL-SERVERS
	EN	Server

SETUP_PLUGIN-EMAIL-SERVERS_DESC
	EN	Address of your POP3 server.

SETUP_PLUGIN-EMAIL-USERS
	EN	Username
	
SETUP_PLUGIN-EMAIL-PASSWORDS
	EN	Server Password
	
'};

#TODO
#SETUP_PLUGIN-EMAIL_SERVERS_LIST
#	EN	POP3 server addresse

#SETUP_PLUGIN-EMAIL_USERS_DESC
#	EN	Comma-separated list of username to match order of servers
	
#SETUP_PLUGIN-EMAIL_PASSWORDS_DESC
#	EN	List of user passwords in matching order of server list.


use strict;

use Net::POP3;
use FindBin qw($Bin);
use File::Spec::Functions qw(catfile);

my $linePos = 0;
my $numMails = 0;
my @messageStrings = ();
my @messageBody;
my $bodyLine = 0;
my $fetching = 1;
my $error = 0;
my $last = undef;
my $mailAlert = Slim::Utils::Misc::fileURLFromPath(catfile($Bin,'Plugins','Email.mp3'));

my @serverNames;
my @userIds;
my @passwords;

sub getMessage {
  my $client = shift;
  my $msgId = shift;
  $fetching = 1;
  $error = 0;
  my $serverNum = 0;
  @messageBody = ();
	if (Slim::Buttons::Common::mode($client) eq 'PLUGIN.Email') {
		Slim::Buttons::Block::block($client,string('PLUGIN_EMAIL_CONNECT'),string('PLUGIN_EMAIL_WAIT'));
	};
  foreach my $serverName (@serverNames) {
    my $pop3 = Net::POP3->new($serverName, Debug =>0);
    if (!$pop3) {
      warn "Couldn't connect to pop3 server: " . $serverName;
    }
    else {
      my $userId = $userIds[$serverNum];
      my $password = $passwords[$serverNum];
      $pop3->login($userId, $password);
      my $message = "";
      $message = $pop3->get($msgId);
      @messageBody = @{$message};
		my $line;
		my $msg = join("",@messageBody);
		my ($head,$bd) = split("\n\n",$msg,2);
		@messageBody = split("\n",$bd);
		#foreach my $line (@messageBody) {
		#	 chomp($line);
		#}
      $pop3->quit();
      $fetching = 0;
    }
    $serverNum++;
  }
  if ($fetching == 1) {
    $error = 1;
    $fetching = 0;
  }
  $bodyLine = 0;
  if (Slim::Buttons::Common::mode($client) eq 'block') {
  		$client->unblock();
  	};
}

sub doFetch {
  my $client = shift;
  $fetching = 1;
  
  	@serverNames = split(",",Slim::Utils::Prefs::get('plugin-Email-servers'));
	@userIds = split(",",Slim::Utils::Prefs::get('plugin-Email-users'));
	@passwords = split(",",Slim::Utils::Prefs::get('plugin-Email-passwords'));

  
  $error = 0;
  my $serverNum = 0;
  $numMails = 0;
  @messageStrings = ();
	if (Slim::Buttons::Common::mode($client) eq 'PLUGIN.Email') {
		$client->block(string('PLUGIN_EMAIL_CONNECT'),string('PLUGIN_EMAIL_WAIT'));
	};
  foreach my $serverName (@serverNames) {
    my $pop3 = Net::POP3->new($serverName, Debug => 0);
    if (!$pop3) {
      warn "Couldn't connect to pop3 server: " . $serverName;
    }
    else {
      my $userId = $userIds[$serverNum];
      my $password = $passwords[$serverNum];
      
      $numMails += $pop3->login($userId, $password);
      my $messages;
      my $msgId;
      $messages = $pop3->list();
      foreach $msgId (sort keys(%$messages)) {
        my $msgContent = $pop3->top($msgId, 0);
        addToList(@$msgContent);
      }
      $pop3->quit();
      $fetching = 0;
    }
    $serverNum++;
  }
  if ($fetching == 1) {
    $error = 1;
    $fetching = 0;
  }
  $linePos = 0;
  if (Slim::Buttons::Common::mode($client) eq 'block') {
  		$client->unblock($client);
  	};
}

sub checkEmail {
	my $client = shift;

	if (!defined($last)) {$last = 0;};
	doFetch($client) if $client->power();
	$::d_plugins && Slim::Utils::Misc::msg("Checking Email $last $numMails\n");
	if ($last < $numMails) {
		my $line1 = string('PLUGIN_EMAIL_UHAVE')." ".$numMails." ".string('PLUGIN_EMAIL_MESSAGES');
		my $line2 = string('PLUGIN_EMAIL_NEW').$messageStrings[($numMails-1)*2+1];
		my $time =  Slim::Utils::Prefs::get('plugin-Email-display');
		if (!defined($time)) {$time = 10;};

		$client->showBriefly({
			'line'     => [$line1, $line2],
			'duration' => $time,
			'block'    => 1,
		});

		if (Slim::Utils::Prefs::get('plugin-Email-audio') && (Slim::Buttons::Common::mode($client) ne "off")) {
			my $ds    = 'Slim::Schema';
			my $track = $ds->objectForUrl({
				'url'      => $mailAlert,
				'readTags' => 1,
				'create'   => 1,
			});
			my $alerttime = $track->durationSeconds();
			
			#Audible Announce Option
			$client->execute(["playlist", "insert", $mailAlert]);
			#Get remaining time of current song, plus duration of alert
			my $offset = Slim::Player::Source::songTime($client);
			my $index = Slim::Player::Source::currentSongIndex($client);
			my $mode = $client->playmode;
			
			$client->execute(["playlist","jump","+1"]);
			#set timer to remove the item after the total time
			$::d_plugins && Slim::Utils::Misc::msg("Playing alert of duration: $alerttime\n");
			Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + $alerttime+1, \&killAlert, $index, $offset,$mode);
		} else {
			my $line1 = string('PLUGIN_EMAIL_UHAVE')." ".$numMails." ".string('PLUGIN_EMAIL_MESSAGES');
			my $line2 = string('PLUGIN_EMAIL_NEW').$messageStrings[($numMails-1)*2+1];
			my $time =  Slim::Utils::Prefs::get('plugin-Email-display');
			if (!defined($time)) {$time = 10;};
			$client->showBriefly({
				'line'     => [$line1, $line2],
				'duration' => $time,
				'block'    => 1,
			});
		}
	}
	$last = $numMails;
	my $mins = Slim::Utils::Prefs::get('plugin-Email-check-when');
	if (!defined($mins)) {$mins = 5;};
	
	Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + $mins * 60, \&checkEmail);
	
}

sub killAlert {
	my $client = shift;
	my $index = shift;
	my $offset = shift;
	my $mode = shift;
	Slim::Player::Source::playmode($client, "stop");
	#Slim::Control::Command::execute($client, ["playlist", "deleteitem", $mailAlert]);
	$::d_plugins && Slim::Utils::Misc::msg("Clearing alert file: $mailAlert\n");
	if ($mode eq 'play') {
		Slim::Player::Source::jumpto($client, $index);
		Slim::Player::Source::gototime($client, $offset, 1);
	} else {
		Slim::Player::Source::playmode($client, $mode);
	}
	$client->execute(["playlist", "deleteitem", $mailAlert]);
}

sub addToList {
  my (@msgLines) = @_;
  my ($from, $subject, $line);
  foreach $line (@msgLines) {
    if ($line =~ m/^From: (.*)/) {
      $from = $1;
    }
    elsif ($line =~ m/^Subject: (.*)/) {
      $subject = $1
    }
    #else {print "line: $line\n";}
    last if (defined($from) && defined($subject));
  }
  if (!defined($from)) {
    $from = "None";
  }
  if (!defined($subject)) {
    $subject = "None";
  }
  push(@messageStrings, "From: " . $from);
  push(@messageStrings, "Subj: " . $subject);
}

sub setMode() {
  my $client = shift;
  $client->lines(\&lines);
  $client->update();
  if (!$error && !(defined($last))) { checkEmail($client);};
}

my %functions = (
	'up' => sub  {
	   my $client = shift;
	   if (scalar(@messageBody > 0)) {
		   my $new = Slim::Buttons::Common::scroll($client, -1, scalar(@messageBody), $bodyLine);
			$bodyLine = $new;
		} else {
			my $new = Slim::Buttons::Common::scroll($client, +1, $numMails, $linePos);
			$linePos = $new;
		}
	   $client->update();
	},
	'down' => sub  {
	   my $client = shift;
	   if (scalar(@messageBody > 0)) {
		   my $new = Slim::Buttons::Common::scroll($client, +1,  scalar(@messageBody), $bodyLine);
			$bodyLine = $new;
		} else {
		   my $new = Slim::Buttons::Common::scroll($client, -1, $numMails, $linePos);
			$linePos = $new;
		}
	   $client->update();
	},
	'left' => sub  {
	   my $client = shift;
	  	if (scalar(@messageBody > 0)) {
			@messageBody = ();
			$bodyLine = 0;
			$client->update()
		} else {
			Slim::Buttons::Common::popModeRight($client);
		}
	},
	'right' => sub  {
	   my $client = shift;
	   if (($numMails > 0) && (scalar(@messageBody==0))) {
			getMessage($client,$linePos+1);
		} else {
			$client->bumpRight();
		}
	},
	'add' => sub  {
	   my $client = shift;
	   my $line1 = string('PLUGIN_EMAIL_CONNECT');
    	my $line2 = string('PLUGIN_EMAIL_WAIT');
    		$last = 0;
			$client->showBriefly({
				'line'     => [$line1, $line2],
			});
	   #doFetch($client);
	   checkEmail($client);
	   $client->update();
	}
);

sub lines {
  	my ($line1, $line2);
  	my $overlay = undef;

  	if ($error) {
    	$line1 = string('PLUGIN_EMAIL_NO_CONNECT');
    	$line2 = string('PLUGIN_EMAIL_RETRY');
  	} elsif (scalar(@messageBody) > 0) {
  		$line1 = $messageStrings[$linePos*2+1];
  		$line2 = $messageBody[$bodyLine];
  	} elsif ($numMails > 0) {
    	$line1 = $messageStrings[$linePos*2];
    	$line2 = $messageStrings[$linePos*2+1];
    	$overlay = "(".($linePos+1)." ".string('OF')." $numMails)";
  	} else {
  		$line1 = string('PLUGIN_EMAIL_BROWSER');
  		$line2 = string('PLUGIN_EMAIL_NO_MESSAGES');
  	}
  	return ($line1, $line2,$overlay,undef);
}

sub getFunctions {
  	return \%functions;
}

sub setupGroup {
	my %setupGroup = (
	PrefOrder =>
	['plugin-Email-check-when','plugin-Email-display','plugin-Email-audio','plugin-Email-servers','plugin-Email-users','plugin-Email-passwords']
	,GroupHead => string('SETUP_GROUP_PLUGIN_EMAIL')
	,GroupDesc => string('SETUP_GROUP_PLUGIN_EMAIL_DESC')
	,GroupLine => 1
	,GroupSub => 1
	,Suppress_PrefSub => 1
	,Suppress_PrefLine => 1
	);
	my %setupPrefs = (
	'plugin-Email-check-when' => {
		'validate' => \&Slim::Utils::Validate::isInt
		,'validateArgs' => [1,undef,1]
	},
	'plugin-Email-display' => {
		'validate' => \&Slim::Utils::Validate::isInt
		,'validateArgs' => [1,undef,1]
	},
	'plugin-Email-audio' => {
		'validate' => \&Slim::Utils::Validate::trueFalse  
		,'options' => {
			'1' => string('SETUP_PLUGIN-EMAIL-AUDIO')
			,'0' => string('SETUP_PLUGIN-EMAIL_NO_AUDIO')
		}
	},
	'plugin-Email-servers' => {
		'validate' => \&Slim::Utils::Validate::acceptAll,
		'PrefSize' => 'large',
	},
	'plugin-Email-users' => {
		'validate' => \&Slim::Utils::Validate::acceptAll,
		'PrefSize' => 'medium',
	},
	'plugin-Email-passwords' => {
		'validate' => \&Slim::Utils::Validate::acceptAll,
		'changeMsg' => string('PLUGIN_EMAIL_PASSWORD_CHANGED'),
		'inputTemplate' => 'setup_input_passwd.html',
		'PrefSize' => 'medium',
	},
	);
	checkDefaults();
	return (\%setupGroup,\%setupPrefs);
}

sub checkDefaults {
	if (!Slim::Utils::Prefs::isDefined('plugin-Email-check-when')) {
		Slim::Utils::Prefs::set('plugin-Email-check-when',5)
	}
	if (!Slim::Utils::Prefs::isDefined('plugin-Email-display')) {
		Slim::Utils::Prefs::set('plugin-Email-display',10)
	}
	if (!Slim::Utils::Prefs::isDefined('plugin-Email-audio')) {
		Slim::Utils::Prefs::set('plugin-Email-audio',0)
	}
	if (!Slim::Utils::Prefs::isDefined('plugin-Email-servers')) {
		Slim::Utils::Prefs::set('plugin-Email-servers',"")
	}
	if (!Slim::Utils::Prefs::isDefined('plugin-Email-users')) {
		Slim::Utils::Prefs::set('plugin-Email-users',"")
	}
	if (!Slim::Utils::Prefs::isDefined('plugin-Email-passwords')) {
		Slim::Utils::Prefs::set('plugin-Email-passwords',"")
	}

	@serverNames = split(",",Slim::Utils::Prefs::get('plugin-Email-servers'));
	@userIds = split(",",Slim::Utils::Prefs::get('plugin-Email-users'));
	@passwords = split(",",Slim::Utils::Prefs::get('plugin-Email-passwords'));

}

#{
#	my $client = shift;
#   Plugins::Email::checkEmail($client);
#}

1;
