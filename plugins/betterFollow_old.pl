############################ 
# betterFollow plugin for OpenKore by MaterialBlade (2014) 
# 
# This software is open source, licensed under the GNU General Public Liscense
# -------------------------------------------------- 
#
# If betterForward_Target in config.txt is set, the bot will try to work around it
#	v0.1 - Base program
#	v0.2 - Added extra checks for available positions
#
############################ 

############################
# 
# 2025 edit
# if you want to search for all the config settings, search for "bf_"
# i dont remember what they do, this is an old plugin
# have fun digging around and seeing what it does
#
############################ 

####### DONE LIST #######
#	8 - add a block where the bots can ask "where is <party leader>?" if they are on the same map and cannot see them ==DONE
#	9 - add a block for party members to group up in combat ==DONE
#	13 - add a sub to check if the person who sent a party message is on screen - used for setting and clearing bases ==DONE

####### TODO LIST #######
#	1 - Add an idle thing so if set, bot will pick an idle cell to go to
#	2 - Add a random variant to the main::ai_route section. just so all the bots aren't running at the leader?
#	4 - Randomly move along the vector once in a while
#	5 - CHECK IF THE PLACE WE'RE WALKING TO IS INSIDE A PORTAL
#	6 - add a timeout to recalc
#	7 - fix it so that we are not forced to stand constantly
#	10 - fix the bots trying to walk to an occupied cell
#	11 - add a 'boredom' timeout where they will shuffle or attack a nearby enemy when they become bored -> related to idle thing? ^
#	12 - add a sub to check if the cell we want to walk to is occupied. if it is, we need to shuffle our target position
#	14 - add a lastKnownPos for our master so that when we lost them we don't go through the whole 'I lost my master, better stop moving' shit
#	15 - add something to help with MVPing where we can record a position and the bot WILL NOT MOVE from that spot, no matter what.
#		-> something along the lines of "{name} stay here" and it sets their LOCKED position to where the player was
#		-> when they are LOCKED it doesn't process any of the regular shuffle movement BS
#
#	update the retreating code so that the bot keeps a history of where the leader was. retreat towards that position so they don't have to
#	rely on the party leader being on screen. could also consider having them call out for help from off screen too
#
######################

####### CHANGELOG #######
#	v0.1	-	Base code finished, adding new options. Removed $followRisk and added bf_rangeSize for the square to select an offset from
#			-	Changing my stupid way of calcing an offset to using calcRectArea2
#			-	Added a rand for a timeout before moving. Simulate player reaction speed?
#
#	v0.2	-	Added two calcrectarea's for when we can't use the player's position
#			-	Removed bf_risk being used in calculations in favor of more options
#			-	changed the offset position to be calculated with the rect thing too
#			-	added more config options: bf_rangeSize, and bf_reaction to use to calc the offset area and how fast the bot reacts 
#				to movement respectively.
#
#	v0.3	-	Added another area rect and experimented with portal distances
#
#	v0.4	-	Another refactor
#			-	Moved the offset calc to a function so we can call it again if we want to
#			-	Moved the vector push to a function
#			-	Added the bf_healer option for healers, and a block so party members will run to leader when hurt
#
#	v0.5	-	General cleanup and commenting of messages
#
#	v0.6	-	Added Debug option to show messages bf_debug
#			-	Added the option for bf_healer types to run to party leader as well. <-- NOT WORKING
#			-	Added a sub for healers to run to the center of the party when shit goes down
#
#	v0.7	-	Added shuffle for dudes who get bored
#
#
#
######################

#$followIndex = AI::findAction("follow"); #this could be useful

#$char->{party} and $char->{party}{users}{$id}

#my $bodydir = ($char->{look}{body} ) % 8;

#lookAtPosition($players{$args->{'ID'}}{'pos_to'})

# @blocks = calcRectArea2($pos->{x}, $pos->{y}, 4, 0);
			# foreach (@blocks) {
				# next unless (whenGroundStatus($_, "Warp Portal"));
				#We must certify that our master was walking towards that portal.
				# getVector(\%vec, $_, $oldPos);
				# next unless (checkMovementDirection($oldPos, \%vec, $_, 15));
				# $found = $_;
				# last;
			# }
			
		#positionNearPortal($pos, $portalDist)

package betterFollow;

use strict;
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

Plugins::register('betterFollow', 'more realistic follow options', \&onUnload); 
my $hooks = Plugins::addHooks(
	['ai_follow', \&mainProcess, undef], 
	["AI_pre", \&prelims, undef],
	['AI_post',       \&ai_post, undef],
	["packet_pre/party_chat", \&partyMsg, undef]
);

message "betterFollow success\n", "success";

my $better_move_timeout = time; #we don't use $args->{move_timeout}, we have to make our own
my $better_recalc_timeout = time; #this is the timeout for recalcing a new position. gives it just a tiny bit more realism
my $better_routefix_timeout = time; #clear the ai when we get stuck during route with no args
my $better_reaction_timeout = time; #rando check for when we should start moving when our target does
my $better_loot_timeout = time; #little buffer for when to cancel items taking while we're still in combat

my $mytimeout; #new container for all timeouts
my $bf_args; #container for variables and shit
my %bf_hash; #container for hashes and shit
my $break_multiplier = 0.75;

my $last_dir;
my $direction;

my $dir_check = 35;
my $max_break = 2+(rand 2);

$mytimeout->{'search_for_leader'} = $mytimeout->{'shuffle_move'} = $mytimeout->{'wander_move'} = time + 10;

my $boredom_dist = 0;

my %new_pos = ();
my %saved_offset = ();
my %offset = ();

my $setup = 0;

my $storedFollow;

sub onLoad {
	if($config{bf_baseX}){
		$bf_args->{'base'} = $config{bf_baseMap}; #$field->baseName
		$bf_hash{'base_pos'}{'x'} = $config{bf_baseX};
		$bf_hash{'base_pos'}{'y'} = $config{bf_baseY};
	}
}

onLoad();

sub onUnload {
    Plugins::delHooks($hooks);
}

sub onReload {
    &onUnload;
}

sub prelims {
	my (undef,$args) = @_;
	
	#print Dumper(\$args);
	
	if (AI::action eq "attack") {
		$args->{move_timeout} = time+2;

		# this basically negates better follow while we're attacking which is maybe not what we want, necessarily
		if(exists $new_pos{x}){
			my $garbage = calcPosition($char);
			$new_pos{'x'} = $garbage->{x};
			$new_pos{'y'} = $garbage->{y};
		}
		
		$break_multiplier = 0.75;
		$mytimeout->{'break_wait'} = time;
		$mytimeout->{'sit_wait'} = time;

	}

	#message "devo: got this far 1\n";
	my $devoMinAggressives = defined $config{bf_devotionMinAggressives} ? $config{bf_devotionMinAggressives} : 3;
	my $devoMinHP = defined $config{bf_devotionMinHP} ? $config{bf_devotionMinHP} : 15; #15% max HP
	my $selfAggressives = scalar(ai_getAggressives());
	my $partyAggressives = scalar(ai_getAggressives(1,1));

	# need to move the aggressives and HP stuff up here, otherwise there is no point
	#if(defined $config{'bf_devotionSource'} and (AI::is(qw(attack skill_use)) || scalar(ai_getAggressives())>3) and timeOut($mytimeout->{'devotion_shuffle'}))
	if(defined $config{'bf_devotionSource'} and
	((percent_hp($char) <= $devoMinHP and $selfAggressives>0) || $partyAggressives>$devoMinAggressives)
	and timeOut($mytimeout->{'devotion_shuffle'},1.0))
	{
		message "devo: got this far 2, aggressives is $selfAggressives\n";

		# let's put the timeout at the top
		$mytimeout->{'devotion_shuffle'} = time;

		message "devo: got this far 3\n";

		# check if we need to move closer to our source of Devotion
		foreach (@playersID) {
			next if (!$_); # next if theyre not valid for some reason
			next unless ($char->{party} and $char->{party}{users}{$players{$_}{ID}}); #next if theyre not in our party

			my $devoSource = $playersList->getByID($_); # this returns an Actor::Player

			next unless $devoSource->{name} eq $config{'bf_devotionSource'};

			my $devoMinDistance = defined $config{bf_devotionChase} ? $config{bf_devotionChase} : 5;

			my $devoPosition = calcPosition($devoSource);
			my $myPos = calcPosition($char);

			my $devoDist = distance($myPos, $devoPosition);

			# prelim checks
			if(!$devoSource->{dead} and $devoDist > $devoMinDistance) #scalar(ai_getAggressives())>$devoMinAggressives
			{
				message TF("Devo Check: We're far away from devo source, we need to move closer.\n"), "teleport";
				message TF("Devo Check: Current dist is $devoDist, minimum $devoMinDistance.\n"), "teleport";
				#my $MAX_CHECK = 3;
				# the code below checks every spot around the target, so... don't need a max checks yet?

				my @stand = calcRectArea2($devoPosition->{x}, $devoPosition->{y},$devoMinDistance-1,0);
				my $exitflag = 0;
			
				while(!$exitflag){
					if(scalar(@stand)==0){
						$exitflag=1;
						return;
					}
			
					my $i = int(rand @stand);
					my $spot = $stand[$i];
				
					if(!$field->isWalkable($spot->{x}, $spot->{y}) || positionNearPortal($spot, 4) ) {
						splice(@stand,$i,1);
					} else {
							$new_pos{'x'} = $spot->{x};
							$new_pos{'y'} = $spot->{y};
							$exitflag=1;
					}

					if($exitflag){
						message TF("!!!!!!!!!! Running to $devoSource for devotion !!!!!!!!!!\n"), "teleport";
						#FIXME: this isn't running to the leader, this is running to our follow target which maye or not be the party leader
				
						if(timeOut($mytimeout->{'devotion_bark'},4)){ # this "wuss out" thing is only for the character shouting
							my @words = ('grouping for devo','grouping','moving for devotion');
							sendMessage($messageSender, "p", $words[rand @words]);
							$mytimeout->{'devotion_bark'} = time;#+6;
						}

						$mytimeout->{'devotion_shuffle'} = time+1;#+3;
						ai_route($field->baseName, $new_pos{'x'}, $new_pos{'y'}, attackOnRoute => 0);
					}
				}
			}
			#last;
		}
	}

	# i could potentially override the routing code here...
	
	if (AI::action eq "follow") {

		# this block should only be used by Acolyte classes
		if($config{bf_healer} and timeOut($mytimeout->{'healer'},0.35)){
				#add in a check to see if we're being attacked and sitting?
				if(ai_getAggressives() and $char->{sitting}){
					stand();
				}
		
				#if we are a healer class, kinda shift our position around to heal people

				# NOTES

				# All members in $char->{party}{users} are of the Actor::Party class.


				# NOTES

				foreach (@playersID) {
					next if (!$_);
					next unless ($char->{party} and $char->{party}{users}{$players{$_}{ID}});
					
					# added for the party center check below
					#push @partyList, $char->{ID};
					my $target = $char->{party}{users}{$playersList->getByID($_)->{ID}}; #this is an Actor:Party, which we apparently can't use to calc positions

					#my $player = Actor::get($ID);
					#my $targetActorMaybe = Actor::get($playersList->getByID($_)); # this is an Actor::Unknown for some reason
					my $targetActorMaybe = $playersList->getByID($_); # this returns an Actor::Player. Seems I don't need to do the 'get'
					my $targetHpPercent = percent_hp($target);

					#message TF("Target:%s ID:%s Timeout:%s \n",$target->{name},$target->{ID},timeOut($mytimeout->{'heal_player'}{$target})), "success";

										# check every condition in the if statement from below for a pass
					if($config{bf_debug}){
						#percent_hp($char->{party}{users}{$id})
						#my $hpPercent = percent_hp($char->{party}{users}{$target->{ID}});
						
						if($targetHpPercent<=$config{bf_healer_range} and $targetHpPercent ne 0)# and $targetHpPercent ne undef)
						{
							#message TF("Attempting to check HP percent for $target->{ID}\n"), "teleport";

							#$mytimeout->{'healer'} = time+10;
						}
						else
						{
							#message TF("Attempting to check HP percent for $target->{ID} and percent is not 0\n"), "teleport";
							#$mytimeout->{'healer'} = time+10;
						}
					}



					if($targetHpPercent ne undef
					and $targetHpPercent<=$config{bf_healer_range}
					and timeOut($mytimeout->{'heal_player'}{$target})
					and !$target->{dead}
					and $targetHpPercent ne 0
					#and $char->{party}{users}{$target->{ID}}{hp} ne undef
					#and distance(calcPosition($char), calcPosition($players{$target->{ID}})) > 4
					#and distance(calcPosition($char), calcPosition($players{$target->{ID}})) < 20
					){
						message TF("Party Member:%s HP:%s\n",$target->{name},
						$char->{party}{users}{$target->{ID}}{hp}
						), "success";

						#$players{$args->{ID}}
						my $tempID = $target->{ID};
						my $monster = Actor::get($tempID);
						my $realTargPos = calcPosition($targetActorMaybe);#calcPosition($players{$target}); #calcPosition($char);#calcPosition($players{$tempID});
						my $mymymyPos = calcPosition($playersList->getByID($_));

						#my $target = $char->{party}{users}{$playersList->getByID($_)->{ID}};

						#my $realTargPos = calcPosition($target);

						if($realTargPos eq undef)
						{
							message "realTargPos is undefined\n";
						}
						else
						{
							message "realTargPos is not undefined, it is $realTargPos\n";
						}

						# TODO: this section could be optimized. rather than waiting for the timeout to check for a new location
						# there should be a loop and a MAX ATTEMPTS or something. Try to find 3 or 4 different cells to move to, THEN give up

						my @stand = calcRectArea2($realTargPos->{x}, $realTargPos->{y},2,0);
						my $i = int(rand @stand);
						my $spot = $stand[$i];

						#my $ID = AI::args->{ID};

						#print Dumper($targetActorMaybe);
						#print Dumper($char->{party}{users});
						#print Dumper($mymymyPos);
						#print Dumper($ID);
						#print Dumper($tempID);
						#print Dumper($monster);

						#print Dumper($target->position());
						#print Dumper($realTargPos);
						print Dumper(\$spot);
						#print Dumper(\$spot);
						$new_pos{'x'} = $spot->{x};
						$new_pos{'y'} = $spot->{y};

						if(!$field->isWalkable($spot->{x}, $spot->{y}))
						{
							message TF("Can't reach $spot->{x}, $spot->{y}!\n"), "teleport";
						}

						my $failSafe = 1;
						if($failSafe ne undef)
						{
							# check that the target can be seen from the new position, otherwise return
							if(!checkLineWalkable($spot, $realTargPos)){
								message TF("Can't reach %s from new spot, trying again!\n",$target->{name}), "teleport";
								$mytimeout->{'heal_player'}{$target} = time+0.2;
							}
							else
							{
								ai_route($field->baseName, $new_pos{'x'}, $new_pos{'y'}, attackOnRoute => 0);

								my @shortName = split(/ /,$target->{name});

								message TF("!!!!!!!!!! Moving to heal !!!!!!!!!!\n"), "teleport";
								sendMessage($messageSender, "p", "I'm healing $shortName[0]");
								stand();
								$mytimeout->{'healer'} = time+2;
								$mytimeout->{'heal_player'}{$target} = time+4;
								$mytimeout->{'break_wait'} = time;
								$mytimeout->{'sit_wait'} = time;
								$better_recalc_timeout = time+3;
							}
						
						}

						return;
					}
				}
			hideInParty();
		}
	}
}

sub mainProcess {
	return 1 if !($config{betterFollow}); #return if the variable is not set :p
	
	my (undef,$args) = @_;
	my (%vec, %pos);
	
	#debug "AI::action = ".AI::action."\n";
	
	$better_loot_timeout = time if(!AI::findAction("items_take"));
	
	#
	# If out HP drops below 40% and there are more than 3 aggressives we will run to our party leader for help
	#
	
	
	if((AI::action eq "attack")){ # added the option for bf_healers to run away as well (hopefully)  || AI:action eq "follow" and $config{bf_healer}
		#get the center of the party if we need to use it?
		my %temp_pos = getInsideParty();
		my $temp_pos2;
		$temp_pos2->{'x'} = $temp_pos{x};
		$temp_pos2->{'y'} = $temp_pos{y};

		my $dist_to_follow_target = distance(calcPosition($char), calcPosition($players{$args->{ID}}));
		my $dist_to_temppos2 = distance(calcPosition($char), $temp_pos2);
		
		if((percent_hp($char)<=40 ||  scalar(ai_getAggressives())>3)
		and $dist_to_follow_target > 5.5
		and $dist_to_follow_target < 20
		and timeOut($better_recalc_timeout,0.65)){
			$better_recalc_timeout = time;
			
			my $ID = $args->{ID};
			my $player = $players{$ID}; # Get the follow target info.			
			my $realFollowPos = calcPosition($player);
		
			my @stand = calcRectArea2($realFollowPos->{x}, $realFollowPos->{y},3,0);
			my $exitflag = 0;
			
			while(!$exitflag){
				if(scalar(@stand)==0){
					$exitflag=1;
					return;
				}
			
				my $i = int(rand @stand);
				my $spot = $stand[$i];
				
				if(!$field->isWalkable($spot->{x}, $spot->{y}) || positionNearPortal($spot, 4) ) {
					splice(@stand,$i,1);
				} else {
						$new_pos{'x'} = $spot->{x};
						$new_pos{'y'} = $spot->{y};
						$exitflag=1;
				}
			}
			if($exitflag){
				message TF("!!!!!!!!!! Running to $player !!!!!!!!!!\n"), "teleport";
				#FIXME: this isn't running to the leader, this is running to our follow target which may or not be the party leader
				#FIXME: not sure if that's what i want, or if it would be better to store some kind of "safe location" for members to run to
				
				if(timeOut($mytimeout->{'wuss_out'})){ # this "wuss out" thing is only for the character shouting
					my @words = ('help','i need help','save me!!','help me','HELP', 'retreat!', 'retreating!!', 'AAAHHHH!!!');
					sendMessage($messageSender, "p", $words[rand @words]);
					$mytimeout->{'wuss_out'} = time+4;
				}
				ai_route($field->baseName, $new_pos{'x'}, $new_pos{'y'}, attackOnRoute => 0);
			}
		}
#=pod		
		elsif ((percent_hp($char)<=40 ||  scalar(ai_getAggressives())>3)
		and $dist_to_temppos2 > 4
		and $dist_to_temppos2 < 20
		and timeOut($better_recalc_timeout,0.35)){
			message TF("!!!!!!!!!! Running to party !!!!!!!!!!\n"), "teleport";
				
			if(timeOut($mytimeout->{'wuss_out'})){ # this "wuss out" thing is only for the character shouting
				my @words = ('help','i need help','save me!!','help me','HELP');
				sendMessage($messageSender, "p", $words[rand @words]);
				$mytimeout->{'wuss_out'} = time+4;
			}
			ai_route($field->baseName, $new_pos{'x'}, $new_pos{'y'}, attackOnRoute => 0);
		}
#=cut
	}
	
	#
	# Take items when we can, but if the party engages in combat or the leader moves too far stop picking
	#

	
	if(AI::action eq "items_take" || AI::action eq "take"){
		#message "got to items_take";
		my $ID = $args->{ID};
		my $player = $players{$ID}; # Get the follow target info.
		
		#message TF("!!!!!!!!!! Trying to take items !!!!!!!!!!\n"), "teleport";
		#print "Player: " . $player . "\n";
		
		my $garbage = calcPosition($char);
			$new_pos{'x'} = $garbage->{x};
			$new_pos{'y'} = $garbage->{y};
		
		my $attackIndex = AI::findAction("attack");
	
		my $dist = distance($char->{pos_to}, $player->{pos_to});	
		

		if(($dist > $config{bf_distanceItems} || ai_getAggressives(1, 1)) and !defined $player){
			#remove the items whatever thing
			message TF("!!!!!!!!!! Remove items take thing !!!!!!!!!!\n"), "teleport";
			AI::clear("items_take");
		}
	}
	
	if(AI::action eq "route"){
		if(timeOut($better_recalc_timeout,0.35)){
			$better_recalc_timeout = time;
		}
	}

	#timeOut($mytimeout->{'search_for_leader'},0.25)

	# this isn't working. i dont think i can do what i want with a plugin. at least, not the current approach
	if(defined $bf_args->{'stop'})
	{
		if(AI::is(qw(route mapRoute)))
		{

			if(defined $bf_args->{stop}){


				if (distance(calcPosition($char), $bf_hash{'stop_pos'}) > 2) #and timeOut($mytimeout->{'base_distance_check'},1.2))
				{
					AI::clear(qw/move route/);
					message TF("Too far away from base \n"), "follow";
					$mytimeout->{'base_distance_check'} = time;
					if($field->baseName eq $bf_args->{base}){
					ai_route($field->baseName, $bf_hash{'stop_pos'}{'x'}, $bf_hash{'stop_pos'}{'y'},
							maxRouteTime => 20,
							attackOnRoute => 0,);
					} else {
						#sendMessage($messageSender, "p", "my base is on a different map");
						#ai_route($bf_args->{base});
						$mytimeout->{'base_distance_check'} = time+20;
					}
				}
		}

			if(timeOut($mytimeout->{'debug_bs'},1.0))
			{
				message "yahallo #0 \n";
				$mytimeout->{'debug_bs'} = time;
			}

			return 1;
		}
	}

=pod
	if((AI::action eq "route" && AI::action(1) eq "follow")){
		if(defined $bf_args->{'stop'})
		{
			return 1;
		}

		if(timeOut($mytimeout->{'debug_bs'},1.0))
		{
			message "yahallo #1 \n";
			$mytimeout->{'debug_bs'} = time;
		}
	}
	elsif((AI::action eq "move" && AI::action(1) eq "follow"))
	{
		if(defined $bf_args->{'stop'})
		{
			if(exists $ai_v{master})
			{
				$ai_v{master}{time} = time+(2*60);
			}
			AI::clear(qw/move route/);
			return 1;
		}

		if(timeOut($mytimeout->{'debug_bs'},1.0))
		{
			message "yahallo #2 \n";
			$mytimeout->{'debug_bs'} = time;
		}
	}
=cut
	
	if (AI::action eq "follow") {
		#debug "Follow header\n";
		
		
		my $ID = $args->{ID};
		my $player = $players{$ID}; # Get the follow target info.
		
		my $field = $::field;
		
		my $realMyPos = calcPosition($char);
		my $realFollowPos = calcPosition($player);
		
		#message "yahallo \n";
		
		if (!defined $args->{ID} and timeOut($mytimeout->{'search_for_leader'},0.25)){
			#message "args id isn't a thing\n" ;
			shuffleMoves() if$config{bf_shuffle};
			#message "after args shuffle";
		}
		
		#============= SEARCHING FOR LEADER =============#
		if($config{follow} and !defined $args->{ID} and timeOut($mytimeout->{'search_for_leader'},0.25)){
			#check to see if our target is online
			#keys %{$char->{party}{users}};
			#while (my ($ID, $playerZ) = each %{$char->{party}{users}}) {
			#	$player  = $players{$playerZ->{ID}} if $playerZ->{name} eq $config{followTarget};
			#}
			
			$player = $char->master();
			if(defined $player){
				$bf_args->{'lastKnownPos'}{'x'} = $player->{pos_to}{x};
				$bf_args->{'lastKnownPos'}{'y'} = $player->{pos_to}{y};
			} else {
				#undef $bf_args->{'lastKnownPos'};
			}
			
			for (my $i = 0; $i < @partyUsersID; $i++) {
				next if ($partyUsersID[$i] eq "");

				if ($partyUsersID[$i] eq $player->{ID}) {
					# Translation Comment: Is the party user on list online?
					($player->{field}{name}) = $char->{'party'}{'users'}{$partyUsersID[$i]}{'map'} =~ /([\s\S]*)\.gat/;
				}
			}
			
			message "our target is online at least\n" if (defined $player and $char->{party}{users}{$player->{ID}}{online});
			message TF("Target field: %s  My field: %s\n",$player->{field}{name},$field->{name}, $char->{party}{users}{$player->{ID}}{online}), "teleport" if (defined $player and $char->{party}{users}{$player->{ID}}{online});
			
			if($player->{field}{name} eq $field->{name} and defined $player and $char->{party}{users}{$player->{ID}}{online}){
				#message TF("Follow target's position is x:%s body y:%s head:%s\n",$realFollowPos->{x},$realFollowPos->{y}), "success";
				message "we are on the same map as our follow target\n";
				
				sendMessage($messageSender, "p", "Can anyone see $player->{name}?");
				$bf_args->{'search_for_follow'} = 1;

				#message TF("Target field: %s  My field: %s\n",$player->{field},$field), "teleport";
			}


			
			$mytimeout->{'search_for_leader'} = time + 10 + rand(10);
		}
		elsif(defined $args->{ID} and $args->{'ai_follow_lost_end'} and !($args->{'following'}) and !($args->{'ai_follow_lost_char_last_pos'}) and timeOut($mytimeout->{'search_for_leader'},0.25))
		{
			$player = $char->master();
			
			my $online_members;
			
			for (my $i = 0; $i < @partyUsersID; $i++) {
				next if ($partyUsersID[$i] eq "");
				
				$online_members++ if $char->{party}{users}{$partyUsersID[$i]}{online};
				
				if ($partyUsersID[$i] eq $player->{ID}) {
					# Translation Comment: Is the party user on list online?
					($player->{field}{name}) = $char->{'party'}{'users'}{$partyUsersID[$i]}{'map'} =~ /([\s\S]*)\.gat/;
				}
			}
			
			message "our target is online at least\n" if (defined $player and $char->{party}{users}{$player->{ID}}{online});
			message TF("Target field: %s  My field: %s\n",$player->{field}{name},$field->{name}, $char->{party}{users}{$player->{ID}}{online}), "teleport";
			
			if($player->{field}{name} eq $field->{name} and defined $player and $char->{party}{users}{$player->{ID}}{online} and $online_members > 2){
				#message TF("Follow target's position is x:%s body y:%s head:%s\n",$realFollowPos->{x},$realFollowPos->{y}), "success";
				message "we are on the same map as our follow target\n";
				
				sendMessage($messageSender, "p", "Can anyone see $player->{name}?");
				$bf_args->{'search_for_follow'} = 1;

				#message TF("Target field: %s  My field: %s\n",$player->{field},$field), "teleport";
			}
			
			$mytimeout->{'search_for_leader'} = time + 10 + rand(10);
		}
		#============= END SEARCHING FOR LEADER =============#
		
		#do the initial setup
		if($setup ne 1){
			%offset = getOffset($ID);
		}

		my $dist = distance($char->{pos_to}, $player->{pos_to}); # Get the distance between me and my target.

		if($config{bf_debug})
		{
			#message TF("Initial Step: dist calc is $dist\n"), "teleport";
		}

		if(defined $bf_args->{'stop'})
		{
			return 1;
		}

		# what does this do, again?
		#if we want to check LOS and we can't walk to our current target, pick a random cell around the target and try to move to that
		if(($config{followCheckLOS} and !checkLineWalkable($realMyPos, $player->{pos_to}))){
			delete $ai_v{sitAuto_forcedBySitCommand} if(!$char->{sitting} and $ai_v{'sitAuto_forcedBySitCommand'});

			print "We are at the first main::ai_route thing.\n";
			
			if(timeOut($better_move_timeout, 0.35)){
				$better_move_timeout = time;
				
				print "We're in the if statement\n";
				
				my @stand = calcRectArea2($realFollowPos->{x}, $realFollowPos->{y},5,1);

				# there is no fall back for if none of the cells around the follow target can't be walked to. unlikely, but it IS possible
				SPOT1: for my $spot (@stand) {

					#Is this spot acceptable? It must be walkable and that's it, really
					if ($field->isWalkable($spot->{x}, $spot->{y}) and checkLineWalkable($realMyPos, $spot)){

						# add another check to see if we can walk directly from our desired location to our follow Target
						# there needs to be some kind of way to make sure we're not getting stuck behind walls and whatnot

						#check if anyone is standing on this cell
						foreach my $player (@{$playersList->getItems()}) {
							next SPOT1 if($player->{pos_to} eq $spot);
						}
					
						#we can walk to this spot, set it as our new destination
						if(exists $new_pos{x}){
							$new_pos{x} = $spot->{x};
							$new_pos{y} = $spot->{y};
							

							$char->sendMove(@new_pos{qw(x y)});
							$mytimeout->{'break_wait'} = time;
							$mytimeout->{'sit_wait'} = time;
							last SPOT1;
						}
					}
				}	
			}
		} else {
			if(!defined $player and defined $bf_args->{'lastKnownPos'}){
				#print "fuck let's move!!!\n";
				message TF("New direction real:%s body:%s head:%s\n"), "success";
				ai_route($field->baseName, $bf_args->{'lastKnownPos'}{'x'}, $bf_args->{'lastKnownPos'}{'y'}, attackOnRoute => 0);
			}
		
			return 1 if($dist > 20 and $player ne "");
			

			#Otherwise, make sure the main time can't do anything
			# That is to say, we "replace" the regular following function by setting the timeout really high so it never gets a chance to do anything
			$args->{move_timeout} = time+(2*60);
			
			#debug "Made it past the distance check\n";

			# better movement is processed every 0.35s (allegedly)
			if(timeOut($better_move_timeout, 0.35)){
				#print "We're in the else statement\n";
				
				$better_move_timeout = time;
				$better_routefix_timeout = time;
				
				#I honestly don't know what these are for but I keep putting them in :u
				$timeout{ai_sit_idle}{time} = time;
				
				#check to see if we haven't been in combat for 10 seconds
				if(ai_getAggressives(1, 1)){
					$mytimeout->{'combat_wait'} = time+10; #well fuck me... i guess this DOES work

					# this is never used???
				}
				
				#check if we're standing in the same spot
				if($new_pos{x} eq $realMyPos->{x} and $new_pos{y} eq $realMyPos->{y} and timeOut($mytimeout->{'break_wait'},3.15) and timeOut($mytimeout->{'combat_wait'},0.2))
				{
					$mytimeout->{'break_wait'} = time;
					$mytimeout->{'move_break'} = time+($break_multiplier);
					$break_multiplier = ($break_multiplier*$config{bf_reaction}>$max_break) ? $max_break : $break_multiplier*$config{bf_reaction};
					#message TF("Increasing break_multiplier to $break_multiplier\n",$mytimeout->{'move_break'}), "follow" if ($break_multiplier < $max_break);
					my $bodydir = ($char->{look}{body} ) % 8;
					if (timeOut($mytimeout->{'sit_wait'},1+rand(1)) and $config{bf_sitAuto} and !$char->{sitting} and rand(100) < ($break_multiplier*(15*$break_multiplier))){
						sit();
						$direction->{'body'} = $bodydir;
						if($bodydir eq 1 || $bodydir eq 0 || $bodydir eq 7){
							#$bodydir = 3 + int(rand(3));
							$direction = new_look($bodydir);
							$mytimeout->{'turn_break'} = time+(rand(3));
						}
					}
					
					if(timeOut($mytimeout->{'turn_break'},0) and $char->{sitting} and (($char->{look}{body} ) % 8) ne $direction->{'body'}and $config{bf_sitAuto} and $config{bf_turnAuto}){
						Misc::look($direction->{'body'},$direction->{'head'});
						message TF("New direction real:%s body:%s head:%s\n",(($char->{look}{body} ) % 8),$direction->{'body'},$direction->{'head'}), "success";
					}
				}
				
				my $checkmove = 0;
				my $moving = 0;
				#we are moving
				if(distance($realMyPos, $char->{pos_to}) >= 1.5 and !$char->{sitting}) { #little breathing room for errors
					$checkmove = 1;
					$moving = 1;
					message TF("We are moving\n"), "follow";
				} elsif ($dist > $config{bf_distanceMin} and !$char->{sitting}){
					$checkmove = 1;
					message TF("Target too far away\n"), "follow";
				} elsif ($dist > ($config{bf_distanceMin}+2) and $char->{sitting}){
					$checkmove = 1;
					message TF("Target too far, stand up\n"), "follow";
					stand();
				}
				
				
				if($checkmove and timeOut($better_recalc_timeout,0.35) and !$char->{sitting})
				{				
					# Our target is beyond the minimum distance, we need to recalculate our new move position
									
					#message TF("Got here\n"), "success";
					if(!timeOut($mytimeout->{'move_break'},0.1)){
							message TF("Waiting for move_break\n"), "follow";
							$break_multiplier = 0.75;
							$mytimeout->{'break_wait'} = time;
							$mytimeout->{'sit_wait'} = time;
							return;
					}
					
					#If the direction we are moving has changed, we need to get a new offset and rotate it
					if(int(rand(100)) < $dir_check){
						if($last_dir ne calcRotation($ID)){
							my %sendArgs = ();
						
							$sendArgs{'rot'} = calcRotation($ID);
							$sendArgs{'x'} = $saved_offset{x};
							$sendArgs{'y'} = $saved_offset{y};

							#rotate it
							my %result = testRotation(%sendArgs);

							#set the offset
							$offset{'x'} = $result{x};
							$offset{'y'} = $result{y};
						}
						
						#reset direction check
						$dir_check = 35; # FIXME: 35 is the CHANCE to check for a new direction. This seems like a bad way to handle this
					} else {
						$dir_check *= 1.56;
					}

					#=== BELOW IS THE REAL MEAT OF THE CODE. THIS IS WHERE WE ACTUALLY SET WHERE WE WANT TO WALK ===#
					
					#added a check to make sure its walkable before setting it
					if ($new_pos{x} eq $realMyPos->{x} and $new_pos{y} eq $realMyPos->{y} and $dist <= $config{bf_distanceMin} and $moving)
					{
						print "case 1\n";	

						$new_pos{x} = $realFollowPos->{x} + $offset{x};
						$new_pos{y} = $realFollowPos->{y} + $offset{y};						
					} elsif($field->isWalkable($player->{pos_to}{x} + $offset{x}, $player->{pos_to}{x} + $offset{y}))
					{
						print "case 2\n";
						
						$new_pos{x} = $player->{pos_to}{x} + $offset{x};
						$new_pos{y} = $player->{pos_to}{y} + $offset{y};
						# FIXME: this block just checks if the cell is walkable, not if we can actually walk to it.
						# FIXME: this also doesn't check if someone is already on the cell

						# NOTE: this is where our target move position is being updated most of the time
						#	what is also relevant is that this is in the CHECKMOVE block.
						
					} else {
						print "case 3\n";
						$new_pos{x} = $realFollowPos->{x} + $offset{x};
						$new_pos{y} = $realFollowPos->{y} + $offset{y};
					}
					
					$better_move_timeout = time;
					
					#Update $last_dir, which is the direction we are currently facing
					$last_dir = calcRotation($ID);
				}
				
				#put the shuffle in here
				if(!$moving and !$checkmove and timeOut($better_recalc_timeout,0.35)){
					shuffleMoves();
					#message "Shuffle move from here";
				}

				#this is here for strict refs whatever bullshit
				my $pos2;
				
				if(!defined $new_pos{'x'}){
					# the majority of the time we NEVER hit this. that means that unless the $moving code above triggers, we never need to move
					print "936: check 1\n";
					$pos2->{'x'} = $new_pos{'x'} = $realMyPos->{x} + $offset{x};
					$pos2->{'y'} = $new_pos{'y'} = $realMyPos->{y} + $offset{y};
				} else {
					#print "940: check 2\n";
					print "940: new_pos{x}:$new_pos{x}\n";
					$pos2->{'x'} = $new_pos{x};
					$pos2->{'y'} = $new_pos{y};
				}
								
				#move to saved position
				if(checkLineWalkable($realMyPos, $pos2)==1 and ((($realFollowPos->{x}) != ($pos2->{x})) || (($realFollowPos->{y}) != ($pos2->{y}))) and ((($realMyPos->{x}) != ($pos2->{x})) || (($realMyPos->{y}) != ($pos2->{y}))))
				{
					print "Made it to saved position moving\n";
					#message TF("A\n"), "success";
					
					#check if the location we want to go to is walkable
					my $walkable = $::field->isWalkable($pos2->{x}, $pos2->{y}) ? "Yes" : "No"; #this is never used
					
					return if !$::field->isWalkable($pos2->{x}, $pos2->{y});										
					
					return if ($config{followSitAuto} and $player->{sitting} == 1);

					my $finalCheck = 1;#checkLineWalkable($pos2, $realFollowPos); #FIXME: this didn't work :[

					#check if we're more than 10 distance away. ragnarok doesnt like move commands that are far i guess?
					if($dist < 8){
						#FIXME: this dist check is our current move_to position vs our targets move_to position
						# this isn't checking our CURRENT position and our move_to position, which would probably be more accurate
						stand() if ($char->{sitting});
						
						#move along vector

						# Make sure that we can walk directly to our follow target from our desired position
						# or barring that, do a check to see if we can get a route time
						if($finalCheck eq 1)
						{
							$char->sendMove(@new_pos{qw(x y)}); # if ($result eq 1)
						}
						else
						{
							#if we can't we need to route to our follow target (i think)
							message TF("Trying to correct follow position\n"), "teleport";
							$new_pos{x} = $realFollowPos->{x};
							$new_pos{y} = $realFollowPos->{y};
							ai_route($field->baseName, $realFollowPos->{x}, $realFollowPos->{y}, attackOnRoute => 0)
						}
						
						$mytimeout->{'break_wait'} = time;
						$mytimeout->{'sit_wait'} = time;
					} else {
						if($config{bf_debug}){
							message TF("Too far away to send move command, pushing current vector instead\n"), "teleport";
						}
						#trying out new sub
						$pos2->{'x'} = $new_pos{x};
						$pos2->{'y'} = $new_pos{y};
						my %pos = pushVector($pos2,$char->{pos_to},$dist - $config{bf_distanceMin});
						
						$pos2->{'x'} = $pos{x};
						$pos2->{'y'} = $pos{y};

						if($finalCheck eq 1)
						{
							if(checkLineWalkable($realMyPos, $pos2)){
								if($config{bf_debug}){
									message TF("Pushed vector is line walkable\n"), "teleport";
								}
								stand() if ($char->{sitting});
								$char->sendMove(@pos{qw(x y)});
							} else {
								if($config{bf_debug}){
									message TF("Trying to route to pushed vector...\n"), "teleport";
								}
								my @stand = calcRectArea2($realFollowPos->{x}, $realFollowPos->{y},2,0);
								my $exitflag = 0;

								while(!$exitflag){
									if(scalar(@stand)==0){
										$exitflag=1;
										return; #guess we just return out if we can't find a position to move to? Wonder how often this happens...
									}

									my $i = int(rand @stand);
									my $spot = $stand[$i];

										if(!$field->isWalkable($spot->{x}, $spot->{y}) || positionNearPortal($spot, 4) ) {
											splice(@stand,$i,1);
										} else {
											$new_pos{'x'} = $spot->{x};
											$new_pos{'y'} = $spot->{y};
											$exitflag=1;
										}
									}
									if($config{bf_debug}){
										message TF("Using route instead\n"), "teleport";
									}
								ai_route($field->baseName, $new_pos{'x'}, $new_pos{'y'}, attackOnRoute => 0) if($exitflag);
							}
						}
						else
						{
							#if we can't we need to route to our follow target (i think)
							message TF("Trying to correct follow position\n"), "teleport";
							$new_pos{x} = $realFollowPos->{x};
							$new_pos{y} = $realFollowPos->{y};
							ai_route($field->baseName, $realFollowPos->{x}, $realFollowPos->{y}, attackOnRoute => 0)
						}
						
						$mytimeout->{'break_wait'} = time;
						$mytimeout->{'sit_wait'} = time;
						return;
					}
				}
				elsif(checkLineWalkable($realMyPos, $pos2)==0 and $field->isWalkable($realFollowPos->{x}, $realFollowPos->{y}))
				{
					print "Made it to the elsif function\n";
					my @stand = calcRectArea2($realFollowPos->{x}, $realFollowPos->{y},3,0);
					my $exitflag = 0;
					
					while(!$exitflag){
						if(scalar(@stand)==0){
							$exitflag=1;
							return;
						}
					
						my $i = int(rand @stand);
						my $spot = $stand[$i];
						
						if(!$field->isWalkable($spot->{x}, $spot->{y}) || positionNearPortal($spot, 4) ) {
							splice(@stand,$i,1);
						} else {
								$new_pos{'x'} = $spot->{x};
								$new_pos{'y'} = $spot->{y};
								$exitflag=1;
						}
					}
					stand() if ($char->{sitting});
					#if the distance is too far, and we can't move, we have to route it instead
					if($dist < 8){
						$char->sendMove(@new_pos{qw(x y)});	
					} else {
						ai_route($field->baseName, $new_pos{'x'}, $new_pos{'y'}, attackOnRoute => 0);
					}
					
					$mytimeout->{'break_wait'} = time;		
					$mytimeout->{'sit_wait'} = time;					
				}
				else
				{
					#message TF("C\n"), "success";
					#print "1086\n";
				}
			}
			
			#putting shuffle move at the bottom to see what happens
			#shuffleMoves();
		
		}
	}
	
	return 1;
}

=pod
sub checkCellAvailable {
	# get sent a position
	my $args = shift;
	my $occupied = 0;
	
	# check if there is someone on it
	foreach my $player (@{$playersList->getItems()}) {

#		if($char->{party} and $char->{party}{users}{$player->{ID}}){
#			push @partyList, $player->{ID};
#			#print Dumper($player);
#			print $player->{name} . "\n";
#			$list_x += $player->{pos}{x};
#			$list_y += $player->{pos}{y};
		}
		if($args->{'x'} eq $player->{pos}{x} and $args->{'y'} eq $player->{pos}{y}){
			$occupied = 1;
			last;
		}
	}
	
	# if there isn't, return
	return $args if $occupied eq 0;
	
	# if there is, find a new spot
	my @stand = calcRectArea2($args->{'x'}, $args->{'y'},3,0);
	my $exitflag = 0;
	
	while(!$exitflag){
		if(scalar(@stand)==0){
			$exitflag=1;
			return;
		}
	
		my $i = int(rand @stand);
		my $spot = $stand[$i];
		
		if(!$field->isWalkable($spot->{x}, $spot->{y}) || positionNearPortal($spot, 4) ) {
			splice(@stand,$i,1);
		} else {
				$new_pos{'x'} = $spot->{x};
				$new_pos{'y'} = $spot->{y};
				$exitflag=1;
		}
	}
	stand() if ($char->{sitting});
	#if the distance is too far, and we can't move, we have to route it instead
	if($dist < 8){
		$char->sendMove(@new_pos{qw(x y)});	
	} else {
		ai_route($field->baseName, $new_pos{'x'}, $new_pos{'y'}, attackOnRoute => 0);
	}
	
	$mytimeout->{'break_wait'} = time;		
	$mytimeout->{'sit_wait'} = time;
	
}
=cut

sub getInsideParty {
	my @partyList;
	my $list_x;
	my $list_y;
	
	my $newx;
	my $newy;
	
	my %result;
	
	$result{x} = $char->{pos_to}{x};
	$result{y} = $char->{pos_to}{y};
	
	#print Dumper (\$args);
	
	foreach my $player (@{$playersList->getItems()}) {
		if($char->{party} and $char->{party}{users}{$player->{ID}}){
			push @partyList, $player->{ID};
			#print Dumper($player);
			#print $player->{name} . "\n";
			$list_x += $player->{pos_to}{x};
			$list_y += $player->{pos_to}{y};
		}
	}
	
	return %result if (scalar(@partyList) < 1);
	$newx = int ($list_x / scalar(@partyList)) + (2-int(rand(3)));
	$newy = int ($list_y / scalar(@partyList)) + (2-int(rand(3)));
	#determine ideal position
	
	
	if($config{bf_debug}){
		message TF("Visible party members: %s\n",scalar(@partyList)), "follow";
		message TF("Ideal position: %s , %s\n",$newx, $newy), "follow";
	}
	
	$new_pos{'x'} = $newx;
	$new_pos{'y'} = $newy;
	
	$result{x} = $newx;
	$result{y} = $newy;
	
	return %result;
}

sub hideInParty {
	#if party aggressives > 2
	#move to the center of the party
	
	# shift these args! $args
	#my $args = shift; #we dont actually use args so this is worthless
	
	if((AI::action eq "follow") 
	and timeOut($mytimeout->{'hideInParty'},0.55) 
	and scalar(ai_getAggressives(0,1))>3
	and timeOut($mytimeout->{'healer'},0.55)){ # and scalar(ai_getAggressives())>3
		my @partyList;
		my $list_x;
		my $list_y;
		
		my $newx;
		my $newy;
		
		#print Dumper (\$args);
		
		foreach my $player (@{$playersList->getItems()}) {
			if($char->{party} and $char->{party}{users}{$player->{ID}}){
				push @partyList, $player->{ID};
				#print Dumper($player);
				print $player->{name} . "\n";
				$list_x += $player->{pos_to}{x};
				$list_y += $player->{pos_to}{y};
			}
		}
		
		return if (scalar(@partyList) < 2);
		$newx = int ($list_x / scalar(@partyList)) + (2-int(rand(4)));
		$newy = int ($list_y / scalar(@partyList)) + (2-int(rand(4)));
		#determine ideal position
		
		
		if($config{bf_debug}){
			message TF("Visible party members: %s\n",scalar(@partyList)), "follow";
			message TF("Ideal position: %s , %s\n",$newx, $newy), "follow";
		}
		
		$new_pos{'x'} = $newx;
		$new_pos{'y'} = $newy;
		
		my $realMyPos = calcPosition($char);
		
		#return if (calcPosition($char) eq $new_pos); #distance($char->{pos_to}, $player->{pos_to})
		#if($new_pos{x} eq $realMyPos->{x} and $new_pos{y} eq $realMyPos->{y} and timeOut($mytimeout->{'break_wait'},3.15)){
						
		
		
		$mytimeout->{'hideInParty'} = time+10;
		$better_move_timeout = time;
		
		return if ($new_pos{x} eq $realMyPos->{x} and $new_pos{y} eq $realMyPos->{y});
		ai_route($field->baseName, $new_pos{'x'}, $new_pos{'y'}, attackOnRoute => 0);
	}
}

#moving the sendmove thing to a ub so i can change timeouts if i want to
sub MoveMe {

}

sub new_look {
	#my $bodydir = shift;
	#headdir: 0 = face directly, 1 = look right, 2 = look left
	my $bodydir = shift;
	my ($new_dir,$head_dir);
	
	$new_dir = 3 + int(rand(3));
	#$mytimeout->{'turn_break'} = time+(1+rand(3));
	
	if($bodydir > $new_dir){
		#look left
		$head_dir = 2;
	} else {
		#look right
		$head_dir = 1;
	}
	
	my $result;
	$result->{'body'} = $new_dir;
	$result->{'head'} = $head_dir;
	
	message TF("New direction body:%s head:%s\n",$result->{'body'},$result->{'head'}), "follow";
	
	return $result;
}

#moving the push along vector to a sub
sub pushVector {
	#we need position1, position2, and the distance
	my $pos1 = shift;
	my $pos2 = shift,
	my $dist = shift;
	
	my (%vec, %pos);

	getVector(\%vec, $pos1, $pos2);
	moveAlongVector(\%pos, $pos2, \%vec, $dist);
	
	return %pos;
}

sub getOffset {
	my %sendArgs = ();
	
	#my $from = shift;
	#my $to = shift;
	
	$mytimeout->{'move_break'} = time;
	$mytimeout->{'break_wait'} = time;
	
	my $ID = shift;
			
	my $offset_x = 0;
	my $offset_y = 0;
	
	my %offset_;
	
	my $realMyPos = calcPosition($char);

	#!!!!!!!! NEW POS CALC, MIGHT NOT WORK !!!!!!!!
	my $range = ($config{bf_rangeSize}>1) ? $config{bf_rangeSize} : 2;
	my @posarray = calcRectArea2($realMyPos->{x}, $realMyPos->{y}, $config{bf_rangeSize}+1, 2);

	my $randomelement = $posarray[int(rand @posarray)];
	$offset_x = $randomelement->{x} - $realMyPos->{x};
	$offset_y = $randomelement->{y} - $realMyPos->{y};
	#$randomelement = $array[rand @array];

	my $followDist = 0-$config{bf_followDistance};

	$sendArgs{'rot'} = calcRotation($ID);
	$sendArgs{'x'} = $saved_offset{'x'} = $offset_x;
	$sendArgs{'y'} = $saved_offset{'y'} = $followDist+$offset_y;

	#rotate it
	my %result = testRotation(%sendArgs);

	#set the offset
	$offset_{'x'} = $result{x};
	$offset_{'y'} = $result{y};

	#save our target's rotation for future checks
	$last_dir = $sendArgs{rot};

	#this is the INITIAL SETUP, we don't need to come here again.
	$setup = 1;
	
	$direction->{'body'} = 4;
	$direction->{'head'} = 0;
	
	return %offset_;
}

sub calcRotation {
	#my (%sendArgs) = @_;
	my ($ID) = @_;
	
	my $player = $players{$ID};
	my $dir = 0;
	
	##message TF("Calculating rotation of %s with ID:%s...\n", ($player->{name}),$ID), "follow";
	
	$dir = 0 if( $player->{pos}{x} ==  $player->{pos_to}{x} and  $player->{pos_to}{y} >  $player->{pos}{y}); #up
	$dir = 1 if( $player->{pos}{x} >  $player->{pos_to}{x} and  $player->{pos_to}{y} >  $player->{pos}{y}); #up left
	$dir = 2 if( $player->{pos}{x} >  $player->{pos_to}{x} and  $player->{pos_to}{y} ==  $player->{pos}{y}); #left
	$dir = 3 if( $player->{pos}{x} >  $player->{pos_to}{x} and  $player->{pos_to}{y} <  $player->{pos}{y}); #down left
	$dir = 4 if( $player->{pos}{x} ==  $player->{pos_to}{x} and  $player->{pos_to}{y} <  $player->{pos}{y}); #down
	$dir = 5 if( $player->{pos}{x} <  $player->{pos_to}{x} and  $player->{pos_to}{y} <  $player->{pos}{y}); #down right
	$dir = 6 if( $player->{pos}{x} <  $player->{pos_to}{x} and  $player->{pos_to}{y} ==  $player->{pos}{y}); #right
	$dir = 7 if( $player->{pos}{x} <  $player->{pos_to}{x} and  $player->{pos_to}{y} >  $player->{pos}{y}); #top right
	
	#debug "(Computet direction $dir, pos: $player->{pos} , pos_to $player->{pos_to}, $player) \n";
	return $dir;
}

sub testRotation {
	my (%sendArgs) = @_;
	
	my $rot;
	my $pie = 3.1415926;
	
	$rot = 360 if($sendArgs{rot} == 0);
	$rot = 45 if($sendArgs{rot} == 1);
	$rot = 90 if($sendArgs{rot} == 2);
	$rot = 135 if($sendArgs{rot} == 3);
	$rot = 180 if($sendArgs{rot} == 4);
	$rot = 235 if($sendArgs{rot} == 5);
	$rot = 270 if($sendArgs{rot} == 6);

	$rot = 315 if($sendArgs{rot} == 7);
	
	my $newRot = ($pie/180)*$rot;
	
	my %returnValue = ();

	my $x = $sendArgs{x};
	my $y = $sendArgs{y};
	
	$returnValue{'x'} = int((cos($newRot)*$x) - (sin($newRot)*$y));
	$returnValue{'y'} = int((sin($newRot)*$x) + (cos($newRot)*$y));
	
	return %returnValue;
	
}

sub ai_post {
	#debug "AI::action = ".AI::action."\n";
	#message TF("words\n"), "teleport";
}

sub shuffleMoves {
	if(!$field->isCity and (AI::action ne "attack" || AI::action ne "move" || AI::action ne "route")){
		#message "we're at the top of shufflemoves\n";
		
		#return if($char->{sitting} or rand(100) < 30);
		
		#message TF("Got this far in shuffling with no FollowTarget\n"), "teleport";
		
		if(defined $bf_args->{base}){
			if (distance(calcPosition($char), $bf_hash{'base_pos'}) > 5 and timeOut($mytimeout->{'base_distance_check'},1.2)){
				message TF("Too far away from base \n"), "follow";
				$mytimeout->{'base_distance_check'} = time;
				if($field->baseName eq $bf_args->{base}){
				ai_route($field->baseName, $bf_hash{'base_pos'}{'x'}, $bf_hash{'base_pos'}{'y'},
						maxRouteTime => 20,
						attackOnRoute => 0,);
				} else {
					sendMessage($messageSender, "p", "my base is on a different map");
					#ai_route($bf_args->{base});
					$mytimeout->{'base_distance_check'} = time+20;
				}
			}
		}
		
		if($char->{sitting} and rand(100) < 30 and timeOut($mytimeout->{'shuffle_move'},0.35)) {
			$direction->{'body'} = int(rand(9));
			$mytimeout->{'shuffle_move'} = time + rand($config{bf_shuffle}) + rand($config{bf_shuffle});
		} elsif (!$char->{sitting} and timeOut($mytimeout->{'shuffle_move'},0.35)){	
			my $butts;
			$boredom_dist ||= 4;
			
			#shuffle block
			if($config{bf_shuffle} and timeOut($mytimeout->{'shuffle_move'},0.35)){
				#message TF("Boredom Move\n"), "teleport";
				
				$butts = $config{bf_shuffle}/2;
				
				# get the optimal position around the party
				my @partyList;
				my $list_x;
				my $list_y;

				my $newx;
				my $newy;

				#print Dumper (\$args);

				foreach my $player (@{$playersList->getItems()}) {
					if($char->{party} and $char->{party}{users}{$player->{ID}}){
						push @partyList, $player->{ID};
						#print Dumper($player);
						#print $player->{name} . "\n";
						$list_x += $player->{pos_to}{x};
						$list_y += $player->{pos_to}{y};
					}
				}

				if (scalar(@partyList) eq 0 or $boredom_dist < 4){
	#=pod			
					my $garbage = calcPosition($char);

					my @stand = calcRectArea2($garbage->{x}, $garbage->{y},int(rand($boredom_dist)+1),1);
					my $i = int(rand @stand);
					my $spot = $stand[$i];

					#print Dumper(\$spot);
					$new_pos{'x'} = $spot->{x};
					$new_pos{'y'} = $spot->{y};
					
					$char->sendMove(@new_pos{qw(x y)});
	#=cut			
					message TF("Shuffling to: %s: %s, %s\n", $field->descString(), $spot->{x}, $spot->{y}), "teleport";
					$mytimeout->{'shuffle_move'} = time + $butts + rand($butts);
					return;
				};
				
				if (scalar(@partyList) > 1){
					$newx = int ($list_x / scalar(@partyList)) + (2-int(rand($boredom_dist)));
					$newy = int ($list_y / scalar(@partyList)) + (2-int(rand($boredom_dist)));
				} else {
					$newx = $list_x;
					$newy = $list_y;
				}
				
				#$char->sendMove(@new_pos{qw(x y)});
				my ($randX, $randY);
				my $i = 500;
				#my $pos = calcPosition($char);
				do {
					if ((rand(2)+1)%2) {
						$randX = $newx + int(rand($boredom_dist) + 1);
					} else {
						$randX = $newx - int(rand($boredom_dist) + 1);
					}
					#if ((rand(2)+1)%2) {
					if ((rand(2)+1)%2) {
						$randY = $newy + int(rand($boredom_dist) + 1);
					} else {
						$randY = $newy - int(rand($boredom_dist) + 1);
					}
				} while (--$i and !$field->isWalkable($randX, $randY));
				if (!$i) {
					error T("Invalid coordinates specified for Boredom Move\n Retrying...\n");
				} else {
					message TF("Shuffling to: %s: %s, %s\n", $field->descString(), $randX, $randY), "teleport";
					ai_route($field->baseName, $randX, $randY,
					maxRouteTime => 20,
					attackOnRoute => 1,);
				}
				
				$new_pos{'x'}=$randX;
				$new_pos{'y'}=$randY;
				
				$boredom_dist--;
				$mytimeout->{'shuffle_move'} = time + $butts + rand($butts);
			}		
			
			#wandering block
			if($config{bf_wander} and timeOut($mytimeout->{'wander_move'},0.35)){
				#print $new_pos{'x'} . " " . $new_pos{'y'} . "\n";
				
				$butts = $config{bf_wander}/2;
				my $time = time + $butts + rand($butts);
							
				if (timeOut($mytimeout->{'wander_move'},0.35)) { #randomly search for portals...
					my ($randX, $randY);
					my $i = 500;
					my $pos = calcPosition($char);
					do {
						if ((rand(2)+1)%2) {
							$randX = $pos->{x} + int(rand(5) + 4);
						} else {
							$randX = $pos->{x} - int(rand(5) + 4);
						}
						#if ((rand(2)+1)%2) {
						if ((rand(2)+1)%2) {
							$randY = $pos->{y} + int(rand(5) + 4);
						} else {
							$randY = $pos->{y} - int(rand(5) + 4);
						}
					} while (--$i and !$field->isWalkable($randX, $randY));
					if (!$i) {
						error T("Invalid coordinates specified for Wander Move\n Retrying...\n");
					} else {
						message TF("Wandering to: %s: %s, %s\n", $field->descString(), $randX, $randY), "teleport";
						ai_route($field->baseName, $randX, $randY,
						maxRouteTime => 20,
						attackOnRoute => 2,
						noMapRoute => 1);
					}
					
					$new_pos{'x'}=$randX;
					$new_pos{'y'}=$randY;
					
					$mytimeout->{'wander_move'} = $time;
					$mytimeout->{'shuffle_move'} = $time/2;
					$mytimeout->{'base_distance_check'} = $time;
				}
			}
			#message "we're at the bottom of shuffle moves \n";
		}
	} elsif ($field->isCity){
		if($char->{sitting} and rand(100) < 30 and timeOut($mytimeout->{'shuffle_move'},0.35)) {
			$direction->{'body'} = int(rand(9));
			$mytimeout->{'shuffle_move'} = time + ($config{bf_shuffle}*2) + rand($config{bf_shuffle});
		}
	}
}

sub getLeaderOrPartyPos {
	my ($args) = @_;
	
	my %result;
}

sub partyMsg {
	#my ($var, $tmp, $args) = @_;
	my ($var, $arg, $tmp) = @_;
	my ($msg, $msg2, $ret, $name, $message);
		
	#print "Party message\n" if defined $arg;
	#print Dumper $var;
	#print Dumper $tmp;
	#print Dumper $arg;

	#print "Split \n" if defined $arg;
	$msg = $arg->{message};
	my @values = split(':', $msg);
	
=pod	
	my @words = split(/[ ,.:;\"\'!?\r\n]/, $msg);
	#my @values = split(':', $msg);
	
	#$ret = getWord($arg);
	
	my $i = 2;
	my $b = scalar(@words);
	my $name;
	my $full_message;
	foreach (@words) {
		$b--;
		if($_ eq ""){
			$i = 0;
			next;
		} elsif ($_ ne "" and $i ne 0){
			$name .= " " if $i eq 1;
			$name .= $_;
			$i--;
		} else {
			$full_message .= $_;
			$full_message .= " " if($b>0);
		}
	}
=cut
	
	#print "----Values Go Herre-----\n";
	
	chop($values[0]);
	substr($values[1], 0, 1) = '';
	
	$name = $values[0];
	$message = $values[1];
	
	#print Dumper @values;
	
	#print "----------\n";
	
	#print Dumper @words;
	
	#are we the sender? ignore it if we are
	return if($char->{name} eq $name);
	#print "regexp\n" if ($message =~ /\w\s\w+\s\w\s\w/);
	
	#if ($message =~ /(\w+)\s+(\w+)\s+(\w+)\s+(\w+)/){
		#print "$1 $2 $3 $4\n";
	#}
	
	#modify the config instead of storing it internally
	#that way we can move to our base if we get disconnected
	#configModify("followTarget", $players{$targetID}{name});
	
	given($message){
		#move to a map
		when ($_ =~ /^(move) (to) ([a-z]+)/){
			ai_route($3);
		}
	
		# move to positions
		when ($_ =~ /^(move) (to) (\d+) (\d+)/){
			continue unless isSpeakerOnScreen($name);
			my %pos;
						
			$pos{'x'} = $3;
			$pos{'y'} = $4;
			
			sendMessage($messageSender, "p", "moving to $3 $4");
			#$char->sendMove(@pos{qw(x y)});
			ai_route($field->baseName, $3, $4, attackOnRoute => 1);
		}
		
		# set a specific group's base
		when ($_ =~ /(group) (\w) (set) (base)/){
			#message "$2\n";
			continue unless uc($2) eq $config{bf_group};
			continue unless isSpeakerOnScreen($name);
			#sendMessage($messageSender, "p", "i am in group $2");
			
			sendMessage($messageSender, "p", "base set");
			$bf_args->{'base'} = $field->baseName; #$field->baseName
			$bf_hash{'base_pos'}{'x'} = $char->{pos_to}{x};
			$bf_hash{'base_pos'}{'y'} = $char->{pos_to}{y};
			
			configModify("bf_baseMap", $field->baseName);
			configModify("bf_baseX", $char->{pos_to}{x});
			configModify("bf_baseY", $char->{pos_to}{y});
		}
		# clear a specific group's base
		when ($_ =~ /(group) (\w) (clear) (base)/){
			#message "$2\n";
			continue unless uc($2) eq $config{bf_group};
			#sendMessage($messageSender, "p", "i am in group $2");
			
			continue unless defined $bf_args->{'base'};
			continue unless isSpeakerOnScreen($name);
			sendMessage($messageSender, "p", "clearing base");			
			undefBase();
		}
		
		# member of group call out
		when ($_ =~ /(say) (group) (\w)/){
			message "$ 3 is $3\n";
			continue unless uc($3) eq $config{bf_group};
			sendMessage($messageSender, "p", "i am in group $config{bf_group}");
		}
		
		# party member move to new group
		when ($_ =~ /(\w+) (move) (to) (group) (\w)/){
			my ($name2, $newgroup) = ($1, uc($5));
			#message "1:$1 2:$2 3:$3 4:$4 5:$5\n";
			continue unless ($char->{name} =~ m/$1/i);
			if($config{bf_group} ne $newgroup){
				sendMessage($messageSender, "p", "moving from group $config{bf_group} to $newgroup");
				configModify("bf_group", $newgroup);
			} else {
				sendMessage($messageSender, "p", "i am already in group $config{bf_group}");
			}
			
		}
		
		# all units say group
		when ("say group"){
			sendMessage($messageSender, "p", "i am in group $config{bf_group}");
		}
		
		when ("say follow"){
			sendMessage($messageSender, "p", "i am following $config{followTarget}");
		}
		
		# all units set base
		when ("set base"){
			continue unless isSpeakerOnScreen($name);
			sendMessage($messageSender, "p", "base set");
			$bf_args->{'base'} = $field->baseName; #$field->baseName
			$bf_hash{'base_pos'}{'x'} = $char->{pos_to}{x};
			$bf_hash{'base_pos'}{'y'} = $char->{pos_to}{y};
			#hideInParty();
		}
		when ("clear base"){
			continue unless defined $bf_args->{'base'};
			continue unless isSpeakerOnScreen($name);
			sendMessage($messageSender, "p", "clearing base");
			undefBase();
		}
		when ("all clear base"){
			continue unless defined $bf_args->{'base'};
			sendMessage($messageSender, "p", "clearing base");
			undefBase();
		}
		when ("say base"){
			continue unless defined $bf_args->{'base'};
			sendMessage($messageSender, "p", "base is $bf_args->{'base'} $bf_hash{'base_pos'}{'x'},$bf_hash{'base_pos'}{'y'}");
		}
		when ("exit"){
			continue unless isSpeakerOnScreen($name);
			die;
		}
		when ("all exit"){
			die;
		}
		when ("function test"){
			isSpeakerOnScreen($name);
		}
		when ("retreat"){
			functionTest();
		}
		when ("whats my pos"){
			continue unless isSpeakerOnScreen($name);
			foreach my $player (@{$playersList->getItems()}) {
				if($char->{party} and $char->{party}{users}{$player->{ID}}){
					sendMessage($messageSender, "p", "$player->{name} is at $player->{pos}{x} ,  $player->{pos}{y}");
					sendMessage($messageSender, "p", "$player->{name}'s new pos is at $player->{pos_to}{x} ,  $player->{pos_to}{y}");
				}
			}
		}

		when ("store follow")
		{
			message TF("Storing followTarget: $config{followTarget}\n"), "follow";
			$storedFollow = $config{followTarget};
		}

		when ("save follow")
		{
			message TF("Storing followTarget: $config{followTarget}\n"), "follow";
			$storedFollow = $config{followTarget};
		}

		when ("reload follow"){
			reloadFollowTarget();
		}

		when ("stay here")
		{
			#storeFollowTarget();
			#configModify("followTarget", "BASE");
			stayHere($name);

		}

		when ("lets go")
		{
			letsGo($name);
			reloadFollowTarget();
		}

		when ("lets move")
		{
			#configModify("follow", 1);
			reloadFollowTarget();
		}

		when ("sit")
		{
			sit();
		}

		when($_ =~ /(set) (conf) (\w+) (\w+)/)
		{
			my ($configTarget) = $3;
			my ($configValue) = $4;
			#if(defined $config{($configTarget)})
			{
				configModify(($configTarget), ($configValue));
				sendMessage($messageSender, "p", "$configTarget set to $configValue");
			}
		}
		
		when ("follow group leader"){
			AI::clear("follow");
			main::ai_follow($config{bf_groupLeader});
			configModify("follow", 1);
			configModify("followTarget", $config{bf_groupLeader});
		}

		when($_ =~ /(\w+) (move here)/)
		{
=pod
			# this isn't done yet. need to remember how to get actors based on just a name

			continue unless ($char->{name} =~ m/$1/i);

			my $realTargPos = calcPosition($targetActorMaybe);

			# realTargPos is not defined
			my @stand = calcRectArea2($realTargPos->{x}, $realTargPos->{y},2,0);
			my $i = int(rand @stand);
			my $spot = $stand[$i];

			my %new_pos = ();
			$new_pos{'x'} = $spot->{x};
			$new_pos{'y'} = $spot->{y};

			if(!$field->isWalkable($spot->{x}, $spot->{y}))
			{
				message TF("Can't reach $spot->{x}, $spot->{y}!\n"), "teleport";
			}

			my $failSafe = 1;
			if($failSafe ne undef)
			{						
				ai_route($field->baseName, $new_pos{'x'}, $new_pos{'y'}, attackOnRoute => 0);
				stand();
			}
=cut
		}

		when ($_ =~ /(\w+) (follow) (\w+)/){
			my ($name2) = $3;
			my $arg1;
			#message "1:$1 2:$2 3:$3 4:$4 5:$5\n";
			continue unless ($char->{name} =~ m/$1/i);
			
			
			if($name2 eq "me"){
				($arg1) = $name;
			} else {
				($arg1) = $name2;
				for (my $i = 0; $i < @partyUsersID; $i++) {
					next if ($partyUsersID[$i] eq "");
					#print $char->{'party'}{'users'}{$partyUsersID[$i]}{'name'} . "\n";
					
					#if($npc->{'name'} =~ m/Kafra Employee/i)
					#my $tempName = $char->{'party'}{'users'}{$partyUsersID[$i]}{'name'};
					
					if ($char->{'party'}{'users'}{$partyUsersID[$i]}{'name'} =~ m/$name2/i) {
						# Translation Comment: Is the party user on list online?
						($arg1) = $char->{'party'}{'users'}{$partyUsersID[$i]}{'name'};		
					}
				}
			}
			
			AI::clear("follow");
			main::ai_follow($arg1);
			configModify("follow", 1);
			configModify("followTarget", $arg1);
			
			sendMessage($messageSender, "p", "I am now following $arg1");
		}

		when("pause shuffle")
		{
			if(defined $mytimeout)
			{
				message TF("Shuffle Move: Pausing shuffling...\n"), "teleport";
				$mytimeout->{'shuffle_move'} = time+99999;
			}
		}

		when("resume shuffle")
		{
			if(defined $mytimeout)
			{
				message TF("Shuffle Move: Resuming shuffling...\n"), "teleport";
				$mytimeout->{'shuffle_move'} = time;
			}
		}
		
		when ($_ =~ /^(follow) (.*)/m){
			my $arg1;
			if($2 eq "me"){
				($arg1) = $name;
			} else {
				($arg1) = $2
			}
			
			AI::clear("follow");
			main::ai_follow($arg1);
			configModify("follow", 1);
			configModify("followTarget", $arg1);
		}
=pod	
		when ("cast sight"){
			if($char->{skills}{MG_SIGHT}){
				sendMessage($messageSender, "p", "don't tell me what to do");
				my $skill = new Skill(handle => 'MG_SIGHT');
				ai_skillUse2($skill, $char->{skills}{MG_SIGHT}{lv}, 1, 0, $char, "MG_SIGHT");
			}
		}
		
		when ("cast firewall"){
			if($char->{skills}{MG_FIREWALL}){
				sendMessage($messageSender, "p", "don't tell me what to do");
				my $skill = new Skill(handle => 'MG_FIREWALL');
				my $target = { x => $char->{pos_to}{x}, y => $char->{pos_to}{y} };
				my $actorList = $playersList; 
				
				require Task::UseSkill;
				
				my $skillTask = new Task::UseSkill(
					actor => $skill->getOwner,
					target => $target,
					actorList => $actorList,
					skill => $skill,
					priority => Task::USER_PRIORITY
				);
				my $task = new Task::ErrorReport(task => $skillTask);
				$taskManager->add($task);
				
				
				#ai_skillUse2($skill, $char->{skills}{MG_SIGHT}{lv}, 1, 0, $target, "MG_FIREWALL");
			}
		}
=cut

		when ("whats my job"){
			my $whatever;
		
			foreach my $player (@{$playersList->getItems()}) {
				#message "name: " . $player->{name} . " args: " . $args . "\n";
				$whatever = $player->{jobID} if($name eq $player->{name});
			}
		
			sendMessage($messageSender, "p", "Your job id is $whatever");
		}
		
		when ("use con") {
			#$flags{'use_con'} = 1;
			
			my $item = $char->inventory->getByNameList("Concentration Potion");
			if ($item) {
				$messageSender->sendItemUse($item->{ID}, $accountID);
				#$ai_v{"useSelf_item_$i"."_time"} = time;
				#$timeout{ai_item_use_auto}{time} = time;
				#debug qq~Auto-item use: $item->{name}\n~, "ai";
			}
		}

		when ($_ =~ /^(cast) (.*)/m){
			my $skill = new Skill(auto => $2);
			#my $identifier = $skill->getHandle();
			
			#sendMessage($messageSender, "p", "trying to cast $identifier");
			
			if($char->{skills}{$skill->getHandle()}){
				#sendMessage($messageSender, "p", "don't tell me what to do");
				
				my $actorList = $playersList;
				my $target = $char;
				
				require Task::UseSkill;
				my $skillTask = new Task::UseSkill(
					actor => $skill->getOwner,
					target => $target,
					actorList => $actorList,
					skill => $skill,
					priority => Task::USER_PRIORITY
				);
				my $task = new Task::ErrorReport(task => $skillTask);
				$taskManager->add($task);
			}
		}

		when ("stop"){
			if(defined $bf_args->{'stop'})
			{
				sendMessage($messageSender, "p", "Moving!");
				undef $bf_args->{'stop'};
			}
			else
			{
				sendMessage($messageSender, "p", "Stopping...");
				$bf_args->{'stop'} = $field->baseName;
				$bf_hash{'stop_pos'}{'x'} = $char->{pos_to}{x};
				$bf_hash{'stop_pos'}{'y'} = $char->{pos_to}{y};
			}
			sendMessage($messageSender, "p", "Beepo!");
		}
		
		when ($_ =~ /^(.*)/m){
			my $skill = new Skill(auto => $1);
			#my $identifier = $skill->getHandle();
			
			#sendMessage($messageSender, "p", "trying to cast $identifier");
			
			if($char->{skills}{$skill->getHandle()}){
				#sendMessage($messageSender, "p", "don't tell me what to do");
				my $level = $char->{skills}{$skill->getHandle()}{lv};

				# no idea how else to get the max level
				$skill = new Skill(auto => $1, level => $level);

				my $actorList = $playersList;
				my $target = $char;
				
				require Task::UseSkill;
				my $skillTask = new Task::UseSkill(
					actor => $skill->getOwner,
					target => $target,
					actorList => $actorList,
					skill => $skill,
					priority => Task::USER_PRIORITY
				);
				my $task = new Task::ErrorReport(task => $skillTask);
				$taskManager->add($task);
			}
		}
		
		default {
			#die;
		}
	}
	
	#{target} is at {d} {d}
	#
	#{name1} {name2} is at {d} {d}
	
	if ($message =~ /(\w+)\s+(\w+)\s+is\s+at\s+(\d+)\s+(\d+)/ and $bf_args->{'search_for_follow'}){
		#print "$1 $2 is at $3 $4\n";
		undef $bf_args->{'search_for_follow'};
		ai_route($field->baseName, $3, $4, attackOnRoute => 0);
		message TF("Moving to: %s, %s to find master\n", $3, $4), "teleport";
		$mytimeout->{'search_for_leader'} = time + 60;		
	}elsif($message =~ /(\w+)\s+is\s+at\s+(\d+)\s+(\d+)/ and $bf_args->{'search_for_follow'}){
		#print "$1 is at $2 $3 TOP ONE\n";
		undef $bf_args->{'search_for_follow'};
		ai_route($field->baseName, $2, $3, attackOnRoute => 0);
		message TF("Moving to: %s, %s to find master\n", $2, $3), "teleport";
		$mytimeout->{'search_for_leader'} = time + 60;
	}
	
	#(\w)\s+(\w+)\s+(\w)\s+(\w)
	#'words words words words';
	
	#print "------BUTTS----\n";
	#print Dumper $name;
	#print Dumper $message;
	
	#print Dump @values;
	
	if($message eq "this is a test"){
		sendMessage($messageSender, "p", "test received");
	}
}

sub functionTest {
	my %temp_pos = getInsideParty();
	my $temp_pos2;
	$temp_pos2->{'x'} = $temp_pos{x};
	$temp_pos2->{'y'} = $temp_pos{y};

	print distance(calcPosition($char), $temp_pos2);
	#message "got this far\n";
	#message "distance: " . distance(calcPosition($char), $temp_pos2) . "\n";
	#message TF("!!!!!!!!!! Shit works !!!!!!!!!!\n"), "teleport" if distance(calcPosition($char), $temp_pos2) ne 0;

	ai_route($field->baseName, $temp_pos{x}, $temp_pos{y}, attackOnRoute => 0) if distance(calcPosition($char), $temp_pos2) ne 0;	
}

sub isSpeakerOnScreen {
	my ($args) = @_;
	
	foreach my $player (@{$playersList->getItems()}) {
		#message "name: " . $player->{name} . " args: " . $args . "\n";
		return 1 if($args eq $player->{name});
	}
	
	return 0;
}

sub storeFollowTarget {
	if(!defined $storedFollow)
	{
		$storedFollow = $config{followTarget};
		message TF("Storing followTarget: $config{followTarget}\n"), "follow";
	}
}

sub reloadFollowTarget {
	if(defined $storedFollow)
	{
		configModify("followTarget", $storedFollow);
	}
}

sub letsGo {
	my ($args) = @_;

	continue unless defined $bf_args->{'base'};
	#continue unless isSpeakerOnScreen($args);
	#sendMessage($messageSender, "p", "clearing base");
	undefBase();
}

# a function to handle clearing the FOLLOWING ai sequence, setting the base, changing the follow etc etc
sub stayHere {
	my ($args) = @_;

	storeFollowTarget();

	continue unless isSpeakerOnScreen($args);

	sendMessage($messageSender, "p", "base set");
	$bf_args->{'base'} = $field->baseName; #$field->baseName
	$bf_hash{'base_pos'}{'x'} = $char->{pos_to}{x};
	$bf_hash{'base_pos'}{'y'} = $char->{pos_to}{y};
	#hideInParty();

	configModify("followTarget", "BASE");

	# stop following our current guy
	AI::dequeue if (AI::action eq "follow");

	# go back to following. should prevent characters from wandering to a random spot first
	AI::queue("follow");
}

#pass in the speaker's name and see if they are in our designated list for commanders
sub isSpeakerDesignated {
	my ($args) = @_;
	
	return 1 if existsInList($config{"bf_Commanders"}, $args);
	
	return 0;
}

sub undefBase {
	$bf_args->{'base'} = undef;
	$bf_hash{'base_pos'} = undef;
	configModify("bf_baseMap", undef);
	configModify("bf_baseX", undef);
	configModify("bf_baseY", undef);
}

#############
#############
#############

return 1;
