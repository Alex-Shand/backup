#!/usr/bin/perl
# Check this is correct too

# Process based on http://www.mikerubel.org/computers/rsync_snapshots/

# Requires passwordless ssh comunication from the server to each client, see README

# TODO: Strip trailing /'s from source paths
# TODO: Check free space

use v5.22;
use warnings;
use autodie qw( :all );

use Getopt::Std qw( getopts );
use File::Basename qw ( basename );
use Time::Piece qw( localtime );
use File::Spec;
use File::Path qw( remove_tree );

#####################################Config#####################################

# Host names of the computers to be backed up, every name has to have a
# corresponding entry in the %sources hash. Extra names here aren't a
# problem, duplicating names here causes the relavent computer to be
# backed up twice into the same folder (Probably not a huge issue with
# rsync)
my @computers = qw( laptop
		    desktop );

# Sources for each computer, all paths should be absolute and shouldn't have a
# trailing slash. There must be an entry for each member of @computers above.
my %sources = ( laptop  => [ '/home/alex' ],
		desktop => [ '/home/alex' ] );

# Excludes directories, the final paths are given relative to the directory they
# are excluded from.
my %excludes = ( laptop => {
                '/home/alex' => [ '/Downloads',
				  '/outside' ]
               } );

# Mount point of the backup disk (Assumed to be mounted ro by default)
my $baseBackupDir = '/root/Backups';

# Location of rsync binary
my $rsync = '/usr/bin/rsync';

# Default options for rsync (May be added to dependant on command line arguments
# and presence of older backups)
my @rsync_options = ( '-a', # Recursive, copy symlinks as symlinks, Keep
                            # permissions, Keep access times, Keep group
                            # information, Keep owner information, Preserve
		            # device and special files

		      '--delete', # Delete files in the backup if not in the
		                  # source

		      '--delete-excluded', # As above but with excluded
                                           # directories

		      '--force', # Delete directories even if non-empty

		      '--one-file-system'); # Don't cross filesystem boundries

###################################End Config####################################

# Disable output buffering in this file
$| = 1;

# Script name
my $me = basename($0);

# Print a header
say header_footer(scalar(localtime), $me);

# Check the backup directory exists
die "Can't find backup directory" if ! -d $baseBackupDir;

# Remount it rw
{
    # Removes the comma warning
    no warnings 'qw';
    system(qw(mount -o remount,rw), $baseBackupDir);
}

# Hash for storing command line options
my %opts;
# Populate it
getopts('p', \%opts);

# If the -p option is passed have rsync print progress information
if ( $opts{p} ) {
    push @rsync_options, '--info=progress2';
}

for my $computer ( @computers ){

    # The time now
    my $time = localtime;

    # Produce a timestamp
    my $stamp = make_time_stamp($time);

    # The directory the backup will be written to
    my $backupDir = File::Spec->catdir($baseBackupDir, $computer);

    # Make the directory if it doesn't exist
    if ( ! -e $backupDir ) {
        mkdir $backupDir;
    # If it exists but isn't a directory warn and move on
    } elsif ( ! -d $backupDir ) {
        warn "$backupDir doesn't appear to be a directory, skipping";
	next;
    }

    # Check for existing backups
    opendir((my $backupDH), $backupDir);
    my @backups = sort grep { ! /^\.+$/ } readdir $backupDH;

    # If there are existing backups link to the last one
    if ( @backups ) {
	# When the backups are sorted lexicographically the newest is the last one
	# in the list
	my $lastBackup = $backups[$#backups];
	push @rsync_options, "--link-dest=$lastBackup";
    }

    # Excludes (If any defined)
    my %currentExcludes = %{$excludes{$computer}};

    # Run the backup
    # For rsync at the bottom of the loop
    my $exit;
    my $transferFail = 0;
    for my $src ( @{$sources{$computer}} ) {
	# Disable autodie for system in this loop (rsync failing shouldn't kill
	# the script)
	no autodie qw( system );

	# Excludes for this directory
	my @dirExcludes = @{$currentExcludes{$src}};
	for my $exclude ( @dirExcludes ) {
	    say $exclude;
	    push @rsync_options, "--exclude=$exclude";
	}

	# TODO: The concatenate operator shouldn't be needed here
	my @cmd = ($rsync, @rsync_options, "alex@" . "$computer:$src", $backupDir);
	system(@cmd) == -1 and die "Can't find rsync ($!)";
	# Break the loop if the command fails
	$exit = $? >> 8;
	# 0 for success, 27 is partial transfer (Caused by permission issues, dissappearing files, etc.)
	unless ( ($exit == 0) or ($exit == 27) ) {
	    $transferFail = 1;
	    last;
	}
    }
    # If the transfer failed warn, clean up the failed backup and die
    if ( $transferFail ) {
	warn "Backup failed, rsync returned $exit";
	remove_tree($backupDir);
	die;
    }
}

sub header_footer {
    my ($time, $me, $flag) = @_;
    my $end = $flag ? 'Finished' : 'Started';
    "$time | $me: Backup $end";
}

sub make_time_stamp {
    my $time = shift;
    $time->date . '|' . $time->hour;
}

# Remount the backup directory and print a footer, regardless of how
# the script exits bar being killed by the OS
END {
    {
    # Removes the comma warning
    no warnings 'qw';
    system(qw(mount -o remount,ro), $baseBackupDir);
    }
    say header_footer(scalar(localtime), $me, 1);
}
