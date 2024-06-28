############################ 
# refreshNPCAttack plugin for OpenKore MaterialBlade
# 
# Will use @refresh if attacked by an enemy called "NPC"
#
# Use:
# Add 'refreshNPCAttack 1' to your config
############################ 




package refreshNPCAttack;

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

Plugins::register('refreshNPCAttack', 'do an [at]refresh when you get attack by an NPC!', \&onUnload); 
my $hooks = Plugins::addHooks(
	['packet_attack', \&onPacketAttack, undef],
);

message "refreshNPCAttack successfully loaded.\n", "success";

my $chance_timeout; #we don't use $args->{move_timeout}, we have to make our own

sub onUnload {
    Plugins::delHooks($hooks);
}

sub onReload {
    &onUnload;
}

sub onPacketAttack
{
	return unless ($config{"refreshNPCAttack"});

	my (undef,$args) = @_;

	my $source = Actor::get($args->{sourceID});

	my $attackerName = substr($source->nameString, 0,3);

	if($attackerName eq "NPC")
	{
		# an enemy is attacking SOMEONE but they're classified as an NPC so we need to refresh
		error "betterFollow: An 'NPC' is attacking someone so we need to refresh.\n";
		sendMessage($messageSender, "p", "\@refresh"); 
	}
}


return 1;