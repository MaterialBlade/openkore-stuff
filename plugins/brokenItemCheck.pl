############################ 
# brokenItemCheck plugin for Openkore
# 
# This software is open source, licensed under the GNU General Public Liscense
# Made by MaterialBlade, ya basterds
# -------------------------------------------------- 
#
# This plugin checks for broken gear when something is equipped, and says a message in party chat about needing repairs
#
############################ 
package brokenItemCheck;

use Globals;
use Log qw(message warning error debug);
use Misc;
use Actor;
use Utils; # timeOut
use Data::Dumper;

Plugins::register("brokenItemCheck", "check for broken items when stuff gets unequipped", \&on_unload, \&on_reload);

my $checkTimeout;
my $temp_ItemName;
my $delay = 2;

my $aiHook = Plugins::addHooks(
	['unequipped_item', \&onUnequip, undef], 
	['AI_post',       \&ai_post, undef],
);

#	TODO
#		- hook into item unequipping. when item unequipped set a "check for broken" variable / timeout
#		- search through char inventory / gear(?) looking for gear with the name BROKEN at the start
#		- if found broken gear, say "I need repairs" in party chat
#
#	FUTURE STUFF
#		- add the broken item name to item control so it doesn't get storage
#
#
#

sub on_unload {
	# This plugin is about to be unloaded; remove hooks
	Plugins::delHook($aiHook);
}

sub on_reload {
	&on_unload;
}

sub onUnequip
{
	# Plugins::callHook('unequipped_item', {slot => $equipSlot_lut{$_}, item => $item});
	my (undef,$args) = @_;

	#print $args->{item}." was unequipped \n";
	#print Dumper($args->{item}->{name});

	$checkTimeout = time;
}

sub ai_post
{
	my $needRepairs = 0;

	if(defined $checkTimeout and timeOut($checkTimeout, $delay))
	{
		# loop through player inventory, looking for items with BROKEN name
		for my $item (@{$char->inventory}) {

			my $shortString = substr($item->{name}, 0, 6);
			#print $shortString."\n";

			if($shortString eq "BROKEN")
			{
				#print "Someone broke my ".$item->{name}."! >:0 \n";
				#sendMessage($messageSender, "p", "I need repairs");

				$needRepairs = 1;

				#sendMessage($messageSender, "p", "Someone broke my ".$item->{name}."! >:0");

				# just do the iconf anyways since it's only if they're broken
				Commands::run("do iconf ".$item->{name}." 1 0 0"); # TODO: confirm this actually works
			}
		}

		if($needRepairs eq 1)
		{
			$checkTimeout = time + 60;
			sendMessage($messageSender, "p", "I need repairs");
		}
		else
		{
			undef $checkTimeout;
		}
	}
}

1;
