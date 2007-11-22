# Updated by Kevin Deane-Freeman (kevin@deane-freeman.com) May 2003
#
# This code is derived from code with the following copyright message:
#
# SliMP3 Server Copyright (C) 2001 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

package Plugins::Bookmark;
sub getDisplayName {return 'PLUGIN_BOOKMARK'}

use Slim::Utils::Strings qw (string);

use vars qw($VERSION);
$VERSION = substr(q$Revision: 1.1 $,10);

sub strings() { return '
PLUGIN_BOOKMARK
	EN	Bookmarks
	DE	Lesezeichen

PLUGIN_BOOKMARK_SAVE
	EN	Press PLAY to save
	DE	Drücke PLAY zum Speichern

PLUGIN_BOOKMARK_RESTORING
	EN	Restoring to bookmark...
	DE	Lade Lesezeichen...
  
PLUGIN_BOOKMARK_SAVING
	EN	Saving Bookmark now...
	DE	Speichere Lesezeichen...
	
PLUGIN_BOOKMARK_RESTORE
	EN	Press PLAY to restore
	DE	Drücke PLAY zum Laden

PLUGIN_BOOKMARK_ERROR
	EN	Error Loading: not found!
	EN	Fehler beim Laden: Nicht gefunden!

PLUGIN_BOOKMARK_ERASE
	EN	Erasing Bookmark...
	DE	Lösche Lesezeichen...
'};

use strict;

use FindBin qw($Bin);
use File::Spec::Functions qw(catfile);

my @bookmarkChoices = ();
my $bookmarkAction;

sub saveBookmark {
	my $client = shift;
	
	my $offset = Slim::Player::Source::songTime($client);
	my $index = Slim::Player::Source::currentSongIndex($client);
	my $playlist = string('PLUGIN_BOOKMARK')." - ".$client->name();

	$client->execute(['playlist', 'save', $playlist]);

	$::d_plugins && Slim::Utils::Misc::msg("Bookmark: Saving $playlist: Song $index at $offset seconds\n");

	Slim::Utils::Prefs::clientSet($client,"bookmarkIndex",$index);
	Slim::Utils::Prefs::clientSet($client,"bookmarkOffset",$offset);

	$client->showBriefly($client->string('PLUGIN_BOOKMARK'),$client->string('PLUGIN_BOOKMARK_SAVING'));
	#Slim::Player::Source::playmode($client, "stop");
}

sub restoreBookmark {
	my $client = shift;
	$client->execute(['stop']);

	my $playlist = string('PLUGIN_BOOKMARK')." - ".$client->name();

	$client->execute(["power", 1]);
	Slim::Player::Playlist::shuffle($client, 0);
	$client->showBriefly($client->string('PLUGIN_BOOKMARK'),$client->string('PLUGIN_BOOKMARK_RESTORING'));
	$::d_plugins && Slim::Utils::Misc::msg("Bookmark: Loading  $playlist\n");
	
	my $ds = Slim::Music::Info::getCurrentDataStore();
	my $playlistObj = $ds->objectForUrl(Slim::Utils::Misc::fileURLFromPath(
		catfile(Slim::Utils::Prefs::get('playlistdir'),$playlist.".m3u")));

	unless ($playlistObj) {
		$client->showBriefly($client->string('PLUGIN_BOOKMARK'),$client->string('PLUGIN_BOOKMARK_ERROR'));
		return;
	}
	$client->execute(["playlist", "loadtracks", "playlist=".$playlistObj->id()], \&bookmarkLoadDone, [$client]);
}

sub bookmarkLoadDone {
	my $client = shift;
	my $index = Slim::Utils::Prefs::clientGet($client,"bookmarkIndex");
	my $offset = Slim::Utils::Prefs::clientGet($client,"bookmarkOffset");
	Slim::Player::Source::jumpto($client, $index);
	$::d_plugins && Slim::Utils::Misc::msg("Bookmark: jump to song $index\n");
	Slim::Player::Source::gototime($client, $offset, 1);
	$::d_plugins && Slim::Utils::Misc::msg("Bookmark: go to $offset\n");
}

sub setMode() {
	my $client = shift;
	$client->lines(\&lines);
	if (!defined($bookmarkAction)) {$bookmarkAction = 0;};
	@bookmarkChoices = (string('PLUGIN_BOOKMARK_SAVE'),string('PLUGIN_BOOKMARK_RESTORE'))
}

my %functions = (
	'up' => sub  {
		my $client = shift;
		my $newposition = Slim::Buttons::Common::scroll($client, -1, ($#bookmarkChoices + 1), $bookmarkAction );
		$bookmarkAction = $newposition;
		$client->update();
	},
	'down' => sub  {
		my $client = shift;
		my $newposition = Slim::Buttons::Common::scroll($client, -1, ($#bookmarkChoices + 1), $bookmarkAction );
		$bookmarkAction = $newposition;
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
		if ($bookmarkAction ==0) {
			$bookmarkAction ==1;
			saveBookmark($client);
		} else {
			$bookmarkAction ==0;
			restoreBookmark($client);
		}
		Slim::Buttons::Common::popModeRight($client);	
	},
	'saveRestore' => sub  {
		my $client = shift;
		if ($bookmarkAction ==0) {
			$bookmarkAction ==1;
			saveBookmark($client);
		} else {
			$bookmarkAction ==0;
			restoreBookmark($client);
		}
	},
	'save' => sub  {
		my $client = shift;
		
		$bookmarkAction ==1;
		saveBookmark($client);
	},
	'restore' => sub  {
		my $client = shift;
		
		$bookmarkAction ==0;
		restoreBookmark($client);
	}
);

sub lines {
	my ($line1, $line2);
	my $overlay = undef;

	$line1 = string('PLUGIN_BOOKMARK');
	$line2 = $bookmarkChoices[$bookmarkAction];
	return ($line1, $line2,$overlay,undef);
}

sub getFunctions() {
	return \%functions;
}

1;
