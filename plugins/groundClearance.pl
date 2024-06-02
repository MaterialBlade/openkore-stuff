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




package groundClear;

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

Plugins::register('condition: groundClear', 'checks if the ground is Clear or NotClear of a ground effect', \&onUnload); 
my $hooks = Plugins::addHooks( 
	['checkSelfCondition', \&checkGroundSelf, undef],
	['checkPlayerCondition', \&checkGroundPlayer, undef],
	['checkMonsterCondition', \&checkGroundEnemy, undef],
);

message "Check groundClear successfully loaded.\n", "success";

sub onUnload {
    Plugins::delHooks($hooks);
}

sub onReload {
    &onUnload;
}

#$mytimeout->{'heal_player'}{$target} = time+0.2;

sub checkGroundSelf { 
    my (undef,$args) = @_;
	
	# this returns 1 if the status ISN'T there (or rather, returns 0 if it is)
	if ($config{$args->{prefix}."_whenGroundInactive"}) {
		# this is the version WITHOUT my extension
		#if(whenGroundStatus(calcPosition($char), $config{$args->{prefix}."_whenGroundInactive"}))
		if(extendedWhenGroundStatus(calcPosition($char), $config{$args->{prefix}."_whenGroundInactive"}))
		{
			#print "ground not clear\n";
			$args->{return} = 0;
		}
	}
	
	# this returns 1 if the status IS there (or rather, returns 0 if it isn't there)
	if ($config{$args->{prefix}."_whenGroundActive"}) {
		if(!extendedWhenGroundStatus(calcPosition($char), $config{$args->{prefix}."_whenGroundActive"}))
		{
			#print "this means the specified status is NOT there. what a backwards way to write it\n";
			$args->{return} = 0;
		}
	}

	if ($config{$args->{prefix}."_extendedWhenGround"}) {
		$args->{return} = 0 unless extendedWhenGroundStatus(calcPosition($char), $config{$args->{prefix}."_extendedWhenGround"});
	}

	if ($config{$args->{prefix}."_extendedWhenNotGround"}) {
		$args->{return} = 0 if extendedWhenGroundStatus(calcPosition($char), $config{$args->{prefix}."_extendedWhenNotGround"});
	}
	
	return 1; 
} 

sub checkGroundPlayer { 
    my (undef,$args) = @_;
	
	# this returns 1 if the status ISN'T there (or rather, returns 0 if it is)
	if ($config{$args->{prefix}."_whenGroundInactive"}) {
		if(extendedWhenGroundStatus(calcPosition($args->{player}), $config{$args->{prefix}."_whenGroundInactive"}))
		{
			#print "ground not clear\n";
			$args->{return} = 0;
		}
	}
	
	# this returns 1 if the status IS there (or rather, returns 0 if it isn't there)
	if ($config{$args->{prefix}."_whenGroundActive"}) {
		if(!extendedWhenGroundStatus(calcPosition($args->{player}), $config{$args->{prefix}."_whenGroundActive"}))
		{
			#print "this means the specified status is NOT there. what a backwards way to write it\n";
			$args->{return} = 0;
		}
	}

	if ($config{$args->{prefix}."_extendedWhenGround"}) {
		$args->{return} = 0 unless extendedWhenGroundStatus(calcPosition($args->{player}), $config{$args->{prefix}."_extendedWhenGround"});
	}

	if ($config{$args->{prefix}."_extendedWhenNotGround"}) {
		$args->{return} = 0 if extendedWhenGroundStatus(calcPosition($args->{player}), $config{$args->{prefix}."_extendedWhenNotGround"});
	}
	
	return 1; 
}

sub checkGroundEnemy { 
    my (undef,$args) = @_;
	
	# this returns 1 if the status ISN'T there (or rather, returns 0 if it is)
	if ($config{$args->{prefix}."_whenGroundInactive"}) {
		if(extendedWhenGroundStatus(calcPosition($args->{monster}), $config{$args->{prefix}."_whenGroundInactive"}))
		{
			#print "ground not clear\n";
			$args->{return} = 0;
		}
	}
	
	# this returns 1 if the status IS there (or rather, returns 0 if it isn't there)
	if ($config{$args->{prefix}."_whenGroundActive"}) {
		if(!extendedWhenGroundStatus(calcPosition($args->{monster}), $config{$args->{prefix}."_whenGroundActive"}))
		{
			#print "this means the specified status is NOT there. what a backwards way to write it\n";
			$args->{return} = 0;
		}
	}

	if ($config{$args->{prefix}."_extendedWhenGround"}) {
		$args->{return} = 0 unless extendedWhenGroundStatus(calcPosition($args->{monster}), $config{$args->{prefix}."_extendedWhenGround"});
	}

	if ($config{$args->{prefix}."_extendedWhenNotGround"}) {
		$args->{return} = 0 if extendedWhenGroundStatus(calcPosition($args->{monster}), $config{$args->{prefix}."_extendedWhenNotGround"});
	}
	
	return 1; 
}

sub extendedWhenGroundStatus {
	my ($pos, $statuses, $mine) = @_;

	my ($x, $y) = ($pos->{x}, $pos->{y});
	for my $ID (@spellsID) {
		my $spell;
		next unless $spell = $spells{$ID};
		next if $mine && $spell->{sourceID} ne $accountID;

		# continue unless the spell we're checking is in the list

		my $spellName = getSpellName($spell->{type});

		#print "got here minus 1\n";
		next unless existsInList($statuses, $spellName);

		# now we need to check if that spells' ORIGIN is in within distance. To do this we'll do an "if/else" for the important ones

		# original code
		#if ($x == $spell->{pos}{x} &&
		#    $y == $spell->{pos}{y}) {
		#	return 1 if existsInList($statuses, getSpellName($spell->{type}));
		#}
		#print "got here 0\n";

		# if we're standing on it, no need for checks
		if ($x == $spell->{pos}{x} &&
			$y == $spell->{pos}{y}) {
			return 1;
		}

		#print "got here 1\n";

		# i hate that I have to make a new reference just for this...
		my $spellPos;
		$spellPos->{x} = $spell->{pos}{x};
		$spellPos->{y} = $spell->{pos}{y};

		#if($spellName eq "Pneuma" && distance($pos, $spellPos) <= 2) # 133, Pneuma
		if($spell->{type} eq 133 && distance($pos, $spellPos) < 3) # 133, Pneuma
		{
			#print "got here 2\n";
			return 1;
		}

		# this might not COUNT??? not sure if Storm Gust is counted as a 'spell'
		#if($spellName eq "Storm Gust" && distance($pos, $spellPos) <= 2) # 89, Storm Gust
		if($spell->{type} eq 89 && distance($pos, $spellPos) <= 2) # 89, Storm Gust
		{
			return 1;
		}

		#if($spellName eq "Demonstration" && distance($pos, $spellPos) <= 2) # 177, Demonstration
		if($spell->{type} eq 177 && distance($pos, $spellPos) <= 2) # 177, Demonstration
		{
			return 1;
		}
	}
	return 0;
}

return 1;
