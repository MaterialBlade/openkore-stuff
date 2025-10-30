############################ 
# getMyGear plugin for Openkore by MaterialBlade
#
# This plugin is meant to be an easy way to update/maintain your default gear set
# When returning to town, the bot will auto-equip their default gear if it isn't equipped
# If the items are added to storage, they will be taken out
# If the gear is broken, the items won't be added to storage
# The intention is to spent a designated amount of time in a map before moving to the next one.
#
# CONFIGURATION
# Add this line to config.txt:
# 	getMyGear [0|1]
# then run `gmg set` in the console then run `gmg inject` or reload the plugin 
#
# getMyGear is a boolean. Set it to 0 to turn the plugin off. Set it to 1 to turn the plugin on.
# getMyGear_list is a comma seperated list of your default gear in a specific order.
#				 DON'T WRITE THIS YOURSELF! Use the 'gmg set' command to generate this line! 
#
# EXAMPLE CONFIG.TXT
# getMyGear 1
# getMyGear_list +7 Illusion Goibne's Helm [King Dramoh] [1],Fin Helm,Buzzy BOL Gum,+7 Stone Buckler [Hodremlin] [1],+7 Hunting Spear [Abysmal Knight] [1],+5 Nidhoggur's Shadow Garb [Raydric] [1],+4 Meteor Plate [Clock] [1],+9 Tidal Shoes [Firelock Soldier] [1],Safety Ring,Safety Ring,
#
# CONSOLE COMMANDS
# `gmg` lists the available commands
# `gmg inject` injects all the necessary 'stuff' for the plugin to work. This SHOULD happen automatically when the plugin loads
# `gmg load` does the same thing as inject
# `gmg toggle` enables / disables the plugin
#
# `gmg test` Test output. You can use this to see if the necessary 'stuff' has been injected. If it hasn't, run `gmg inject`
# `gmg DC` Another testing function. Spits stuff out to a text file
#
# This software is open source, licensed under the GNU General Public Liscense
############################ 

package getMyGear;

use Globals;
use Log qw(message warning error debug);
use Misc;
use Actor;
use Utils;
use AI;
use AI::SlaveManager;
use Time::HiRes qw(time);
use Actor;
use Actor::You;
use Actor::Player;
use Actor::Item;
use Actor::Unknown;
use Data::Dumper;

use constant {
	TRUE => 1,
	FALSE => 0,
};

#use Item;

Plugins::register("getMyGear", "Maintains a default equip list, keeps it equipped", \&on_unload, \&on_reload);

my $injected = FALSE;

my $aiHook = Plugins::addHooks(
	['configModify',	\&on_configModify, undef],
	['AI_pre',			\&ai_pre, undef],
	['AI_post',			\&ai_post, undef]
);

my $commands_handle = Commands::register(
	['gmg', 'testing command for getMyGear', \&test_cmd],
	#['DC', 'dumps config to a file', \&dumpConfig],
);

my $loghook = Log::addHook(\&consoleCheckWrapper);

=pod
	TODO:
		- add something for item control for the BROKEN versions of these items, just in case // DONE? Not tested

		- BIGGER TODO: make a big getAuto block to get the gear in this list from STORAGE // DONE
		- spit out a string that contains all the character's equip slots // DONE
		- hook into config a getAuto block and an equipAuto block // DONE
		- actually INJECT the new equipAuto block into the config at some point // DONE
		- BIG TODO: if the config is changed or reloaded, need to re-insert the block // DONE

	COMMAND:
		- saveGear - save the gear list to the config file

	HOOKS:
		- ai_pre - actually do all the stuff
		- mapChanged - detect the equipAuto for gear
=cut

sub on_unload {
	# This plugin is about to be unloaded; remove hooks
	Plugins::delHook($aiHook);
	Commands::unregister($commands_handle);
}

sub on_reload {
	&on_unload;
}

message "getMyGear successfully loaded :3\n", "success";

my @equip_slots = qw(
	topHead midHead lowHead
	leftHand rightHand
	robe armor shoes
	leftAccessory rightAccessory
	arrow
);

sub on_configModify
{
	my (undef, $args) = @_;

	#print "Hello world\n";
}

sub consoleCheckWrapper
{
	return unless $_[1] =~ /^(?:parseConfigFile)$/;
	$injected = FALSE;
	return unless $config{'getMyGear'} == 1;

	message "Config reloaded!!! :3\n", "success";
	inject(); # re-inject it
}

sub test_cmd
{
	my @values = split(' ', $_[1]);

	if($_[1] eq "set")
	{
		my $output = "";

		# set the config data
		foreach (@equip_slots)
		{
			if($char->{equipment}{$_})
			{
				# we have this item equipped, so get it
				$output .= $char->{equipment}{$_}->{name};
			}

			if($_ ne "arrow")
			{
				$output .= ",";
			}
		}

		configModify("getMyGear_list", $output);
	}
	elsif($_[1] eq "load" || $_[1] eq "inject")
	{
		# load the stuff from config data into the ai config whatever
		inject();
	}
	elsif ($_[1] eq "toggle")
	{
		if($config{"getMyGear"})
		{
			configModify("getMyGear", !$config{"getMyGear"});
		}
		else
		{
			configModify("getMyGear", 1);
		}
	}
	elsif($_[1] eq "test")
	{
		# search through the equipAutos for a gmg block
		my $result = FALSE;
		my $equipAutoIndex = 0;
		for (my $i = 0; exists $config{"equipAuto_$i"}; $i++) {
			$equipAutoIndex = $i;

			# disable any equipAutos with 'prontera' set in them
			if($config{"equipAuto_$equipAutoIndex"."_gmg"})
			{
				message "[getMyGear] Found it!! At idx $equipAutoIndex !! \n", "success";
				$result = TRUE;
				last;
			}
		}

		if($result == FALSE)
		{
			error "Couldn't find the equipGroup! Total groups is: $equipAutoIndex\n";
		}
		else
		{
			#message "getMyGear successfully loaded :3\n", "success";
		}
	}
	elsif($_[1] eq "DC")
	{
		dumpConfig();
	}
	else
	{
		message "[getMyGear] Unrecognized 'gmg' command.\n", "teleport";
		message "[getMyGear] Commands are: 'set', 'load/inject' and 'test'\n", "teleport";
		#spitCommands();
	}
}

sub inject
{
	return unless $config{'getMyGear'} == 1;

	my $alreadyInjected = FALSE;

	my $equipAutoIndex = 0;
	for (my $i = 0; exists $config{"equipAuto_$i"}; $i++) {
		$equipAutoIndex = $i;

		# check to make sure it's not ALREADY injected
		if($config{"equipAuto_$equipAutoIndex"."_gmg"})
		{
			message "[getMyGear] Found a block that is already injected!~ \n", "teleport";
			$alreadyInjected = TRUE;
			last;
		}

		# disable any equipAutos with 'prontera' set in them
		if($config{"equipAuto_$equipAutoIndex"."_inMap"} eq 'prontera')
		{
			$config{"equipAuto_$equipAutoIndex"."_disabled"} = 1;
		}

	}
	$equipAutoIndex++;

	if($alreadyInjected == TRUE)
	{
		return;
	}

	# get the config file
	my @values = split(',', $config{'getMyGear_list'});

	# inject an equipAuto for a NEW prontera
	$config{"equipAuto_$equipAutoIndex"} = undef;

	for (my $i = 0; $i < scalar(@equip_slots); $i++) {
		$config{"equipAuto_$equipAutoIndex"."_".$equip_slots[$i]} = $values[$i];
	}

	$config{"equipAuto_$equipAutoIndex"."_inMap"} = "prontera, geffen, veins, yuno, aldebaran, niflheim";
	$config{"equipAuto_$equipAutoIndex"."_gmg"} = 1;

	# get the... getAuto idx
	my $getAutoIndex = 0;
		for (my $i = 0; exists $config{"getAuto_$i"}; $i++) {
		$getAutoIndex = $i;
	}
	$getAutoIndex++;

	# inject the get autos
	foreach (@values)
	{
		next if $_ eq "";
		#print "Adding a getAuto for $_ : getAuto_$getAutoIndex \n";

		# use $_ as the thing
		$config{"getAuto_$getAutoIndex"} = $_;
		$config{"getAuto_$getAutoIndex"."_maxAmount"} = 1;
		$config{"getAuto_$getAutoIndex"."_passive"} = 1;
		$config{"getAuto_$getAutoIndex"."_batchSize"} = undef;

		$getAutoIndex++;
	}

	# inject the items_control stuff
	my $items_ctrl = \%items_control;
	my $realKey;

	# the important ones
	#'cart_get' => '0',
	#'cart_add' => '0',
	#'keep' => '0',
	#'storage' => '0',
	#'sell' => '0'

	# loop it again! Yattaze!
	foreach (@values)
	{
		next if $_ eq "";
		next if exists $items_ctrl->{lc($_)};

		#print "The \$_ is $_ \n";

		$realKey = lc($_);

		$items_ctrl->{$realKey}{keep} = 1;
		$items_ctrl->{$realKey}{storage} = 0;
		$items_ctrl->{$realKey}{sell} = 0;
		$items_ctrl->{$realKey}{cart_get} = 0;
		$items_ctrl->{$realKey}{cart_add} = 0;

		# also add the BROKEN version
		my $brkn = "broken ".$realKey;
		next if exists $items_ctrl->{$brkn};

		$items_ctrl->{$brkn}{keep} = 1;
		$items_ctrl->{$brkn}{storage} = 0;
		$items_ctrl->{$brkn}{sell} = 0;
		$items_ctrl->{$brkn}{cart_get} = 0;
		$items_ctrl->{$brkn}{cart_add} = 0;
	}

	message "[getMyGear] successfully injected\n", "success";
}

sub ai_post
{
	return unless $config{'getMyGear'} == 1;

	if(defined $field and $injected == FALSE)
	{
		inject();
		$injected = TRUE;
	}
}

sub ai_pre {

}

sub dumpConfig
{
	# Open a file for writing
	my $filename = 'dump_output.txt';
	open my $fh, '>', $filename or die "Cannot open $filename: $!";

	# Print the Dumper output to the file handle
	#print $fh Dumper(\%config);
	#print $fh Dumper(\%items_control);

	foreach my $key ( keys %items_control ) { 
	   print $fh $key . " => ". $items_control{$key}."\n";
	   print $fh Dumper($items_control{$key});
	   print $fh "\n";
	}

	# Close the file handle
	close $fh;
}

1;
