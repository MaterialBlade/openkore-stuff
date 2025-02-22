############################ 
# stuckRouteShuffle plugin for OpenKore MaterialBlade
# 
# Bot will try to shuffle to a nearby open cell when it gets stuck
#
# Use:
# Add 'stuckRouteShuffle 1' to your config
############################ 

package stuckRouteShuffle;

use strict;
use Config;
eval "no utf8;";
use bytes;
use Globals;
use Modules;
use Settings;
use Log qw(message warning error debug);
use Interface;
use Commands;
use Misc;
use Plugins;
use Utils;
use ChatQueue;
use AI;
use Actor;

Plugins::register('stuckRouteShuffle', 'move to a new position when you can\'t reach your target', \&onUnload); 
my $hooks = Plugins::addHooks(
	['route', \&stuckRoute, undef],
	['AI_post', \&ai_post, undef],
);

message "stuckRouteShuffle successfully loaded.\n", "success";

sub onUnload {
    Plugins::delHooks($hooks);
}

sub onReload {
    &onUnload;
}

my $gotStuckPos;
sub stuckRoute {
	my (undef,$args) = @_;
	
	return unless $config{"stuckRouteShuffle"};
	return if $char->{dead};

	# don't think i even need to check status since this only gets called if we're stuck? unless route gets called in mutple places...
	if(defined $args->{status} and $args->{status} eq "stuck")
	{
		return if (AI::action eq "NPC");
		return if (AI::inQueue("NPC"));
		return if ($char->statusActive('EFST_STOP'));

		# should be getting the route destination, not the char position methinks
		# ->{dest}{pos}{x}
		my @stand;

		if(AI::action eq "route" and defined AI::args(0)->{dest})
		{
			@stand = calcRectArea2(AI::args(0)->{dest}{pos}{x}, AI::args(0)->{dest}{pos}{y},1,0);
			print "using new routeargs\n";
		}
		else
		{
			@stand = calcRectArea2($char->{pos_to}{x}, $char->{pos_to}{y},1,0);
			print "using old stand\n";
		}

		# do a move thing
		#my @stand = calcRectArea2($char->{pos_to}{x}, $char->{pos_to}{y},1,0);
		my $i = int(rand @stand);
		my $spot = $stand[$i];
		#$char->sendMove($spot);

		if($field->isWalkable($spot->{x}, $spot->{y})
		and $field->checkLOS(calcPosition($char), $spot, 0))
		{
			#ai_route($field->baseName, $3, $4, attackOnRoute => 1);
			#ai_route($field->baseName, $spot->{x}, $spot->{y});
			$gotStuckPos = $spot;
		}


		#sendMessage($messageSender, "p", "\@refresh");
		sendMessage($messageSender, "p", "I got stuck!");
	}
}

sub ai_post
{
	if(defined $gotStuckPos)
	{
		stand();

		print "Trying to fix stuck route, ".$gotStuckPos->{x}.",".$gotStuckPos->{y}."\n";
		AI::dequeue if (AI::action eq "route");
		ai_route($field->baseName, $gotStuckPos->{x}, $gotStuckPos->{y});
		undef $gotStuckPos;
	}
}


return 1;