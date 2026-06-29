####### TODO LIST #######
#	1 - Merge in the reading thng from monsterDB.pl so we can grab the monster's level for our check
#	2 - Fix the dmg to party check so that it will ignore the timer if the target has dealt enough damage to the party
#	3 - consider adding a 'skill use' command when switching targets to an enemy that is targeting a support
#	4 - be more lenient with enemies that are not aggressive when calling out support attackers
#	5 - can probably use sql workbench to spit out the info i need for a new (and more accurate) table
#
#
######################

package attackDefender;

use strict;
use Time::HiRes qw(time usleep);
use Text::ParseWords;
use Config;
eval "no utf8;";

use Globals;
use Modules;
use Settings;
use Log qw(message warning error debug);
use FileParsers;
use Interface;
use Commands;
use Misc;
use Plugins;
use Utils;
use ChatQueue;

use AI;
use Actor;
use Actor::You;
use Actor::Player;
use Actor::Monster;
use Actor::Party;

use Data::Dumper;
use Translation qw(T TF);
use feature "switch";

#use Network::DirectConnection;

		# calc time stuff

		#my $time = time;
		#while ( !$self->{done} && (!$self->{maxTime} || !timeOut($time, $self->{maxTime})) ) {
		#	$self->searchStep();
		#}

#use monsterDB; #does this work?

Plugins::register("attackDefender", "attackDefender Plugin", \&on_unload, \&on_reload);
#my $aiHook = Plugins::addHook("AI_pre", \&ai_pre, undef);

my $aiHook = Plugins::addHooks(
	['AI_pre', \&ai_pre, undef],
	["packet_pre/party_chat", \&partyMsg, undef],
	["packet_pre/monster_hp_info", \&monsterHPUpdate, undef],
	['packet_skilluse', \&skillUse, undef],
	['is_casting', \&casting, undef],
	['checkMonsterCondition', \&monCheck, undef],
	['add_monster_list', \&monster_added, undef],
	['packet/actor_display', \&actor_stuff, undef],
	['packet_pre/actor_action', \&actor_action, undef],
	['AI_post',       \&ai_post, undef]
);

my $commands_handle = Commands::register(
	['ad_size', 'databazse size', \&ad_size],
	['ad_dump', 'dumps the whole database (ruh oh)', \&ad_dump],
);

use constant {
	MAX_MONSTER_PROXIMITY_THRESHOLD => 15, # when there are more than X monsters to check, don't bother checking proximity
	TRUE => 1,
	FALSE => 0,
	MAX_CALC_TIME => 0.2,
	BOSS_TANKED_PROXIMITY => 3.5,
};

#AI_post

my @monsterDB;
my $recalc_timeout = time; #we don't use $args->{move_timeout}, we have to make our own
my $mytimeout; #new container for all timeouts
my $boredom = 0;
my $current_target;
my $storage; # random stuff i need to keep track of

my $storedBossID; # variable to store our current boss ID. need to maintain that the boss is OK to attack if we've refreshed

my %self;

sub on_unload {
	# This plugin is about to be unloaded; remove hooks
	Plugins::delHook($aiHook);
	@monsterDB = undef;
}

sub on_reload {
	&on_unload;
}

my $self;

loadMonDB2(); # Load MonsterDB into Memory

sub loadMonDB2 {
	@monsterDB = undef;
	my @temp;
	debug ("MonsterDB: Loading DataBase\n",'attackDefender',2);
	my $file = Settings::getTableFilename('monsterDB2.txt');
	error ("MonsterDB: cannot load $file\n",'attackDefender',0) unless (-r $file);
	{ open my $fp, '<', $file; @temp = <$fp> }
	my $i = 0;
	foreach my $line (@temp) {
		#ID	lvl	hp	size	race	element(lvl)	aggressive	threat? (i added level and threat)
		#1001 16 153 0 4 23
		#print $line;
		next unless ($line =~ /(\d+)\s+(\d+)\s+(\d+)\s+(\d)\s+(\d)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/);
		#next unless ($line =~ /(\d{4})\s+(\d+)\s+(\d)\s+(\d)\s+(\d+)\s+(\d+)/);
		$monsterDB[(int($1) - 1000)] = [$2,$3,$4,$5,$6,$7,$8,$9];
		$i++;
		
		#(\d{4})\s+(\d+)\s+(\d)\s+(\d)\s+(\d+)
	}
	message "FUCKYOUFUCKYOUFUCKYOU\n";
	message TF("%d monsters in database\n", $i), 'attackDefender';
}

sub ad_size {
	print scalar(@monsterDB)."\n";
	print Dumper($monsterDB[scalar(@monsterDB)-1]);
}

sub ad_dump {

}

sub monster_added {

	# Plugins::callHook('add_monster_list', $actor);
	my (undef,$args) = @_;

	# get monster info from the db
	my $monsterInfo = $monsterDB[(int($args->{nameID}) - 1000)];

	# update if it exists
	if($monsterInfo)
	{
		$args->{hp} = $monsterInfo->[2];
		$args->{hp_max} = $monsterInfo->[2];
		#print "~~~ updated ".$args->{name}." monster hp info\n";
	}
}

my $actor_spam_delay = 0;
sub actor_stuff {
	my (undef,$args) = @_;

	return;

	# '09FD' => ['actor_moved'
	# '09FE' => ['actor_connected'
	# '09FF' => ['actor_exists'

	# TYPE: 0 = PLAYER

	return unless $args->{'object_type'} eq 0; # player

	return if $args->{switch} eq "0086"; # no hp in this one
	return if $args->{switch} eq "09FD"; # sometimes hp in this one, if its already hurt
	return if $args->{switch} eq "09FF"; # sometimes hp in this one, if its already hurt
	return if $args->{switch} eq "09FE"; # sometimes hp in this one, if its already hurt

=pod
	if($args->{'object_type'} eq 5) # i think 5 is monsters
	{
		my $actorGet = = $monstersList->getByID($args->{ID});
		if()
		{

		}
	}
=cut

	if(timeOut($actor_spam_delay, 5.0))
	{

		print Dumper($args);

		$actor_spam_delay = time;
	}
}
	# sub meetingPosition
	# my ($actor, $actorType, $target, $attackMaxDistance, $runFromTargetActive) = @_;

	# 4. The route should not exceed at any point $max_pathfinding_dist distance from the target.
	#my $solution = [];
	#my $dist = new PathFinding(
	#	field => $field,
	#	start => $realMyPos,
	#	dest => $spot,
	#	avoidWalls => 0,
	#	min_x => $min_pathfinding_x,
	#	max_x => $max_pathfinding_x,
	#	min_y => $min_pathfinding_y,
	#	max_y => $max_pathfinding_y
	#)->run($solution);

#my $also_delete_me_later;
sub monsterHPUpdate {
	my ($self, $args) = @_;

	# ID
	# hp
	# hp_max

	#print "bet \n";
	#print Dumper($args);
	my $targetToUpdate = $monstersList->getByID($args->{ID});

	#print "Got here AD 1\n";

	if($targetToUpdate)
	{
=pod
		$targetToUpdate->{hp} = $args->{hp};
		$targetToUpdate->{hp_max} = $args->{hp_max};

		# if the monster's current detlaHP is LOWER than what the server is sending us, use that
		if(abs($targetToUpdate->{deltaHP}) < $targetToUpdate->{hp})
		{
			$targetToUpdate->{hp} = abs($targetToUpdate->{deltaHP});
		}
=cut
		# the target requires having its hp_max value to be set to check for focus fire, so set that here
		$targetToUpdate->{hp_max} = $args->{hp_max};

		# store the current hp as a NEGATIVE value as deltaHP (easier to work with)
		my $tmp_val = $args->{hp} - $args->{hp_max};
		if($tmp_val < $targetToUpdate->{deltaHP})
		{
			$targetToUpdate->{deltaHP} = $tmp_val;
		}

		# special condition for monsters that (can) change their elements at HP thresholds
		my $hpRatio = 100;
		if($args->{hp} > 0 and $args->{hp_max} > 0)
		{
			$hpRatio = $args->{hp} / $args->{hp_max};
		}

		#print "Got here AD 2\n";

		# test
		#if($hpRatio <= 0.5 and !defined $flags{"ThanaHoly"})
		#{
		#	sendMessage($messageSender, "p", "thanatos is holy!");
		#}
		
		if($targetToUpdate->{name} eq "Thanatos Phantom"
			and $hpRatio <= 0.5
			and !defined $flags{"ThanaHoly"}) # thanatos phantom
		{
			sendMessage($messageSender, "p", "thanatos is holy!");
		}

		#print "adding HP to ".$targetToUpdate->{name}.", ID: ".$args->{ID}."\n";

		#print $args->{hp}."/".$args->{hp_max}."\n";
	}
	else
	{
		error("no monster HP to update somehow???\n", 'attackDefender', 1);
	}

	#if(timeOut($also_delete_me_later, 5.0))
	#{
	#	print Dumper($args);
	#	$also_delete_me_later = time;
	#}

}

my $DELETE_ME_L8R;
my $stop_talking_so_much;
sub ai_pre {
	#my ($type, $party, $hookArgs) = @_;
	my (undef,$args) = @_;
	my @arrayPlayers;
	my %argumentHash;
	my $count;
	my $otherCount = 1;
	my $targetDistance = 4;
	
	my $personalSpace;
	my $friendBubble;
	my $printer;
	
	#while($printer = $self->{remote_socket})
	#{
	#	message "$printer\n";
	#}
	
	#while(<$self->{remote_socket}>)
	#{
	#	print;
	#}
	
	#message "got this far D:\n";
	
	#$char->{name}
	#return 0 if !$args;
	
	#return if ($config{'teleportAuto_useItemForRespawn'});
	return if (!defined $::config{attackDefender});
	
	$personalSpace = $config{'attackDefender_self'};
	$friendBubble = $config{'attackDefender'};
	
	my $me = $char->{ID};
	
	#give it some breathing room
	#return if (!timeOut($recalc_timeout, 0.65));
	return unless timeOut($recalc_timeout, 0.65);
	
	return if $char->{dead};

	return if AI::action eq "NPC";
	
	return if (percent_hp($char) < $config{'attackDefender_hpMin'});

	my $time = time;
	
	#message "hello world, im $me\n";
	# create player array
	my @partyList;
	my $myPos = calcPosition($char);

	foreach my $player (@{$playersList->getItems()}) {
		if($char->{party} && $char->{party}{users}{$player->{ID}}){
			push @partyList, $player->{ID};
		}
	}
	
	my $ataqArgs = AI::args if AI::action eq "attack";

	my $attackIndex = AI::findAction("attack");
	my $ataq_id = AI::args($attackIndex)->{ID} if (defined $attackIndex);

	my $experimental = 0;
	my $experimental2 = 0;

	my @monsterList = @{$monstersList->getItems()};

	# TODO: dont think i need this anymore
	#if($experimental)
	#{
	#	# append the PLAYER LIST to the monster list???
	#	#@monsterList = (@{$monstersList->getItems()}, @{playersList->getItems()});
	#	@monsterList = (@$monstersList, @$playersList);
	#
	#	print "monsterList size is ".scalar(@monsterList)."\n";
	#}

	#if($experimental2)
	#{
	#	# append the PLAYER LIST to the monster list???
	#	#@monsterList = (@{$monstersList->getItems()}, @{playersList->getItems()});
	#
	#	return unless timeOut($DELETE_ME_L8R, 1.0);
	#
	#	foreach my $monster (@monsterList) {
	#		#if(defined )
	#
	#		if(defined $monster->{hp})
	#		{
	#			message TF("Monster %s has hp %s/%s (%s%)\n", $monster->name, $monster->{hp}, $monster->{hp_max}, ($monster->{hp}/$monster->{hp_max})*100);
	#			$DELETE_ME_L8R = time + 5.0;
	#		}
	#		else
	#		{
	#			$DELETE_ME_L8R = time;
	#		}
	#
	#	}
	#}

	# focusFire stuff
	my $ff_target_ID;
	my $ff_hp_percent;
	my $ff_maxDist = $config{"attackDefender_focusFire_maxDist"} ? $config{"attackDefender_focusFire_maxDist"} : 12;

	# high prio stuff
	my $highPrio_maxDist = $config{"attackDefender_highPrio_maxDist"} ? $config{"attackDefender_highPrio_maxDist"} : 12;

	my $high_prio_switch;

	# put a scalar monster cap here? need SOME way to optimize this. checking all monsters kill the AI in endless tower

	my $monsterOverLimit = scalar(@monsterList) > MAX_MONSTER_PROXIMITY_THRESHOLD ? TRUE : FALSE;

	foreach my $monster (@monsterList) {
		if($experimental)
		{
			next if $monster->{actorType} eq "Player"
				and existsInList($config{"attackDefender_dontKill"}, $monster->{name});
		}

		#print "got here\n";

		# retreat tech goes here for endless tower?
		if(defined $flags{"Disengage"}
			and existsInList($config{"attackDefender_always_inMap"}, $field->baseName))
		{
			#ignore the monster for now...?
			IgnoreMonster($monster->{ID}, $monster);
			return;
		}

		if(timeOut($time, MAX_CALC_TIME))
		{
			#error("~~~ calc overcapped ~~~\n");
			overcapped();
			return;
		}

		# need to put this before any "nexts" because we're checking for high prio targets
		# adding in the disengage check at the top since it affects multiple characters including party leader
		if(!defined $flags{"bossOnScreen"}
			and !defined $flags{"Disengage"}
			and defined $config{'attackDefender_highPriority'}
			and !existsInList($config{"attackDefender_highPrio_disableMaps"}, $field->baseName)
			and $ataq_id
			and $monsterOverLimit eq FALSE) # experimental. don't check this stuff when there are too many mobs
		{
			# checking if there is a high priority target on screen
			my $currTargetID = $ataq_id;
			my $currTarget = Actor::get($currTargetID);
			#message TF("We got this far at least...\n"), "attackMon";

			# we won't do anything unless our current target ISN'T' already high prio
			#if(!existsInList($config{"attackDefender_highPriority"}, $currTarget->{name}) ||
			#	!existsInList($config{"attackDefender_highPriority"}, $currTarget->{nameID}))
			if(!existsInList($config{"attackDefender_highPriority"}, $currTarget->{nameID}))
			{
				# ok, we can check
				#if(existsInList($config{"attackDefender_highPriority"}, $monster->{name}) ||
				#	existsInList($config{"attackDefender_highPriority"}, $monster->{nameID}))
				if(existsInList($config{"attackDefender_highPriority"}, $monster->{nameID}))
				{
					if($config{'attackCanSnipe'})
					{
						next unless $field->checkLOS($myPos, $monster->{pos_to}, $config{'attackCanSnipe'});
					}
					else
					{
						next unless Misc::checkLineWalkable($myPos, $monster->{pos_to});
					}

					# skip if it's too far. don't want to run across the map and pull more enemies
					# $highPrio_maxDist
					my $dist_to_target = distance($myPos, $monster->{pos_to});
					next if ($dist_to_target > $highPrio_maxDist);

					$monster->{dmgToYou} += 1;
					$monster->{dmgFromParty} += 1;
					$monster->{forceFight} = 1;

					message TF("Changing to higher priority target %s\n", $monster->{name}), "attackMon";
					if(timeOut($stop_talking_so_much, 0.65))
					{
						sendMessage($messageSender, "p", "switching to $monster->{name}");
						$stop_talking_so_much = time;
					}
					$char->sendAttackStop;
					AI::dequeue while (AI::action eq "attack");
					AI::dequeue while (AI::action eq "route");
					AI::dequeue;
					attack($monster->{ID});
					stand() if $char->{sitting};

					#message "Boss is not on screen and you're bored'.\n";
					#delete $ai_v{sitAuto_forcedBySitCommand} if(!$char->{sitting} && $ai_v{'sitAuto_forcedBySitCommand'});
					#stand() if ($char->{sitting});
					#$char->sendAttackStop;
					#AI::dequeue while (AI::inQueue("attack"));
					##ai_setSuspend(0);
					#message TF("Changing to higher priority target %s\n", $monster->{name}), "attackMon";
					#sendMessage($messageSender, "p", "switching to $monster->{name}");
					#$char->attack($monster);
					#AI::Attack::process();
					#$monster->{dmgFromParty} += 1;
					#$monster->{forceFight} = 1;
					#$boredom = 0;
					$high_prio_switch = 1;
					last;
				}

			}
		}

		# update it?
		$ataqArgs = AI::args if AI::action eq "attack";

		$attackIndex = AI::findAction("attack");
		$ataq_id = AI::args($attackIndex)->{ID} if (defined $attackIndex);

		# this needs to be, if attack is INQUEUE, and then we get the attack args
		if($ataq_id)
		{
			#print "~~~~~~~~~~~~ got an attack id fam\n";
		}

		if(!defined $flags{"bossOnScreen"}
			and !defined $flags{"Disengage"}
			and !defined $high_prio_switch
			and defined $config{'attackDefender_focusFire'}
			and $monsterOverLimit eq FALSE # experimental. don't check this stuff when there are too many mobs
			and $ataq_id
			and existsInList($config{"attackDefender_focusFire_maps"}, $field->baseName))
		{
			# FOCUS FIRE block

			# wtf is this supposed to do????

			# check all monsters that are engaged with party OR are aggressive
			# dont check monsters > X dist
			# store target with least HP
			# if target is diff, change to that target

			# TODO --OPTIMIZATION: prioritize enemies that are closer to 'the party'

			# checking if there is a high priority target on screen
			my $currTargetID = $ataq_id;
			my $currTarget = Actor::get($currTargetID);

			# to use deltaHP all the hp threshold values and whatnot must be inverted to be NEGATIVE
			# because deltaHP starts at 0 and goes down

			my $hp_switch_threshold = 2000;
			my $dist_to_ff_target = distance($myPos, $monster->{pos_to});

			#TODO: consider whether or not it's a good idea to be doing NEXTS in this block...

			next if (defined $config{'attackDefender_highPriority'} and existsInList($config{"attackDefender_highPriority"}, $currTarget->{nameID}));
			next if (defined $config{'attackDefender_highPriority'} and existsInList($config{"attackDefender_highPriority"}, $currTarget->{ID}));

			next unless ($currTarget);

			# using new deltaHP tech, so this 'next' isn't useful
			next unless (defined $currTarget->{hp});

			# what I REALLY have to do is...
			# compare the HP % of the monsters im currently attacking, to the hp of the monsters that im analyzing

			next if $currTargetID eq $monster->{ID};
			#print "~~~~~~ got here focus fire ~~~~~~~\n";

			# using new deltaHP tech

			next if $currTargetID eq $monster->{ID};
			#print "~~~~~~ got here focus fire ~~~~~~~\n";


			# the enemy HAS TO have had it's hp_max set, otherwise we can't work with it :\
			if (!defined $monster->{hp_max} || !defined $currTarget->{hp_max})
			{
				#print $monster->{name}.", ID: ".$monster->{ID}." doesn't have HP set\n";
				next;
			}

			my $currTarget_hp = $currTarget->{detlaHP} + $currTarget->{hp_max};
			my $monster_hp = $monster->{detlaHP} + $monster->{hp_max};

			#print "FF: monster got some hp!\n";

			# need a different hp threshold check here since deltaHP doesn't know the monsters' full hp value...
			# unless i utilize the monster db, which i certainly could

			next if ($currTarget_hp <= $hp_switch_threshold);
			next if ($dist_to_ff_target > $ff_maxDist);
			#print "FF: target got some hp!\n";

			#next if ($currTarget_hp <= $monster_hp and distance($myPos, $currTarget->{pos_to}) < $ff_maxDist);
			next if ($currTarget_hp <= $monster_hp and distance($char->{pos}, $currTarget->{pos_to}) < $ff_maxDist);
			next if (defined $ff_hp_percent and $ff_hp_percent <= $monster_hp);

			# TODO: this is wrong. need to keep checking vs the NEW target
			if(defined $ff_hp_percent and $monster_hp > $hp_switch_threshold and $monster_hp < $ff_hp_percent)
			{
				# queue change targets to this monster
				$ff_target_ID = $monster->{ID};
				$ff_hp_percent = $monster_hp;

				print "~~~~~ switching targets: ".$ff_hp_percent." < ".$currTarget_hp."\n";
			}
			elsif($monster_hp > $hp_switch_threshold and $monster_hp < $currTarget_hp)
			{
				# queue change targets to this monster
				$ff_target_ID = $monster->{ID};
				$ff_hp_percent = $monster_hp;

				print "~~~~~ switching targets: ".$ff_hp_percent." < ".$currTarget_hp."\n";
			}


		}
		#elsif(AI::action eq "attack")
		#{
		#	$args = AI::args;
		#	print "merp \n";
		#	print Dumper($args);
		#}

		#monster is already considered aggressive, ignore it
		next if ($monster->{dmgFromParty} > 0 || $monster->{dmgToParty} > 0);
		
		#ignore list
		next if (existsInList($config{"attackDefender_ignore"}, $monster->{name}));
	
		my $control = Misc::mon_control($monster->name,$monster->{nameID});
		my $ID = $monster->{ID};
		next if (!timeOut($monster->{attack_failedLOS}, 6));
		
		next if !$monster || $monster->{nameID} eq '';
		
		#get the DB info
		my $monsterInfo = $monsterDB[(int($monster->{nameID}) - 1000)];
		my $isBoss = 0;
		if (!defined $monsterInfo) {
			my $arse = (int($monster->{nameID}) - 1000);
			error("monsterDB2: Monster {$monster->{name}, $arse, $monster->{nameID}} not found\n", 'attackDefender', 1);
			error("monsterDB2 size is: ".scalar(@monsterDB)."\n");
		}
		else
		{
			$isBoss = $monsterInfo->[7];
		}

		# check if the monster is a boss and if we're the party leader :eyes:
		if($isBoss and defined $config{'attackDefender_Leader'} and !AI::inQueue("attack"))
		{
			$monster->{dmgToYou} += 99999;
			attack($monster->{ID});

			# need to route to the boss if it's not too far
			ai_route(
				$field->baseName,
				$monster->{pos_to}{x},
				$monster->{pos_to}{y},
				attackOnRoute => 1,
				maxRouteTime => $config{route_randomWalk_maxRouteTime},
				#isFollow => 1,
				distFromGoal => 3
			);
		}
		elsif(defined $config{'attackDefender_chase'}
			and !(existsInList($config{"attackDefender_chase_notInMap"}, $field->baseName))
			and (existsInList($config{"attackDefender_chase"}, $monster->{name}) || existsInList($config{"attackDefender_chase"}, $monster->{nameID}))
			and !AI::inQueue("attack")
			and defined $flags{"bossOnScreen"})
		{
			# make sure you can actually WALK to it...
			my $pos = meetingPosition($char, 1, $monster, $config{"attackMaxRouteDistance"});
			if($pos)
			{
				#print "~~~~~~ Got here attackDefender_chase ~~~~~~~~~~\n";
				# try to attack it
				message("[attackDefender] Chasing: ".$monster->{name}."\n", "attackMon");
				#print "Chasing: ".$monster->{name}."\n";
				$monster->{dmgToYou} += 99999;
				attack($monster->{ID});
				last;
			}
			else
			{
				error "[attackDefender] Chasing: Can't chase ".$monster->{name}.", no meeting position\n";
				$monster->{attack_failed} = time;
				#print "Chasing: Can't chase ".$monster->{name}.", no meeting position\n";
			}
		}

		#Check if the monster is either too high to attack, or too low to care about
		my $mon_lvl = $monsterInfo->[0];
		
		#message "hello world, monster level is $mon_lvl \n";
		
		#debug("monsterDB: Monster {$monster->{name} , Level: $mon_lvl } found\n", 'attackDefender', 1);
		
		#timeout($mytimeout->{'boredTime'}, $config{attackDefender_bored})
		# or ) && defined $config{attackDefender_bored}

		#$monsterOverLimit eq FALSE

		if(!existsInList($config{"attackDefender_always_inMap"}, $field->baseName)
			and $config{attackDefender_ignoreLevels} ne 1
			and !existsInList($config{"attackDefender_always"}, $monster->{name})){
			#|| ($config{"attackDefender_always_inMap"} and !existsInList($config{"attackDefender_always_inMap"}, $field->baseName))){
			if(defined $config{attackDefender_bored}){
				#message "attackDefender_bored is defined at least\n";
				if(timeOut($mytimeout->{'boredTime'}, $config{attackDefender_bored})){
					$boredom = 1;
				}
			}
			
			next if(($mon_lvl - $char->{lv}) > $config{attackDefender_ignoreLow} or
			($mon_lvl - $char->{lv}) < (-$config{attackDefender_ignoreHigh}) and
			$boredom eq 0);
			#print Dumper(\$monsterInfo);
		}
		
		#message "Got this far 0\n";

		if(Misc::checkMonsterCleanness($ID) || 1 eq 1){			
			#message "we can attack the monster\n";
			
			#message "Got this far 1\n";
			
			if ($config{'attackDefender_self'}>0){
				#checkfor self
				#push @partyList, $me;
				#my $bonertime = $char->{ID};
				
				my $myPos2 = calcPosition($char);
				my $pos2 = $monster->{pos_to};#calcPosition($monster);

				#message "current target is $monster->{name}\n";
				#message "Failed can't walk to target\n" if (!Misc::checkLineWalkable($myPos2, $pos2));
				#message "Failed can't snipe to target\n" if (!Misc::checkLineSnipable($myPos2, $pos2));
				#message "Failed other snipe check to target\n" if (!$field->checkLOS($myPos2, $pos2, $config{'attackCanSnipe'}));
				#message "Passed snipe check to target\n" if ($field->checkLOS($myPos2, $pos2, $config{'attackCanSnipe'}));

				# this stuff is broken ---V
				#f (!$field->checkLOS($myPos, $pos, $attackCanSnipe))
				#f (!$field->checkLOS($myPos2, $pos2, $config{'attackCanSnipe'}))
				#checkLineWalkable

				my $attackCanSnipe = $config{'attackCanSnipe'};

				#adding a new line of sight check
				#if we CAN snipe, check that we're able to. if our attack can't snipe, then we just need to check if it's walkable

				if($attackCanSnipe)
				{
					my $snipeResult = $field->checkLOS($myPos2, $pos2, $config{'attackCanSnipe'});
					next if (!$snipeResult);
				}
				elsif(!Misc::checkLineWalkable($myPos2, $pos2))
				{
					next;
				}

				#next if ((($config{'attackCanSnipe'}) ? !Misc::checkLineSnipable($myPos2, $pos2) : (!Misc::checkLineWalkable($myPos2, $pos2) || !Misc::checkLineSnipable($myPos2, $pos2))));

				#message "Got this far 2\n";

				if (distance($pos2, $myPos2) <= $personalSpace) {
					delete $ai_v{sitAuto_forcedBySitCommand} if(!$char->{sitting} && $ai_v{'sitAuto_forcedBySitCommand'});
					message __LINE__ . ": Monster {$monster} is within acceptable range\n" if ($config{attackDefender_Debug});
					#if($self->{remote_socket}->connected)
					#{
					#	my $msg = stringToBytes("$monster->{name} is withing acceptable range!!");
					#	$self->{remote_socket}->send($msg);
					#}
					message TF("Mon level is: %s\n", $mon_lvl), "attackDefender" if ($config{attackDefender_Debug});
					$monster->{dmgFromParty} += 1;
					$monster->{dmgToYou} += 1;
					$monster->{forceFight} = 1;
					stand() if ($char->{sitting});
				}
			}

			#if($boredom eq 1)
			#{
			#	message "You are bored.\n";
			#}

			# MAX_MONSTER_PROXIMITY_THRESHOLD => 20,
			# when there are more than X monsters to check, don't bother checking proximity to party members
			if(scalar(@monsterList) <= MAX_MONSTER_PROXIMITY_THRESHOLD)
			{
				#cycle through all members and check distance
				foreach (@partyList){
					if(timeOut($time, MAX_CALC_TIME))
					{
						#error("~~~ calc overcapped ~~~\n");
						overcapped();
						return;
					}

					#last if($config{'attackDefender'}==0);
			
					#->getByID
					my $plyrPos = calcPosition($playersList->getByID($_));
					my $mon_pos_to = $monster->{pos_to};#calcPosition($monster);
					my $plyr_mon_dist = distance($mon_pos_to, $plyrPos);

					#adding a new line of sight check
					#next if ((($config{'attackCanSnipe'}) ? !Misc::checkLineSnipable($plyrPos, $mon_pos_to) : (!Misc::checkLineWalkable($plyrPos, $mon_pos_to) || !Misc::checkLineSnipable($myPos, $pos))));

					my $attackCanSnipe = $config{'attackCanSnipe'};
								
					if($attackCanSnipe)
					{
						my $snipeResult = $field->checkLOS($plyrPos, $mon_pos_to, $config{'attackCanSnipe'});
						next if (!$snipeResult);
					}
					elsif(!Misc::checkLineWalkable($plyrPos, $mon_pos_to))
					{
						next;
					}

					#boredom check
					#if($boredom eq 1 && distance($mon_pos_to, $plyrPos) <= ($config{attackMaxDistance} + 2)){
					if(!defined $flags{"bossOnScreen"}
					and $boredom eq 1
					and $plyr_mon_dist <= (($config{attackMaxDistance} + 2)>7 ? ($config{attackMaxDistance} + 2) : 7)
					and percent_hp($char) > $config{'attackDefender_hpMin'}){

						if(!defined $flags{"bossOnScreen"})
						{
							message "Boss is not on screen and you're bored'.\n";
						}
						else
						{
							message "Boss IS on screen and you're bored'.\n";
						}


						delete $ai_v{sitAuto_forcedBySitCommand} if(!$char->{sitting} && $ai_v{'sitAuto_forcedBySitCommand'});
						message "You are bored.\n";
						$monster->{dmgFromParty} += 1;
						$monster->{forceFight} = 1;
						stand() if ($char->{sitting});
						$mytimeout->{'boredTime'} = time + $config{attackDefender_bored};
						$boredom = 0;
						last;
					}

					my $monsterInfo = $monsterDB[(int($monster->{nameID}) - 1000)];
					my $isAggressive=$monsterInfo->[5];

					if($isAggressive
					and $config{attackDefender_support}
					and $plyr_mon_dist <= 2
					and checkForPriest($playersList->getByID($_)->{jobID}) #fixme getByID could be stored as a variable so i dont have to keep getting it
					){
						delete $ai_v{sitAuto_forcedBySitCommand} if(!$char->{sitting} && $ai_v{'sitAuto_forcedBySitCommand'});
						message TF("AI_pre: Enemy %s  is trying to attack one of our supports. \n", $monster), "attacked" if ($config{attackDefender_Debug});

						sendMessage($messageSender, "p", "$monster->{name} is trying to attack a support!!");
						AI::dequeue while (AI::inQueue("attack"));
						$monster->{dmgFromParty} += 1;
						$monster->{forceFight} = 1;
						stand();
						last;
					}
				
					if ($plyr_mon_dist <= $friendBubble) {
						delete $ai_v{sitAuto_forcedBySitCommand} if(!$char->{sitting} && $ai_v{'sitAuto_forcedBySitCommand'});
						message __LINE__ . ": Monster is within acceptable range\n" if ($config{attackDefender_Debug});
						message TF("Mon level is: %s\n", $mon_lvl), "attackDefender" if ($config{attackDefender_Debug});
						$monster->{dmgFromParty} += 1;
						$monster->{dmgToYou} += 1;
						stand() if ($char->{sitting});
						last;
					}
				}
			}
		}
	}

	# focus fire switching. this should never hit if monsters over the limit
	if($ff_target_ID)
	{
		print "got here focus fire\n";

		my $new_monster = $monstersList->getByID($ff_target_ID);

		# we have a target, so switch to it
		if($new_monster and
			(($config{'attackCanSnipe'} and $field->checkLOS($myPos, $new_monster->{pos_to}, $config{'attackCanSnipe'}))
			|| Misc::checkLineWalkable($myPos, $new_monster->{pos_to}))
		)
		{
			$new_monster->{dmgToYou} += 1;
			$new_monster->{dmgFromParty} += 1;
			$new_monster->{forceFight} = 1;

			message TF("Changing to focus fire target %s\n", $new_monster->{name}), "attackMon";
			#sendMessage($messageSender, "p", "focusing $new_monster->{name} (".int($ff_hp_percent*100)."%)");
			sendMessage($messageSender, "p", "focusing $new_monster->{name} (".int($ff_hp_percent).")") unless $config{"attackDefender_focusFire_silent"};
			$char->sendAttackStop;
			AI::dequeue while (AI::action eq "attack");
			AI::dequeue while (AI::action eq "route");
			AI::dequeue;
			attack($new_monster->{ID});
			stand() if $char->{sitting};
		}
	}

	# player detection
	if(!defined $flags{"bossOnScreen"}
		and !AI::inQueue("attack")
		and $field and existsInList($config{"attackDefender_pvpMaps"},$field->{baseName})
	)
#		and 1 eq 2)
	{
		my $personalSpace = $config{'attackDefender_self'};
		my $friendBubble = $config{'attackDefender'};

		# TODO: don't want someone to run too far from the party (or arlinn chase too far)
		# check visible party members, maybe?

		# TODO: the actual distance checks and whatnot
		# TODO: track if someone dealt damage to us

		if($monsterOverLimit eq FALSE) # experimental. don't check this stuff when there are too many mobs
		{
			foreach my $player (@$playersList) {

				if(timeOut($time, MAX_CALC_TIME))
				{
					#error("~~~ calc overcapped ~~~\n");
					overcapped();
					return;
				}

				#print $player->{name}." dmgToMe: ".$player->{dmgToYou}."\n";
				#print $player->{name}." dmgTo: ".$player->{dmgTo}."\n";
				#next if (existsInList($config{"attackDefender_dontKill"}, $player->{name}) and $player->{dmgToYou} < 1 and $player->{dmgToParty} < 1);
				#print "result: ".main::findPartyUserID($player->{name})."\n";
				next if $char->{party}{users}{$player->{ID}};
				next if existsInList($config{"attackDefender_dontKill"}, $player->{name});
				next if $player->{dead};
				#next if ($monster->{dmgFromParty} > 0 || $monster->{dmgToParty} > 0);
				if(!AI::inQueue("attack"))
				{
					$player->{dmgToYou} += 99999;
					attack($player->{ID});

					# need to route to the boss if it's not too far
					#ai_route(
					#	$field->baseName,
					#	$player->{pos_to}{x},
					#	$player->{pos_to}{y},
					#	attackOnRoute => 1,
					#	maxRouteTime => $config{route_randomWalk_maxRouteTime},
					#	#isFollow => 1,
					#	distFromGoal => 3
					#);
				}
			}
		}
	}
	$recalc_timeout = time;
}

sub casting {
	my (undef,$args) = @_;

	#my $target = Actor::get($args->{targetID});
	my $skillID = $args->{skillID};

	#message TF("!!!!!!!!!! Running to Got this far 1 !!!!!!!!!!\n"), "teleport";


	#message TF("!!!!!!!!!! Running to Got this far 2 !!!!!!!!!!\n"), "teleport";

	# ask for rebuffs after getting dispelled

	#Expulsion
	#if($skillID eq 19
	#if($skillID eq 397

	# 271 is ASURA
	if($skillID eq 271 and $char->{name} eq "Kruin Outlaw" and $args->{sourceID} eq $accountID)
	{
		sendMessage($messageSender, "c", "ISORA STRIKE !!");

		Utils::Win32::playSound('F:\AsgardGloryRO\Stuff\Sounds\super-activate.wav');
	}
}

sub skillUse {
	#Plugins::callHook('packet_skilluse', {
	#	'skillID' => $args->{skillID},
	#	'sourceID' => $args->{sourceID},
	#	'targetID' => $args->{targetID},
	#	'damage' => $args->{damage},
	#	'amount' => 0,
	#	'x' => 0,
	#	'y' => 0,
	#	'disp' => \$disp
	#});

	#return 1 unless ($config{'autoFlagSetter'});

	# 250 Shield Charge (Knockback)

	my (undef,$args) = @_;

	my $target = Actor::get($args->{targetID});
	my $skillID = $args->{skillID};

	# TODO: confirm if we need this or not. the boss just PHYSICALLY ATTACKING ARLINN might be enough
=pod
	if($args->{damage} > 0)
	{
		print "Got here skill damajes\n";
		# do the tanking check here

		# tank check logic is ...

		# my $storedBossID; is something we can always check
		# in fact, i can probably just leave the current code and add NEW stuff that will overwrite it

		if(defined $storedBossID and $storedBossID eq $args->{targetID} and !($target->{'tank_checked'}))
		{
			# this gets cleared when the 'boss clear!' message gets called

			# we need to see if the caster was Arlinn
			my $caster = Actor::get($args->{sourceID});
			if($caster and $caster->{name} eq "Arlinn Kord")
			{
				# Arlinn IS the caster. Now we need to make sure she's actually BESIDE the Boss
				if(distance($caster->{pos},$target->{pos}) <= BOSS_TANKED_PROXIMITY)
				{
					# Arlinn is close enough... SHE'S GOTTA BE TANKING IT!'
				}
			}
		}

		#if(!(defined $monster->{'tank_checked'} || $storedBossID eq $monster->{ID})
		#	#and defined $config{"attackDefender_tankMode"}
		#	#and existsInList($config{"attackDefender_tankMode"}, $monster->{name})
		#	and $isBoss
		#	and !defined $config{"attackDefender_dontHitBoss"}
		#)
		#{
		#
		#	# might need to move that --v value into its own variable
		#	# need to add a distance check for if the boss is RIGHT ON TOP OF US
		#	if($monster->{dmgFromParty} < 1500 and !defined $config{"attackDefender_ignoreBossTanked"}) # this was 1500
		#	{
		#		message TF("attackDefender: Enemy %s  isn't being tanked yet. \n", $monster->{name}), "attacked";
		#		$monster->{'tank_recheck'} = time;
		#		$monster->{attack_failed} = time;# + 2;
		#		$monster->{ignore} = 1; # NOTE: Setting an enemy to be ignored doesn't do shit apparently
		#		#$monster->{forceFight} = 0;
		#		AI::dequeue while (AI::inQueue("attack"));
		#		#IgnoreMonster($ID, $monster);
		#		return;
		#	}
		#	else
		#	{
		#		message TF("attackDefender: Enemy %s  is being tanked now! \n", $monster->{name}), "attackMon";
		#		$monster->{attack_failed} = undef; #-= 5; # i don't think this works
		#		$monster->{'tank_checked'} = 1; # hopefully this means we never come back here
		#		$storedBossID = $monster->{ID}; # store the boss so we can check again (if we have to)
		#	}
		#}
	}
=cut

	# attack dancing

	# if source is me
	#if($config{"attack_dance"} and $args->{sourceID} eq $accountID and !defined $flags{"bossOnScreen"})
	#{
	#	#if($skillID eq 56) # spiral pierce (397), pierce (56)
	#	if($skillID eq 397) # spiral pierce (397), pierce (56)
	#	{
	#		sendMessage($messageSender, "p", "I'M DANCING HERE!!!!");
	#		#Utils::Win32::playSound('F:\AudioLibraries\GDC 2020\Sound Spark LLC - Whooshes Impacts and Transitions\Whoosh_Fast_02.wav');
	#		Utils::Win32::playSound('F:\AudioLibraries\GDC 2020\Soundholder - Cartoon Voices\cartoon voices female amused 2.wav');
	#
	#		my $realMyPos = calcPosition($char);
	#		my $cell = get_dance_position($char, $target);
	#
	#		$char->sendMove($cell->{x}, $cell->{y});
	#		$char->sendMove($realMyPos->{x},$realMyPos->{y});
	#		#$char->sendAttack ($ID);
	#		$char->attack($args->{targetID});
	#	}
	#	#if(timeOut($mytimeout->{'attack_dance'},0.25))
	#	#{
	#	#
	#	#}
	#}

	# only play the laser if Arlinn can see DAYBREAK
	if($skillID eq 382)
	{
		my $caster = Actor::get($args->{sourceID});
		if($caster and $caster->{name} eq "Daybreak Ranger")
		{
			#Utils::Win32::playSound('F:\Video Stuff\SS-Laser-Fast.wav');
		}
	}

	# kruin Raid DANCING
	if($char->{name} eq "Kruin Outlaw" and $args->{sourceID} eq $accountID)
	{

		# kruin got spheres
		if($skillID eq 401
			and $char->statusActive('EFST_EXPLOSIONSPIRITS')
			and timeOut($mytimeout->{'letsGo'}, 2)) #dangerous soul & 
		{
			Utils::Win32::playSound('F:\AsgardGloryRO\Stuff\Sounds\letsGO.wav');
			$mytimeout->{'letsGo'} = time;
		}

		if($skillID eq 214) # raid
		{
			my $realMyPos = calcPosition($char);
			my $cell = get_dance_position($char, $target);

			$char->sendMove($cell->{x}, $cell->{y});
			$char->sendMove($realMyPos->{x},$realMyPos->{y});
			#$char->sendAttack ($ID);
			$char->attack($args->{targetID});
		}

		# asura strike KO check #271
		if($skillID eq 271 and $args->{damage} > 0)
		{
			# get the target (if its a monster)
			my $actorGet = $monstersList->getByID($args->{targetID});

			if($actorGet and defined $actorGet->{hp} and $args->{damage} >= $actorGet->{hp})
			{
				# play sound
				Utils::Win32::playSound('F:\AsgardGloryRO\Stuff\Sounds\KO-DEMON.wav');
			}
		}
	}

	# if source is daybreak
	if($char->{name} eq "Daybreak Ranger" and $args->{sourceID} eq $accountID)
	{
		if($skillID eq 382) # sharp shooting
		{
			#sendMessage($messageSender, "p", "I'M SHARPSHOOTING HERE!!!!");
			#Utils::Win32::playSound('F:\AudioLibraries\GDC 2020\Sound Spark LLC - Whooshes Impacts and Transitions\Whoosh_Fast_02.wav');
			#Utils::Win32::playSound('F:\AudioLibraries\GDC 2020\Soundholder - Cartoon Voices\cartoon voices female amused 2.wav');

			my $realMyPos = calcPosition($char);
			my $cell = get_dance_position($char, $target);

			$char->sendMove($cell->{x}, $cell->{y});
			$char->sendMove($realMyPos->{x},$realMyPos->{y});
			#$char->sendAttack ($ID);
			$char->attack($args->{targetID});
		}
	}
}

sub ai_post {

	#if (defined($msg) && length($msg) > 0) {
	#	message "Message received from Unit";
	#}
	#while (1) {
	#   $self->{remote_socket}->recv($data, 1024);
	#   message $data;
	#   last if $data eq '';
	#}

	my $args = @_;

	#print "GOIT HERE\n";

	#return if (!defined $::config{attackDefender});

	# TODO: THINK OF A BETTER WAY TO SPLIT THIS OFF
	# party check
	# don't call out a boss if we're actively disengaging
	if(!defined $flags{"bossOnScreen"}
		and !defined $flags{"Disengage"}
		and timeOut($mytimeout->{'mvpCallout'}, 0.5))
	{
		my $bossMonster;

		foreach my $monster2 (@{$monstersList->getItems()})
		{
			my $monsterInfo = $monsterDB[(int($monster2->{nameID}) - 1000)];
			if($monsterInfo->[7] eq 1)# || 1 eq 1) #it's an MVP
			{
				$bossMonster = $monster2;
				last;
			}
		}

		if(defined $bossMonster)
		{
			# I've spotted an MVP. call it out!
			sendMessage($messageSender, "p", "I've seen a boss at ".$bossMonster->{pos_to}{x}." ".$bossMonster->{pos_to}{y}."!");
			$mytimeout->{'mvpCallout'} = time+5;
		}

	}

	return if (!defined $::config{attackDefender});

	# hanweir stuff
=pod
	if(timeOut($mytimeout->{'mvpCheck'}, 0.5))
	{
		# full party checking for if boss is on screen
		$mytimeout->{'mvpCheck'} = time;
		my $sawBoss = 0;
		my $bossMonster;

		foreach my $monster2 (@{$monstersList->getItems()})
		{
			my $monsterInfo = $monsterDB[(int($monster2->{nameID}) - 1000)];
			if($monsterInfo->[7] eq 1)# || 1 eq 1) #it's an MVP
			{
				$sawBoss = 1;
				$bossMonster = $monster2;
				last;
			}
		}



		if(defined $bossMonster)
		{
			if(!defined $flags{"bossOnScreen"} and timeOut($mytimeout->{'mvpCallout'}, 0.5))
			{
				# I've spotted an MVP. call it out!
				sendMessage($messageSender, "p", "I've seen a boss at ".$bossMonster->{pos}{x}." ".$bossMonster->{pos}{y}."!");
				$mytimeout->{'mvpCallout'} = time+5;
			}

			# hanweir stuff moved here
			if($config{"bf_callGroupUp"})
			{
				if(!defined $flags{"bossOnScreen"})
				{
					sendMessage($messageSender, "p", "repositioning!"); # re-emptive to stop some defensive skills getting wasted

					# boss spotted
					sendMessage($messageSender, "p", "boss spotted");

					# call out which boss it is
					sendMessage($messageSender, "p", "engaging $bossMonster->{name}");

					# make sure Han isn't chasing enemies
					if($char->{name} eq "Hanweir Watchkeep")
					{
						$storage->{'han_waitForAggressive'} = $config{"attackBeyondMaxDistance_waitForAgressive"};
						configModify("attackBeyondMaxDistance_waitForAgressive", 1);
					}

					$flags{"storedBoss"} = $bossMonster->{name};
					my $tempVal = $bossMonster->{name};
					$flags{$tempVal} = 1;

					# stop everything
					AI::clear(qw/attack skill_use move route mapRoute/);
				}
				# set the flag?
				$flags{"bossOnScreen"} = 1;

				$mytimeout->{'mvpCheck'} = time+5; # recheck every 10s

				if($sawBoss eq 0 and defined $flags{"bossOnScreen"})
				{
					# i dunno, do something here
			
					delete($flags{"bossOnScreen"});
					if(defined $flags{"storedBoss"})
					{
						my $storedBossValue = $flags{"storedBoss"};
						delete $flags{$storedBossValue};
						delete $flags{"storedBoss"};
						delete $flags{"devotionReady"};

						sendMessage($messageSender, "p", "Cleared!");

						if($char->{name} eq "Hanweir Watchkeep" and defined $storage->{'han_waitForAggressive'})
						{
							configModify("attackBeyondMaxDistance_waitForAgressive", $storage->{'han_waitForAggressive'}); #might need to store this
						}
					}
					else
					{
						sendMessage($messageSender, "p", "Whoops! No boss is stored");
					}
					sendMessage($messageSender, "p", "boss clear");
				}
				elsif($sawBoss eq 1)
				{
					# need some kind of check to see if we need to STOP calling the shots for a boss
				}
			}
		}

	}
=cut

	# TODO: retreating / falling back stuff. need to set / check that stuff before bothering with the stuff below
	# unless i add it as an OR, like ( stuff || (defined $flags{"bossOnScreen"} and defined $flags{"retreat"}))
	# in which case the latter would fire immediately. might be best to do it that way? :thinking:
	# i want to bypass that half second timeout, so whatever i need to do for that

	# checking for if a boss is on screen
	# don't check for a boss if we're disengaging
	if($config{"bf_callGroupUp"}
		and !defined $flags{"Disengage"}
		and timeOut($mytimeout->{'mvpCheck'}, 0.5))
	{


		# if "retreat" and "bossOnScreen" flags, do the clear block stuff?
		# or should a party chat command already handle all of that... this is tricky
		# currently hanweir controls all that stuff, but it's communicated via party chat so can do the same where i guess
		# what is it that i need to do...?

		# check all monsters on screen every 0.5s unless there WAS a boss, then do the check every 10s
		$mytimeout->{'mvpCheck'} = time;
		my $sawBoss = 0;
		foreach my $monster2 (@{$monstersList->getItems()}) {
			#my $ID2 = $monster2->{ID};
			my $monsterInfo = $monsterDB[(int($monster2->{nameID}) - 1000)];
			if($monsterInfo->[7] eq 1)# || 1 eq 1) #it's an MVP
			{


				$sawBoss = 1;
				if(!defined $flags{"bossOnScreen"})
				{
					sendMessage($messageSender, "p", "repositioning!"); # re-emptive to stop some defensive skills getting wasted

					# boss spotted
					sendMessage($messageSender, "p", "boss spotted");

					my $monName = $monster2->{name};

					# say the adjusted name
					if($monster2->{nameID} eq 2362)
					{
						$monName = "Nightmare Amon Ra";
					}
					elsif($monster2->{nameID} eq 3796)
					{
						$monName = "Ktullanux"; # TODO: fix this for the new name
					}

					# call out which boss it is
					sendMessage($messageSender, "p", "engaging $monName");

					# make sure Han isn't chasing enemies
					if($char->{name} eq "Hanweir Watchkeep")
					{
						$storage->{'han_waitForAggressive'} = $config{"attackBeyondMaxDistance_waitForAgressive"};
						configModify("attackBeyondMaxDistance_waitForAgressive", 1);
					}

					$flags{"storedBoss"} = $monster2->{name};
					my $tempVal = $monster2->{name};
					$flags{$tempVal} = 1;

					# stop everything
					AI::clear(qw/attack skill_use move route mapRoute/);
				}
				# set the flag?
				$flags{"bossOnScreen"} = 1;

				$mytimeout->{'mvpCheck'} = time+5; # recheck every 10s
				#sendMessage($messageSender, "p", "there is a monster on screen");

				# ok there is an MVP on screen, what do I want to do here?
				# the simplest thing is to have hanweir shout out BOSS SPOTTED or something and then intercept that in better follow and do something there

				# tell ulvenwald to start bombing [DONE]
				# kessig needs to fall back [DONE]
				# back away from the boss (should this be controlled here?)
				# make sure everyone stays grouped

				last;
			}
		}

		# special case where we want them to think the boss is already on screen and get their shit set up
		if($sawBoss eq 0 and defined $flags{"bossOnScreen"} and !defined $flags{"ThanatosPrep"})
		{
			# i dunno, do something here
			
			delete($flags{"bossOnScreen"});
			if(defined $flags{"storedBoss"})
			{
				my $storedBossValue = $flags{"storedBoss"};
				delete $flags{$storedBossValue};
				delete $flags{"storedBoss"};
				delete $flags{"devotionReady"};

				sendMessage($messageSender, "p", "Cleared!");

				if($char->{name} eq "Hanweir Watchkeep" and defined $storage->{'han_waitForAggressive'})
				{
					configModify("attackBeyondMaxDistance_waitForAgressive", $storage->{'han_waitForAggressive'}); #might need to store this
				}
			}
			else
			{
				sendMessage($messageSender, "p", "Whoops! No boss is stored");
			}
			sendMessage($messageSender, "p", "boss clear");
		}
		elsif($sawBoss eq 1)
		{
			# need some kind of check to see if we need to STOP calling the shots for a boss
		}
	}

	if (AI::action eq "attack"){
		
		#print Dumper(!timeOut($mytimeout->{'healer'}, 0.36));
		
		#return if (!timeOut($mytimeout->{'healer'}, 0.36));
		
		#message TF("We are inside the healer timeout\n"), "success";
				
		my $ID = AI::args->{ID};
		my $monster = Actor::get($ID);

		#if($config{"attack_dance"})
		#{
		#	if(timeOut($mytimeout->{'attack_dance'},0.25))
		#	{
		#
		#	}
		#}

		return if(defined $monster->{'dirty'}); # don't need to process the enemy if we're already determind to
		return if (!timeOut($monster->{'tank_recheck'},0.25));

		# smart detect check. this is the best place I can think of to put this...
		if($config{"attackDefender_smartDetect"}
			and existsInList($config{"attackDefender_smartDetect"}, $monster->{name})
			and $monster->statusActive("Hide, Hiding, Cloaking, Cloak, Turn Invisible, Invisibility"))
		{
			my $skill = new Skill(auto => "Detect");

			print __LINE__ . ": We got here for SmartDETECTION\n";

			if($char->{skills}{$skill->getHandle()}){
					#sendMessage($messageSender, "p", "Trying to detect boss...");
				
					my $actorList = $playersList;
				
					require Task::UseSkill;
					my $skillTask = new Task::UseSkill(
						actor => $skill->getOwner,
						target => $monster,
						actorList => $actorList,
						skill => $skill,
						maxCastTries => 4,
						priority => Task::USER_PRIORITY
					);
					my $task = new Task::ErrorReport(task => $skillTask);
					$taskManager->add($task);
				}
		}

		# my $isAggressive=$monsterInfo->[5];
		#get the DB info
		my $monsterInfo = $monsterDB[(int($monster->{nameID}) - 1000)];
		my $isBoss = 0;
		if (!defined $monsterInfo) {
			my $arse = (int($monster->{nameID}) - 1000);
			debug("monsterDB: Monster {$monster->{name} , $arse, $monsterInfo} not found\n", 'attackDefender', 1);
		}
		else
		{
			$isBoss = $monsterInfo->[7];

			# if we're meant to always ignore the boss, return early here (might need to revise this)
			if($isBoss and $config{"attackDefender_dontHitBoss"})
			{
				message TF("Don't attack the boss, god dammit!!!! \n"), "attacked";
				$monster->{attack_failed} = time+9999;
				$monster->{'attack_recheck'} = time+9999;
				$monster->{ignore} = 1;
				$monster->{'dirty'} = 1;
				$monster->{forceFight} = 0;
				AI::dequeue while (AI::inQueue("attack"));
				return;
			}
		}

		# leader rush in and fight the boss
		if($isBoss and defined $config{'attackDefender_Leader'} and !defined $monster->{'tank_checked'})
		{
			#$monster->{'attack_recheck'} = time+9999;
			$monster->{dmgToYou} += 99999;
			$monster->{forceFight} = 1;
			$monster->{'tank_checked'} = time;
			$monster->{'tank_checked'} = 1;

			message TF("Change target to boss : %s \n", $monster->{name});
			$char->sendAttackStop;
			AI::dequeue while (AI::action eq "attack");
			AI::dequeue while (AI::action eq "route");
			AI::dequeue;
			attack($monster->{ID});
			stand() if $char->{sitting};
		}

		# tankmode check (early return, this logic trumps everything below it)
		if(!(defined $monster->{'tank_checked'} || $storedBossID eq $monster->{ID})
			#and defined $config{"attackDefender_tankMode"}
			#and existsInList($config{"attackDefender_tankMode"}, $monster->{name})
			and $isBoss
			and !defined $config{"attackDefender_dontHitBoss"}
		)
		{

			# might need to move that --v value into its own variable
			# need to add a distance check for if the boss is RIGHT ON TOP OF US
			if($monster->{dmgFromParty} < 1500 and !defined $config{"attackDefender_ignoreBossTanked"}) # this was 1500
			{
				message TF("attackDefender: Enemy %s  isn't being tanked yet. \n", $monster->{name}), "attacked";
				$monster->{'tank_recheck'} = time;
				$monster->{attack_failed} = time;# + 2;
				$monster->{ignore} = 1; # NOTE: Setting an enemy to be ignored doesn't do shit apparently
				#$monster->{forceFight} = 0;
				AI::dequeue while (AI::inQueue("attack"));
				#IgnoreMonster($ID, $monster);
				return;
			}
			else
			{
				message TF("attackDefender: Enemy %s  is being tanked now! \n", $monster->{name}), "attackMon";
				$monster->{attack_failed} = undef; #-= 5; # i don't think this works
				$monster->{'tank_checked'} = 1; # hopefully this means we never come back here
				$storedBossID = $monster->{ID}; # store the boss so we can check again (if we have to)
			}
		}

		#message TF("We are after the args thing\n"), "success";
		#return if(!timeOut($monster->{attack_failed}, 0.2));
		if(defined $monster->{'attack_recheck'})
		{
			# do a check to see if the monster has dealt sufficient damage to the party to continue
			my $ignoreDmgThreshold = $char->{lv} * 10;
			if (defined $config{attackDefender_threatCheckHPPerLevel})
			{
				$ignoreDmgThreshold = $char->{lv} * $config{attackDefender_threatCheckHPPerLevel};
			}
			
			#check how much damage the monster has done to the party
			if($monster->{dmgToParty} > $ignoreDmgThreshold)
			{
				#ignore it
				#$monster->{'attack_recheck'} = 0;
				undef $monster->{'attack_recheck'};
				message TF("Target %s has done a lot of damage to party. \n", $monster), "attacked" if ($config{attackDefender_Debug});
				$monster->{ignore} = 0;
			}
			
			return if (!timeOut($monster->{'attack_recheck'},0.25));
		}
		
		
=pod
	my $ID = AI::args->{ID};
	my $target = Actor::get($ID);
	$target->{attack_failed} = time if ($monsters{$ID});
	AI::dequeue;
=cut
		my $currTarget = Actor::get($ID);

		if(!defined $currTarget || ($currTarget->{actorType} eq "Player" and !$players{$ID}) || ($currTarget->{actorType} eq "Monster" and!$monsters{$ID})){
			#error "Weird actor bug! Abort mission! Enemy is probably dead but hasn't disappeared\n";
			error "Enemy is dedge, don't need to keep going\n";
			return;
		}
		return if(!$monsters{$ID});
		
		$mytimeout->{'boredTime'} = time+$config{attackDefender_bored};

		my $forceIgnored = 0;
		
		if($monster->{ignore} eq 1 and timeOut($monster->{attack_failed}, 0.36))
		{
			if($monster->{'attack_ghost_checked'} eq 1 &&
			$monster->{'attack_ghost_dmgDealtTo'} eq $monster->{dmgToParty} &&
			$monster->{'attack_ghost_dmgDealtFrom'} eq $monster->{dmgFromParty})
			{
				# we've tried to attack the enemy for 2s, we haven't dealt damage to it and it hasn't dealt damage to the Party
				# therefore, this enemy is a GHOST and should be force-ignored
				$monster->{attack_failed} = time+999;
				return;
			}

			$monster->{attack_failed} = time+2;
			$monster->{'attack_recheck'} = time+0.5;
			message TF("%s has been attacking us long enough, KILL IT!!!\n", $monster), "attacked" if ($config{attackDefender_Debug});;

			# some extra settings to see if they enemy is actually there or not (ie a ghost)
			$monster->{'attack_ghost_dmgDealtTo'} = $monster->{dmgToParty};
			$monster->{'attack_ghost_dmgDealtFrom'} = $monster->{dmgFromParty};
			$monster->{'attack_ghost_checked'} = 1;
			return;
		}
		
		# so I can't override the attack decision values at the bottom because we never get there...
		# really there are two BIG overrides for whether or not I need to check things further
		# 1 - if it DOESN'T need to be tanked and we're set to force fight, then we always hit it
		# 2 - if we need the enemy to be tanked and its not being tanked, we dont hit it

		#my $shouldEarlyReturn = defined $monster->{forceFight};

		my $monsterInfo = $monsterDB[(int($monster->{nameID}) - 1000)];
		if (!defined $monsterInfo) {
			my $arse = (int($monster->{nameID}) - 1000);
			debug("monsterDB: Monster {$monster->{name} , $arse, $monsterInfo} not found\n", 'attackDefender', 1);
		}

		# attackDefender_focusBoss_ignore

		# ignore the monster if it's not a boss and we're set to only attack bosses (requires bossOnScreen flag)
		if(defined $flags{"bossOnScreen"} and defined $config{"attackDefender_focusBoss"} and $isBoss eq 0 and !existsInList($config{"attackDefender_focusBoss_ignore"}, $flags{"storedBoss"}))
		{
			#print "we got here 2\n";
			#print "isBoss is $isBoss\n";
			$monster->{ignore} = 1;
			$monster->{forceFight} = 0; #yes, ignore it even if we've set it to force fight
			$monster->{attack_failed} = time + 30;
			$monster->{'attack_recheck'} = time + 30;
			AI::dequeue while (AI::inQueue("attack")); # maybe do this isntead?
			error "We're focusing MVPs! Ignoring this monster for 30s\n" if($config{"attackDefender_Debug"});
		}

		# force fight check (another early return)
		if(defined $monster->{forceFight}){
			$mytimeout->{'healer'} = time+2; # not sure what this healer thing was for but there it is...
			#error "forceFight active\n";
			return;
		}

		return if(defined $monster->{ignoreCheck} and !timeOut($monster->{ignoreCheck}, 0.36));
		
		#Check if the monster is either too high to attack, or too low to care about
		my $mon_lvl = $monsterInfo->[0];
		
		#debug("monsterDB: Monster {$monster->{name} , Level: $mon_lvl } found\n", 'attackDefender', 1);

=pod
		# high priority targets
		# this needs to be AFTER the boss check because that should always be the priority. this is mainly for DAYBREAK who is my assistant killer
		# maybe for Arlinn for high prio targets like Thanatos summons or Gryphons or whatever

		# TODO: finish this proper. this is currently checking if our CURRENT target is high prio. we need to check ALL targets (or when they appear)
		# this should probably be in get aggressives? since there is already a check through all monsters
		if(existsInList($config{"attackDefender_highPriority"}, $monster->{name})
			|| existsInList($config{"attackDefender_highPriority"}, $monster->{nameID}))
		{
			# if we're already fighting this enemy, or rather, if our current target is ALSO in the list, we shouldn't do anything...
			# my $ID = AI::args->{ID};
			# my $monster = Actor::get($ID);

			# we fight it! the thing is, we ALSO want to switch to this target...
			AI::dequeue while (AI::inQueue("attack"));
			$monster->{dmgFromParty} += 1;
			$monster->{forceFight} = 1;
			stand() if $char->{sitting};
			message TF("Changing to higher priority target %s\n", $monster->{name}), "attackMon";
			$monster->{ignoreCheck} = time + 5;
			return;
		}
=cut

		if(!existsInList($config{"attackDefender_always"}, $monster->{name})
			and $config{attackDefender_ignoreLevels} ne 1
			and !existsInList($config{"attackDefender_always_inMap"}, $field->baseName)){
			#next if(($mon_lvl - $char->{lv}) > $config{attackDefender_ignoreLow} or
			#($mon_lvl - $char->{lv}) < (-$config{attackDefender_ignoreHigh}));
			
			my $attackDecision = 1;
			
			#message "$monster->{name}'s level is $mon_lvl\n";

			#check if it's too far away
			my $myPos2 = calcPosition($char);
			my $pos2 = $monster->{pos_to};#calcPosition($monster);
			if (distance($pos2, $myPos2) > $config{attackMaxDistance}){
				#too far away, ignore it
				$attackDecision = 0;
				message TF("Target %s is too far away. \n", $monster), "attackMon" if ($config{attackDefender_Debug});
			}

			#check if it's been damaged by the party
			if($monster->{dmgFromParty} > 1) {
				#check if we always assist
				if($config{"attackDefender_alwaysAssist"})
				{
					$attackDecision = 1;
				}
				else
				{
					#ignore it
					$attackDecision = 0;
					message TF("Party member already attack target. \n"), "attackMon" if ($config{attackDefender_Debug});
				}
			}
			
			#check how many aggressives the party has
			if(ai_getAggressives(undef, 1) > 2){
				$attackDecision = 1;
				message TF("Party aggressives > 2. \n"), "attacked" if ($config{attackDefender_Debug});
			}
			
			#check if it has hurt US or tried to attack US
			if($monster->{dmgToYou} >= 0 && $monster->{missedYou}){
				#ignore it
				$attackDecision = 1;
				message TF("Target %s tried to hurt us. \n", $monster), "attacked" if ($config{attackDefender_Debug});
			}
			
			#check if the monster is too low
			if(($mon_lvl - $char->{lv}) < (-$config{attackDefender_ignoreHigh})){
				$attackDecision = 0;
				my $t_val = ($mon_lvl - $char->{lv});
				my $t_val2 = (-$config{attackDefender_ignoreHigh});
				message TF("Target %s level difference is too low: $t_val < $t_val2. \n", $monster), "attackMon" if ($config{attackDefender_Debug});
			}
			
			my $threatDmgThreshold = $char->{lv} * 10;
			if (defined $config{attackDefender_threatCheckHPPerLevel})
			{
				$threatDmgThreshold = $char->{lv} * $config{attackDefender_threatCheckHPPerLevel};
			}
			
			#check how much damage the monster has done to the party
			if($monster->{dmgToParty} > $threatDmgThreshold) {
				#ignore it
				$attackDecision = 1;
				message TF("Target %s has done a lot of damage to party. \n", $monster), "attacked" if ($config{attackDefender_Debug});
			}
			
			#check the monster's threat level
			#my $control = Misc::mon_control($monster->name,$monster->{nameID});
			if($monsterInfo->[6] >= $config{attackDefender_minThreat} && defined $config{attackDefender_minThreat}){
				#ignore it
				$attackDecision = 1;
				message TF("Enemy %s is a high threat level. \n", $monster), "attacked" if ($config{attackDefender_Debug});
			}
			
			if (
			(existsInList($config{"attackDefender_alwaysHelp"}, $monster->{name}) and $monster->{dmgToParty} > 0) or 
			(existsInList($config{"attackDefender_alwaysHelp"}, $monster->{name}) and $monster->{dmgFromParty} > 0)
			){
			#attackDefender_alwaysHelp
				#message "!!!!!!!!!!!!!!!! GOT THIS FAR !!!!!!!!!!!!!\n";
				$attackDecision = 1;
				#message "attackDecision is: " . $attackDecision . "\n";
				message TF("Enemy %s help our teammates!. \n", $monster), "attacked" if ($config{attackDefender_Debug});
			}

			if($config{"attackDefender_forced"})
			{
				$attackDecision = 1;
				message TF("Always attack defender!!\n"), "attacked" if ($config{attackDefender_Debug});;
			}

			#check if there are multiple monsters around our target, then combine their threat level

			#NEW: only check this if the number of aggressives the part has is 3 or less
=pod #removing this section for now (and probably forever)
			my $partyAggressives = ai_getAggressives(undef, 1);

			if($attackDecision eq 0 and $partyAggressives <= 3){
				my $threat_level = $monsterInfo->[6];
				my $threat_count = 1;
				my $monsterpos = calcPosition($monster,2);
				
				foreach my $monster2 (@{$monstersList->getItems()}) {
					my $ID2 = $monster2->{ID};
					next if $ID2 eq $monster->{ID};
					my $monstersLocation =calcPosition($monsters{$ID2},2);
					#message "DistanceMin: $rangeArgs{dist_}\n";
					if (distance($monstersLocation,$monsterpos) <= 3) {
						#my $boobs = distance($monstersLocation,$monsterpos);
						my $monsterInfo2 = $monsterDB[(int($monster2->{nameID}) - 1000)];
						#message "Dist: $boobs\n";
						#push @agMonsters, $ID2;
						$threat_count++;
						$threat_level+=$monsterInfo2->[6];
					}
				}
				
				my $math = $threat_level / $threat_count;
				if(defined $config{attackDefender_minThreat} and $threat_level / $threat_count >= $config{attackDefender_minThreat})
				{
					message "threat level around this monsters is $math, within acceptable range\n";
					$attackDecision = 1;
				}
				
			}
=cut

			my $monsterInfo = $monsterDB[(int($monster->{nameID}) - 1000)];
			my $isAggressive=$monsterInfo->[5];

			if($isAggressive)
			{
				message TF("AI_post: Enemy %s  is aggressive. \n", $monster), "attacked" if ($config{attackDefender_Debug});
			}
			else
			{
				message TF("AI_post: Enemy %s aggressive = $isAggressive. \n", $monster), "attacked" if ($config{attackDefender_Debug});
			}

			#TODO: review this block of code here. it's probably not good to check every single monster on screen constantly (maybe)

			# this guy error'd out once?
			foreach my $iteminitem (keys %{$monster->{'dmgToPlayer'}}){
				#print Dumper($iteminitem);
				#print "\n";
				if(defined $char->{party}{users}{$iteminitem} 
					and defined $players{$iteminitem}
					and $config{attackDefender_support}
					and $isAggressive){

					return unless checkForPriest($players{$iteminitem}->{jobID});

					$attackDecision = 1;
					message TF("AI_post: Enemy %s  is attacking one of our supports. \n", $monster), "attacked" if ($config{attackDefender_Debug});
					my $name = $players{$iteminitem}->{name};

					my @shortName = split(/ /,$name);

					$monster->{ignoreCheck} = time+0.5;
					sendMessage($messageSender, "p", "$monster->{name} is trying to attack $shortName[0]!!");
					stand();
				}
			}

			#check if the monster is moving near one of our supports
=pod			
			foreach my $player (@{$playersList->getItems()}) {
				if($char->{party} 
				and $char->{party}{users}{$player->{ID}} 
				and distance($monster->{pos_to}, calcPosition($players{$player->{ID}})) <= 3
				and checkForPriest($player->{ID})
				){
					delete $ai_v{sitAuto_forcedBySitCommand} if(!$char->{sitting} && $ai_v{'sitAuto_forcedBySitCommand'});
					message TF("Enemy %s  is trying to attack one of our supports. \n", $monster), "attacked" if (defined $config{attackDefender_Debug});
					$attackDecision = 1;
					stand();
				}
			}
=cut
			
			#check if the monster is too low
			#if(($mon_lvl - $char->{lv}) < (-$config{attackDefender_ignoreHigh})){

			#message "attackDecision is: " . $attackDecision . "\n"; #FIXME
			
			if($attackDecision eq 0){
=pod
				message TF("Ignore it!\n"), "teleport" if (defined $config{attackDefender_Debug});

				
				#if we're rechecking it after already ignoring, then don't add more time
				return if($monsters{$ID}{ignore} eq 1);
				
				#message "Sending attack stop!\n";
				$char->sendAttackStop;				
				$monsters{$ID}{ignore} = 1;
				
				if (!defined $config{attackDefender_killAfterSeconds}){
					$monster->{attack_failed} = time + 2;
					$monster->{'attack_recheck'} = time;
					error "Ignoring the monster for 2 seconds...\n";
				} else {
					$monster->{attack_failed} = time + $config{attackDefender_killAfterSeconds};
					$monster->{'attack_recheck'} = time;
					error TF("Ignoring the monster for %s seconds...\n", $config{attackDefender_killAfterSeconds}), "attackDefender";
				}
				# Right now, the queue is either
				#   move, route, attack
				# -or-
				#   route, attackbor
				AI::dequeue;
				AI::dequeue;
				AI::dequeue if (AI::action eq "attack");
				$mytimeout->{'healer'} = time+2;
=cut
				IgnoreMonster($ID, $monster);
				return;
				
			} else {
				$monster->{ignoreCheck} = time+2;
				message TF("!!! Attack the target !!!\n"), "attacked";
				$monster->{'dirty'} = 1;
			}
			$mytimeout->{'healer'} = time+2;
			
			
		} else {
			$mytimeout->{'healer'} = time+2;
		}

	#message "before check to defend\n";
	#checkToDefend($monster) if $config{attackDefender_support};
	#message "after check to defend\n";
	}

	#checking for a few things in regards to dropping targets
	
	# 1 - Number of aggressives hitting us
	# 2 - the enemy's status / threat level
	# 3 - is anyone already hitting it?
	
	# potential scenario
	# the party is just chilling, hangin out
	# a poison spore approaches the party
	# archer stands up and starts attacking it
	# 5 other characters stand up and start to attack it as well
	# the poison spore only has enough HP to take a few hits so why did 5 people try?
	
	# ideal solution
	# the hunter attacks the spore
	# ai_post checks if
	#	1 - the enemy's level is within 10 of us
	#	2 - what our HP % is
	#	3 - what the monsters threat is (mon_control access?)
	#	4 - how many aggressives are attacking us
	#	5 - our distance to the enemy
	
	# Enemy Attacks Me
	# check monster->{dmgToYou} in case it's hurt me. if it has then fight it
	# check monster->{dmgFromYou} to see if we have already hit it. if we have then continue to fight it
	# check the monster's threat level -> related to mon_control i think. if the threat is tangible then continue
	# check if the monster is within 10 levels? if it is, then continue
	# check monster->{dmgFromParty} to see if it's been hurt more than 1. dmgFromParty will be set to 1 by attackDefender above ^
	# check what our HP% is -> if we're low % HP then we should kill it just in case
	# check how many aggressives are attacking our party -> if there are a lot (more than 2?) then we should attack it
	# don't check distance as it's already hit us so it's a threat
	# OTHERWISE drop the target and set it to ignore
	
	# Enemy Attacks Party Member
	# monster->{dmgToParty} will be > 0 since we will be attacking it based on attackDefender probably
	# that being said we need to see if it
	# 
	# 
	# 
	# 
	# 
	# 
	
	# so let's continue with our theoretic scenario
	# a poison spore is attacking one of our party members
	# poison spore is set to always attack since it's an aggressive monster, so we're attacking it
	# the enemy is within 10 levels of us
	# our hp is at 100%
	# the monster has a low threat level
	# there is only 1 aggressive attacking us
}

sub partyMsg
{
	my ($var, $arg, $tmp) = @_;
	my ($msg, $msg2, $ret, $name, $message);

	$msg = $arg->{message};
	my @values = split(':', $msg);
	
	chop($values[0]);
	substr($values[1], 0, 1) = '';
	
	$name = $values[0];
	$message = $values[1];

	if($config{'attackDefender_Leader'})
	{
		# check if we can't see the boss
		given($message){
			when($_ =~ /^(I've) (seen) (a) (boss) (at) (\d+) (\d+)(!)/)
			{
				# "I've seen a boss at ".$bossMonster->{pos}{x}." ".$bossMonster->{pos}{y}."!"
				continue if $field->baseName eq "thana_boss"; # don't be setting waypoints at the top of the tower
				if($char->{name} eq "Arlinn Kord" and $name ne "Arlinn Kord")
				{
					sendMessage($messageSender, "p", "roger that");
				}
				$mytimeout->{'mvpCallout'} = time+5;
				Commands::run("waypoint $6 $7 1");
				# NOTE: used to not have the '1' flag at the end, but that might have broken Arlinn's brain, maybe
			}

			when($_ =~ /(engaging) (.*)/)
			{
				continue unless AI::state == AI::AUTO;

				my $bossActor;
				foreach my $monster (@{$monstersList->getItems()}) {
					$bossActor = $monster if ($monster->{name} eq $2);
				}

				if(!$bossActor and !defined $flags{"ThanatosPrep"})
				{
					# boss isn't on screen but Hanweir called it out. Gotta get to Hanweir!
					foreach (@partyUsersID) {
						next if (!$_ || $_ eq $accountID); # next if doesn't exist or is me
						next if (!$char->{'party'}{'users'}{$_}{'online'}); # next if they're not online
						next unless ($char->{'party'}{'users'}{$_}{'name'} eq ("Hanweir Watchkeep")); # next if they're not the leader

						# this --v seems dumb
						my $tmp_charMap;
						($tmp_charMap) = $char->{party}{users}{$_}{map} =~ /([\s\S]*)\.gat/; # not sure what putting this in brackets does. will have to look it up later

						next unless ($field->baseName eq $tmp_charMap); # next unless they're on the same map
						#print("got this far 4\n");

						my $actor = $playersList->getByID($_);
			
						# FIND HAN!!
						my %leaderPos;
						$leaderPos{x} = $char->{party}{users}{$_}{pos}{x};
						$leaderPos{y} = $char->{party}{users}{$_}{pos}{y};

						# TODO: don't do this if we're set to manual mode

						AI::clear("move", "route", "mapRoute", "attack");
						ai_route(
							$field->baseName,
							$leaderPos{x},
							$leaderPos{y},
							attackOnRoute => 0,
							#isFollow => 1,
							isRandomWalk => $field->baseName eq $config{'lockMap'},
							isToLockMap =>  $field->baseName ne $config{'lockMap'},
							distFromGoal => 1
						);

						message TF("########## Han found a boss but we can't see it! ##########\n"), "follow";
						last;
					}
				}
			}
		}
	}

	if($message eq "boss clear")
	{
		undef $storedBossID;
	}
}

# this function is used to check the monsters currently attacking the party, and if they have attacked a support character
# if they have, we will drop our target and attack that monster instead
sub checkToDefend {
	#cycle through monsters
	
	my ($currentTarget) = @_;
	
	return if !timeOut($mytimeout->{'checkToDefend'},0.5);
	
	my $monster;
	my $escape = 0;
	
	message "got this far 1\n";
	
	foreach my $player (@{$playersList->getItems()}) {
		next if $escape ne 0;

		message "got this far $_\n";
		
		if($char->{party} && $char->{party}{users}{$player->{ID}} and checkForPriest($player->{jobID})){
			message "got this far 2\n";
		
			my @agMonsters = ai_getMonstersAttacking($player->{ID});
			if(scalar(@agMonsters)>0){
				my $count = scalar(@agMonsters);
				#sendMessage($messageSender, "p", "$player->{name} has $count aggros");
				print "$player->{name} has $count aggros\n";
				#$monster = $agMonsters[int(rand(@agMonsters))];
				$monster = Actor::get($agMonsters[int(rand(@agMonsters))]);
				$escape = 1;
			}
		}
	}
	
	if($escape eq 1 and defined $monster){
		# Change target to closer aggressive monster
		#print Dumper (\$monster);
		#print $monster->{name};
		#print Dumper (AI::args);
		#$monster->{ignore} = 1;
		
		my $changeTarget = 1;
		
		message "got this far $currentTarget\n" if defined $currentTarget;
		
		#ignore our current target?
		if (AI::action eq "attack" and AI::args->{ID}){
		
			#if (defined $current_target and $monster->{ID} eq $current_target->{ID}){
			#	$mytimeout->{'checkToDefend'} = time;
			#	return;
			#}
		
			message "got this far\n";
		
			my $ID = AI::args->{ID};
			my $monster2 = Actor::get($ID);
			
			#print "current target: " . $monster2 . "\n";
			#print "new target: ". $monster . "\n";
			
			message TF("current target: %s\n",$ID), "success";
			message TF("new target: %s\n",$monster), "success";
			
			if( $monster eq $monster2){
				$changeTarget = 0;
			} else {			
				$monsters{$ID}{ignore} = 1;
				$monster2->{attack_failed} = time+1;
				$monster2->{'attack_recheck'} = time+1;
			}
		}
		
		#dont change target if we're already attacking this target
		
		if($changeTarget eq 1){		
			$monster->{forceFight} = 1;
			message TF("Change target to aggressive : %s \n", $monster->{name});
			#sendMessage($messageSender, "p", "Trying to target $monster->{name}");
			$char->sendAttackStop;
			AI::dequeue;
			AI::dequeue if (AI::action eq "route");
			AI::dequeue;
			attack($monster->{ID});
			$current_target = $monster;
			stand() if $char->{sitting};		
		}
	}
	
	$mytimeout->{'checkToDefend'} = time;
	
	#return $escape;
	
	#drop our current target
	
	#attack the new target
}

sub checkForCaster {
	my ($args) = @_;
	return 1 if $args eq 2; # 2 is magician
	return 0;

}

sub checkForPriest {
	my ($args) = @_;
	#print "args is $args \n";
	#print Dumper ($args);
	
	#$args = $players{$args}->{jobID};
	
=pod
	if(defined $config{attackDefender_support}){
		print "attackDefender_support is defined\n";
	} else {
		print "attackDefender_support is not defined\n";
	}
=cut
	#$char->{jobID} eq 4009 for HP
	if($config{"attackDefender_helpHP"} and $args eq 4009)
	{
		return 1;
	}

	return 1 if ($args eq 4 || $args eq 8); # || $args eq 1 is swordsman??
	
	return 0;
}

sub IgnoreMonster
{
	my $ID = shift;
	my $monster = shift;

	message TF("Ignore it!\n"), "teleport" if ($config{attackDefender_Debug});
				
	#if we're rechecking it after already ignoring, then don't add more time
	return if($monster->{ignore} eq 1);
				
	#message "Sending attack stop!\n";
	#$char->sendAttackStop;				
	$monster->{ignore} = 1;
				
	if (!defined $config{attackDefender_killAfterSeconds}){
		$monster->{attack_failed} = time + 2;
		$monster->{'attack_recheck'} = time;
		error "Ignoring the monster for 2 seconds...\n" if ($config{attackDefender_Debug});;
	} else {
		$monster->{attack_failed} = time + $config{attackDefender_killAfterSeconds};
		$monster->{'attack_recheck'} = time;
		error TF("Ignoring the monster for %s seconds...\n", $config{attackDefender_killAfterSeconds}), "attackDefender" if ($config{attackDefender_Debug});
	}
	# Right now, the queue is either
	#   move, route, attack
	# -or-
	#   route, attackbor
	#AI::dequeue;
	#AI::dequeue;
	#AI::dequeue if (AI::action eq "attack");

	AI::dequeue while (AI::inQueue("attack")); # maybe do this isntead?

	$mytimeout->{'healer'} = time+2;
	return;
}

sub monCheck {
    my (undef, $args) = @_;

    return 0 if !$args->{monster} || $args->{monster}->{nameID} eq '';

    if (!defined $monsterDB[int($args->{monster}->{nameID})]) {
        debug("Attack Defender: Monster {$args->{monster}->{name}} not found\n", 'attackDefender', 2);
        return 0;
    }    #return if monster is not in DB

	my $monsterInfo = $monsterDB[(int($args->{monster}->{nameID}) - 1000)];
	my $level = $monsterInfo->[0];

	if ($config{$args->{prefix} . '_lvl'})
	{
		return 0 if (!inRange($level, $config{$args->{prefix} . '_lvl'}));
	}

	#if ($config{$prefix."_sp"}) {
	#	if ($config{$prefix."_sp"} =~ /^(.*)\%$/) {
	#		return 0 if (!inRange($char->sp_percent, $1));
	#	} else {
	#		return 0 if (!inRange($char->{sp}, $config{$prefix."_sp"}));
	#	}
	#}

	return 1;
}

sub overcapped
{
	error("~~~ calc overcapped. delay for 2s ~~~\n");
	$recalc_timeout = time+1.0;
}

my $spam_guard_666 = 0;
sub actor_action
{
	my ($self, $args) = @_;

	# IF...
	#	there is a boss on screen
	#	AND the source a boss (meaning the boss attacked)
	#	AND the target is Arlinn
	#	AND the distance between them is less than the desired amount...
	#	then consider the boss to be TANKED

	# if there is a bossOnScreen and we don't have a storedBossID already
	return unless (defined $flags{"bossOnScreen"}
					and !defined $config{"attackDefender_ignoreBossTanked"}
					and !defined $storedBossID);

	# we're only checking physical attacks, no skills (for now)
	return if $args->{type} eq 1 || $args->{type} eq 2 || $args->{type} eq 3;

	# don't bother unless the actor is a monster
	my $source =  Actor::get($args->{sourceID});
	return unless $source->{'object_type'} eq 5; #OBJECT TYPE: 5 = MONSTER

	#print "check1: attacker is a monster\n";

	#print "nameID ".$args->{nameID}."\n";

	my $monsterInfo = $monsterDB[(int($source->{nameID}) - 1000)];
	return unless defined $monsterInfo; # can't continue if we don't have info on it

	#print "check2: we got monster info\n";

	my $isBoss = 0;
	$isBoss = $monsterInfo->[7]; # make sure the monster is a boss

	# we need to see if the caster was Arlinn
	my $target = Actor::get($args->{targetID});

	#print "check3: it is a boss\n" if $isBoss;

	# the source of the attack is a boss
	if($isBoss and $target and $target->{name} eq "Arlinn Kord")
	{
		#print "check4: it's a boss and it is attacking Arlinn\n";

		my $calcdPos1 = calcPosition($source);
		my $calcdPos2 = calcPosition($target);

		my $dist_to_check = distance($calcdPos1,$calcdPos2);
		# Arlinn IS the caster. Now we need to make sure she's actually BESIDE the Boss
		#if(distance($source->{pos},$target->{pos}) <= BOSS_TANKED_PROXIMITY)
		if($dist_to_check <= BOSS_TANKED_PROXIMITY)
		{
			message "NEW ATTACK DEFENDER TECH\n";
			# Arlinn is close enough... SHE'S GOTTA BE TANKING IT!'
			message TF("attackDefender: Enemy %s is being tanked now! \n", $source->{name}), "attackMon";
			$source->{attack_failed} = undef; #-= 5; # i don't think this works
			$source->{'tank_checked'} = 1; # hopefully this means we never come back here
			$storedBossID = $source->{ID}; # store the boss so we can check again (if we have to)
		}
		else
		{
			message "BOSS IS TOO FAR: $dist_to_check\n";
		}
	}

	return;
	# ~~~~~~~~~~~~~~~ testing stuff below ~~~~~~~~~~~~~~~

	#return unless timeOut($spam_guard_666, 5.0);

	#return unless ($args->{switch} eq "08C8" || $args->{switch} eq "008A");

	#return unless $args->{type} eq 0 || $args->{type} eq;
	return if $args->{type} eq 1 || $args->{type} eq 2 || $args->{type} eq 3;
	print "ACTION PACKET!!!: ";
	print $args->{switch};
	print "\n";

	# do the tanking check here

	#return if $args->{switch} eq "0086"; # no hp in this one. this is a "walk" packet
	#return if $args->{switch} eq "008A"; # no hp in this one
	#return if $args->{switch} eq "08C8"; # no hp in this one
	$spam_guard_666 = time;

	#print Dumper($args);

	# Skill attack effect and damage.
	# 0114 <skill id>.W <src id>.L <dst id>.L <tick>.L <src delay>.L <dst delay>.L <damage>.W <level>.W <div>.W <type>.B (ZC_NOTIFY_SKILL)
	# 01de <skill id>.W <src id>.L <dst id>.L <tick>.L <src delay>.L <dst delay>.L <damage>.L <level>.W <div>.W <type>.B (ZC_NOTIFY_SKILL2)


	# Notifies clients in an area, that an other visible object is walking (ZC_NOTIFY_PLAYERMOVE).
	# 0086 <id>.L <walk data>.6B <walk start time>.L

	# 008a <src ID>.L <dst ID>.L <server tick>.L <src speed>.L <dst speed>.L <damage>.W <div>.W <type>.B <damage2>.W (ZC_NOTIFY_ACT)
	# 02e1 <src ID>.L <dst ID>.L <server tick>.L <src speed>.L <dst speed>.L <damage>.L <div>.W <type>.B <damage2>.L (ZC_NOTIFY_ACT2)
	# 08c8 <src ID>.L <dst ID>.L <server tick>.L <src speed>.L <dst speed>.L <damage>.L <IsSPDamage>.B <div>.W <type>.B <damage2>.L (ZC_NOTIFY_ACT3)

	# type:
	#     0 = damage [ damage: total damage, div: amount of hits, damage2: assassin dual-wield damage ]
	#     1 = pick up item
	#     2 = sit down
	#     3 = stand up
	#     4 = damage (endure)
	#     5 = (splash?)
	#     6 = (skill?)
	#     7 = (repeat damage?)
	#     8 = multi-hit damage
	#     9 = multi-hit damage (endure)
	#     10 = critical hit
	#     11 = lucky dodge
	#     12 = (touch skill?)
	#     13 = multi-hit critical

	#008A
	#$VAR1 = {
	#		  'dual_wield_damage' => 57982,
	#		  'div' => 18320,
	#		  'damage' => 0,
	#		  'dst_speed' => 11471,
	#		  'src_speed' => 422903808,
	#		  'switch' => '008A',
	#		  'RAW_MSG_SIZE' => 29,
	#		  'sourceID' => '|ì▲ ',
	#		  'type' => 2,
	#		  'RAW_MSG' => 'è |ì▲   áXm┬ΓU  5↓╧,    ÉG☻~Γ',
	#		  'KEYS' => [
	#					  'sourceID',
	#					  'targetID',
	#					  'tick',
	#					  'src_speed',
	#					  'dst_speed',
	#					  'damage',
	#					  'div',
	#					  'type',
	#					  'dual_wield_damage'
	#					],
	#		  'targetID' => '  áX',
	#		  'tick' => 'm┬ΓU'
	#		};

	# 08C8 - actor taking damage i think

	if($args->{"targetID"})
	{
		# target stuff
		my $targetActor = Actor::get($args->{"targetID"});
		if($targetActor)
		{
			print "actor type: ".$targetActor->{"actorType"}."\n";
		}
	}

	if($args->{"damage"} > 0)
	{
		#my $actor = GetActorByID($args->{"targetID"});
		my $target = Actor::get($args->{"targetID"});

		if(defined $target and $target->{"actorType"} eq "You" and 1 == 2)
		{
			#print Dumper(\$args);


			# 'dst_speed' 

			print "actor type: ".$target->{"actorType"}."\n";
			print "dmg: ".$args->{"damage"}."\n";
			print "dmg motion: ".$args->{"dst_speed"}."\n"; # this is if the target actually plays damage anim
			print "endure dmg: ".($args->{"type"} eq 4 ? "Yes" : "No")."\n";
			print "devotion status: active\n" if $target->statusActive('EFST_DEVOTION');
			print "devotion status: not active\n" if !$target->statusActive('EFST_DEVOTION');
		}
		# 'targetID' => '├É┬å▲ ',
		# $args->{target}->statusActive('EFST_DEVOTION')
	}

}

1;
