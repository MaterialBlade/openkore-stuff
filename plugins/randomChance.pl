############################ 
# mobsInRange plugin for OpenKore by theDrops(2014) 
# 
# This software is open source, licensed under the GNU General Public Liscense
# Special thanks to kaliwanagan and Damokles for reference
# -------------------------------------------------- 
#
# This plugin hooks into checkMonsterCondition in Misc.pm
# It get's your current attack target, searches for monsters within a certain distance, then returns
# If the number of monsters within that distance are >= to the number specified, the skill block will cast
#
# Use:
# Add 'target_mobsInRange [distance],[# of enemies] to attackSkillSlot
# ie target_mobsInRange 8,6
# Will cast when there are 6+ monsters within 8 distance of the target
############################ 




package randomChance;

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

Plugins::register('condition: randomChance', 'get some RNG in those skill uses', \&onUnload); 
my $hooks = Plugins::addHooks( 
	['checkSelfCondition', \&checkRandom, undef], 
);

message "Check RandomChance successfully loaded.\n", "success";

my $chance_timeout; #we don't use $args->{move_timeout}, we have to make our own

sub onUnload {
    Plugins::delHooks($hooks);
}

sub onReload {
    &onUnload;
}

#$mytimeout->{'heal_player'}{$target} = time+0.2;

sub checkRandom { 
    my (undef,$args) = @_;
	
	if ($config{$args->{prefix} . '_random'}){
		$args->{return} = 0;
		
		if(timeOut($chance_timeout->{'words'}{$args->{prefix}},0.75)){
			$chance_timeout->{'words'}{$args->{prefix}} = time;
			my $chance = int(rand(100));			
			#message TF("Rolled %s, needed less than %s\n", $chance, $config{$args->{prefix} . '_random'}), "randomChance";
			if ($chance < int($config{$args->{prefix} . '_random'})){
				$args->{return} = 1;
			}
		}
	}
	return 1; 
} 

return 1;