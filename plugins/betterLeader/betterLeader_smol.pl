###########
#	Small version of 'betterLeader' made by MaterialBlade. Based in part on the wait4Party plugin by Contrad
#
#	This software is open source, licensed under the GNU General Public Liscens
#	USER NOTE:
#	If you use betterWalkPlan you will need to modify the top of the `on_ai_processRandomWalk` to look like this:
#
#		sub on_ai_processRandomWalk {
#			my (undef, $args) = @_;
#	
#
#			if($args->{return} eq 1)
#			{
#				return 1;
#			}
#		...
#
#	This $args->{return} prevents the map route from updating every time betterLeader sets a waypoint
#
#
#
=pod
	--- CONFIGURATION
	Add to config.txt
	- betterLeader [1] - enables the plugin
	- betterLeader_castWait [1.7] - 'wait'' if a skill's cast time is longer than this
	- betterLeader_showMsg [0|1] - show some msgs in console
	- betterLeader_ignoreList [comma separated list] - list of char names to IGNORE waiting for
	- betterLeader_waitCastList [comma separated list] - list of char names to check for long cast times

	Add mapWalkDist.json to your control folder
	Add add map+distance pairs to mapWalkDist.json

	- "DISTBREAK" as a map value always needs to be wrapped in quotes
	- "DISTBREAK*#" as a map value always needs to be wrapped in quotes, where # = a multilier (eg 0.5)
	- regular numbers don't need to be wrapped in quotes

	--- EXAMPLE config.txt
	betterLeader 1
	betterLeader_castWait 1.7
	betterLeader_showMsg 0
	betterLeader_ignore Kruin Outlaw, Moonrise Intruder, Kessig Forgemaster, Ulvenwald Mystic
	betterLeader_waitCastList Hanweir Watchkeep

	--- EXAMPLE mapWalkDist.json
	{
		"data":{
			"distbreak":16,
		
			"map_name1":8,
			"map_name2":50,
			"map_name3":"DISTBREAK",
			"map_name4":"DISTBREAK*0.75",
		}
	}

	--- CONSOLE COMMANDS
	`blc` lists the available commands
	`blc reload` list the options for reloading
	
=cut

###########


package betterLeader;

use strict;
#use warnings;

use Time::HiRes qw(time);

use Carp::Assert;
use IO::Socket;
use Text::ParseWords;
use encoding 'utf8';
use feature "switch";

use Globals;
use Log qw(message warning error debug);
use Misc;
use Network::Send ();
use Settings;
use AI;
use AI::SlaveManager;

use Actor;
use Actor::You;
use Actor::Player;
use Actor::Monster;
use Actor::Party;
use Actor::NPC;
use Actor::Portal;
use Actor::Pet;
use Actor::Slave;
use Actor::Unknown;

use ChatQueue;
use Utils;
use Commands;
use Network;
use FileParsers;
use Translation;
use Field;
use Task::TalkNPC;
use Task::UseSkill;
use Task::ErrorReport;
use Utils::Exceptions;
use Data::Dumper;
use Math::Trig;

# safe location tracking =====
use File::Spec;
use JSON::Tiny qw(from_json to_json);
# ============================

use Scalar::Util qw(looks_like_number);

use constant {
	RECALC_DELAY => 0.2,
	WAIT_TIME => 1.5,
	TRUE => 1,
	FALSE => 0,
	WALK_DIST => 10,
	MANA_BREAK => 20,
	CAST_BREAK => 2,
	DISTBREAK => 20, # can delete this later
	RESUPPLY => 60,
	CAST_TIME_WAIT => 1.7,
};

Plugins::register('betterLeader', 'better control when leading a party', \&onUnload); 
my $hooks = Plugins::addHooks(
	['ai_follow', \&mainProcess, undef], 
	["AI_pre", \&prelims, undef],
	['AI_post',       \&ai_post, undef],
	['AI/lockMap',       \&ai_lockMap, undef],
	['ai_processRandomWalk',       \&ai_lockMap, undef],
	["packet_pre/party_chat", \&partyMsg, undef],
	['Network::Receive::map_changed', \&changedMap, undef],
	#['AI_start', \&changedMap, undef],
	['is_casting', \&waitCast, undef],
);

my $commands_handle = Commands::register(
	['waypoint', 'sets the stored position in betterLeader', \&setWayPoint],
	['walkmaps', 'commands related to the distance check maps', \&walkmaps],
	['blc', 'commands for betterLeader', \&blCommands],
);

message "betterLeader success\n", "success";

#### VARIABLES
my %stored_pos = ("x", 0, "y", 0);
my $stored_dest;
my $distance_check;
my $myPos;
my $mytimeout;
my $isWaiting = FALSE;
my $waitForParty = FALSE;
my $waitForMana = FALSE;
my $waitForCast = FALSE;
my $waitForGroupUp = FALSE;

my $init;

my $resupply_timeout;
my $groupup_timeout;

my $aggressives_limit = 10; # X checks for aggressives before we refresh
my $aggressives_count = 0;

my $missing_limit = 20; # X checks for missing party member before we refresh
my $missing_count = 0;

my $big_missing_limit = 100; # X checks for someone missing before we assume something happened and we respawns, maybe clear ai and stuff?
my $big_missing_count = 0;

# map walk dist =============
my $file_handle2;
my $mapWalkDist_file = "mapWalkDist.json";
my %walkDistMaps;

####

#changedMap();


sub onUnload {
	Settings::removeFile($file_handle2) if (defined $file_handle2);
	undef $file_handle2;
	undef $mapWalkDist_file;
	undef %walkDistMaps;

	undef $init;

	undef %stored_pos;
	undef $myPos;
    Plugins::delHooks($hooks);
	Commands::unregister($commands_handle);
}

sub onReload {
    &onUnload;

	#changedMap();
}

sub loadFiles {
	$file_handle2 = setLoad2($mapWalkDist_file);
	Settings::loadByHandle($file_handle2);
}
# map walk distance stuff ==========
sub setLoad2 {
	my $file = shift;
	my $handle = Settings::addControlFile(
		$file,
		loader => [\&parseWalkPlan2, \%walkDistMaps],
		internalName => $mapWalkDist_file,
		mustExist => 0
	);
	return $handle;
}

# I don't think i need to make two of this
sub parseWalkPlan2 {
	my $file = shift;
	my $r_hash = shift;

	open FILE, "<:utf8", $file;
	my @lines = <FILE>;
	close(FILE);
	chomp @lines;
	my $jsonString = join('',@lines);

	my %converted = %{from_json($jsonString, { utf8  => 1 } )};

	%{$r_hash} = %converted;
	return 1;
}

sub updateWalkDist
{
	# see if there is a distance break for this map. otherwise, we undef it (which is don't do it)
	undef $distance_check;

	if(exists $walkDistMaps{data}{$field->baseName})
	{
		# for the json need to check for STRING
		my $newDISTBREAK = $walkDistMaps{data}{distbreak};
		my $mapValue = $walkDistMaps{data}{$field->baseName};

		# if the string is just DISTBREAK we can just do distbreak
		if($walkDistMaps{data}{$field->baseName} eq 'DISTBREAK')
		{
			$distance_check = $newDISTBREAK;
		}
		# otherwise need to eval it
		elsif($mapValue =~ /DISTBREAK/)
		{
			my $newString = $walkDistMaps{data}{$field->baseName};
			$newString =~ s/DISTBREAK/$newDISTBREAK/; # i don't know if this will work

			$distance_check = eval($newString);
		}
		# otherwise it's just a number
		else
		{
			$distance_check = $walkDistMaps{data}{$field->baseName};
		}
			
		# if we have increase agility, reduce that distance by a lil bit
		if ($char->statusActive('EFST_INC_AGI') and $config{"betterLeader_useAgi"})
		{
			$distance_check *= 0.5; 
			message TF("Distance check updated to $distance_check (INC AGI)\n"), "teleport";
		}
		else
		{
			message TF("Distance check updated to $distance_check\n"), "teleport";
		}
	}
	else{
		my $tmp = $field->baseName;
		message TF("Distance check reset. $tmp is safe.\n"), "teleport";
		$isWaiting = FALSE;
	}
}

sub blCommands
{
	my @values = split(' ', $_[1]);

	if($values[0] eq 'reload')
	{
		if($values[1] eq 'walkmaps')
		{
			$file_handle2 = setLoad2($mapWalkDist_file);
			Settings::loadByHandle($file_handle2);
			#sleep(0.333);
			updateWalkDist() if defined $field;
		}
		else
		{
			print "reload options are: walkmaps\n";
		}
	}
	else
	{
		print "blc commands are:\n";
		print "reload (walkmaps)\n";
	}
}

sub walkmaps
{
	my @values = split(' ', $_[1]);

	if($_[1] eq "reload")
	{
		$file_handle2 = setLoad2($mapWalkDist_file);
		Settings::loadByHandle($file_handle2);
		#sleep(0.333);
		updateWalkDist();
	}
}



sub setWayPoint
{
	my @values = split(' ', $_[1]);
	
	# first make sure the location is walkable
	if($field
		and scalar(@values) eq 2
		and looks_like_number($values[0])
		and looks_like_number($values[1])
		and $field->isWalkable($values[0], $values[1]))
	{
		message TF("~~~ Updating stored position to new waypoint ~~~\n"), "success";
		$stored_dest->{pos}{x} = $values[0];
		$stored_dest->{pos}{y} = $values[1];


		my $myPos = calcPosition($char);
		$stored_pos{x} = $myPos->{x};
		$stored_pos{y} = $myPos->{y};
	}
	else
	{
		message TF("~~~ Couldn't stored position to new waypoint ~~~\n"), "teleport";
		print "Desired pos: $_[1]\n";
	}
}

sub partyMsg
{
	return 1 unless ($config{betterLeader}); #return if we ain't leading shit

	my ($var, $arg, $tmp) = @_;
	my ($msg, $msg2, $ret, $name, $message);

	$msg = $arg->{message};
	my @values = split(':', $msg);
	
	chop($values[0]);
	substr($values[1], 0, 1) = '';
	
	$name = $values[0];
	$message = $values[1];

	given($message){
		#when("Group up!")
		#{
		#	# sometimes WE will call for the group up
		#	return if($char->{name} eq $name);
		#
		#	# it would probably make more sense to have the leader do it's own but... whatever
		#	# need to not record the current route position or whatever for a bit, or not do distance checks or something
		#	$waitForGroupUp = TRUE;
		#	$groupup_timeout = time + 5;
		#}

		#when("I need mana!")
		#{
		#	my $tmps = MANA_BREAK;
		#	message TF("mana break for $tmps seconds\n"), "success";
		#	$waitForMana = TRUE;
		#}

		#when ($_ =~ /(.*) (Arrow left)/)
		#{
		#	callResupply()
		#}

		#when ("I need Blue Gems")
		#{
		#	callResupply()
		#}

		#when ($_ =~ /(.*) (Overweight)/)
		#{
		#	callResupply()
		#}
	}
}

sub changedMap
{
	return 1 unless ($config{betterLeader}); #return if we ain't leading shit

	if(defined $field and defined $stored_dest and ($stored_dest->{map}->{baseName} eq $field->baseName))
	{
		# we reloaded into the same map
		return 1;
	}

	undef $stored_dest;

	# see if there is a distance break for this map. otherwise, we undef it (which is don't do it)
	undef $distance_check;
	if(defined $field)
	{
		updateWalkDist();

		#if(exists $maps{$field->baseName})
		#{
		#	$distance_check = $maps{$field->baseName};
		#	
		#	# if we have increase agility, reduce that distance by a lil bit
		#	if ($char->statusActive('EFST_INC_AGI'))
		#	{
		#		$distance_check *= 0.5; 
		#		message TF("Distance check updated to $distance_check (INC AGI)\n"), "teleport";
		#	}
		#	else
		#	{
		#		message TF("Distance check updated to $distance_check\n"), "teleport";
		#	}
		#}
		#else{
		#	my $tmp = $field->baseName;
		#	message TF("Distance check reset. $tmp is safe.\n"), "teleport";
		#	$isWaiting = FALSE;
		#}
	}
}

sub ai_lockMap
{
	return 1 unless ($config{betterLeader}); #return if we ain't leading shit

	my (undef,$args) = @_;

	if(AI::findAction("buyAuto") || AI::findAction("autosell") || AI::findAction("autostorage"))
	{
		$args->{'return'} = 1; #this prevents other movement plugins down the waterfall from acting
		return 1;
	}

	if($isWaiting)
	{
		if(timeOut($mytimeout->{'pause_move'},WAIT_TIME))
		{
			# we still need to make sure the router doesn't take over, I guess
			$args->{'return'} = 1;
			
			# if the party is in combat, we don't want to start moving around
			my $tval = scalar(ai_getAggressives(1,1));
			if(ai_getAggressives(1,1))
			{
				$mytimeout->{'pause_move'} = time;
				message TF("party has aggressives ($tval)! waiting to move\n"), "teleport";
				$aggressives_count++;
				if($aggressives_count > $aggressives_limit)
				{
					sendMessage($messageSender, "c", "\@refresh");
					$aggressives_count = 0;
				}
				return;
			}
			elsif(searchForParty())
			{
				$mytimeout->{'pause_move'} = time;
				message TF("someone is missing! waiting to move\n"), "teleport";
				$missing_count++;
				$big_missing_count++;

				if($missing_count eq 3)
				{
					# give that first one a LITTLE BIT more time than the rest
					$mytimeout->{'pause_move'} = time + WAIT_TIME*3;

					stand() if $char->{sitting};
					my @stand = calcRectArea2($char->{pos}{x}, $char->{pos}{y},2,0);
					my $i = int(rand @stand);
					my $spot = $stand[$i];

					if(!positionNearPortal($spot, 3))
					{
						ai_route(
							$field->baseName,
							$spot->{x},
							$spot->{y},
							maxRouteTime => $config{route_randomWalk_maxRouteTime},
							attackOnRoute => 2,
							#noMapRoute => ($config{route_randomWalk} == 2 ? 1 : 0),
							#isRandomWalk => 1
						);
					}
				}

				if(($missing_count % 6) eq 0)
				{
					#sendMessage($messageSender, "p", "Group up!");
				}

				# someone has been missing for a long time. resupply just in case
				if($big_missing_count > $big_missing_limit)
				{
					#sendMessage($messageSender, "p", "resupply");
					$big_missing_count = 0;
					$missing_count = 0;
				}
				elsif($missing_count > $missing_limit)
				{
					sendMessage($messageSender, "p", "\@refresh");
					$missing_count = 0;
				}
				return;
			}
			else
			{
				message TF("party does NOT have aggressives and no one is missing\n"), "teleport";
				$missing_count = 0;
				$big_missing_count = 0;
				$aggressives_count = 0;
			}

			# clear out any lingering routes, just in case
			AI::dequeue while (AI::inQueue("route"));

			if($field->baseName eq $config{'lockMap'}) # we're in lockMap (duh)
			{
				# restore our old route (if it exists)
				if(defined $stored_dest and $stored_dest->{map}->{baseName} eq $config{'lockMap'})
				{
					print "We're in LockMap. Attempting to route to stored: $stored_dest->{map}->{baseName} ($stored_dest->{pos}{x},$stored_dest->{pos}{y})\n" if $config{betterLeader_showMsg};
					ai_route(
						$stored_dest->{map}->{baseName},
						$stored_dest->{pos}{x},
						$stored_dest->{pos}{y},
						attackOnRoute => 2,
						#isFollow => 1,
						isRandomWalk => $field->baseName eq $config{'lockMap'},
						isToLockMap =>  $field->baseName ne $config{'lockMap'},
					);
				}
				else
				{
					print("stored destination was not defined\n") if $config{betterLeader_showMsg};
				}
			}
			else # we're not, so we have to route to that map
			{
				# make sure lockMap is valid before trying to route to it
				if(!($maps_lut{$config{'lockMap'}.'.rsw'}))
				{
					$args->{'return'} = 1;
					return;
				}

				my ($lockX, $lockY);

				ai_route(
					$config{'lockMap'},
					$lockX,
					$lockY,
					attackOnRoute => 2,
					isToLockMap => 1
				);
			}

			$isWaiting = FALSE;
		}
		else
		{
			$args->{'return'} = 1; #this will prevent the lockmap and random walk code from functioning while we're "waiting"
		}
	}
}

sub prelims
{
	return 1 unless ($config{betterLeader}); #return if we ain't leading shit

	if($field and !defined $init)
	{
		changedMap();
		$init = TRUE;
	}

	my (undef,$args) = @_;

	if(AI::action eq "route" and !AI::inQueue("attack"))
	{
		if(timeOut($mytimeout->{'recheck'}, RECALC_DELAY)) # some buffer so we're not checking every single frame
		{
			$mytimeout->{'recheck'} = time;

			$myPos = calcPosition($char);

			my $value = Hash2Ref(%stored_pos);
			my $aggressives = ai_getAggressives(1,1);
			if(defined $distance_check and distance($myPos, $value) > $distance_check || $waitForMana || $aggressives || $waitForCast)
			{
				# if we were told to move by a "Group Up!" call, then we don't want to update the stored info
				if($waitForGroupUp)
				{
					if(timeOut($groupup_timeout, 1) || $aggressives eq 0)
					{
						$waitForGroupUp = FALSE;
					}
					else
					{
						message TF("Don't update stored position, we're Grouping Up!!\n"), "selfSkill";
						return;
					}
				}

				# we need to stop moving for a bit. how the fuck do we do that? :D
				message "we're too far from stored position. pause movement\n", "follow" if $config{betterLeader_showMsg};
				message TF("waiting for cast\n"), "selfSkill" if($waitForCast and $config{betterLeader_showMsg});

				$args->{move_timeout} = time+(2*60);
				my $time_increase = time;
				$time_increase = $time_increase+MANA_BREAK if($waitForMana);
				$time_increase = $time_increase+CAST_BREAK if($waitForCast);

				$mytimeout->{'pause_move'} = $time_increase;

				# set our current position here I guess
				$stored_pos{x} = $myPos->{x};
				$stored_pos{y} = $myPos->{y};

				if (AI::action eq 'route' && defined(AI::args(0)->getSubtask()))
				{
					my $routeArgs = AI::args(0);
					my $routeTask = $routeArgs->getSubtask;

					if(defined $routeTask->{dest})
					{
						$stored_dest = $routeTask->{dest};
					}
					
				}
				else
				{
					if ($config{betterLeader_showMsg})
					{
						print "Something went wrong and we can't store the destination\n";
						print "Resetting stored dest\n";
					}
					undef $stored_dest;
				}

				$isWaiting = TRUE;
				$waitForMana = FALSE;
				$waitForCast = FALSE;
				print "setting isWaiting to $isWaiting\n" if $config{betterLeader_showMsg};
				
				AI::dequeue() while (
					AI::is(qw/attack move route mapRoute/) && AI::args()->{isRandomWalk} ||
					AI::is(qw/attack move route mapRoute/) && AI::args()->{isToLockMap}
				);
				
				my $dist_stop_time = 2.0;
				$dist_stop_time = 6.0 if ($char->statusActive('EFST_INC_AGI'));
			}			
		}
	}
}

sub waitCast
{
	return 1 unless ($config{betterLeader}); #return if we ain't leading shit

	my (undef,$actor) = @_;

	# the line below waits for only guild members, regardless of their name
	#return unless ($actor->{source}->{guild}->{name} eq $char->{guild}{name});

	# the line below uses a list of characters to wait for
	return unless existsInList($config{"betterLeader_waitCastList"}, $actor->{source}->{name});

	my $castTime = ($actor->{castTime})* 0.001;
	if($castTime > $config{"betterLeader_castWait"})
	{
		message TF("waiting for cast, time is $castTime\n"), "selfSkill" if $config{betterLeader_showMsg};
		$mytimeout->{'recheck'} = time;
		$waitForCast = TRUE;
	}
}

sub mainProcess
{
	# not sure i need anything here since we're not following
}

sub ai_post
{
	return 1 unless ($config{betterLeader}); #return if we ain't leading shit

	my $doRespawn = TRUE;

	if($char->{dead})
	{
		my $actor;
		foreach (@partyUsersID) {
			next if (!$_ || $_ eq $accountID);
			next if existsInList($config{'betterLeader_ignoreList'}, $char->{'party'}{'users'}{$_}{'name'});
			$actor = $playersList->getByID($_);
			
			# PARTY MISSING!!
			if(!$char->{'party'}{'users'}{$_}{'dead'})
			{
				$doRespawn = FALSE;
			}
		}

		if($doRespawn eq TRUE)
		{
			#sendMessage($messageSender, "p", "respawn");
			if(timeOut($mytimeout->{'respawn_time'},WAIT_TIME))
			{
				#my $outout = $mytimeout->{'respawn_time'} + WAIT_TIME;
				#print "respawn_time is ".$mytimeout->{'respawn_time'}." and time is $outout\n";
				$mytimeout->{'respawn_time'} = time;
				sendMessage($messageSender, "p", "respawn");
			}
		}
		

	}
}

sub searchForParty
{
	my $actor;

	foreach (@partyUsersID) {
		next if (!$_ || $_ eq $accountID);
		next if existsInList($config{'betterLeader_ignoreList'}, $char->{'party'}{'users'}{$_}{'name'});
		$actor = $playersList->getByID($_);
			
		# PARTY MISSING!!
		if(!$actor && $char->{'party'}{'users'}{$_}{'online'}) {

			my $missingChar = $char->{'party'}{'users'}{$_};

			#check if they're missing AND if they're dedge
			if($missingChar->{dead} || $missingChar->{hp} eq 0)
			{
				# if they're not on the same map we don't go looking for them and we don't count them. ONLY if they're on a different map and dead.
				# MAY change this later to update it to go and find dead characters by that introduces a whole can of worms
				my $tmp_charMap;
				($tmp_charMap) = $missingChar->{map} =~ /([\s\S]*)\.gat/;
				if($field->baseName ne $tmp_charMap)
				{
					# they are dead but they're NOT on the same map as us. Fuck em!
					print ("we lost $missingChar->{'name'}! They're dead somewhere else so we won't wait!\n");
					next;
				}

				# they're dead AND they're on the same map. but we still need to wait for characters that are ALIVE
				# update the stored destination
				$stored_dest->{"map"} = $field;
				$stored_dest->{"pos"}{"x"} = $missingChar->{pos}{x}; #these might need to be ->{pos}{x} i forget
				$stored_dest->{"pos"}{"y"} = $missingChar->{pos}{y};

				message TF("Attempting to route for dead ally $missingChar->{'name'}\n"), "teleport";
				next; # still wait for alive characters if we need to.
			}

			print ("we lost $missingChar->{'name'}!\n");
			return 1;
		}
	}

	return 0;
}

sub Hash2Ref
{
	my (%pos) = @_;
	
	my $ret;
	$ret->{'x'} = $pos{x};
	$ret->{'y'} = $pos{y};
	
	return $ret;
}

#duplicated function from the actual openkore logic so i can comment some stuff out
sub ai_getAggressives {
	my ($type, $party) = @_;
	my $wantArray = wantarray;
	my $num = 0;
	my @agMonsters;
	my $portalDist = $config{'attackMinPortalDistance'} || 4;


	for my $monster (@$monstersList) {
		my $control = Misc::mon_control($monster->name,$monster->{nameID}) if $type || !$wantArray;
		my $ID = $monster->{ID};
		my $pos = calcPosition($monster);

		next if ($monster->{nameID} eq 1068); # ignore hydras. they fuck things up in byalan dungeon

		# Never attack monsters that we failed to get LOS with
		next if (!timeOut($monster->{attack_failedLOS}, $timeout{ai_attack_failedLOS}{timeout}));

		# ignore enemies that are near portals
		next if($config{"betterLeader_ignoreNearPortal"} and positionNearPortal($pos, $portalDist));
		#next if (!timeOut($monster->{attack_failed}, $timeout{ai_attack_unfail}{timeout})); # skip the fail for now, since this is what attackDefender controls...
		next if (!Misc::checkMonsterCleanness($ID));
		next if ($control->{attack_auto} == -1);

		if (Misc::is_aggressive($monster, $control, $type, $party)) {
			if ($wantArray) {
				# Function is called in array context
				push @agMonsters, $ID;

			} else {
				# Function is called in scalar context
				if ($control->{weight} > 0) {
					$num += $control->{weight};
				} elsif ($control->{weight} != -1) {
					$num++;
					#print "$monster->name is aggressive\n";
				}
			}
		}
	}

	if ($wantArray) {
		return @agMonsters;
	} else {
		return $num;
	}
}

sub callResupply()
{
	if(timeOut($resupply_timeout,RESUPPLY))
	{
		$resupply_timeout = time;
		sendMessage($messageSender, "p", "resupply");
	}
}

1;
