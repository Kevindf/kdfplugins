#line 1 "Plugins/Email/Plugin.pm"
# $Id: Plugin.pm,v 1.1 2007-11-07 07:35:43 fishbone Exp $
# Email.pm by Andrew Hedges (andrew@hedges.me.uk) October 2002
# Updated by Kevin Deane-Freeman (kevin@deane-freeman.com) May 2003
#
# This code is derived from code with the following copyright message:
#
# SliMP3 Server Copyright (C) 2001 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

package Plugins::Email::Plugin;

use base qw(Slim::Plugin::Base);
use strict;

my $log          = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.email',
	'defaultLevel' => 'WARN',
	'description'  => getDisplayName(),
});

sub getDisplayName { return 'PLUGIN_EMAIL_BROWSER';}

use Slim::Utils::Strings qw (string);

use Plugins::Email::Settings;

use Slim::Utils::Prefs;

my $prefs = preferences('plugin.email');

use vars qw($VERSION);
$VERSION = substr(q$Revision: 1.1 $,10);

use Mail::POP3Client;
#use Mail::IMAPClient;
use FindBin qw($Bin);
use File::Spec::Functions qw(catfile);

my %linePos = ();
my $numMails = 0;
my %messageList = ();
my %newMessageList = ();
my @messages;
my @messageBody;
my $bodyLine = 0;
my %fetching = ();
my %error = ();

my %functions = ();

my $mailAlert = Slim::Utils::Misc::fileURLFromPath(catfile($Bin,'Plugins','Email.mp3'));

my @serverNames;
my @userIds;
my @passwords;

sub getMessage {
	my $client = shift;
	my $msgId = shift;
	
	$fetching{$client} = 1;
	$error{$client} = 0;
	
	my $serverNum = 0;
	
	@messageBody = ();
	
	for my $serverName (@serverNames) {
		my $userId = $userIds[$serverNum];
		my $password = $passwords[$serverNum];
		my $useSSL = $prefs->get('useSSL');
	
		my $pop3 = new Mail::POP3Client (
			HOST      => $serverName,
			USER      => $userId,
			PASSWORD  => $password,
			#DEBUG     => 1,
			#AUTH_MODE => 'PASS',
			USESSL    => $useSSL,
			TIMEOUT   => 20,
		);
		
		if (!$pop3) {
			warn "Couldn't connect to pop3 server: " . $serverName;
		} else {
			my $userId = $userIds[$serverNum];
			my $password = $passwords[$serverNum];
			
			$pop3->User($userId);
			$pop3->Pass($password);
			
			my $message = "";
			
			@messageBody = $pop3->Body($msgId);
			Data::Dump::dump(\@messageBody);

			$fetching{$client} = 0;
		}
		$serverNum++;
	}
	
	if ($fetching{$client} == 1) {
		$error{$client} = 1;
		$fetching{$client} = 0;
	}
	
	$bodyLine = 0;
	
	$client->unblock;
}

sub doFetch {
	my $client = shift;
	
	$fetching{$client} = 1;
	
	@serverNames = split(",",$prefs->get('servers'));
	@userIds = split(",",$prefs->get('users'));
	@passwords = split(",",$prefs->get('passwords'));
	my $useSSL = $prefs->get('useSSL');
	
	$error{$client} = 0;
	
	my $serverNum = 0;
	
	$numMails = 0;
	
	#my $imap = Mail::IMAPClient->new(  
       #                 Server => 'jupiter',
        #                User    => 'fishbone',
        #                Password=> '432is666',
        #                Clear   => 5,   # Unnecessary since '5' is the default
        #);
	
	#Data::Dump::dump($imap->select("INBOX"));
	
	#my $hashref = $imap->parse_headers(1,"Date","Received","Subject","To");
	#Data::Dump::dump($hashref);
	my $newMail = 0;
	
	for my $serverName (@serverNames) {
		my $userId = $userIds[$serverNum];
		my $password = $passwords[$serverNum];
		
		my $pop3 = new Mail::POP3Client (
			HOST      => $serverName,
			USER      => $userId,
			PASSWORD  => $password,
			#DEBUG     => 1,
			#AUTH_MODE => 'PASS',
			USESSL    => $useSSL,
			TIMEOUT   => 20,
		);
		
		if (!$pop3) {
			warn "Couldn't connect to pop3 server: " . $serverName;
		} else {

			$pop3->Login;
			#Data::Dump::dump($pop3);
			
			#%newMessageList = ();
			@messages = ();
			
			$numMails = $pop3->Count;
			
			print "Message count is $numMails\n";
			
			#print $pop3->Alive."\n";
			for (my $i = 1; $i <= $pop3->Count(); $i++) {
				
				# remove the leaading index and space
				my $id = substr($pop3->Uidl($i),index($pop3->Uidl($i),' ')+1);
				chomp($id);
				push @messages, $id;
				
				if (!exists $messageList{$client}{$id}) {
					#print "NEW MAIL\n";
					$newMail = 1;
				}
				
				for ( $pop3->Head( $i ) ) {
					#/^(From):\s+/i and print $_, "\n";
					#/^(Subject):\s+/i and print $_, "\n";
					if (/^(From):\s+/i) {
						#print "$id - $_\n";
						$newMessageList{$client}{$id}{'from'} = $_;
					}
					
					if (/^(Subject):\s+/i) {
						#print "$id - $_\n";
						$newMessageList{$client}{$id}{'subject'} = $_;
					};
				}
			}
			
			$pop3->Close();
			$fetching{$client} = 0;
			Data::Dump::dump(\%newMessageList);
			#Data::Dump::dump(\@messages);
			%messageList = %newMessageList;
			%newMessageList = ();
		}
		
		$serverNum++;
	}
	
	if ($fetching{$client} == 1) {
		$error{$client} = 1;
		$fetching{$client} = 0;
	}
	
	$linePos{$client} = 0;
	
	$client->unblock;
	
	return $newMail;
}

sub checkEmail {
	my $client = shift;

	my $newMail = doFetch($client) if $client->power();
	$log->info("Checking Email $numMails");
	
	if ($newMail) {
		my $line1 = string('PLUGIN_EMAIL_UHAVE')." ".$numMails." ".string('PLUGIN_EMAIL_MESSAGES');
		my $line2 = string('PLUGIN_EMAIL_NEW');
		
		my $time =  $prefs->get('display');
		
		if (!defined($time)) {$time = 10;};

		$client->showBriefly({
			'line'     => [$line1, $line2],
			'duration' => $time,
			'block'    => 1,
		});

		if ($prefs->get('audio') && (Slim::Buttons::Common::mode($client) ne "off")) {
			#Audible Announce Option
			$client->execute(["playlist", "insert", $mailAlert]);
			
			#Get remaining time of current song, plus duration of alert
			my $offset    = Slim::Player::Source::songTime($client);
			my $index     = Slim::Player::Source::currentSongIndex($client);
			
			my $mode      = $client->playmode;
			my $ds        = 'Slim::Schema';
			my $track     = $ds->objectForUrl($mailAlert);
			my $alerttime = $track->durationSeconds();
			
			$client->execute(["playlist","jump","+1"]);
			#set timer to remove the item after the total time
			
			$log->info("Playing alert of duration: $alerttime");
			Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + $alerttime+1, \&killAlert, $index, $offset,$mode);
		} else {
			my $line1 = string('PLUGIN_EMAIL_UHAVE')." ".$numMails." ".string('PLUGIN_EMAIL_MESSAGES');
			my $line2 = string('PLUGIN_EMAIL_NEW');
			my $time  =  $prefs->get('display');
			
			if (!defined($time)) {$time = 10;};
			
			$client->showBriefly({
				'line'     => [$line1, $line2],
				'duration' => $time,
				'block'    => 1,
			});

		}
	}
	
	my $mins = $prefs->get('checkwhen');
	
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
	
	$log->info("Clearling alert file: $mailAlert");
	
	if ($mode eq 'play') {
		Slim::Player::Source::jumpto($client, $index);
		Slim::Player::Source::gototime($client, $offset, 1);
	
	} else {
		Slim::Player::Source::playmode($client, $mode);
	}
	
	$client->execute(["playlist", "deleteitem", $mailAlert]);
}

sub setMode {
	my $class  = shift;
	my $client = shift;
	my $method = shift;

	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}
	
	$fetching{$client} = 1;
	
	$client->showBriefly({
		'line' => [ $client->string('PLUGIN_EMAIL_CONNECT'), $client->string('PLUGIN_EMAIL_WAIT') ],
	});
		
	if (!$error{$client}) { checkEmail($client);};
	
	if ($numMails) {
		my %params = (
			'listRef'		=> [1..$numMails],
			'externRef'		=> sub {
							return $messageList{$_[0]}{$messages[$_[1]]}{'subject'};
						},
			'header'		=> sub {
							return $messageList{$_[0]}{$messages[$_[1]]}{'from'};
						},
			'headerArgs'		=> 'CV',
			'callback'		=> \&selectMailHandler,
			'overlayRef'		=> \&overlayFunc,
			'overlayRefArgs'	=> 'CV',
			);
			
		Slim::Buttons::Common::pushModeLeft($client,'INPUT.List',\%params);
	} else {
	#	$client->lines(\&lines);
	}
}

sub selectMailHandler {
	my ($client,$exittype) = @_;
	$exittype = uc($exittype);

	if ($exittype eq 'LEFT') {
		Slim::Buttons::Common::popModeRight($client);
		
	} elsif ($exittype eq 'RIGHT') {
		my $selection = $client->modeParam('listRef')->[$client->modeParam('listIndex')];
		
		getMessage($client,$selection+1);
		
		if (scalar @messageBody > 0) {
			my %params = (
				'listRef'		=> [0..scalar @messageBody],
				'externRef'		=> sub {
								return $messageBody[$_[1]];
							},
				'header'		=> $messageList{$client}{$messages[$selection]}{'subject'},
				);
				
			Slim::Buttons::Common::pushModeLeft($client,'INPUT.List',\%params);
		}
	}
}

sub initPlugin {
	my $class = shift;

	%functions = (
		'add' => sub  {
			my $client = shift;
			my $line1 = string('PLUGIN_EMAIL_CONNECT');
			my $line2 = string('PLUGIN_EMAIL_WAIT');
	
			$client->showBriefly({
				'line'     => [$line1, $line2],
			});
	
			checkEmail($client);
		}
	);
	
	Plugins::Email::Settings->new;
	
	$class->SUPER::initPlugin();
};

sub overlayFunc {
	my $client = shift;
	my $value  = shift;
	
	return (
			"(".($client->modeParam('listIndex') + 1)." ".$client->string("OF")." ".scalar @{$client->modeParam('listRef')}.")", 
			Slim::Display::Display::symbol('rightarrow')
		);
}


sub lines {
	my $client = shift;

	my ($line1, $line2);
	my $overlay = undef;

	#if ($error{$client}) {
		$line1 = string('PLUGIN_EMAIL_NO_CONNECT');
		$line2 = string('PLUGIN_EMAIL_RETRY');
	
	#} elsif ($fetching{$client}) {
	
		$client->block({
			'line' => [ string('PLUGIN_EMAIL_CONNECT'),string('PLUGIN_EMAIL_WAIT') ],
		});
	
	#} else {
	#	$line1 = string('PLUGIN_EMAIL_BROWSER');
	#	$line2 = string('PLUGIN_EMAIL_NO_MESSAGES');
	#}
	
	return {'line'    => [$line1, $line2],
		'overlay' => [$overlay,undef]};
}

sub getFunctions {
	return \%functions;
}

1;
