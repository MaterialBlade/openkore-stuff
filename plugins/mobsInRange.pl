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




package mobsInRange;

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

use AI;
use Actor;

Plugins::register('condition: mobsInRange', 'extends skill condition to check for mobs in range', \&onUnload); 
my $hooks = Plugins::addHooks( 
	['checkMonsterCondition', \&checkInRange, undef], 
);

message "Check Mob Range successfully loaded.\n", "success";

sub onUnload {
    Plugins::delHooks($hooks);
}

sub onReload {
    &onUnload;
}

sub checkInRange { 
    my (undef,$args) = @_;
	my @agMonsters;
	my %rangeArgs;
	my $currentTarget;
		
	return 0 if !$args->{monster} || $args->{monster}->{nameID} eq ''; 
	
	if ($config{$args->{prefix} . '_mobsInRange'}){
		($rangeArgs{'dist_'}, $rangeArgs{'mon_count'}) = split / *, */, $config{$args->{prefix} . '_mobsInRange'};

		$currentTarget = $args->{monster};
		my $monsterpos = calcPosition($args->{monster},2);
		my $monsterrr = $monstersList->getByID($args->{monster}->{ID});
		#my @names = keys $args;
		#message "Args: @names\n";
		#message "Monster: $monsterrr\n";
		#message "Current Target: $currentTarget\n";
		#message "Current Target: $args->{targetID}\n";
		#message "Curr_TargetPOS: $monsterpos->{x} , $monsterpos->{y}\n";
		
		foreach my $monster (@{$monstersList->getItems()}) {
			my $ID2 = $monster->{ID};
			next if $ID2 eq $currentTarget;
			my $monstersLocation =calcPosition($monsters{$ID2});
			#message "DistanceMin: $rangeArgs{dist_}\n";
			if (distance($monstersLocation,$monsterpos) <= $rangeArgs{dist_}) {
				my $boobs = distance($monstersLocation,$monsterpos);
				#message "Dist: $boobs\n";
				push @agMonsters, $ID2;
			}
		}
		
		my $agMonLength = $#agMonsters + 1;
		#my $agMonLength = @agMonsters;
		#message "Array Length: $agMonLength  MinCount: $rangeArgs{mon_count}\n";
		if($agMonLength < $rangeArgs{mon_count}){
			#message "You can't cast\n";
			#message "You can't cast\n";
			undef %rangeArgs;
			$args->{return} = 0;
		}
	}

	# this v is a different block! this checks to see if there AREN'T any monsters in range target
	if ($config{$args->{prefix} . '_noMobsInRange'}){
		($rangeArgs{'dist_'}, $rangeArgs{'mon_count'}) = split / *, */, $config{$args->{prefix} . '_noMobsInRange'};

		$currentTarget = $args->{monster};
		my $monsterpos = calcPosition($args->{monster},2);
		my $monsterrr = $monstersList->getByID($args->{monster}->{ID});
		
		foreach my $monster (@{$monstersList->getItems()}) {
			my $ID2 = $monster->{ID};
			next if $ID2 eq $currentTarget;
			my $monstersLocation =calcPosition($monsters{$ID2});
			if (distance($monstersLocation,$monsterpos) <= $rangeArgs{dist_}) {
				my $boobs = distance($monstersLocation,$monsterpos);
				push @agMonsters, $ID2;
			}
		}
		
		my $agMonLength = $#agMonsters + 1;
		if($agMonLength > $rangeArgs{mon_count}){
			undef %rangeArgs;
			$args->{return} = 0;
		}
	}
	return 1; 
} 

return 1;
