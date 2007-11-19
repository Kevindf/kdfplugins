# Updated by Kevin Deane-Freeman (kevin@deane-freeman.com) May 2003
#
# This code is derived from code with the following copyright message:
#
# SliMP3 Server Copyright (C) 2001 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

package Plugins::Bookmark::Plugin;

use Slim::Utils::Prefs;
use base qw(Slim::Plugin::Base);
use strict;
use Slim::Utils::Strings qw (string);
#use vars qw($VERSION);
#$VERSION = substr(q$Revision: 1.1 $,10);
#use FindBin qw($Bin);
use File::Spec::Functions qw(catfile);

my $prefs = preferences('plugin.bookmark2');
my $prefsServer = preferences('server');

my %menuItems;
my %numOfMenuItems;
my %menuSelection;

my @bookmarkChoices = ();
my %bookmarkAction;

my $log          = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.bookmarkplugin',
	'defaultLevel' => 'WARN',
	'description'  => getDisplayName(),
});

sub initPlugin {
	my $class = shift;
	$class->SUPER::initPlugin();
}

sub getDisplayName {return 'PLUGIN_BOOKMARK';}

sub setMode() {
	my $class = shift;
	my $client = shift;
	my $push = shift;

	$client->lines(\&lines);

	if (!defined($bookmarkAction{$client}))
	   {$bookmarkAction{$client} = 0;}

	@bookmarkChoices = ($client->string('PLUGIN_BOOKMARK_SAVE'),$client->string('PLUGIN_BOOKMARK_RESTORE'));
}

sub saveBookmark {
	my $client = shift;
	my $num    = shift  || 0;
	my $pop    = shift || 0;
	
	my $offset = Slim::Player::Source::songTime($client);
	my $index = Slim::Player::Source::currentSongIndex($client);
	my $playlist = string('PLUGIN_BOOKMARK')." -$num- ".$client->name();

	$client->execute(['playlist', 'save', $playlist]);

	$log->info("Bookmark: Saving as item $num - $playlist: Song $index at $offset seconds");

	$prefs->client($client)->set('bookmark2Index' . $num, $index);

	$prefs->client($client)->set('bookmark2Offset' . $num, $offset);
	
	$client->showBriefly( {
		'line'  => [ $client->string('PLUGIN_BOOKMARK'),
					 $client->string('PLUGIN_BOOKMARK_SAVING').": Item ".$num],
		},
		{
			'duration'     => 1,
			'block'        => 1,
			'callback'     => $pop ? \&showDone : '',
			'callbackargs' => $client,
		}
	);
}

sub restoreBookmark {
	my $client = shift;
	my $num    = shift || 0;
	my $pop    = shift  || 0;
	
	$client->execute(['stop']);

	my $playlist = string('PLUGIN_BOOKMARK')." -$num- ".$client->name();

	$client->execute(["power", 1]);
	Slim::Player::Playlist::shuffle($client, 0);
	
	$client->showBriefly( {
		'line'  => [ $client->string('PLUGIN_BOOKMARK'),
					 $client->string('PLUGIN_BOOKMARK_RESTORING')." ".$num],
		},
		{
			'duration'     => 1,
			'block'        => 1,
			'callback'     => $pop ? \&showDone : '',
			'callbackargs' => $client,
		}
	);
	
	$log->info("Bookmark: Item $num - Loading  $playlist");
	
	my $playlistObj = Slim::Schema->objectForUrl(Slim::Utils::Misc::fileURLFromPath(
		catfile($prefsServer->get('playlistdir'), $playlist.".m3u")));

	unless ($playlistObj) {
		$client->showBriefly(
			{'line'      => [$client->string('PLUGIN_BOOKMARK'),$client->string('PLUGIN_BOOKMARK_ERROR')],},
			{
				'duration'     => 1,
				'block'        => 1,
				'callback'     => $pop ? \&showDone : '',
				'callbackargs' => $client,
			}
			);
		return;
	}
	$client->execute(["playlist", "loadtracks", "playlist=".$playlistObj->id()], \&bookmarkLoadDone, [$client, $num]);
}

sub bookmarkLoadDone {
	my $client = shift;
	my $num    = shift;
	
	my $index = $prefs->client($client)->get('bookmark2Index' . $num);
	my $offset = $prefs->client($client)->get('bookmark2Offset' . $num);

	Slim::Player::Source::jumpto($client, $index);
	
	$log->info("Bookmark: jump to song $index");
	
	Slim::Player::Source::gototime($client, $offset, 1);
	
	$log->info("Bookmark: go to $offset");
}

my %functions = (
	'up' => sub  {
		my $client = shift;
		
		my $newposition = Slim::Buttons::Common::scroll($client, -1, ($#bookmarkChoices + 1), $bookmarkAction{$client} );
		
		$bookmarkAction{$client} = $newposition;
		$client->update();
	},
	
	'down' => sub  {
		my $client = shift;
		
		my $newposition = Slim::Buttons::Common::scroll($client, -1, ($#bookmarkChoices + 1), $bookmarkAction{$client} );
		
		$bookmarkAction{$client} = $newposition;
		$client->update();
	},
	
	'left' => sub  {
		my $client = shift;
		
		Slim::Buttons::Common::popModeRight($client);
	},
	
	'right' => sub  {
		my $client = shift;
		
		$client->bumpRight($client);
	},
	
	'play' => sub  {
		my $client = shift;

		if ($bookmarkAction{$client} == 0) {
			$bookmarkAction{$client} = 1;
			saveBookmark($client, 0, 1);

		} else {
			$bookmarkAction{$client} = 0;
			restoreBookmark($client, 0, 1);
		}
	},
	
	'numberScroll' => sub  {
		my $client = shift;
		my $button = shift;
		my $num    = shift;
		
		if ($bookmarkAction{$client} == 0) {
			$bookmarkAction{$client} = 1;
			saveBookmark($client, $num, 1);
		
		} else {
			$bookmarkAction{$client} = 0;
			restoreBookmark($client, $num, 1);
		}
	},
	
	'saveRestore' => sub  {
		my $client = shift;
		my $num    = shift;
		
		if ($bookmarkAction{$client} == 0) {
			$bookmarkAction{$client} = 1;
			saveBookmark($client, $num);
		
		} else {
			$bookmarkAction{$client} = 0;
			restoreBookmark($client, $num);
		}
	},
	
	'save' => sub  {
		my $client = shift;
		my $num    = shift;
		
		$bookmarkAction{$client} = 1;
		saveBookmark($client, $num);
	},
	
	'restore' => sub  {
		my $client = shift;
		my $num    = shift;
		
		$bookmarkAction{$client} = 0;
		restoreBookmark($client, $num);
	}
);

sub showDone {
	my $client = shift;

	Slim::Buttons::Common::popModeRight($client);
}

sub lines {
	my $client = shift;
	
	my ($line1, $line2);
	my $overlay = undef;

	$line1 = $client->string('PLUGIN_BOOKMARK');
	$line2 = $bookmarkChoices[$bookmarkAction{$client}];

	return {'line'    => [$line1, $line2],
			'overlay' => [$overlay,undef]};
}

sub getFunctions() {
	return \%functions;
}

# ----------------------------------------------------------------------------
# some initialization code, adding modes for this module
#Slim::Buttons::Common::addMode('bookmarkmode', getRemoteControlFunctions(), \&enterRemoteControl, \&leaveRemoteControl);

1;
