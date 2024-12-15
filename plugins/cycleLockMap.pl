############################ 
# cycleLockMap plugin for Openkore
#
# This plugin cycles through a list of maps. Time only ticks down while INSIDE the map.
# The intention is to spent a designated amount of time in a map before moving to the next one.
#
# CONFIGURATION
# Add These Lines to config.txt:
# 
# cycleLockMap [0|1]
# cycleLockMap_duration [Number of minutes]
# cycleLockMap_list [Comma Seperated List]
# cycleLockMap_showtime [0|1]
#
# cycleLockMap is a boolean. Set it to 0 to turn the plugin off. Set it to 1 to turn the plugin on.
# cycleLockMap_duration is the number of MINUTES that you would like the plugin to wait until the next map change.
# cycleLockMap_list is a comma seperated list of lockMaps that you would like the plugin cycle through.
# cycleLockMap_showtime is a boolean. Set it to 1 to show how much time is left in the current lockMap.
#
# EXAMPLE CONFIG.TXT
# cycleLockMap 1
# cycleLockMap_duration 60
# cycleLockMap_list prt_fild01,prt_fild02,prt_fild03,prt_fild04
#
# CONSOLE COMMANDS
# `cycling skip` skips to the next map in the list
# `cycling reload` reloads the map list. this will reset the current lockMap
#
############################ 
package cycleLockMap;

use strict;
use Globals;
use Utils;
use Misc;
use Log qw(message warning error debug);
use Translation;
use Actor;
use Data::Dumper;
use Time::HiRes qw(time);

Plugins::register("cycleLockMap", "cycle through a list of lockMaps", \&on_unload, \&on_reload);

my %mapCycling;
my $mapCycling_setup;
my @mapCycling_list;

# to check if the map list changed when reloading conf
my $stored_map_list;

my $aiHook = Plugins::addHooks(
	["AI_pre", \&ai_pre, undef],
	['configModify',			\&on_configModify],
);

my $commands_handle = Commands::register(
	['cycling', 'commands related to cyclingLockMap plugin', \&mapCycling],
);

sub on_unload {
	# This plugin is about to be unloaded; remove hooks
	Plugins::delHook($aiHook);
}

sub on_reload {
	&on_unload;
}

sub mapCycling
{
	my @values = split(' ', $_[1]);

	if($_[1] eq "skip")
	{
		message TF("Skip to the next map in the list\n"), "success";
		$mapCycling{time} = 0;
	}
	elsif($_[1] eq "reload")
	{
		message TF("reloaded the cycling list.\n"), "success";
		$mapCycling_setup = 0;

		# TODO. maybe store the current map and current time? so it's not a FULL reset
	}
	else
	{
		message TF("Unrecognized 'cycling' command.\n"), "teleport";
	}
}

sub on_configModify {

	# TODO: check if the list changed. if it did, we need to update the stored list
}

sub ai_pre {
	processMapCycling();
}

sub processMapCycling
{
	return unless ($config{cycleLockMap});

	if($mapCycling_setup ne 1)
	{
		@mapCycling_list = split(/,/,$config{cycleLockMap_list});
		$mapCycling_setup = 1;

	}

	return unless $field;

	# need to only decrement the time while we're IN the map
	if(defined $mapCycling{field}
		and $field->baseName eq $mapCycling{field}
		and timeOut($mapCycling{timeOut}, 1.0))
	{
		$mapCycling{timeOut} = time;
		$mapCycling{time}--;
		print "map cycle time left: ".$mapCycling{time}."\n" if $config{"cycleLockMap_showtime"};
	}

	if(!defined $mapCycling{time} || $mapCycling{time} <= 0)
	{
		$mapCycling{field} = shift(@mapCycling_list);

		# trim it, just in case the user fucked up and there are spaces
		$mapCycling{field} =~ tr/ //ds;

		push(@mapCycling_list, $mapCycling{field}); # add it back to the end of the list
		$mapCycling{time} = $config{"cycleLockMap_duration"}*60; #set farming time to 1h

		if($mapCycling{time} <= 0)
		{
			$mapCycling{time} = 60*60; #1h, just in case
		}

		configModify("lockMap", $mapCycling{field});
		AI::clear(qw/route mapRoute /); # clear the route
	}
}

1;
