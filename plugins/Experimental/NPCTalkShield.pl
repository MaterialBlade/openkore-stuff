############################ 
# NPCTalkShield plugin for OpenKore by MaterialBlade
# 
# This software is open source, licensed under the GNU General Public Liscense
# -------------------------------------------------- 
#
# This plugin prevents using Skills when talking to an NPC so it doesn't break the AI
#
#
# TODO: Check for other stuff that might break the queue
# TODO: Clean up unneeded 'uses'
# TODO: make sure this doesn't break AI::MANUAL
#
############################ 




package NPCTalkShield;

use strict;
use Time::HiRes qw(time usleep);
use IO::Socket;
use Text::ParseWords;
use Config;
eval "no utf8;";
use bytes;

use Globals;
use Modules;
use Settings;
use Log qw(message warning error debug);
use FileParsers;
use Interface;
use Network::Receive;
use Network::Send;
use Commands;
use Misc;
use Plugins;
use Utils;
use ChatQueue;
use Translation qw(T TF);

use AI;
use Actor;

Plugins::register('NPCTalkShield', 'prevent talking to an NPC in \'route\' from breaking', \&onUnload); 
my $hooks = Plugins::addHooks( 
	['checkSelfCondition', \&NPCGuard, undef],
	['checkPlayerCondition', \&NPCGuard, undef],
	['checkMonsterCondition', \&NPCGuard, undef],
);

message "NPCTalkShield successfully loaded.\n", "success";

sub onUnload {
    Plugins::delHooks($hooks);
}

sub onReload {
    &onUnload;
}

my $mytimeouts;

sub printMessage
{
	return unless timeOut($mytimeouts->{"printMsg"}, 1.5);

	my $message = shift;
	$mytimeouts->{"printMsg"} = time;
	#sendMessage($messageSender, "p", $message);
	print $message;
}

sub NPCGuard
{
	my (undef,$args) = @_;

	# return unless AI::state == AI::AUTO;

	if(AI::action(0) eq "route")
	{
		if(NPCTalk_Shield())
		{
			$args->{return} = 0;
		}

		#my $task = AI::args;  #<-- THIS is the task????!!!
		#
		#if ($task && $task->isa('Task::TalkNPC')) {  
		#	$args->{return} = 0;
		#	printMessage("[NPCTalkShield] Got here in checkPlayerCondition");
		#
		#}
	}
}

sub NPCTalk_Shield
{
	if(AI::action(0) eq "route")
	{
		#my $task = AI::args;  #<-- THIS is the task????!!!
		#my $task = $args->{task};

		if (AI::action(0) eq 'route' && defined(AI::args(0)->getSubtask()))
		{
			my $routeArgs = AI::args(0);
			my $routeTask = $routeArgs->getSubtask;

			if ($routeTask && $routeTask->isa('Task::TalkNPC')) {  
				#$args->{return} = 0;
				printMessage("[NPCTalkShield] NPCTalkShield triggered\n");
				#sendMessage($messageSender, "p", "TalkNPC guard tripped");
				return 1;
			}
		}
	}

	return 0;
}

return 1;
