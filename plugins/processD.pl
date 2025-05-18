############################ 
# processD plugin for Openkore
# made by MaterialBlade with help from Kwak/Isora
#
# USAGE: type 'processD (monsternumber) [0/1]' in the OpenKore window. the [0/1] for if the monster is a boss protocol type
#
# EXAMPLE: processD 1001
# OUTPUT: 1001,SCORPION,Scorpion,Scorpion,24,1109,0,574,352,1,80,135,30,0,1,24,24,5,52,5,10,12,0,4,23,0x2003695,200,1000,900,432,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
#
# That ^ data line can be added to mob_db.txt
#
############################ 
package processD;

use strict;
use Globals;
use Utils;
use Misc;
use Log qw(message warning error debug);
use Translation;
use Data::Dumper;
use Settings;

Plugins::register("processD", "converts monsterinfo command into mob_db data", \&on_unload, \&on_reload);

my %requestQueue;
my $mytimeout;
my $lockOut = 0;
my $iw_map;

use Scalar::Util qw(looks_like_number);

my $aiHook = Plugins::addHooks(
	['packet_pre/self_chat',       \&selfChat, undef],
);

my $commands_handle = Commands::register(
	['processD', 'process the dater', \&processD],
);

sub on_unload {
	# This plugin is about to be unloaded; remove hooks
	Plugins::delHook($aiHook);
}

sub on_reload {
	&on_unload;
}


my $mvpYes = 0;
my $capturesLeft = 0;
my $captureString = "";

sub selfChat
{
	my (undef,$args) = @_;

	if($capturesLeft > 0)
	{
		$captureString .= $args->{message};

		if($capturesLeft > 1)
		{
			$captureString .= " ";
		}

		$capturesLeft--;
	}

	if($capturesLeft == 0)
	{
		$capturesLeft--;

		processDataCall($captureString);
	}
}

sub processD
{
	my @values = split(' ', $_[1]);
	
	# first make sure the data is usable
	if(scalar(@values) eq 0 || !looks_like_number($values[0]))
	{
		print "ERROR: Need to supply a monster # with processD\n";
		return;
	}

	$captureString = "";

	my $mi = $values[0];
	$mvpYes = 0;
	if(scalar(@values) eq 2 and looks_like_number($values[1]))
	{
		$mvpYes = $values[1];
	}

	$capturesLeft = 4;
	sendMessage($messageSender, "c", "\@mi $mi");
}

sub processDataCall
{
	my $string = shift;

	my %size_lut = ('Small' => 0,'Medium' => 1,'Large' => 2);
	my %race_lut = ('Formless' => 0, 'Undead' => 1, 'Beast' => 2, 'Plant' => 3, 'Insect' => 4, 'Fish' => 5, 'Demon' => 6, 'Demi-Human' => 7, 'Angel' => 8, 'Dragon' => 9);
	my %element_lut = ('Neutral' => 0, 'Water' => 1, 'Earth' => 2, 'Fire' => 3, 'Wind' => 4, 'Poison' => 5, 'Holy' => 6, 'Dark' => 7, 'Ghost' => 8, 'Undead' => 9);
	
	my $file = Settings::getTableFilename('mob_db.txt');

	if($string =~ /Monster\:\s\'(.*)\'\/?\'(.*)'\/?\'(.*)\'+\s+\((\d+)\)\sLv\:(\d+)\s+HP\:(\d+)\s+Base\s+EXP\:(\d+)\s+Job\s+EXP\:(\d+)\s+HIT\:(\d+)\s+FLEE\:(\d+)\s+DEF\:(\d+)\s+MDEF\:(\d+)\s+STR\:(\d+)\s+AGI\:(\d+)\s+VIT\:(\d+)\s+INT\:(\d+)\s+DEX\:(\d+)\s+LUK\:(\d+)\s+ATK\:(\d+)\~(\d+)\s+Range\:(\d+)\~(\d+)\~?(\d+?)\s+Size\:(\w+)\s+Race\:\s+(\w+)\s+Element\:\s+(\w+)\s+\(Lv\:(\d+)\)/)
	{
		print "ENEMY INFO DUMP\n";
		# 24 is size
		# 25 is the race
		# 26 is the Element
		# 27 is the level

		# 0x6200000 for boss mode
		# 0x2003695 for regular mode

		# we need to convert element and levle to the new thingy
		my $size = $size_lut{$24};
		my $race = $race_lut{$25};

		my $element = ($27*2)."".$element_lut{$26};
		my $mode = "0x2003695";

		if($mvpYes eq 1)
		{
			$mode = "0x6200000";
		}

		#print "$4,$3,$1,$2,$5,$6,0,$7,$8,$21,$19,$20,$11,$12,$13,$14,$15,$16,$17,$18,$22,$23,$size,$race,$element,$mode,200,1000,900,432,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0\n";
		# save data to mon_db.txt directly
		open my $fh, '>>', $file;
		print $fh "$4,$3,$1,$2,$5,$6,0,$7,$8,$21,$19,$20,$11,$12,$13,$14,$15,$16,$17,$18,$22,$23,$size,$race,$element,$mode,200,1000,900,432,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0\n";
		close $fh;
		message "Saved $4,$3,$1,$2,$5,$6,0,$7,$8,$21,$19,$20,$11,$12,$13,$14,$15,$16,$17,$18,$22,$23,$size,$race,$element,$mode,200,1000,900,432,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0 to mon_db.txt!\n";
	}
}

1;
