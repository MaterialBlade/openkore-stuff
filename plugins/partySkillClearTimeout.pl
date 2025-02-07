############################ 
# partySkillClearTimeout plugin for Openkore
#
# This plugin clears partySkill timeouts for a party member when they become dedge
#
# CONFIGURATION
# Add These Lines to config.txt:
# 
# partySkillClearTimeout [0|1]
#
# partySkillClearTimeout is a boolean. Set it to 0 to turn the plugin off. Set it to 1 to turn the plugin on.
#
# EXAMPLE CONFIG.TXT
# partySkillClearTimeout 1
#
############################ 
package partySkillClearTimeout;

use strict;
use Globals;
use Utils;
use Misc;
use Log qw(message warning error debug);
use Translation;
use Actor;
use Data::Dumper;
use Time::HiRes qw(time);

Plugins::register("partySkillClearTimeout", "clear timeouts on party member when they die", \&on_unload, \&on_reload);


# to check if the map list changed when reloading conf


my $aiHook = Plugins::addHooks(
	["packet_pre/party_dead", \&partyMemberDied, undef],
);

sub on_unload {
	# This plugin is about to be unloaded; remove hooks
	Plugins::delHook($aiHook);
}

sub on_reload {
	&on_unload;
}


sub partyMemberDied
{
	#return 1; # don't need this function for now'

	my ($self, $args) = @_;

	return unless $config{"partySkillClearTimeout"};

	if ($args->{isDead} == 1) {
		my %party_skill;
		for (my $i = 0; exists $config{"partySkill_$i"}; $i++) {
			next if (!$config{"partySkill_$i"});
			
			$party_skill{skillObject} = Skill->new(auto => $config{"partySkill_$i"});
			$party_skill{owner} = $party_skill{skillObject}->getOwner;

			my $prefix = "partySkill_$i"."_target";
			$ai_v{$prefix . "_time"}{$args->{ID}} = 0;
			$targetTimeout{$args->{ID}}{$party_skill{$args->{ID}}} = $i;
		}
	}
}

1;
