############################ 
# devotionFlash plugin for Openkore
# 
# This software is open source, licensed under the GNU General Public Liscense
# Made by MaterialBlade, ya basterds
# -------------------------------------------------- 
#
# This plugin is a bandaid for Devotion not passing reflect shield, auto guard, and defender to targets
# is those statuses are already active. This basically tricks Kore into thinking it doesn't have those
# statuses active so it tries to cast them again.
#
# Use:
# Add 'devotionFlash 1' to your config
############################ 
package devotionFlash;

use Globals;
use Log qw(message warning error debug);
use Misc;
use Actor;
use Utils; # timeOut
use Data::Dumper;

Plugins::register("devotionFlash", "work around for Devotion being broken", \&on_unload, \&on_reload);

my $checkTimeout;
my $delay = 0;

my $aiHook = Plugins::addHooks(
	['packet_skilluse', \&skillUse, undef],
	['AI_post',       \&ai_post, undef],
	['is_casting', \&isCasting, undef],
);

sub on_unload {
	# This plugin is about to be unloaded; remove hooks
	Plugins::delHook($aiHook);
}

sub on_reload {
	&on_unload;
}

sub isCasting {
	return unless ($config{'devotionFlash'});
	#return 1 unless ($config{'autoFlagSetter'});

	#sourceID => $sourceID,
	#targetID => $targetID,
	#source => $source,
	#target => $target,
	#skillID => $skillID,
	#skill => $skill,
	#time => $source->{casting}{time},
	#castTime => $wait,
	#x => $x,
	#y => $y

	my (undef,$args) = @_;

	return unless $args->{sourceID} eq $accountID;
	return unless $args->{skillID} eq 255;

	undef $checkTimeout;
}

sub skillUse
{
	return unless ($config{'devotionFlash'});

	my (undef,$args) = @_;
	return unless $args->{sourceID} eq $accountID;
	return unless $args->{skillID} eq 255;

	$checkTimeout = time;
	$delay = defined $config{'devotionFlash_delay'} ? $config{'devotionFlash_delay'} : 1.5;
}

sub ai_post
{
	return unless ($config{'devotionFlash'});

	if(defined $checkTimeout and timeOut($checkTimeout, $delay))
	{
		$char->setStatus('EFST_AUTOGUARD', 0);
		$char->setStatus('EFST_DEFENDER', 0);

		undef $checkTimeout;
	}
}

1;
