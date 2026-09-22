# made by MaterialBlade
# swaps the unidentified display name and sprite with the indentified version
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
	
	my $nameType = 3;
	
	print "File can't be loaded\n" unless (-r $file);
	return unless (-r $file);

	{ open my $fp, '<', $file; @temp = <$fp> }
	
	# duplicate the current file
	open(FH, '>', "itemInfo_EN_backup.lua") or die $!;
	foreach my $line (@temp) {
		print FH $line;	
	}
	close(FH);
	
	# convert the dater
	print "Converting...\n";

	foreach my $line (@temp) {
		push @output, $line;

		# check for -3
		if($line =~ /(unidentifiedDescriptionName = \{ ")/)
		{
			$nameType = 3;
		}
		# check for -5
		elsif($line =~ /(unidentifiedDescriptionName = \{)[\n]/)
		{
			$nameType = 5;
			
			# check if the next line AFTER is also the closing bracket
			# if it is, we use 4 instead of 5 (thanks Nathan >:\ )
			if($temp[$i+1] =~ /(\},)[\n]/)
			{
				$nameType = 4;
			}
		}

		if($line =~ /(\s+)(identifiedDisplayName = ")(.*)/)
		{
			$output[$i-$nameType] = $1."un".$2."[?]".$3."\n";
			$nameLine = ($i-$nameType);
		}

		if($line =~ /(\s+)(identifiedResourceName = ")(.*)/)
		{
			$output[$i-$nameType] = $1."un".$2.$3."\n";
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

	#open(FH, '>', "itemInfo_EN_new.lua") or die $!;
	open(FH, '>', "itemInfo_EN.lua") or die $!;
	foreach my $line (@output) {
		print FH $line;	
	}
	close(FH);

	print "All done!\n";
}