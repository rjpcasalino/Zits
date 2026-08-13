#!/usr/bin/env perl
use strict;
use warnings;
use List::Util qw(shuffle);

my $interval = 240;
my $wallpaper_dir = "$ENV{HOME}/Pictures/Wallpaper";

# Trap SIGUSR1 to interrupt sleep and immediately skip to the next wallpaper
$SIG{USR1} = sub { print "Skipping to next wallpaper...\n"; };

# Ensure daemon is running (simplified)
# system("pgrep -x awww-daemon > /dev/null || awww-daemon &");

# Ensure awww-daemon is running and responsive over IPC
if (system("awww query > /dev/null 2>&1") != 0) {
    system("awww-daemon &");
    sleep(1);
}

while (1) {
    # Shuffle the glob output for true randomness
    my @files = shuffle(glob("$wallpaper_dir/*"));

    unless (@files) {
        warn "No wallpapers found in $wallpaper_dir\n";
        sleep($interval);
        next;
    }

    for my $file (@files) {
        next unless -f $file;
        print "Setting: $file\n";
        
        # Set wallpaper with transition
        system("awww", "img", $file, "--transition-type", "fade", "--transition-step", "90");
        
        # Sleep is interrupted by our SIGUSR1 trap, immediately moving to the next file
        sleep($interval);
    }
}
