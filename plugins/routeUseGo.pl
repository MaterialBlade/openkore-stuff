##############################
# =======================
# routeUseGo
# =======================
# This plugin is licensed under the GNU GPL
# Created by materialblade and copiousfish <3
#
# What it does: scans route for maps we can @go to. If there is, we @go to them
#
# Config key (put in config.txt):
#	route_routeUseGo 1
# 
# Source Mod: CalcMapRoute.pm
# update the 'iterate' sub. look for the following code
#		debug "Map Solution Ready for traversal.\n", "route";
#		debug sprintf("%s\n", $self->getRouteString()), "route";
# 		
# and add this hook below it		
#		Plugins::callHook('MapSolutionReady', { route => $self->getRouteString() });
#
###############################################
package routeUseGo;

use strict;
use Plugins;
use Globals;
use Utils;
use Misc;
#use AI;
use Log qw(debug message warning error);
use Translation;
use Data::Dumper;

use List::Util qw(shuffle);

Plugins::register('routeUseGo', 'Automatically uses @go if a town is in the route', \&onUnload);

my $hooks = Plugins::addHooks(
	['MapSolutionReady',			\&getRoute],
);

message "routeUseGo success\n", "success";

my %maps =  (	
				'alberta' => undef,
				'aldebaran' => undef,
				'amatsu' => undef,
				'ayothaya' => undef,
				'comodo' => undef,
				'einbech' => undef,
				'einbroch' => undef,
				'geffen' => undef,
				'gonryun' => undef,
				'hugel' => undef,
				'izlude' => undef,
				'jawaii' => undef,
				'kunlun' => undef,
				'lighthalzen' => undef,
				'louyang' => undef,
				'lutie' => undef,
				'morocc' => undef,
				'morroc' => undef,
				'moscovia' => undef,
				'niflheim' => undef,
				'payon' => undef,
				'prontera' => undef,
				'rachel' => undef,
				'umbala' => undef,
				'veins' => undef,
				'xmas' => undef,
				'yuno' => undef,
				'Dummy' => undef
);

sub onUnload {
	Plugins::delHooks($hooks);
}

sub onReload {
    &onUnload;
}

sub getRoute {
	return unless ($config{'route_useGoCommand'});

	my (undef, $args) = @_;
	my @route = split(' -> ', $args->{route});
	my $destination = $route[$#route]; # get the destination

	my $step;
	while(@route)
	{
		$step = pop(@route);

		last if($field->baseName eq $destination); #if for whatever reason we're at the dest, don't warp

		next unless (exists $maps{$step}); # not in the list
		next if ($field->baseName eq $step); # don't TP if it's the map we're on

		sendMessage($messageSender, "p", "\@go $step");
		undef @route;
	}
}

1;
