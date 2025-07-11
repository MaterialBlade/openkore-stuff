############################ 
# botPartyGo plugin for Openkore
# 
############################ 
package botPartyGo;

use strict;
use Globals;
use Utils;
use Misc;
use Log qw(message warning error debug);
use Translation;
use Actor;
use AI;
use Data::Dumper;
use Time::HiRes qw(time);
use feature "switch";

Plugins::register("botPartyGo", "plugin for remote automatic party play", \&on_unload, \&on_reload);

use constant {
	OFFLINE_RECHECK => 120, # 120s * 2 = 4 minutes for someone to reconnect
	WEIGHT_RECHECK => 20,
	BROADCAST_TIMEOUT => 120,
	TRUE => 1,
	FALSE => 0,
 	ANSWER_JOIN_ACCEPT => 2,
};

my $myTimeouts;
my %partyStoredLevel;
my @offlineCheckList = ();
my $offlineCheckLeader = FALSE;
my $queueUpdatePartyRange = FALSE;

#use Scalar::Util qw(looks_like_number);

=pod

=== WHAT DOES THIS NEED TO WORK ===

-- PARTY LEADER --
	- PARTY LEADER ANNOUNCING OPEN PARTY (Global Chat) // DONE
	- PARTY LEADER MANAGE PARTY MEMBERS (invite / kick / etc)
		-> invite //DONE
		-> kick // still need to figure out how leveling up and breaking share range works

-- PARTY MEMBER --
	- PARTY MEMBERS IDLE STATE -> waiting for a party to join? (Maybe they hang out in pront when not in party)
	- PARTY MEMBERS LOOKING FOR OPEN PARTY (Global Chat)
	- PARTY MEMBERS UPDATE FOLLOW TARGET (Who? How? etc)
	- PARTY QUALITY CHECK?
		-> if you're dying too often, leave PARTY (optional)
		-> if you aren't going anywhere (same map), leave PARTY (optional)
		-> if the party share settings aren't what you want, leave PARTY (optional)

-- PARTY FUNCTIONALITY --
	- RESUPPLY - Characters asking to go back to town for stuff, sell, storage // DONE (Kinda)
	- NEED A WAY TO GROUP UP / ASK FOR SHUFFLE - when characters don't have a spot to move to
	- //DONE - LEVEL RANGE CHECK? -- devotion is 10 levels, xp share is 15 levels
		-> party settings (set by leader)
	- TIMEOUT FOR OFFLINE BEFORE KICKING / TIMEOUT FOR OFFLINE (LEADER) BEFORE LEAVING
		-> if a party member is offline for too long, kick them // DONE
		-> if party leader is offline for too long, leave
	- PARTY ROLES?
		-> tank, ranged-phys, priest, prof, other?

-- PARTY CHAT... CHAT --
	- "I need mana!" if there is a prof in the PARTY
	- "Mana break please!" if there ISN'T a prof in the PARTY
	- "Heal Me!" queue a heal on this Character
	- "Where is Party Leader?" <RC map,x,y>
		-> 'RC' is a response code that we can use to parse party messages
		-> alternatively, instead of writing out the questions, use a QC (Question Code)

-- PARTY PERFORMANCE / CONFIG --
	- TODO: add a setting for if the party IS set to be shared XP or not. If it's not, we don't need to kick. TBD
	- being able to cast buffs on certain allies
	- casting Devotion on allies
		-> not changing configuration files. being able to set it up beforehand and it just WORKS in the party
	- Assumptio and Kyrie
	- Pneuma screws over ranged classes
	- Multiple Performers of same class (Clown & Clown)
	- Blacksmith / Whitesmith using Power Thrust
		-> if a character uses power thrust they get kicked immediately
	- Wizard Ice Wall
		-> if a character uses Ice Wall they get kicked (maybe)
	- If you're a super novice, you get kicked immediately

	- when a party member levels up, have them say they leveled up so that the party range can be immediately updated
		-> also if the share range is now broken, kick somebody (figure out who to kick... maybe the person who leveld?)

	- not getting resurrected
	- dying and getting left behind

	- getting left behind (in general)

-- TBD / LOW PRIO --
- TBD OUTSIDE party info
- TBD Rules for sharing XP / Items
- Some way to have your characters stick together (2 chars wanting to join a party with 11 people)

=cut

=pod
	#### PHASE 1 ####

	~~~ PARTY LEADER ~~~
	- Respond to someone asking for party
		=> need a config to designate this bot / character as the leader of a party
		=> MSG: Broadcast active party level range
	- Invite person to party
		=> RCV: Receive party request, send invite
	- Broadcast that party is OPEN when there are member slots, can do this on TIMEOUT or at certain times

	~~~ PARTY MEMBER ~~~
	- Search for party / Ask for peeps online
		=> need a config to designate this bot / characters as the MEMBER of a party
		=> MSG: Ask for active parties
		=> RCV: receive / process party leader broadcast
			--> send request if applicable
			--> or ignore

	- Accept party invite (this should be a conf setting, not plugin dependant)

=cut

=pod
	### CONFIG SETTINGS ###

	~~~ GENERAL ~~~
	- botPartyGo [1] - enables the plugin

	~~~ PARTY LEADER ~~~
	- BPG_isPartyLeader [0/1] - designates this character as the leader of a party

	~~~ PARTY MEMBER ~~~
	- BPG_isPartyMember [0/1] - designates this character as the member of a party

=cut

my $aiHook = Plugins::addHooks(
	['packet_skilluse', \&skillUse, undef],
	['is_casting', \&isCasting, undef],
	['npc_chat', \&npcMsg, undef],
	["packet_pre/party_chat", \&partyMsg, undef],

	# TODO: confirm what this is for
	# check for a following target when joining a party
	["packet_pre/party_join", \&partyJoin, undef],
	["packet_pre/party_users_info", \&partyUsersInfo, undef],
	["packet_pre/party_invite_result", \&party_invite_result, undef],
	["packet_pre/party_leave", \&party_leave, undef],
	["packet_pre/actor_info", \&actor_info, undef],

	#Plugins::callHook('npc_chat', {
	#['monster_disappeared', \&monsterDisappeared, undef],
	#['checkPlayerCondition', \&checkPlayerCondition, undef],
	#['checkSelfCondition', \&checkSelfCondition, undef],
	#['checkMonsterCondition', \&checkMonCondition, undef],
	["AI_pre", \&ai_pre, undef],
	['AI_post',       \&ai_post, undef],
);

my $commands_handle = Commands::register(
	#['setflag', 'sets the entered flag and value', \&setFlag],
);

sub on_unload {
	# This plugin is about to be unloaded; remove hooks
	Plugins::delHook($aiHook);
}

sub on_reload {
	&on_unload;
}

# TODO
# autoFlag_set Land Protector
# autoFlag_clearOnSkill Land Protector
#
#
#

sub actor_info
{
	#my (undef,$args) = @_;
	print "~~~~~~~~~~~~~~~ Got here actor_info!\n";

}

=pod
	PARTY JOIN WATERFALL

	Got here partyUsersInfo!
	Got here party join!
	Got here party_invite_result!
	Got here party_leave!

=cut

sub party_leave
{
	#my (undef,$args) = @_;
	print "~~~~~~~~~~~~~~~ Got here party_leave!\n";

	return unless $config{"BPG_isPartyLeader"};

	# have to queue this update to do it in ai_post, because updating in the actual reject packet sets the wrong levels
	$queueUpdatePartyRange = TRUE;
}

sub party_invite_result
{
	return unless $config{"BPG_isPartyLeader"};

	my (undef,$args) = @_;
	my $type = $args->{type};
	print "~~~~~~~~~~~~~~~ Got here party_invite_result!\n";

 	# Trigger for when someone joins the party
	my $name = $args->{name};
	
	if ($type == ANSWER_JOIN_ACCEPT)
 	{
	message "[botPartyGo] Party invite accepted by $name\n", "success";
 	# TODO: Check level of new party member vs the level range?
	}
}

sub partyUsersInfo
{
	my (undef,$args) = @_;

	# keys => [qw(ID GID name map admin online jobID lv)],

=pod
          'playerInfo' => '·à▲ L☻ tutorial thief          morocc.gat        ♠ % DÅ▲ ²W☻ tutorial aco            morocc.gat      ☺☺♦ # ',
          'party_name' => 'FieldPartyTest',
          'len' => 136,
          'RAW_MSG_SIZE' => 136,
          'switch' => '0AE5',
          'RAW_MSG' => 'σ
ê FieldPartyTest          ·à▲ L☻ tutorial thief          morocc.gat        ♠ % DÅ▲ ²W☻ tutorial aco            morocc.gat      ☺☺♦ # ',
          'KEYS' => [
                      'len',
                      'party_name',
                      'playerInfo'
                    ]
=cut

	print "~~~~~~~~~~~~~~~ Got here partyUsersInfo!\n";
	#sendMessage($messageSender, "p", "partyUsersInfo got here!");

	return unless $config{"BPG_isPartyLeader"};

	#my $currentMin = getPartyLevelRangeMin();
	#my $currentMax = getPartyLevelRangeMax();

	print "~~~~~~~~ current min~max is ".$partyStoredLevel{min}."~".$partyStoredLevel{max}."\n";

	#print Dumper($args->{playerInfo});
}

sub partyJoin
{
	return unless $config{"botPartyGo"};
	return unless $config{"BPG_isPartyLeader"};

	my (undef,$args) = @_;
	return unless $char->{'party'}{'users'}{$args->{ID}};

	print "~~~~~~~~~~~~~~~~~~ Got here party join!\n";

	#my $minLvl = getPartyLevelRangeMin();
	#my $maxLvl = getPartyLevelRangeMax();

	my $minLvl = $partyStoredLevel{min};
	my $maxLvl = $partyStoredLevel{max};

	if($args->{lv} < $minLvl || $args->{lv} > $maxLvl)
	{
		#outside of level range, kick their ass out
		print $args->{user}."(".$args->{lv}.") is NOT within the range of $minLvl ~ $maxLvl! Kick them out!\n";
		Commands::run("party kick ".$args->{user});
	}
	else
	{
		print $args->{user}."(".$args->{lv}.") is within the range of $minLvl ~ $maxLvl!\n";
		UpdatePartyLevelRange();
	}

	#print Dumper($args);

	#$VAR1 = {
	#          'ID' => 'DÅ▲ ',
	#          'x' => 109,
	#          'item_pickup' => 1,
	#          'lv' => 26,
	#          'map' => 'moc_fild12.gat',
	#          'y' => 169,
	#          'RAW_MSG_SIZE' => 89,
	#          'user' => 'tutorial aco',
	#          'KEYS' => [
	#                      'ID',
	#                      'charID',
	#                      'role',
	#                      'jobID',
	#                      'lv',
	#                      'x',
	#                      'y',
	#                      'type',
	#                      'name',
	#                      'user',
	#                      'map',
	#                      'item_pickup',
	#                      'item_share'
	#                    ],
	#          'name' => 'FieldPartyTest',
	#          'charID' => '²W☻ ',
	#          'jobID' => 4,
	#          'switch' => '0AE4',
	#          'type' => 0,
	#          'item_share' => 1,
	#          'role' => 1,
	#          'RAW_MSG' => 'Σ
	#DÅ▲ ²W☻ ☺   ♦ → m ⌐  FieldPartyTest          tutorial aco            moc_fild12.gat  ☺☺'

	#sendMessage($messageSender, "p", "Party join got here!");
}

sub checkMonCondition
{
	my (undef,$args) = @_;

	#print "butt pirates\n";

	return 1; 
}

sub checkSelfCondition
{
	my (undef,$args) = @_;

	return 1; 
}

sub checkPlayerCondition {
	my (undef,$args) = @_;

	#my %args = (
	#	player => $player,
	#	prefix => $prefix,
	#	return => 1
	#);

	return 1; 
}

sub npcMsg
{
	return unless $config{"botPartyGo"};

	my (undef,$args) = @_;
	my ($msg, $msg2, $ret, $name, $message);

	#print Dumper($args);


	#     'ID' => '    ',
	#     'message' => '[Global] tutorial thief (): hello world',
	#     'actor' => bless( {
	#                         'ID' => '    ',
	#                         'onNameChange' => bless( [], 'CallbackList' ),
	#                         'onUpdate' => bless( [], 'CallbackList' ),
	#                         'actorType' => 'Unknown',
	#                         'pos_to' => {},
	#                         'deltaHp' => 0,
	#                         'nameID' => 0
	#                       }, 'Actor::Unknown' )

	$msg = $args->{message};
	my @values = split(':', $msg);
	
	#chop($values[0]);
	substr($values[1], 0, 1) = '';

	#$name = $values[0];
	$name = substr($values[0], 9, -3);
	$message = $values[1];

	#print "$name is saying \"$message\"\n";

	given($message){

		# someone is search for a party
		when($_ =~ /(LFG) (\d+)/)
		{
			# someone is LFG, if we're the party leader, do some stuff
			if($config{"BPG_isPartyLeader"})
			{
				# STEP 1 - check if the party is full. If it's not, continue
				if(scalar(@partyUsersID) < 12
					and $2 <= $partyStoredLevel{max}
					and $2 >= $partyStoredLevel{min})
				{
					# we can Invite
					sendMessage($messageSender, "p", "sending a request to $name");
					Commands::run("party request $name");
				}
			}
		}
	}
}

sub partyMsg
{
	return unless $config{"botPartyGo"};
	#return 1 unless ($config{'botPartyGo'});

	my ($var, $arg, $tmp) = @_;
	my ($msg, $msg2, $ret, $name, $message);

	$msg = $arg->{message};
	my @values = split(':', $msg);
	
	chop($values[0]);
	substr($values[1], 0, 1) = '';
	
	$name = $values[0];
	$message = $values[1];

	#return if($char->{name} eq $name);

	#print "GOT THIS FAR\n";

	given($message){
		when("test")
		{
			continue unless isPartyLeader();

			$messageSender->sendEmotion(0); # !

			#print Dumper($char->{party}{users});

			my $maxLevel = getPartyLevelRangeMax();
			#my $maxLevel = $minLevel + 15;
			my $minLevel = getPartyLevelRangeMin();

			#print "GOT THIS FAR\n";

			sendMessage($messageSender, "p", "Actual level range is $minLevel ~ $maxLevel");
		}

		when("resupply")
		{
			# only the party leader can call for resupplying
			continue unless $name eq getPartyLeaderName();
			Commands::run("autobuy");
			Commands::run("autosell");
			Commands::run("autostorage");
		}
	}
}

sub isCasting {
	#return 1 unless ($config{'botPartyGo'});

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

	#print Dumper(\$args);
	#$args->{casting}->{skill}->{idn} # id number
}

sub skillUse
{
	#return 1 unless ($config{'botPartyGo'});

	return;

	# DON'T DO SHIT YET

	my (undef,$args) = @_;

	# if source is me
	if($args->{sourceID} eq $accountID)
	{

	}

	# if target is me
	if($args->{targetID} eq $accountID)
	{

	}
	#print Dumper(\$args);
}

sub monsterDisappeared
{
	my (undef,$args) = @_;

	#print Dumper(\$args);
}

sub ai_pre
{
	#return if !$char->{party}{joined};

	return unless $field;
	return unless $config{"botPartyGo"};

	if($config{"BPG_isPartyLeader"})
	{
		ai_pre_LEADER();
	}

	if($config{"BPG_isPartyMember"})
	{
		ai_pre_MEMBER();
	}
}

sub ai_pre_LEADER
{
	return unless ($char->{party}{joined});

	if(!%partyStoredLevel)
	{
		print "Shits not stored yall!\n";

		UpdatePartyLevelRange();
	}

	# check if there are empty party slots, if there are, send out a broadcast message
	if(scalar(@partyUsersID) < 12 and timeOut($myTimeouts->{'broadcast_spam'},BROADCAST_TIMEOUT))
	{
		$myTimeouts->{'broadcast_spam'} = time;

		#my $minLevel = getPartyMemberMinLevel();
		#my $maxLevel = $minLevel + 15;

		my $minLevel = getPartyLevelRangeMin();
		my $maxLevel = getPartyLevelRangeMax();

		sendMessage($messageSender, "pm", "Open Party $minLevel~$maxLevel at ".$config{lockMap}.", pm 'LFG \{lvl\}' to #Global for invite", "#Global");

		# TODO: level range stuff

		# we can Invite
		#sendMessage($messageSender, "p", "sending a request to $name");
		#Commands::run("party request $name");
	}

	# offline member check
	if(timeOut($myTimeouts->{'offline_check'},OFFLINE_RECHECK))
	{
		print "~~~~~~ Checking for online / offline members....\n";

		$myTimeouts->{'offline_check'} = time;

		while(@offlineCheckList)
		{
			my $check = shift(@offlineCheckList);

			print "Checking ID: ".$check."\n";

			if($char->{'party'}{'users'}{$check} and !$char->{'party'}{'users'}{$check}{'online'})
			{
				# kick them
				print $char->{'party'}{'users'}{$check}->{name}." has been offline for too long! Kick them out!\n";
				Commands::run("party kick ".$char->{'party'}{'users'}{$check}->{name});
			}
		}

		@offlineCheckList = ();

		foreach (@partyUsersID) {
			next if (!$_ || $_ eq $accountID);

			if(!$char->{'party'}{'users'}{$_}{'online'})
			{
				# party member is offline. maybe we add them to a list to recheck?
				print "       ".$char->{'party'}{'users'}{$_}->{name}." is offline, check them again in ".OFFLINE_RECHECK." seconds\n";
				push @offlineCheckList, $_;
			}
		}
	}

	# overweight or inventory full check
	OverweightCheck();
}

# $char->{party}{joined}
# ($char->{'party'}{'users'}{$partyUsersID[$i]}{'admin'})
# if (!$net || $net->getState() != Network::IN_GAME) {

sub ai_pre_MEMBER
{
	# check if you're in a party, if you're not, send out some feelers for open parties
	if(!$char->{party}{joined} && timeOut($myTimeouts->{'request_spam'},60))
	{
		$myTimeouts->{'request_spam'} = time;
		# send out feelers

		sendMessage($messageSender, "pm", "LFG ".$char->{lv}, "#Global");

		if($config{"follow"} eq 0)
		{
			configModify("follow", 0); # MAYBE LEAVE THIS UP TO THE USER????
		}
	}
	elsif($char->{party}{joined})
	{
		# do party stuff?
		if($config{"follow"} eq 0)
		{
			checkForFollowing();
		}

		# overweight or inventory full check
		OverweightCheck();

		# offline LEADER check
		if(timeOut($myTimeouts->{'offline_check'},OFFLINE_RECHECK))
		{
			print "~~~~~~ Checking for online / offline leader....\n";

			$myTimeouts->{'offline_check'} = time;

			# get the party leader's name
			for (my $i = 0; $i < @partyUsersID; $i++) {
				next if ($partyUsersID[$i] eq "");
				next unless ($char->{'party'}{'users'}{$partyUsersID[$i]}{'admin'});

				# check if this user is offline
				if(!$char->{'party'}{'users'}{$partyUsersID[$i]}{'online'})
				{
					if($offlineCheckLeader == TRUE)
					{
						# party leader has been offline for too long, leave the Party
						# TODO: handle leaving the party

						# leaving the party! so long!!
						print "Party leader has been offline for too long! Leaving party!\n";
						Commands::run("party leave");
					}
					else
					{
						# they're offline, so we need to check again
						$offlineCheckLeader = TRUE;
					}
				}
				else
				{
					# party leader isn't offline anymore :D
					$offlineCheckLeader = FALSE if $offlineCheckLeader == TRUE;
				}
			}
		}
	}
}

	#'DÅ▲ ' => bless( {
	#                   'admin' => '',
	#                   'ID' => 2002756,
	#                   'onNameChange' => bless( [], 'CallbackList' ),
	#                   'GID' => 153597,
	#                   'name' => 'tutorial aco',
	#                   'jobID' => 4,
	#                   'lv' => 17,
	#                   'online' => 1,
	#                   'map' => 'moc_fild12.gat',
	#                   'dead_time' => undef,
	#                   'dead' => undef,
	#                   'actorType' => 'Party',
	#                   'onUpdate' => bless( [], 'CallbackList' ),
	#                   'deltaHp' => 0,
	#                   'pos' => {
	#                              'y' => 96,
	#                              'x' => 142
	#                            }
	#                 }, 'Actor::Party' ),
	#'·à▲ ' => bless( {
	#                   'admin' => 1,
	#                   'ID' => 2000378,
	#                   'onNameChange' => bless( [], 'CallbackList' ),
	#                   'GID' => 150535,
	#                   'name' => 'tutorial thief',
	#                   'jobID' => 6,
	#                   'lv' => 27,
	#                   'online' => 1,
	#                   'map' => 'moc_fild12.gat',
	#                   'dead_time' => undef,
	#                   'dead' => undef,
	#                   'actorType' => 'Party',
	#                   'onUpdate' => bless( [], 'CallbackList' ),
	#                   'deltaHp' => 0
	#                 }, 'Actor::Party' )


# --- Party Member Status Check Stuff Starts Here ---
sub OverweightCheck
{
	return unless timeOut($myTimeouts->{"weight_check"}, WEIGHT_RECHECK);
	$myTimeouts->{"weight_check"} = time;

	# check every Xs if the character is overweight
	my $result = FALSE;

	# if they ARE, send a party message to let the leader know
	# TODO: Need to make this an option for the party leader? Maybe they don't always want to go back when overweight :\
	if(percent_weight($char) >= 50)
	{
		$result = TRUE;
	}
	# this will also check if the characters inventory is full
	elsif(scalar(@{$char->inventory}) eq 100)
	{
		# DANGER WILL ROBINSON
		error "Inventory is maxed out! Ask for resupply!\n";
		$result = TRUE;
		#sendMessage($messageSender, "p", "My inventory is full!!!");
	}

	if($result == TRUE)
	{
		sendMessage($messageSender, "p", "I need to resupply!!!");
	}
}

# --------------------------------------------

sub getPartyMemberMinLevel_new
{
	return 20;

	# needs to be based around the party leader's level
	# need to check newly added characters to make sure they are in the correct range
	# IF a newly added character is NOT in the correct range, kick them from the party
}

	#my $maxLevel = getPartyMemberMinLevel() + 15;
	#my $minLevel = getPartyMemberMaxLevel() - 15;

sub getPartyLevelRangeMin
{
	return getPartyMemberMaxLevel() - 15;
}

sub getPartyMemberMinLevel
{
	#{lv}

	my $minLvl = 100;

	#if(scalar(@partyUsersID) == 1)
	#{
	#	# party leader is the only one in the party
	#	$minLvl = $char->{lv} - 15;
	#}
	#else
	#{
		# search for the lowest party member
		for (my $i = 0; $i < @partyUsersID; $i++) {
			$minLvl = $char->{'party'}{'users'}{$partyUsersID[$i]}{'lv'} if $char->{'party'}{'users'}{$partyUsersID[$i]}{'lv'} < $minLvl;
		}
	#}

	return $minLvl;
}

sub getPartyLevelRangeMax
{
	return getPartyMemberMinLevel() + 15;
}

sub getPartyMemberMaxLevel
{
	#{lv}

	my $maxLvl = 0;

	#if(scalar(@partyUsersID) == 1)
	#{
	#	# party leader is the only one in the party
	#	$maxLvl = $char->{lv} + 15;
	#}
	#else
	#{
		# search for the lowest party member
		for (my $i = 0; $i < @partyUsersID; $i++) {
			$maxLvl = $char->{'party'}{'users'}{$partyUsersID[$i]}{'lv'} if $char->{'party'}{'users'}{$partyUsersID[$i]}{'lv'} > $maxLvl;
		}
	#}

	return $maxLvl;
}

sub UpdatePartyLevelRange
{
	$partyStoredLevel{min} = getPartyLevelRangeMin();
	$partyStoredLevel{max} = getPartyLevelRangeMax();

	print "[botPartyGo] New Party Level Range is ".$partyStoredLevel{min}."~".$partyStoredLevel{max}."\n";
}

sub checkForFollowing
{
	# ask who you should follow?
	# or just follow the leader...?

	my $followTarget = "";

	# get the party leader's name
	for (my $i = 0; $i < @partyUsersID; $i++) {
		next if ($partyUsersID[$i] eq "");
		next unless ($char->{'party'}{'users'}{$partyUsersID[$i]}{'admin'});

		$followTarget = $char->{'party'}{'users'}{$partyUsersID[$i]}{'name'};

		configModify("follow", 1);
		configModify("followTarget", $followTarget);

		sendMessage($messageSender, "p", "I'm following $followTarget now!");

		last;
	}
}

sub getPartyLeaderName
{
	# get the party leader's name
	for (my $i = 0; $i < @partyUsersID; $i++) {
		next if ($partyUsersID[$i] eq "");
		next unless ($char->{'party'}{'users'}{$partyUsersID[$i]}{'admin'});
		return $char->{'party'}{'users'}{$partyUsersID[$i]}{'name'};
	}
}

sub isPartyLeader
{
	return ($char->{party}{users}{$char->{ID}}{admin});
}

sub ai_post
{
	# have to do this in post, because updating in the actual reject packet sets the wrong levels
	if($queueUpdatePartyRange == TRUE)
	{
		UpdatePartyLevelRange();
		undef $queueUpdatePartyRange;

		# also force an update to the party share range
		$timeout{ai_partyShareCheck}{time} = 0;
	}
}

1;
