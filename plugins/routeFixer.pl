############################ 
# routeFixer plugin for Openkore by MaterialBlade
#
# Trying to fix times when bots are stupid and go back and forth between portals
# This is a WIP plugin. There is no configuration, it just activates if it's loaded
#
# This software is open source, licensed under the GNU General Public Liscense
############################ 

package routeFixer;

use strict;
use encoding 'utf8';

use Globals;
use Log qw(message warning error debug);
use Misc;
use Settings;

use AI;
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

use Utils;
use Commands;

use Translation;
use Field;
use Task::TalkNPC;
use Task::UseSkill;
use Task::ErrorReport;
use Utils::Exceptions;
use Data::Dumper;


use constant {
	RECHECK_TIMEOUT => 5,
	FALSE => 0,
	TRUE => 1,
	NPC_REFRESH_COOLDOWN => 1.5,
};

Plugins::register('routeFixer', 'more realistic follow options', \&onUnload); 
my $hooks = Plugins::addHooks(
	#['ai_follow', \&mainProcess, undef], 
	#["AI_pre", \&prelims, undef],
	['AI_post',       \&ai_post, undef],
	#['Network::Receive::map_changed', \&changedMap, undef],

	#['route', \&stuckRoute, undef],
	['route', \&stuckRoute, undef],
	['FullSolutionReady',			\&getRoute],
	# prontera 35 208 -> aldebaran 140 135 -> c_tower1

	#["packet_pre/party_chat", \&partyMsg, undef],

	# ==== i dunno, reference stuff below?

	#['packet/actor_moved', \&mapMoveActor, undef],
	#['packet_pre/actor_display', \&actorMoved, undef],

	# Plugins::callHook('player_exist', {player => $actor}); this is AFTER the actor has been added, so maybe better

	# Plugins::callHook('packet/actor_display', $args);
	# Plugins::callHook('item_gathered',{item => $item->{name}, amount => $amount});
	# Plugins::callHook('route', {status => 'stuck'});
	# Plugins::callHook('packet_attack', {sourceID => $args->{sourceID}, targetID => $args->{targetID}, msg => \$msg, dmg => $totalDamage, type => $args->{type}});
);

my $loghook = Log::addHook(\&consoleCheckWrapper);

sub onLoad {
	
}

onLoad();

sub onUnload {
    Plugins::delHooks($hooks);
	Log::delHook($loghook);
}

sub onReload {
    &onUnload;
}

message "routeFixer success\n", "success";

my $mytimeout;

sub ai_post {

	if(AI::inQueue("NPC") and AI::inQueue("skill_use"))
	{
		AI::clear(qw/skill_use/); # this doesn't do anything
	}
}

sub stuckRoute
{
	#print "HEY MOM WE GOT HERE!!!!!!!!\n";
}

sub consoleCheckWrapper {
	return;

	#return unless defined $conState;
	# skip "macro" and "cvsdebug" domains to avoid loops
	return if $_[1] =~ /^(?:macro|cvsdebug)$/;

	# skip debug messages unless macro_allowDebug is set
	#return if ($_[0] eq 'debug' && !$::config{macro_allowDebug});

	my @args = @_;
	#print Dumper(@args);
	#automacroCheck("log", \@args)

	#[2025.10.13 12:31:21.32] NPC error: Could not find an NPC at location (156,174)..
	#$VAR1 = 'warning';
	#$VAR2 = 'route';
	#$VAR3 = 0;
	#$VAR4 = 1;
	#$VAR5 = 'NPC error: Could not find an NPC at location (156,174)..

	# we want to fix some routing stuff here. i don't think this works for some reason
	if(	$args[0] eq 'warning'
		and $args[1] eq 'route'
		and $args[2] eq 0
		and $args[3] eq 1)
	{
		sendMessage($messageSender, 'c', "\@refresh");
	}
}

sub getRoute
{
	my (undef, $args) = @_;

	# incoming data is in the format of...
	# prontera 35 208 -> aldebaran 140 135 -> c_tower1

	#print Dumper($args);
	return unless timeOut($mytimeout, RECHECK_TIMEOUT);

	$mytimeout = time;

	#sleep(1);

	my @route = split(' -> ', $args->{route});
	my $destination = $route[$#route]; # get the destination

	# turn the route into a hash table? does this actually do anything?
	my %routeHash = @route;

	# check to see if the map we're in appears more than 1 time in the route
	my $step;
	my $doubleRouteCheck = 0;

	# check for duplicate
	while(@route)
	{
		$step = pop(@route);

		if($step eq $field->baseName)
		{
			$doubleRouteCheck++;
		}

=pod
		last if($field->baseName eq $destination); #if for whatever reason we're at the dest, don't warp

		if(!exists $maps{$step})
		{
			print "$step is not in list!\n";
		}
		next unless (exists $maps{$step}); # not in the list
		next if ($field->baseName eq $step); # don't TP if it's the map we're on

		print "$step is in the list!\n";

		sendMessage($messageSender, "p", "\@go $step");
		undef @route;
=cut
	}

	if($doubleRouteCheck > 1)
	{
		#sendMessage($messageSender, "p", "Shit, the pathfinding is broken!!!!!");

		error "[routeFixer] Shit, the pathfinding is broken!!!!!\n";

		# emotion 53
		$messageSender->sendEmotion(53);

		# need to get the SECOND map route and use that
		my @fullRoute = split(' -> ', $args->{fullRoute});

		# incoming data is in the format of...
		# prontera 35 208 -> aldebaran 140 135 -> c_tower1

		while(@fullRoute)
		{
			$step = pop(@fullRoute);

			# split it again
			my @pieces = split(' ', $step);

			# need to know what these pieces look like

			#print "Got here, should be printing something\n";

			#print Dumper(@pieces);

			#Got here, should be printing something
			#$VAR1 = 'thor_v01';
			#Got here, should be printing something
			#$VAR1 = 've_fild03';
			#$VAR2 = '168';
			#$VAR3 = '240';
			#Got here, should be printing something
			#$VAR1 = 've_fild04';
			#$VAR2 = '44';
			#$VAR3 = '249';
			#Got here, should be printing something
			#$VAR1 = 've_fild03';
			#$VAR2 = '355';
			#$VAR3 = '223';

			if($pieces[0] eq $field->baseName)
			{
				# ok, we're got the correct routing here (i think)
				# so route to that

				AI::clear(qw/move route mapRoute/);

				# maybe grab the args from the old route before deleting it?

				# Move
				ai_route(
					$field->baseName,
					$pieces[1],
					$pieces[2],
					attackOnRoute => 2, # consider changing this to $config{"attackAuto"}
					isRandomWalk => $field->baseName eq $config{'lockMap'},
					isToLockMap =>  $field->baseName ne $config{'lockMap'},
					isFollow => AI::inQueue("follow"),
					#isEscape => 1,
					#maxTime => 5,
					#distFromGoal => 1 #{followDistanceMin}
				);

				#attackOnRoute => 2,
				#isFollow => 1,
				#isRandomWalk => 0, #$field->baseName eq $config{'lockMap'},
				#isToLockMap =>  1, #$field->baseName ne $config{'lockMap'},

				#sendMessage($messageSender, "p", "Trying to route to ".$pieces[1].",".$pieces[2]." instead!");
				message TF("[routeFixer] Trying to route to ".$pieces[1].",".$pieces[2]." instead!"), "teleport";

				$mytimeout = time;

				last;
			}

		}
	}

	# somehow need to check to see if we're going to a single map multiple times

	# check to see if we're going to our CURRENT MAP multiple times
	# if we ARE, use the SECOND destination and force a route to that instead
}

return 1;
