#! /usr/bin/perl -w
#
# (C) Copyright 2002 Jay Grizzard and Whispering Wolf Productions
# Contact elfchief+atron@lupine.org
#
# You need MP3::Tag from
# ftp://cpan.pair.com/authors/id/T/TH/THOGEE/tagged-0.40.tar.gz
# 
# and MP3::Info from
# ftp://cpan.pair.com/authors/id/C/CN/CNANDOR/MP3-Info-1.01.tar.gz
#
# and also Audio::Wav from
# ftp://cpan.pair.com/authors/id/N/NP/NPESKETT/Audio-Wav-0.02.tar.gz
#
# And Compress-Zlib (sigh)
# ftp://cpan.pair.com/authors/id/P/PM/PMQS/Compress-Zlib-1.16.tar.gz
#
# If you haven't played with the perl CPAN module yet, now might be
# a really really good time to check it out. On most systems, you can
# just type 'cpan' and get into it, though if that doesn't work, you
# can definately get there with 'perl -MCPAN -e shell'. Configure it
# once, and then all you have to do is type:
#     install MP3::Tag MP3::Info Audio::Wav Compress::Zlib
#
# Disclaimer: Butt ugly, modified from a script for a different project
# I was working on. Should be functional.
#
# Usage: script.pl /path/to/share/root
# (Creates /path/to/share/root/atrontc.vtc)
# Use -w and/or -m (no arguments) to also create 'new this week' and
# 'new this month' m3u playlists in the same location.
#
# If you like this little script, go forth and find a group 
# called 'Nightwish' and check out their music. Best stuff on earth.
# That, or send me a gift certificate to a bay-area used-CD  store
# of your choice. :>
#
# Special thanks (email addys omitted, courtesy the spammers of the world):
#
# Kevin P. Fleming (Performance & other tweaks)
# Bery Rinaldo (Bugfixing & 'recently added' support)
# Dennis DeDonatis (Having lots of corurpt mp3s to play with)

use File::Basename;
use MP3::Info;
use MP3::Tag;
use Audio::Wav;
use Getopt::Long;
use File::stat;

use strict; 
$| = 1;
my $VERSION = '0.7';

my $DAYS_IN_WEEK = 7;
my $DAYS_IN_MONTH = 31;

my $WEEK_DEFAULT_FILE = "Added_This_Week.m3u";
my $MONTH_DEFAULT_FILE = "Added_This_Month.m3u";

my $count = 0;
my @spinchars = qw[ - \ | / ];

my %dupehash;

my %opts = ( );
if (!GetOptions(\%opts, 
				'help|h+',
				'pastweek|w+',	
				'pastmonth|m+',
				'playlists|p+',
				'version|v',
			   )) {
	usage();
	exit(1);
}

if ($opts{version}) {
	print STDERR "attoc.pl v$VERSION\n"
	  ."(C) Copyright 2002, Jay Grizzard and Whispering Wolf Productions\n";
	exit(0);
}

my $indir;
if ($opts{help} || !defined($ARGV[0])) {
	usage();
	exit(1);
} else {
	$indir = $ARGV[0];
}

my $weekfile = undef;
my $monthfile = undef;

$weekfile = $WEEK_DEFAULT_FILE if (defined($opts{pastweek}));
$monthfile = $MONTH_DEFAULT_FILE if (defined($opts{pastmonth}));

# Clear off trialing slashes
$indir =~ s/\/+$//;

my %songs = ( );
my %newweek = ( );
my %newmonth = ( );
my %playlists = ( );
my $now = time();

print "Finding music files...  ";
processrecursive($indir, \&processfile);

print "\nWriting playlists:\n";
writeplaylists();

print "\b\nWriting atrontc.vtc...  ";
writetoc();

print "\n$count files processed\n";

exit;

# Takes two arguments -- A filename, and a reference to the funciton 
# we want to call...
sub processrecursive {
    my ($filename, $callback) = @_;
    
    if ( -d $filename ) {
		opendir(DIRH, $filename) || die "Failed to open directory $filename";
		my @dirs = grep { ! /^\./ } readdir(DIRH);
		closedir(DIRH);
		foreach my $dir (@dirs) {
			processrecursive($filename . "/" . $dir, $callback);
		}
    } elsif ( -f $filename ) {
		$callback->($filename);
    } else {
		print STDERR "$filename: Unknown file type, skipping.\n";
    }
}

# Actually extract id3 tags and the like...
sub processfile {
	my $filepath = shift;

	my %song;

	# Check the filename...
	return unless (($filepath =~ /\.mp3$/i) ||
				   ($filepath =~ /\.wma$/i) ||
				   ($filepath =~ /\.wav$/i) ||
				   ($filepath =~ /\.m3u$/i) ||
				   ($filepath =~ /\.pls$/i));
		
	# Count & Spinner...
	$count++;
	if (!($count % 5)) {
		my $c = shift @spinchars;
		print "\b$c";
		push @spinchars, $c;
	}
	
	# Okay, now lets derive some filenames. First off, substitute out the 
	# base directory, which we consider to be the share root.
	my $filename = $filepath;
	my $filedir;
	$filename =~ s/^\Q$indir//o;
	
	
	# Figure out our diretory name and filename, and make sure the 
	# former has a leading slash...
	($filename, $filedir) = fileparse($filename);
	$filedir =~ s/^\///;
	if ($filedir eq ".") {
		$filedir = "";
	}
	
	# And now, make it look like a windows directory... (replace / with \)
	$filedir =~ s/\//\\/g;

	my $song;
	my $key = uc($filename . $filedir);

	if (!($song = get_tcd($filepath))) {
		if ($filename =~ /\.mp3$/) {
			$song = get_id3v2($filepath) || get_id3v1($filepath);
			if (!exists($song->{TLEN})) {
				my $info = get_mp3info($filepath);
				$song->{TLEN} = int($info->{SECS});
			}
		} elsif ($filename =~ /\.wav$/) {
			$song = get_wav($filepath);
		} elsif ($filename =~ /\.m3u$/) {
			$song = get_m3u($filepath); 
		} elsif ($filename =~ /\.pls$/) {
			$song = get_pls($filepath);
		} elsif ($filename =~ /\.wma$/) {
			$song = get_wma($filepath);
		} else {
			$song = get_fallthrough($filepath);
		}
	}

	$song->{TIT2} = $filename if (!$song->{TIT2});;
	$song->{FILE} = $filename;
	$song->{DIR}  = $filedir;

   # Check for duplicated title
	my $dupekey = uc($song->{TIT2});
	if (exists($dupehash{$dupekey})) {
		my $firstsongkey = $dupehash{$dupekey};
		$dupehash{$dupekey} = undef;
		tweaktitle($song);

		if (defined($firstsongkey)) {
			my $firstsong = $songs{$firstsongkey};
			tweaktitle($firstsong);
		}
	} else {
		$dupehash{$dupekey} = $key;
	}

	# Store it away for later fun
 	$songs{$key} = $song;


	# Playlist building.
	if (($filepath =~ /\.mp3$/i) ||
		($filepath =~ /\.wav$/i) ||
		($filepath =~ /\.wma$/i)) {

		my $st = stat($filepath);
		my $age = $now - $st->mtime();

		if ($age < (60 * 60 * 24 * $DAYS_IN_MONTH)) {
			$newmonth{$key} = $song;
			if ($age < (60 * 60 * 24 * $DAYS_IN_WEEK)) {
				$newweek{$key} = $song;
			}
		}
		
		# And embedded playlists...
		if (defined($song->{PLAYLISTS})) {
			foreach my $list (split(/,/, $song->{PLAYLISTS})) {
				$playlists{$list}{$key} = $song;
			}
		}
	}
}


# This will tweak the $song reference it was handed directly.
sub tweaktitle {
	my $song = shift;

	my $addendum = $song->{TPE1} || "No Artist";
	$addendum .= " - ";
	$addendum .= $song->{TALB} || "No Album";
	$song->{TIT2} = $song->{TIT2} . " [$addendum]";
}


sub writetoc {
	open(OUTFILE, ">$indir/atrontc.vtc.tmp") or 
	  die "Can't open atrontc.vtc.tmp: $!";


	print OUTFILE "VERS=Created by ATTOC $VERSION\n";
	print OUTFILE "DATE=Creation time: " . localtime() . "\n";
	print OUTFILE "SECS=" . time() . "\n\n";

	foreach my $key (sort {$a cmp $b} keys %songs) {
		my %song = %{$songs{$key}};

		# Output the actual structure.
		print OUTFILE "SONG\n";
		print OUTFILE "FILE=$song{FILE}\n";
		print OUTFILE "DIR =$song{DIR}\n";
		print OUTFILE "TIT2=$song{TIT2}\n";
		print OUTFILE "TPE1=$song{TPE1}\n" if ($song{TPE1});
		print OUTFILE "TALB=$song{TALB}\n" if ($song{TALB});
		print OUTFILE "TRCK=$song{TRCK}\n" if ($song{TRCK});
		print OUTFILE "TCON=$song{TCON}\n" if ($song{TCON});
		print OUTFILE "TLEN=$song{TLEN}\n" if ($song{TLEN});
		print OUTFILE "END \n\n";
	}

	close(OUTFILE);

	# We could just move one file on top of the other, but that isn't
	# guaranteed to work on all platforms, and we -do- want to be able
	# to run this thing on something besides unixes, eventually.

	unlink("$indir/atrontc.vtc");   # We don't care if this fails, really.
	rename("$indir/atrontc.vtc.tmp", "$indir/atrontc.vtc") or
	  die "Unable to rename atrontc.vtc.tmp to atrontc.vtc in $indir: $!";
}

sub writeplaylists {
	if ($weekfile) {
		print "\nWriting $weekfile...  ";
		if (writeplaylist($weekfile, "Music Added This Week", 
						  %newweek)) {
			print "(new)";
			processfile("$indir/$weekfile");
		}
	}		

	if ($monthfile) {
		print "\nWriting $monthfile...  ";
		if (writeplaylist($monthfile, "Music Added This Month", 
						  %newmonth)) {
			print "(new)";
			processfile("$indir/$monthfile");
		}
	}

	if ($opts{playlists}) {
		foreach my $playlist (keys %playlists) {
			print "\nWriting $playlist.m3u...  ";
			if (writeplaylist($playlist . ".m3u", "Autoplaylist: $playlist", 
							  %{$playlists{$playlist}})) {
				print "(new)";
				processfile("$indir/$playlist.m3u");
			}
		}
	}

	return;
}

# Write out an m3u file from a hash of song info...
# Will return true if the file hadn't existed...
sub writeplaylist {
	my ($filename, $title, %listhash) = @_;
	my $newfile = undef;
	$newfile = 1 if (! -f "$indir/$filename");
	
	open(PLAYLIST, ">$indir/$filename") 
	  or die "Couldn't open playlist: $indir/$filename: $!";

	# FIXME: Do we actually need to use \r\n ??
	print PLAYLIST "# M3UTITLE $title\r\n";

	if(scalar(%listhash)) {
		foreach my $key (sort {
			$listhash{$a}->{DIR} cmp $listhash{$b}->{DIR} ||
			  ($listhash{$a}->{TRCK} || 0) <=> ($listhash{$b}->{TRCK} || 0)
		  } keys %listhash) {
			my $song = $listhash{$key};
			print PLAYLIST "$song->{DIR}$song->{FILE}\r\n";
		}
	}
	close(PLAYLIST);
	return $newfile;
}

sub get_tcd {
	# Look for .tcd files, whos contents override whatever file they're
	# named after.
	my $filepath = shift;

	my $datfile = $filepath . ".tcd";
	my %song;

	if ( -f $datfile) {
		# Use the .tcd file instead of whatever we can learn about the
		# thing.
		open (TDC, "<$datfile") or die "Couldn't open $datfile: $!";
		my $lineno = 0;
		while (my $grab = <TDC>) {
			$lineno++;
			if (($grab =~ /^\#/) || ($grab =~ /^\s*$/)) {
				next;
			} elsif ($grab =~ /^\s*TITLE=(.*)$/) {
				$song{TIT2} = $1;
			} elsif ($grab =~ /^\s*GENRE=(.*)$/) {
				$song{TCON} = $1;
			} elsif ($grab =~ /^\s*TRACK=(.*)$/) {
				$song{TRCK} = $1;
			} elsif ($grab =~ /^\s*ARTIST=(.*)$/) {
				$song{TPE1} = $1;
			} elsif ($grab =~ /^\s*ALBUM=(.*)$/) {
				$song{TALB} = $1;
			} elsif ($grab =~ /^\s*LENGTH=(.*)$/) {
				$song{TLEN} = $1;
			} else {
#				print "$datfile: Syntax error on line $lineno\n";
			}
		}
		close(TDC);
		return \%song;
	}
	return undef;
}

sub get_id3v2 {
	my $filepath = shift;
	my %song;

	if (!($filepath =~ /\.mp3$/i)) {
		return undef;
	}

	my $mp3 = MP3::Tag->new($filepath);
	if (!$mp3) {
		print STDERR "$filepath: Not an mp3 file?\n";
		return undef;
	}
	
	# Try ID3v2
	$mp3->getTags();
	return undef if (!exists($mp3->{ID3v2}));

	my $id3v2 = $mp3->{ID3v2};
	$song{TIT2} = $id3v2->getFrame("TIT2");
	$song{TCON} = $id3v2->getFrame("TCON");
	$song{TRCK} = $id3v2->getFrame("TRCK");
	$song{TPE1} = $id3v2->getFrame("TPE1") || 
	  $id3v2->getFrame("TPE2");
	$song{TALB} = $id3v2->getFrame("TALB");
	my $tlen  = $id3v2->getFrame("TLEN");
	if ($tlen) {
		$tlen = ($tlen / 1000);
		$song{TLEN} = $tlen;
	}
	
	# Get out of here if we're not gonna look for embedded playlist
	# tags.
	return \%song if (!$opts{playlists});
	

	# Look for playlists in tag
	my @pl = ( );
	my $ids = $id3v2->get_frame_ids();
	foreach my $i (keys %$ids) {
		if (!($i =~ /^TXXX/)) {
			next;
		}
		
		my ($info, $name) = $id3v2->get_frame($i);
		if (!ref($info)) {
			next;
		}
		
		if ($info->{Description} ne "WWP-PLAYLST") {
			next;
		}
		
		if (length($info->{Text}) > 1) {
			$song{PLAYLISTS} = $info->{Text};
			last;
			
		}
		next;
		
	}
	return \%song;
}


sub get_id3v1 {
	my $filepath = shift;
	my %song;

	if (!($filepath =~ /\.mp3$/i)) {
		return undef;
	}

	my $mp3 = MP3::Tag->new($filepath);
	if (!$mp3) {
		print STDERR "$filepath: Not an mp3 file?\n";
		return undef;
	}
	
	$mp3->getTags();
	if (exists $mp3->{ID3v1}) {
		my $id3v1 = $mp3->{ID3v1};
		
		$song{TIT2} = $id3v1->song();
		
		$song{TCON} = $id3v1->genre();
		$song{TRCK} = $id3v1->track();
		$song{TPE1} = $id3v1->artist();
		$song{TALB} = $id3v1->album();

		return \%song;
	}

	return undef;
}


sub get_m3u {
	my $filepath = shift;
	my %song;

	if (!($filepath =~ /\.m3u$/i)) {
		return undef;
	}

	# Scan it for M3UTITLE tags ...
	open(M3U, "<$filepath") or die "Couldn't open $filepath: $!";
	while (my $grab = <M3U>) {
		if ($grab =~ /^\#\s?M3UTITLE\s+(.*)$/) {
			$song{TIT2} = $1;
			return \%song;
		}
	}
	close(M3U);
	return undef;
}


sub get_wav {
	my $filepath = shift;
	my %song;

	if (!($filepath =~ /\.wav$/i)) {
		return undef;
	}
	my $wav = new Audio::Wav;
	my $read = $wav->read($filepath);
	if ($read) {
	    my $info = $read->get_info();
	  
		$song{TIT2} = $info->{name};
		$song{TCON} = $info->{genre};
		$song{TALB} = $info->{product};
		$song{TPE1} = $info->{artist};

		return \%song;
	}

	return undef;
}


sub get_pls {
	my $filepath = shift;
	my %song;

	if (!($filepath =~ /\.pls$/i)) {
		return undef;
	}

	return undef;
}


sub get_wma {
	my $filepath = shift;
	my %song;

	if (!($filepath =~ /\.pls$/i)) {
		return undef;
	}

	return undef;
}


sub get_fallthrough {
	my %song;

	return \%song;
}

sub usage {
	print STDERR <<EOF
Usage: $0 [-w][-m] <directory>
  
Options:
  -w [filename]        Create .m3u file with last 7 days of new/updated mp3s
  -m [filename]        Create .m3u file with last 31 days of new/updated mp3s
  <directory>          The directory from which the TOC is built.
EOF
;

    return;
}
