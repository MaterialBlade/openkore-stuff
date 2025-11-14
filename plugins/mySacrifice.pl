############################ 
# mySacrifice plugin for Openkore
# 
# This software is open source, licensed under the GNU General Public Liscense
# Made by MaterialBlade, ya basterds
# -------------------------------------------------- 
#
# Adds a condition for casting Sacrifice on yourself
# Also adds console command to see how many Sacrifice attacks you have left
#
# Use:
#
# Add 'needSacrifice 1' to your useSelSkill slot for Sacrifice
# Type 'sac' in console to see how many attacks you have left
#
############################ 
package mySacrifice;

use Globals;
use Log qw(message warning error debug);
use Misc;
use Actor;
use Utils; # timeOut
use Data::Dumper;

Plugins::register("mySacrifice", "keep track of how many Sacrifice attacks you have", \&on_unload, \&on_reload);

my $checkTimeout;
my $delay = 0;
my $sacCount = 0;

my $aiHook = Plugins::addHooks(
	['packet_skilluse', \&skillUse, undef],
	['checkSelfCondition', \&checkSelfCondition, undef],
);

my $commands_handle = Commands::register(
	['sac', 'check how many attacks of Sacrifice you have left', \&checkSac],
	['creed', '...', \&creed],
);

sub on_unload {
	# This plugin is about to be unloaded; remove hooks
	Plugins::delHook($aiHook);
	Commands::unregister($commands_handle);
}

sub on_reload {
	&on_unload;
}

sub checkSelfCondition
{
	my (undef,$args) = @_;

	if ($config{$args->{prefix} . "_needSacrifice"})
	{
		$args->{return} = 0;
		$args->{return} = 1 if($sacCount == 0);
	}
}

sub checkSac
{
	message "You have $sacCount Sacrifice attack(s) left\n", "selfSkill",
}

sub skillUse
{

	my (undef,$args) = @_;
	return unless $args->{sourceID} eq $accountID;

	# sacrifice detection
	if($args->{skillID} eq 368)
	{
		# casting on myself
		if($args->{sourceID} eq $args->{targetID}){
			$sacCount = 5;
		}
		# casting on target
		else
		{
			$sacCount--;
		}
	}
}

my $idx = 0;
my @lyrics = (
	"Hello, my friend, we meet again",
	"It's been a while, where should we begin?",
	"Feels like forever",
	"Within my heart are memories",
	"Of perfect love that you gave to me",
	"Oh, I rememberrrrrrrrr!",
	"When you are with me, I'm free!",
	"I'm careless, I believe!",
	"Above all the others, we'll fly!",
	"This brings tears to my eyes!",
	"My sacrifice...!"
);

sub creed
{
	return unless $field;

	sendMessage($messageSender, "c", $lyrics[$idx]);

	$idx++;
	$idx = 0 if($idx > scalar(@lyrics));
}

1;
