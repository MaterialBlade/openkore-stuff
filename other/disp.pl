# made by MaterialBlade
# swaps the unidentified display name and sprite with the identified version
# 
# make sure you have itemInfo_EN.lua in the same folder as the perl script
# do perl disp.pl to run in the command line to run it
# don't ask me for help

use strict;
use warnings;
#use Data::Dumper;

package disp;

main();

sub main
{	
	my @temp;
	my @output;
	my $file = 'itemInfo_EN.lua';
	my $i = 0;
	my $nameLine = -1;
	
	print "File can't be loaded\n" unless (-r $file);
	return unless (-r $file);

	{ open my $fp, '<', $file; @temp = <$fp> }

	print "Converting...\n";

	foreach my $line (@temp) {
		push @output, $line;

		if($line =~ /(\s+)(identifiedDisplayName = ")(.*)/)
		{
			$output[$i-3] = $1."un".$2."[?]".$3."\n";
			$nameLine = ($i-3);
		}

		if($line =~ /(\s+)(identifiedResourceName = ")(.*)/)
		{
			$output[$i-3] = $1."un".$2.$3."\n";
		}
		
		if($line =~ /(\s+)(slotCount = )(\d+)(,)/)
		{
			if($3 > 0)
			{
				#print "Got here!\n";
				my $temp = $output[$nameLine];
				my $slots = " [".$3."]\",";
				$temp =~ s/",/$slots/;
				$output[$nameLine] = $temp;
			}
		}

		$i++;
		#last if $i > 100;
	}

	open(FH, '>', "itemInfo_EN_new.lua") or die $!;
	foreach my $line (@output) {
		print FH $line;	
	}
	close(FH);

	print "All done!\n";
}