############################ 
# fixDoubleAccessory plugin for OpenKore by MaterialBlade
# 
# This software is open source, licensed under the GNU General Public Liscense
# -------------------------------------------------- 
#
# This plugin is a bandaid for equipping two accessories that have the exact same name
#
############################ 

package fixDoubleAccessory;

use strict;

use Globals;
use Modules;
use Settings;
use Log qw(message warning error debug);
use Network::Receive;
use Network::Send;
use Misc;
use Plugins;
use Utils;
use Actor;

# equip_item

Plugins::register('fixDoubleAccessory', 'fix two accessories with same name equip', \&onUnload); 
my $hooks = Plugins::addHooks( 
	['packet_pre/equip_item', \&checkEquips, undef],
);

message "fixDoubleAccessory successfully loaded.\n", "success";

sub onUnload {
    Plugins::delHooks($hooks);
}

sub onReload {
    &onUnload;
}

#$mytimeout->{'heal_player'}{$target} = time+0.2;

sub checkEquips
{
	my (undef,$args) = @_;

	#			? ['equip_item', 'a2 v C', [qw(ID type success)]]
	#		: ['equip_item', 'a2 v2 C', [qw(ID type viewid success)]],

	
#	if ((!$args->{success} && $args->{switch} eq "00AA") || ($args->{success} && $args->{switch} eq "0999")) {
#		message TF("You can't put on %s (%d)\n", $item->{name}, $item->{binID});

	# my $item = $char->inventory->getByID($args->{ID});

	if((!$args->{success} && $args->{switch} eq "00AA") || ($args->{success} && $args->{switch} eq "0999"))
	{
		# check if there is a duplicate of the item we're trying to equip
		# equip the OTHER version of the items

		my $item = $char->inventory->getByID($args->{ID}, 1);
		return unless ($item);

		my @getList = getAllByName($item->{name});

		if(scalar(@getList) > 1)
		{
			#print "We got a few items!!!".scalar(@getList)."\n";

			# get the idx of the one that is equipped
			my $equip_idx = -1;
			#my $equipped_item;
			my $new_item;

			foreach (@getList)
			{
				if($_->{equipped})
				{
					#$equipped_item = $_;
					$equip_idx = $_->{equipped};
					#last;
				}
				else
				{
					$new_item = $_;
				}
				#next if $_->{equipped};

				# try to equip it?
				# we need to know the OTHER SLOT that it's not equipped in
=pod
				print $_->{name};
				print " (".$_->{binID}.") ";
				print " $_->{equipped}" if($_->{equipped});
				print " isn't equipped!" if($_->{equipped} eq 0);
				print "\n";
=cut
			}

			#print "Got here\n";
			#print $equipped_item->{type}."\n";

			# equip the one that isn't
			if($new_item->{type} eq 4) # 4 type is accessories
			{
				# EQP_ACC_R            = 0x000008, // 8
				# EQP_ACC_L            = 0x000080, // 128

				#print "Didn't get here\n";

				# leftAccessory rightAccessory
				# 
				my $equipSlot;
				#$equipSlot = $char->{equipment}{'rightAccessory'}->{name} eq $new_item->{name} ? "leftAccessory" : "rightAccessory";
				$equipSlot = "leftAccessory" if $equip_idx eq 8;
				$equipSlot = "rightAccessory" if $equip_idx eq 128; # this will probably never get hit but it's there


				if(defined $equipSlot and defined $new_item)
				{
					$new_item->equipInSlot($equipSlot);
					message "[fixDoubleAccessory] Trying to equip $new_item->{name} ($new_item->{binID}) into $equipSlot\n";
				}
			}
		}
	}

	# my $invItem = $char->inventory->get($item->{index});

	#sub get {
	#	my ($name, $skipIndex, $notEquipped) = @_;
}

sub getAllByName
{
	my ($name) = @_;

	my @returnList = ();

	for my $item (@{$char->inventory}) {
		if($item->{name} eq $name and $item->{identified})
		{
			push(@returnList, $item);
		}
	}

	return @returnList;
}

return 1;
