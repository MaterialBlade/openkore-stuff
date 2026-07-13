####################################
# gatherMonsters      by MaterialBlade
#---------------------------------------------------------------------
# Licensed under the GNU General Public License v2.0
# License: http://www.gnu.org/licenses/gpl-2.0.htm
####################################

####################################
# CONFIG SETTINGS
# 
# gatherMonsters [0/1] <-- enables it
# gatherMonsters_minGatherStart 3 <-- don't start gathering unless there are 3 enemies visible
# gatherMonsters_aggroLimit 3 <-- # of aggro monsters to stop and attack
# gatherMonsters_aggroLimit_min 3 <-- min # of aggro monsters to stop and attack (overrides above)
# gatherMonsters_aggroLimit_max 5 <-- max # of aggro monsters to stop and attack (if there are enough visible)
# gatherMonsters_1v1Time 15 <-- time in seconds the bot will 1v1 an enemy before moving on
# 
####################################

####################################
# SELF CONDITIONS
# gatherAggressives <-- # of enemies currently aggro'd
# whenGathering <-- use when in the 'gathering' state
# whenNotGathering <-- use when NOT in the 'gathering' state
# 
####################################

####################################
# COMMANDS
# aggro <- says how many enemies are currently aggro'd
# 
####################################

package gatherMonsters;

use strict;
use Plugins;
use Commands;
use Globals;
use Utils;
use Misc;
use Log qw(message error);
use Data::Dumper;

use AI;

Plugins::register('gatherMonsters','gather monsters and then kill them :D',\&unload);

my $hook = Plugins::addHooks(
	['checkSelfCondition', \&checkSelfCondition, undef],
	["AI_pre", \&ai_pre, undef],
	['Network::Receive::map_changed', \&changedMap, undef],
	#['AI_post', \&ai_post, undef],
	#['AI_post', \&ai_pre, undef],
);

my $commands_handle = Commands::register(
	['aggro', 'check how many aggro mons you have in gatherMonsters', \&checkAggro],
);

use constant {
	TRUE => 1,
	FALSE => 0,
	AGGRO_LIMIT => 3,
	RECALC_DELAY => 0.5,

	STUTTER_STEP => 0.5,
	STUTTER_DELAY => 1.8,
	STUTTER_DIST => 4,

	MIN_GATHER_START => 3, # don't start gathering enemies unless there are AT LEAST this # of enemes
	DONT_STUTTER_DIST => 7,

	ROUTE_USESTORED_MINDIST => 20,
	ONEvONE_TIMEOUT => 6.5,
	#GATHER => 1,
	#FIGHT => 2,
};

# STATES
use enum qw(
	GATHER
	ATTACK
);

sub unload {
	Plugins::delHooks($hook);
}

my $gather_state = GATHER;
my $stored_info;
my $initialized = FALSE;
my $stored_dest;
my $stored_pos;
my $mytimeout;
my $myPos;

my $currentTarget;


=pod
	#### TODO ####
	- figure out an alternateive to route_step 10 not working
	- {dmgToYou} and {attackedYou} don't work when you're just routing. need another way to get the target from 'route'
	- check if it works with betterLeader (?)
	- add character condition for skills if the character is gathering

	- //DONE check if it works with BetterWalkPlan
	- //DONE add character condition for gatheringAggressives (as a replacement for 'aggressives')
	- //DONE add a distance check before stuttering if we're < 2 distance from our current target
	- //DONE use distance check instead of timeout in general
	- //DONE add a way to gather MORE enemies if they're nearby while not losing the pack
		-- min limit and max limit maybe
	- //DONE use blockDistance for all dist checks

=cut

sub changedMap
{
	undef $stored_pos;
}

sub ai_pre
{
	return unless $config{"gatherMonsters"} eq 1; # kill switch
	my (undef,$args) = @_;

	if($initialized eq FALSE)
	{
		error ("[gatherMonsters] WARNING: it is recommended that 'route_step' is set to AT LEAST 5 or higher\n") if $config{"route_step"} < 5;
		error ("[gatherMonsters] WARNING: do NOT use run from target if you're a melee character!!!'\n") if $config{"runFromTarget"} eq 1;

		$gather_state = GATHER;
		$stored_info->{"attackAuto"} = 2; #$config{"attackAuto"};
		$config{attackAuto} = 2;
		AI::clear("gather");
		$initialized = TRUE;
	}

=pod
	if(inLockMap == true)
	{
		switch(AI_STATE)
		{
			AI_STATE == GATHER
			{
				# change to fight mode
				if(AGGRESSIVES >= AGGRO_LIMIT)
				{
					AI_STATE = FIGHT
				}
			
				# otherwise, gather
			
			
				# if no monsters on screen, search the map for monsters to gather
			
				# if monsters on screen, go up to them and hit them (ONCE)
			
				# stutter step to not lose the pack
			}
		
			AI_STATE == FIGHT
			{
				# fight
				if(AGGRESSIVES<=0)
				{
					AI_STATE = GATHER
				}
			}
	
		}
	}
=cut

	# we're in lockMap :D
	if($field->baseName eq $config{"lockMap"})
	{
		return if (AI::action eq "sitAuto");

		if($gather_state == GATHER)
		{
			# do stuff to initialize attack gather here, like ... idk whatever
			#if($config{"attackAuto"} ne -1)
			#{
			#	$config{"attackAuto"} = -1;
			#}

			# gather :D
			# -----------------

			my $myPos = calcPosition($char); #doing this up here since it gets used in a few places
			if(!defined $stored_pos)
			{
				$stored_pos->{x} = $myPos->{x};
				$stored_pos->{y} = $myPos->{y};
			}

			my $ataq_route;
			# if no monsters on screen, search the map for monsters to gather

			if(AI::action eq "route"
				and AI::action(1) eq "attack")
			{
				# we're on route to a target
				if(timeOut($mytimeout->{"route_attack"},3))
				{
					#sendMessage($messageSender, "p", "routing to target");
					$mytimeout->{"route_attack"} = time;
				}

				my $attackSeq = AI::args(1);
				my $attackTarget = Actor::get($attackSeq->{ID});

				if($attackTarget and ($attackTarget->{dmgFromYou} > 0 || $attackTarget->{dmgToYou} > 0 || $attackTarget->{attackedYou} > 0))
				{
					# go next

					# we've already hit, stop hitting, and ignore it
					$attackTarget->{ignore} = 1;
					$attackTarget->{attack_failed} = time + 9999;
					$char->sendAttackStop;
					AI::clear("attack");
					print "Trying to clear the current target and ignore it \n";
				}
				elsif($attackSeq->{monsterPos}
					and %{$attackSeq->{monsterPos}}
					#and blockDistance($realMyPos, $realMonsterPos) < 2
				)
				{
					#print "monsterPos: \n";
					#print Dumper($attackSeq->{monsterPos});
					$ataq_route->{x} = $attackSeq->{monsterPos}->{x};
					$ataq_route->{y} = $attackSeq->{monsterPos}->{y};

					
				}
			}

			# if no monsters on screen that we haven't hit already
			# $monster->{ignore} = 1;
			if(AI::action eq "attack")
			{
				# $monster->{ignore} = 1;
				my $attackIndex = AI::findAction("attack");
				my $ataq_id = AI::args($attackIndex)->{ID} if (defined $attackIndex);

				# find the route to the target
				#my $route

				my $currTarget = Actor::get($ataq_id);

				if($currTarget->{dmgFromYou} > 0 || $currTarget->{dmgToYou} > 0 || $currTarget->{attackedYou} > 0)
				{
					# we've already hit, stop hitting, and ignore it
					$currTarget->{ignore} = 1;
					$currTarget->{attack_failed} = time + 9999;
					$char->sendAttackStop;
					AI::clear("attack");
					print "Trying to clear the current target and ignore it \n";
				}
			}
			
			# if monsters on screen, go up to them and hit them (ONCE)
			#my $myPos = calcPosition($char);

			# stutter step to not lose the pack

			my $minGatherStart = defined $config{"gatherMonsters_minGatherStart"} ? $config{"gatherMonsters_minGatherStart"} : MIN_GATHER_START;
			if(AI::action eq "route"
				and scalar(myGetAggressives()) > 0
				and scalar(@$monstersList) >= $minGatherStart
				#and timeOut($mytimeout->{"stutter_step"},STUTTER_STEP)
				and blockDistance($myPos, $stored_pos) > STUTTER_DIST)
			{

				# before clearing the route, we need to save it
				if (AI::action eq 'route' && defined(AI::args(0)->getSubtask()))
				{
					my $routeArgs = AI::args(0);
					my $routeTask = $routeArgs->getSubtask;

					if(defined $routeTask->{dest})
					{
						$stored_dest = $routeTask->{dest};

						#print Dumper($stored_dest->{map}->{baseName});
						#print Dumper($stored_dest->{pos});
					}
					
				}

				# check to see if you destination is outside a reasonable threshold to clear it!
				#print Dumper($ataq_route);
				my $dist = defined $ataq_route ? blockDistance($ataq_route, $myPos) : undef;
				if(!defined $dist || $dist > DONT_STUTTER_DIST)
				{
					#print "$dist is > ".DONT_STUTTER_DIST."\n";

					# stop moving
					#$char->sendMove(@{calcPosition($char,4)}{qw(x y)});
					AI::clear("route");

					# need to stutter step here
					$mytimeout->{"stutter_wait"} = time;
					$stored_pos->{x} = $myPos->{x};
					$stored_pos->{y} = $myPos->{y};

					AI::queue("gather");

				}
				# otherwise don't!'
				#else
				#{
				#	$mytimeout->{"stutter_step"} = time;
				#}

			}

			# ai will route->attack to get to the target

			# step 1 - add gather to the ai queue
			# step 2 - clear route
			# step 3 - after waiting for 1.2s, clear gather from the ai and let the ai_attack take over

			#if(AI::action(0) eq "gather")
			if(AI::action eq "gather" and timeOut($mytimeout->{"stutter_wait"},STUTTER_DELAY))
			{
				# process our gather logic here

				# stop moving for 1.2s, then clear gather

				# reset the stutter step time
				#$mytimeout->{"stutter_step"} = time;
				AI::clear("gather");

				# restore our move
				if(defined $stored_dest and blockDistance($myPos, $stored_dest) > ROUTE_USESTORED_MINDIST)
				{
					# start with just checking if we have a stored destination

					# then route to it IF we're > X dist away. the X dist thing is for in case there are NPCs or some shit

					message "[betterLeader] trying to use stored route\n", "success";

					ai_route(
						$stored_dest->{map}->{baseName},
						$stored_dest->{pos}{x},
						$stored_dest->{pos}{y},
						attackOnRoute => 2,
						#isFollow => 1,
						isRandomWalk => $field->baseName eq $config{'lockMap'},
						isToLockMap =>  $field->baseName ne $config{'lockMap'},
						distFromGoal => 5 # maybe don't need this
					);
				}
			}


			# check for monsters to gather. do we keep a list of monsters we've hit? keep a hash table?

			# -----------------

			# we have enough, start attacking
			my $aggroLimit = defined $config{"gatherMonsters_aggroLimit"} ? $config{"gatherMonsters_aggroLimit"} : AGGRO_LIMIT;

			# new aggro tech. check if there are more monsters on the map?
			my $monCount = scalar(@$monstersList);

			$aggroLimit =	$monCount <= $config{"gatherMonsters_aggroLimit_min"} ? $config{"gatherMonsters_aggroLimit_min"} :
							$monCount >= $config{"gatherMonsters_aggroLimit_max"} ? $config{"gatherMonsters_aggroLimit_max"} :
							$monCount;
							#$config{"gatherMonsters_aggroLimit"};

			#my $year = $credits < 30 ? "freshman" :
			#$credits <= 59 ? "sophomore" :
			#$credits <= 89 ? "junior" :
			#				"senior";

			#if monster count is <= min, set min
			#if monster count is >= max, set max
			#else set config

			if(scalar(myGetAggressives()) >= $aggroLimit)
			{
				# switch to attack state
				#sendMessage($messageSender, "p", "Switching to attack mode, attack is ".$stored_info->{"attackAuto"});
				$messageSender->sendEmotion(27);
				#print "Switching to attack mode\n";

				# loop monsters, reset ignored

				my @monsterList = @{$monstersList->getItems()};
				foreach my $monster (@monsterList) {
					$monster->{ignore} = 0;
					undef $monster->{attack_failed};
				}

				$char->sendAttackStop;
				$gather_state = ATTACK;
				#AI::clear("route");
				#AI::clear("gather");
				AI::clear();
				$char->queue('checkMonsters');
				return;
			}


			# check monster->{dmgToYou} in case it's hurt me. if it has then fight it
			# check monster->{dmgFromYou} to see if we have already hit it. if we have then continue to fight it
		}
		elsif($gather_state == ATTACK)
		{
			# do stuff to initialize attack state here

			# attack :D
			$config{"attackAuto"} = $stored_info->{"attackAuto"}; # this SHOULD be 2, but whateverrrrrrr

			my $timeout1v1 = defined $config{"gatherMonsters_1v1Time"} ? $config{"gatherMonsters_1v1Time"} : ONEvONE_TIMEOUT;
			if(!defined $mytimeout->{"1v1"} and scalar(myGetAggressives()) <= 1)
			{
				$mytimeout->{"1v1"} = time;
			}
			elsif(timeOut($mytimeout->{"1v1"}, $timeout1v1) and scalar(myGetAggressives()) <= 1
				or scalar(myGetAggressives()) <= 0)
			{
				undef $mytimeout->{"1v1"};
				$gather_state = GATHER;
				#sendMessage($messageSender, "p", "Switching to gather mode");
				#print "Switching to gather mode\n";
			}
		}
	}
}

sub checkSelfCondition
{
	my (undef,$args) = @_;

	if ($config{$args->{prefix} . "_gatherAggressives"})
	{
		$args->{return} = 0;

		$args->{return} = 1 if (inRange(scalar(myGetAggressives()), $config{$args->{prefix} . "_gatherAggressives"}));
	}

	if ($config{$args->{prefix} . "_whenGathering"})
	{
		$args->{return} = 0;

		$args->{return} = 1 if ($gather_state == GATHER);
	}

	if ($config{$args->{prefix} . "_whenNotGathering"})
	{
		$args->{return} = 0;

		$args->{return} = 1 if ($gather_state == ATTACK);
	}
}

sub checkAggro
{
	if($field)
	{
		sendMessage($messageSender, "p", "I have ".(scalar(myGetAggressives()))." aggro monsters");
	}
}

sub myGetAggressives {
	my ($type, $party) = @_;
	my $wantArray = wantarray;
	my $num = 0;
	my @agMonsters;

	for my $monster (@$monstersList) {
		my $control = Misc::mon_control($monster->name,$monster->{nameID}) if $type || !$wantArray;
		my $ID = $monster->{ID};
		# Never attack monsters that we failed to get LOS with
		next if (!timeOut($monster->{attack_failedLOS}, $timeout{ai_attack_failedLOS}{timeout}));
		#next if (!timeOut($monster->{attack_failed}, $timeout{ai_attack_unfail}{timeout}));
		next if (!Misc::checkMonsterCleanness($ID));

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

# storing the last place we were walking to
=pod
if (AI::action eq 'route' && defined(AI::args(0)->getSubtask()))
{
	my $routeArgs = AI::args(0);
	my $routeTask = $routeArgs->getSubtask;

	$storedTask = $routeArgs;

	if(defined $routeTask->{dest})
	{
		$stored_dest = $routeTask->{dest};

		print Dumper($stored_dest->{map}->{baseName});
		print Dumper($stored_dest->{pos});
	}
					
}
=cut

# restoring the saved walk destination
=pod
if(defined $stored_dest and distance($myPos, $stored_dest) > ROUTE_USESTORED_MINDIST)
{
	# start with just checking if we have a stored destination

	# then route to it IF we're > X dist away. the X dist thing is for in case there are NPCs or some shit

	message "[betterLeader] trying to use stored route\n", "success";

	ai_route(
		$stored_dest->{map}->{baseName},
		$stored_dest->{pos}{x},
		$stored_dest->{pos}{y},
		attackOnRoute => 2,
		#isFollow => 1,
		isRandomWalk => $field->baseName eq $config{'lockMap'},
		isToLockMap =>  $field->baseName ne $config{'lockMap'},
		distFromGoal => 5 # maybe don't need this
	);
}
=cut

1;
