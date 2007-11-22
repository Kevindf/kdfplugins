###################################################################
## Weather.Com Forecaster ##
###################################################################

###################################################################
## Instructions for use ##
###################################################################

# The initial menu offers 'Search' and 'Saved Cities'
#
# Search offers the ability to search weather.com for forecasts for
# a city you decide upon.
# The up and down arrows scroll through the letters A-Z and space
# (no numbers, dunno any cities with numbers in the name).
# You can also use the number/letter keys to insert the letters
# (zero is space).
# Press right twice to search or simply press the search button.
#
# If one city is found you will be taken to the weather list. Press
# up and down to scroll through the weather entries for the week
# If a list is presented, choose one to load weather for that city.
# Otherwise press back to return to the search page.
#
# You may press add on the search list or weather pages to add the
# city to a permanent list on your server (should be in the plugins
# directory)
# if you want to delete a city...open the file and delete it
# manually. Next time you load the list, it will magically have
# disappeared.
#
# The 'Saved Cities' option shows the list of cities you have saved
# (if you haven't saved any the SLIMP3 will display a message stating
# this)
#

package Plugins::Forecaster;

use strict;
use File::Spec::Functions qw(:ALL);
use FindBin qw($Bin);
use lib(File::Spec->catdir($Bin, 'Plugins'));
use FileHandle;
use FindBin qw($Bin);
use Slim::Buttons::Common;
use Slim::Utils::Misc;
use XML::Simple;
use Weather::Cached;
use IO::Socket::INET;
use IO::Socket qw(:DEFAULT :crlf);

use vars qw($VERSION);
$VERSION = substr(q$Revision: 1.32 $,10);

use Slim::Utils::Strings qw (string);
use Socket;

my $timeout = 30;
my $proxy;

#### INSERT YOUR OWN ID INFO HERE - THESE ARE FOR SAMPLE ONLY
# Sign up at http://registration.weather.com/registration/xmloap/step1 and enter ID and Key in server settings.
my $Partner = "";
my $License = "";

my $length = 10;

sub getDisplayName() {return 'PLUGIN_WEATHER2'}

sub strings() { return '
PLUGIN_WEATHER_MENU
	EN	Choose...
	
PLUGIN_WEATHER2
	EN	Forecasts from Weather.com XML

PLUGIN_WEATHER_NOINFO
	EN	No Info Found

PLUGIN_WEATHER_SEARCHING
	EN	Searching Weather.com for

PLUGIN_WEATHER_LOADCITY
	EN	Get weather forecast for
	
PLUGIN_WEATHER_UPDATING
	EN	Updating Forecast...

PLUGIN_SCREENSAVER_FORECASTER
	EN	Weather Screensaver

SETUP_GROUP_PLUGIN_FORECASTER_DESC
	EN	You can choose to have the forecast in either Metric or Imperial units.

SETUP_PLUGIN_FORECASTER_UNITS
	EN	Forecaster Units

SETUP_PLUGIN_FORECASTER_1
	EN	Metric Units

SETUP_PLUGIN_FORECASTER_0
	EN	Imperial Units

SETUP_PLUGIN_FORECASTER_PARTNER
	EN	Partner ID

SETUP_PLUGIN_FORECASTER_LICENSE
	EN	License Key

CURRENT
	EN	Current

NIGHT
	EN	Night

DAY
	EN	Day

'};

my @menuitems=("Saved Cities","Search");
my $nummenuitems=2;
my @cities=();
my @city_codes=();

my $numcities=0;
my $numdays=0;

my $menu;
my (@forecast, @daynames);
my %curr_city=();
my %curr_day=();
my %curr_menu=();

my (@searchTerm);
my $searchCursor =0;

my @searchChars = (
Slim::Hardware::VFD::symbol('rightarrow'),
'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',' '
);



# button functions

# These functions are run when the respective button is pressed on
# the remote

my %functions = (
'left' => sub {
	Slim::Buttons::Common::popModeRight(shift) unless defined $menu ;
	return unless defined $menu;
	if($menu eq "MENU"){
		my $client = shift;
		my $funct = shift;
		my $functarg = shift;
		if (!$functarg) { #don't repeat out of searchfor mode
			Slim::Buttons::Common::popModeRight($client);
		}
	} elsif($menu eq "SEARCH"){
		my $client = shift;
		my $funct = shift;
		my $functarg = shift;
		Slim::Utils::Timers::killTimers($client,\&nextChar);
		if ($searchCursor == 0) {
			$menu="MENU";
			$client->update();
		} else {
			pop @searchTerm;
			$searchCursor--;
			$client->update();
		}
	} elsif($menu eq "CITYLIST"){
		$menu="MENU";
		my $client = shift;
		$client->update();
	} elsif($menu eq "WEATHER"){
		$menu="CITYLIST";
		my $client = shift;
		$client->update();
	} elsif($menu eq "SEARCH_ERROR"){
		$menu="SEARCH";
		my $client = shift;
		$client->update();
	}
},
'up' => sub {
	my $client = shift;
	return unless defined $menu;
	if($menu eq "MENU"){
		$curr_menu{$client} = Slim::Buttons::Common::scroll( $client, -1, $nummenuitems, $curr_menu{$client});
		$client->update();
	} elsif($menu eq "SEARCH"){
	my $char = $searchTerm[$searchCursor];
	my $index = 0;
	foreach my $match (@searchChars) {
		last if ($match eq $char);
		$index++;
	}
	$index = Slim::Buttons::Common::scroll($client, -1, scalar(@searchChars), $index);

	if ($index < 0) {
		$index = scalar
		@searchChars - 1;
	};
	$searchTerm[$searchCursor]=$searchChars[$index];
	Slim::Utils::Timers::killTimers($client,\&nextChar);
	$client->update();
	} elsif($menu eq "CITYLIST"){
		$curr_city{$client} = Slim::Buttons::Common::scroll($client, -1, $numcities, $curr_city{$client});
		$client->update();
	} elsif($menu eq "WEATHER"){
		$curr_day{$client} = Slim::Buttons::Common::scroll( $client, -1, $numdays, $curr_day{$client});
		#print $curr_day{$client};
		$client->update();
	}
},

'down' => sub {
	my $client = shift;
	return unless defined $menu;
	if($menu eq "MENU"){
		$curr_menu{$client} = Slim::Buttons::Common::scroll( $client, 1, $nummenuitems, $curr_menu{$client});
		$client->update();
	} elsif($menu eq "SEARCH"){
		my $char = $searchTerm[$searchCursor];
		my $index = 0;
		foreach my $match (@searchChars) {
			last if ($match eq $char);
			$index++;
		}
		$index = Slim::Buttons::Common::scroll
		($client, +1, scalar(@searchChars), $index);

		if ($index >= scalar @searchChars) { $index = 0 };
		$searchTerm[$searchCursor]=$searchChars[$index];
		Slim::Utils::Timers::killTimers($client,	\&nextChar);
		$client->update();
	} elsif($menu eq "CITYLIST"){
		$curr_city{$client} = Slim::Buttons::Common::scroll( $client, 1, $numcities, $curr_city{$client});
		$client->update();
	} elsif($menu eq "WEATHER"){
		$curr_day{$client} = Slim::Buttons::Common::scroll( $client, 1, $numdays, $curr_day{$client});
		$client->update();
	}
},
'right' => sub {
	my $client = shift;
	return unless defined $menu;
	if($menu eq "MENU"){
		if($menuitems[$curr_menu{$client}] eq "Saved Cities"){
			my $file = $Bin."/Plugins/Weather.lst";
			my $fh = FileHandle->new();

			if ($fh->open("< ".$file)) {
				$menu="CITYLIST";
				$numcities=0;
				@cities=();
				@city_codes=();
				$curr_city{$client}=0;
				$curr_day{$client}=0;
				while(<$fh>){
					my ($key,$val) =
					split(/:/);
					$cities[$numcities] = $key;
					$city_codes[$numcities] = $val;
					$numcities++;
				}
				$fh->close();
				$client->update();
			} else {
				Slim::Display::Animation::showBriefly($client, "No saved
				cities !","",3);
			}
		} elsif($menuitems[$curr_menu{$client}] eq "Search"){
			$menu="SEARCH";
			$client->update();
		}
	} elsif($menu eq "SEARCH"){
		my $char = $searchTerm[$searchCursor];
		Slim::Utils::Timers::killTimers($client,\&nextChar);
		if ($char eq Slim::Hardware::VFD::symbol('rightarrow')) {
			Slim::Display::Animation::showBriefly
			($client, string('PLUGIN_WEATHER_SEARCHING'), term($client));
			$curr_day{$client} = 0;
			$curr_city{$client} = 0;
			@cities=();
			@city_codes=();
			$numcities=0;
			$menu="CITYLIST";

			startSearch($client);

			$client->update();
		} else {
			nextChar($client);
		}
	} elsif($menu eq "CITYLIST"){
		$curr_day{$client} = 0;
		$menu="WEATHER";
		&retrieveWeather($client);
		$client->update();
	}

	return;
},
'numberScroll' => sub {
	my $client = shift;
	my $button = shift;
	my $digit = shift;
	Slim::Utils::Timers::killTimers($client, \&nextChar);
	# if it's a different number, then skip ahead
	if (Slim::Buttons::Common::testSkipNextNumberLetter($client, $digit)) {
		nextChar($client);
	}
	# update the search term
	$searchTerm[$searchCursor]
	=Slim::Buttons::Common::numberLetter($client, $digit);
	# set up a timer to automatically skip ahead
	Slim::Utils::Timers::setTimer($client, Time::HiRes::time
	() + Slim::Utils::Prefs::get("displaytexttimeout"), \&nextChar);
	#update the display
	$client->update();
},
'search' => sub {
	my $client = shift;
	$curr_city{$client} = 0;
	$menu="CITYLIST";
	Slim::Display::Animation::showBriefly($client, "Searching Weather.com for", term($client));
	$curr_day{$client} = 0;
	$curr_city{$client} = 0;
	@cities=();
	@city_codes=();
	$numcities=0;
	startSearch($client);
	Slim::Display::Animation::showBriefly
	($client, "menu=$menu","",1);
	$client->update();
},
'add' => sub {
	my $addCity;
	if($menu eq "WEATHER" || $menu eq "CITYLIST"){
		my $client = shift;
		my $file = $Bin."/Plugins/Weather.lst";
		my $fh = FileHandle->new();

		if ($fh->open(">> ".$file)) {
			print $fh $cities[$curr_city{$client}].":".$city_codes[$curr_city{$client}]."\n";
			Slim::Display::Animation::showBriefly($client, "Adding $cities[$curr_city{$client}] to permanent list","",3);
			$fh->close();
		} else {
			Slim::Display::Animation::showBriefly
			($client, "Failed to open file",$file,3);
		}
	}
}
);

sub getFunctions {
	#export the functions to the system
	return \%functions;
}

sub retrieveWeather {
	my $client = shift;
	@forecast=();
	@daynames=();

	Slim::Buttons::Block::block($client,string('PLUGIN_WEATHER2'),string('PLUGIN_WEATHER_UPDATING'));
	
	$::d_plugins && Slim::Utils::Misc::msg("Forecaster: retrieving weather\n");

	my $loc = $city_codes[$curr_city{$client}];
	chomp $loc;
	my $proxy = Slim::Utils::Prefs::get('webproxy') ? 'http://'.Slim::Utils::Prefs::get('webproxy') : undef;
	
	my %comargs = (
			'partner_id' => &Partner,
			'license'    => &License,
			'debug'      => 0,
			'cache'      => Slim::Utils::Prefs::get('cachedir'),
			'proxy'      => $proxy,
			'current'    => 1,
			'forecast'   => 10,
			'links'      => 0,
			'units'      => metric() ? 'm' : 's',
			'timeout'    => 250
			);

	my $wc = Weather::Cached->new(%comargs);
	my $weather = $wc->get_weather($loc);
	
	$::d_plugins && Slim::Utils::Misc::msg("Forecaster: current data\n");
	use Data::Dumper;
	print Dumper($weather->{cc});
	
	$::d_plugins && Slim::Utils::Misc::msg("Forecaster: units returned\n");
	use Data::Dumper;
	print Dumper($weather->{head});
	
	#create display info
	my $day = 1;
	$daynames[0] = string("CURRENT");
	$forecast[0] = _parseCurrent($weather->{cc},$weather->{head});
	foreach (@{$weather->{'dayf'}->{'day'}}) {
		$daynames[$day] = $_->{'t'}." ".string('DAY')." ".$_->{dt};
		$forecast[$day] = _parseDay($_,$weather->{head});
		$day++;
		$daynames[$day] = $_->{'t'}." ".string('NIGHT')." ".$_->{dt};
		$forecast[$day] = _parseNight($_,$weather->{head});
		$day++;
	}
	$daynames[1] = "Today";
	if (Slim::Buttons::Common::mode($client) eq 'block') {
		Slim::Buttons::Block::unblock($client);
	}
	$numdays=@daynames;
}

sub nextChar {
	my $client = shift;
	$searchCursor++;
	$searchTerm[$searchCursor]= Slim::Hardware::VFD::symbol('rightarrow');
	$client->update();
}


sub setMode {
	my $client = shift;

	if(!(@cities)){@cities=();}
	if(!(@city_codes)){@city_codes=();}

	#(@forecast, @daynames);
	if (!(%curr_city)){%curr_city=();}
	if (!(%curr_day)){%curr_day=();}
	if (!($curr_menu{$client})){$curr_menu{$client}=0;}

	if (!defined($numcities)){$numcities=0;}
	if (!defined($numdays)){$numdays=0;}
	$searchCursor = 0;
	@{searchTerm} = ('A');

	$client->lines(\&lines);

}

sub startSearch {
	my $client = shift;
	
	my $terms = term($client);

	$terms=~s/ /%20/;
	#$terms = 'vancouver';
	
	my $proxy = Slim::Utils::Prefs::get('webproxy') ? 'http://'.Slim::Utils::Prefs::get('webproxy') : undef;
	
	my %comargs = (
		'partner_id' => &Partner,
		'license'    => &License,
		'debug'      => 0,
		'cache'      => Slim::Utils::Prefs::get('cachedir'),
		'proxy'      => $proxy,
		'current'    => 1,
		'forecast'   => 10,
		'links'      => 0,
		'units'      => metric() ? 'm' : 's',
		'timeout'    => 250
	);

	my $wc = Weather::Cached->new(%comargs);
	my $weather = $wc->search($terms);
	
	if ($weather){
		my $day=0;
		my $title="";
		my $line="";

		foreach my $loc (keys %{$weather}) {

			if (scalar(keys %{$weather}) == 1) {
				#found redirect
				@cities=();
				@city_codes=();
				$city_codes[0]=$loc;
				$cities[0] = $weather->{$loc};
				$menu="WEATHER";
				&retrieveWeather($client);
				last;
			} else {
				#found list
				$::d_plugins && Slim::Utils::Misc::msg("Forecaster found multiple locations\n");
				$city_codes[$numcities]=$loc;
				$cities[$numcities] =$weather->{$loc};
				$numcities++;
			}
		}
	}
}

sub term {
	my $client = shift;

	# do the search!
	my $term = "";
	foreach my $a (@searchTerm) {
		if (defined($a) && ($a ne Slim::Hardware::VFD::symbol ('rightarrow'))) {
			$term .= $a;
		}
	}
	return $term;
}


sub lines {
	my $client = shift;
	my ($line1, $line2);

	if (!Partner() || !License() || Partner() eq "" || License() eq "") {
		$line1 = "Partner ID and License Key Required";
		$line2 = "Sign up at http://registration.weather.com/registration/xmloap/step1 and enter ID and Key in server settings.";
		return ($line1, $line2);
	} else {
		if (!(defined($menu))) {$menu = "MENU";};
		if($menu eq "MENU"){
			$line1 = string('PLUGIN_WEATHER_MENU');
			$line2 = $menuitems[$curr_menu{$client}];
			return ($line1, $line2);
		} elsif($menu eq "SEARCH"){
			$line1 = "Search for city:";
	
			$line2 = "";
			for (my $i = 0; $i < scalar @{searchTerm}; $i++) {
				if (!defined $searchTerm[$i]) {
					last;
				};
				if ($i == $searchCursor) {
					$line2 .= Slim::Hardware::VFD::symbol
					('cursorpos');
				}
				$line2 .= $searchTerm[$i];
			}
			return ($line1, $line2);
		} elsif($menu eq "CITYLIST"){
			$line1 = string('PLUGIN_WEATHER_LOADCITY');
			if (defined $cities[$curr_city{$client}]) {
				$line2 = "$cities[$curr_city{$client}]";
			}
			else {
				$line2 = string('PLUGIN_WEATHER_NOINFO');
			}
			return ($line1, $line2);
		} elsif($menu eq "WEATHER"){
			$line1 = "$cities[$curr_city{$client}] - ";
			if (defined $daynames[$curr_day{$client}]) {
				$line1 .= "$daynames[$curr_day{$client}]";
			}
			if (defined $forecast[$curr_day{$client}]) {
				$line2 = "$forecast[$curr_day{$client}]";
			}
			else {
				$line2 = string('PLUGIN_WEATHER_NOINFO');
			}
			return ($line1, $line2);
		} elsif($menu eq "SEARCH_ERROR"){
			$line1 = "Nothing found for search [".term($client)."]";
			$line2 = "Press 'left' to search again";
			return ($line1, $line2);
		}
	}
}

sub setupGroup {
	my %setupGroup = (
		PrefOrder => ['plugin_Forecaster_units','plugin_Forecaster_partner','plugin_Forecaster_license']
		,GroupHead => string('PLUGIN_WEATHER2')
		,GroupDesc => string('SETUP_GROUP_PLUGIN_FORECASTER_DESC')
		,GroupLine => 1
		,GroupSub => 1
		,Suppress_PrefHead => 1
		,Suppress_PrefDesc => 1
		,Suppress_PrefSub => 1
		,Suppress_PrefLine => 1
		,PrefsInTable => 1
	);
	my %setupPrefs = (
		'plugin_Forecaster_units' => {
			'validate' => \&Slim::Utils::Validate::trueFalse  
				,'options' => {
					'0' => string('SETUP_PLUGIN_FORECASTER_0')
					,'1' => string('SETUP_PLUGIN_FORECASTER_1')
				}
			,'PrefChoose' => string('SETUP_PLUGIN_FORECASTER_UNITS')
		}
		,'plugin_Forecaster_partner' => {
			'validate' => \&Slim::Utils::Validate::hasText
			,'PrefChoose' => string('SETUP_PLUGIN_FORECASTER_PARTNER')
			,'PrefSize' => 'medium'
		}
			
		,'plugin_Forecaster_license' => {
			'validate' => \&Slim::Utils::Validate::hasText
			,'PrefChoose' => string('SETUP_PLUGIN_FORECASTER_LICENSE')
			,'PrefSize' => 'medium'
		}
	);
	
	checkDefaults();
	return (\%setupGroup,\%setupPrefs);
}

sub checkDefaults {
	if (!Slim::Utils::Prefs::isDefined('plugin_Forecaster_units')) {
		Slim::Utils::Prefs::set('plugin_Forecaster_units',0)
	}
}

###################################################################
### Section 3. Your variables for your screensaver mode go here ###
###################################################################
# First, Register the screensaver mode here.  Must make the call to addStrings in order to have plugin
# localization available at this point.
#sub screenSaver() {
#	#slim::Utils::Strings::addStrings(&strings());
#	Slim::Buttons::Common::addSaver('SCREENSAVER.forecaster', getScreensaverForecaster(), \&setScreensaverModeForecaster,undef,string('PLUGIN_SCREENSAVER_FORECASTER'));
#}
#
#my %screensaverForecasterFunctions = (
#	'done' => sub  {
#					my ($client
#					,$funct
#					,$functarg) = @_;
#					Slim::Buttons::Common::popMode($client);
#					$client->update();
#					#pass along ir code to new mode if requested
#					if (defined $functarg && $functarg eq 'passback') {
#						Slim::Hardware::IR::resendButton($client);
#					}
#				},
#);
#
#sub getScreensaverForecaster {
#	return \%screensaverForecasterFunctions;
#}
#
#sub setScreensaverModeForecaster() {
#	my $client = shift;
#	$client->lines(\&screensaverForecasterLines);
#}
#
#sub screensaverForecasterLines {
#	my $client = shift;
#	return Slim::Buttons::Common::dateTime($client);
#}

sub valid {
	my $data = shift;
	return (defined($data) && ($data ne "N/A"));
}

sub _parseCommon {
	my $day = shift;
	my $units = shift;
	my @info;
	if (valid($day->{'hi'})) {
		my $high = "High: ".$day->{'hi'}.$units->{ut};
		push(@info,$high);
	}
	if (valid($day->{'low'})) {
		my $low = "Low: ".$day->{'low'}.$units->{ut};
		push(@info,$low);
	}
	if (valid($day->{suns})) {
		my $sunrise = "Sunrise: ".$day->{sunr};
		push(@info,$sunrise);
	}
	if (valid($day->{suns})) {
		my $sunset = "Sunset: ".$day->{suns};
		push(@info,$sunset);
	}
	return join(" - ",@info);;
}

sub _parseDay {
	my $day = shift;
	my $units = shift;
	
	my $common = _parseCommon($day,$units);
	my $dayf = _parseCurrent($day->{part}->[0],$units);
	return "$dayf - $common";
}

sub _parseNight {
	my $day = shift;
	my $units = shift;
	
	my $common = _parseCommon($day,$units);
	my $dayf = _parseCurrent($day->{part}->[1],$units);
	return "$dayf - $common";
}

sub _parseCurrent {
	my $cc = shift;
	my $units = shift;

	my @info;
	if (valid($cc->{tmp})) {
		my $temp = $cc->{tmp}.$units->{ut};
		push(@info,$temp);
	}
	if (valid($cc->{t})) {
		my $desc = $cc->{t};
		push(@info,$desc);
	}
	if (valid($cc->{wind})) {
		my $wind = _parse_wind($cc->{wind},$units);
		push(@info,$wind) if defined $wind;
	}
	if (valid($cc->{ppcp})) {
		my $precip = "Precip: ".$cc->{ppcp}."%";
		push(@info,$precip);
	}
	if (valid($cc->{hmid})) {
		my $humidity = $cc->{hmid}."% Humidity";
		push(@info,$humidity);
	}
	if (valid($cc->{bar})) {
		my $pressure = _parse_pressure($cc->{bar},$units);
		push(@info,$pressure) if defined $pressure;
	}
	return join(" - ",@info);
}

####
# parsing routines borrowed from Weather::Simple
####
sub metric {
	return Slim::Utils::Prefs::get('plugin_Forecaster_units');
}

sub Partner {
	return Slim::Utils::Prefs::get('plugin_Forecaster_partner') || $Partner;
}

sub License {
	return Slim::Utils::Prefs::get('plugin_Forecaster_license') || $License;
}

sub _parse_wind {
	my $winddata = shift;
	my $units = shift;
	
	my $wind;
	if ( lc( $winddata->{s} ) =~ /calm/ ) {
		$wind = "calm";

	} elsif (valid($winddata->{s})) {
		my $speed       = $winddata->{s};
		#my $mph       = sprintf( "%d", $kmh * 0.6213722 );
		my $direction = &Weather::Com::convert_winddirection($winddata->{t});
		$wind = "Winds: $speed".$units->{us}." from $direction";

	} else {
		return undef;
	}

	return $wind;
}
	
sub _parse_pressure {
	my $pressuredata = shift;
	my $units = shift;
	
	my $pressure = $pressuredata->{r};
	
	my $d = $pressuredata->{d};
	$pressure =~ s/,//g;
	
	if ($pressure) {
		return "$pressure".$units->{up}." and $d";
	} else {
		return undef;
	}
}
1;