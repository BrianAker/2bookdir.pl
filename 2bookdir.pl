#!/usr/bin/env perl
use strict;
use warnings;

use File::Basename qw(basename dirname);
use File::Copy qw(copy move);
use File::Find qw(find);
use File::Path qw(make_path);
use File::Spec;
use Getopt::Long qw(GetOptions);
use IPC::Open3 qw(open3);
use Symbol qw(gensym);

my $help = 0;
GetOptions('help|h' => \$help) or usage(1);

usage(0) if $help;
usage(1) if @ARGV < 1;

my ($book_file, $part_number, $book_title) = parse_args(@ARGV);
my $is_dir_source = -d $book_file;
my @audio_files = find_audio_files($book_file);
my $audio_count = scalar @audio_files;

if (!-e $book_file) {
    die "Error: book_file '$book_file' does not exist.\n";
}
if (!-f $book_file && !-d $book_file) {
    die "Error: '$book_file' is not a regular file or directory.\n";
}

my $dir_name = build_dir_name($book_file, $part_number, $book_title);

if ($is_dir_source) {
    my $dest_dir = build_dir_target_path($book_file, $dir_name);
    if (-e $dest_dir) {
        die "Error: destination '$dest_dir' already exists.\n";
    }

    move($book_file, $dest_dir)
      or die "Error: failed to move '$book_file' to '$dest_dir': $!\n";

    maybe_rename_single_audio(
        source_root => $book_file,
        dest_root   => $dest_dir,
        title       => $book_title,
        part_number => $part_number,
        audio_files => \@audio_files,
    );
    maybe_create_cover_image($dest_dir);

    print "Moved: $book_file -> $dest_dir\n";
    exit 0;
}

if (-e $dir_name && !-d $dir_name) {
    die "Error: '$dir_name' exists and is not a directory.\n";
}
if (!-d $dir_name) {
    make_path($dir_name) or die "Error: failed to create directory '$dir_name': $!\n";
}

my $dest_file = "$dir_name/" . build_dest_name($book_file, $book_title, $audio_count);
if (-e $dest_file) {
    die "Error: destination file '$dest_file' already exists.\n";
}

move($book_file, $dest_file)
  or die "Error: failed to move '$book_file' to '$dest_file': $!\n";

if ($audio_count == 1 && defined $book_title && length $book_title) {
    tone_set_audio_metadata(
        path        => $dest_file,
        album       => album_name_from_path($dest_file),
        part_number => $part_number,
    );
} elsif ($audio_count == 1 && is_publishing_year($part_number)) {
    tone_set_publishing_date($dest_file, $part_number);
}

print "Created/used directory: $dir_name\n";
print "Moved: $book_file -> $dest_file\n";

sub build_dir_name {
    my ($file, $part, $title) = @_;

    my $resolved_title = defined $title && length $title
      ? $title
      : basename($file);

    $resolved_title =~ s/\.[^.]+$//;
    $resolved_title =~ s/^\s+|\s+$//g;
    $resolved_title =~ s/\s+/ /g;

    if (defined $part && length $part) {
        if (is_publishing_year($part)) {
            return sprintf('%s - %s', $part, sanitize($resolved_title));
        }
        return sprintf('Vol. %s - %s', $part, sanitize($resolved_title));
    }

    return sanitize($resolved_title);
}

sub build_dest_name {
    my ($file, $title, $audio_count) = @_;

    my $source_name = basename($file);
    my $is_file = -f $file;
    my $ext = '';
    if ($is_file) {
        my ($file_ext) = $source_name =~ /(\.[^.]+)$/;
        $ext = defined $file_ext ? $file_ext : '';
    }

    if (defined $title && length $title && $audio_count == 1) {
        my $name = $title;
        $name =~ s/^\s+|\s+$//g;
        $name =~ s/\s+/ /g;
        $name = sanitize($name);

        if ($is_file && $ext ne '' && $name !~ /\Q$ext\E$/i) {
            $name .= $ext;
        }

        return $name;
    }

    return $source_name;
}

sub find_audio_files {
    my ($path) = @_;

    if (-f $path) {
        return $path =~ /\.(?:mp3|mka|m4b)\z/i ? ($path) : ();
    }
    if (!-d $path) {
        return ();
    }

    my @files;
    find(
        {
            wanted => sub {
                return unless -f $_;
                return unless $_ =~ /\.(?:mp3|mka|m4b)\z/i;
                push @files, $File::Find::name;
            },
            no_chdir => 1,
        },
        $path,
    );

    return @files;
}

sub maybe_rename_single_audio {
    my (%args) = @_;
    my $title = $args{title};
    my $audio_files = $args{audio_files} // [];

    return if !defined $title || $title eq '';
    return if @$audio_files != 1;

    my $source_root = File::Spec->rel2abs($args{source_root});
    my $dest_root = File::Spec->rel2abs($args{dest_root});
    my $source_audio = File::Spec->rel2abs($audio_files->[0]);
    my $relative_audio = File::Spec->abs2rel($source_audio, $source_root);
    my $dest_audio = File::Spec->catfile($dest_root, $relative_audio);

    my ($ext) = $dest_audio =~ /(\.[^.]+)\z/;
    return if !defined $ext || $ext eq '';

    my $name = $title;
    $name =~ s/^\s+|\s+$//g;
    $name =~ s/\s+/ /g;
    $name = sanitize($name);
    my $renamed_audio = File::Spec->catfile(dirname($dest_audio), $name . $ext);

    return if $renamed_audio eq $dest_audio;
    if (-e $renamed_audio) {
        die "Error: destination file '$renamed_audio' already exists.\n";
    }

    move($dest_audio, $renamed_audio)
      or die "Error: failed to rename '$dest_audio' to '$renamed_audio': $!\n";

    tone_set_audio_metadata(
        path        => $renamed_audio,
        album       => album_name_from_path($renamed_audio),
        part_number => $args{part_number},
    );
}

sub maybe_create_cover_image {
    my ($dir) = @_;
    return if !defined $dir || !-d $dir;

    opendir my $dh, $dir or die "Error: failed to open directory '$dir': $!\n";
    my @entries = readdir $dh;
    closedir $dh or die "Error: failed to close directory '$dir': $!\n";

    my @candidates;
    for my $entry (@entries) {
        next if $entry eq '.' || $entry eq '..';
        next if $entry =~ /^cover\.(?:jpg|png)\z/i;
        next if $entry !~ /\.(jpg|png)\z/i;

        my $full = File::Spec->catfile($dir, $entry);
        next if !-f $full;

        my $size = -s $full;
        $size = 0 if !defined $size;
        my ($ext) = $entry =~ /\.(jpg|png)\z/i;
        push @candidates, { path => $full, size => $size, ext => lc($ext) };
    }

    return if !@candidates;

    my ($largest) = sort {
        $b->{size} <=> $a->{size}
          || $a->{path} cmp $b->{path}
    } @candidates;

    my $cover_path = File::Spec->catfile($dir, "cover.$largest->{ext}");
    copy($largest->{path}, $cover_path)
      or die "Error: failed to copy '$largest->{path}' to '$cover_path': $!\n";
}

sub album_name_from_path {
    my ($path) = @_;
    my $name = basename($path);
    $name =~ s/\.[^.]+\z//;
    return $name;
}

sub tone_set_audio_metadata {
    my (%args) = @_;
    my $path = $args{path};
    my $album = $args{album};
    my $part_number = $args{part_number};
    return if !defined $album || $album eq '';

    my @tag_cmd = ('tone', 'tag', '--meta-album', $album);
    if (defined $part_number && $part_number ne '' && !is_publishing_year($part_number)) {
        if ($part_number =~ /^\d+$/ && $part_number >= 0) {
            push @tag_cmd, '--meta-movement', $part_number;
        } else {
            push @tag_cmd, '--meta-part', $part_number;
        }
    } elsif (defined $part_number && is_publishing_year($part_number)) {
        push @tag_cmd, "--meta-publishing-date=$part_number-01-01";
    }
    push @tag_cmd, $path;

    my ($tag_exit, $tag_out, $tag_err) = run_external_cmd(@tag_cmd);
    my $tag_output = lc("$tag_out\n$tag_err");
    if ($tag_output =~ /\b(error|failed|panic|exception)\b/) {
        die "Error: tone tag failed for '$path': $tag_out$tag_err";
    }

    my ($dump_exit, $dump_out, $dump_err) = run_external_cmd(
        'tone', 'dump', $path, '--format', 'json', '--query', '$.meta.album'
    );
    my $dump_output = lc("$dump_out\n$dump_err");
    if ($dump_output =~ /\b(error|failed|panic|exception)\b/) {
        die "Error: tone dump failed for '$path': $dump_out$dump_err";
    }
    if ($dump_out !~ /\Q$album\E/) {
        die "Error: tone album verification failed for '$path': expected '$album', got '$dump_out'";
    }

    if (defined $part_number && $part_number ne '' && !is_publishing_year($part_number)) {
        if ($part_number =~ /^\d+$/ && $part_number >= 0) {
            my ($mv_exit, $mv_out, $mv_err) = run_external_cmd(
                'tone', 'dump', $path, '--format', 'json', '--query', '$.meta.movement'
            );
            my $mv_combined = lc("$mv_out\n$mv_err");
            if ($mv_combined =~ /\b(error|failed|panic|exception)\b/) {
                die "Error: tone movement verification failed for '$path': $mv_out$mv_err";
            }
            if ($mv_out !~ /\Q$part_number\E/) {
                die "Error: tone movement mismatch for '$path': expected '$part_number', got '$mv_out'";
            }
        } else {
            my ($part_exit, $part_out, $part_err) = run_external_cmd(
                'tone', 'dump', $path, '--format', 'json', '--query', '$.meta.part'
            );
            my $part_combined = lc("$part_out\n$part_err");
            if ($part_combined =~ /\b(error|failed|panic|exception)\b/) {
                die "Error: tone part verification failed for '$path': $part_out$part_err";
            }
            if ($part_out !~ /\Q$part_number\E/) {
                my ($alt_exit, $alt_out, $alt_err) = run_external_cmd(
                    'tone', 'dump', $path, '--format', 'json', '--query', '$.meta.additionalFields.part'
                );
                my $alt_combined = lc("$alt_out\n$alt_err");
                if ($alt_combined =~ /\b(error|failed|panic|exception)\b/) {
                    die "Error: tone part verification failed for '$path': $alt_out$alt_err";
                }
                if ($alt_out !~ /\Q$part_number\E/) {
                    die "Error: tone part mismatch for '$path': expected '$part_number', got '$part_out'";
                }
            }
        }
    } elsif (defined $part_number && is_publishing_year($part_number)) {
        verify_tone_publishing_date($path, $part_number);
    }
}

sub tone_set_publishing_date {
    my ($path, $year) = @_;
    return if !defined $year || !is_publishing_year($year);

    my ($tag_exit, $tag_out, $tag_err) = run_external_cmd(
        'tone', 'tag', "--meta-publishing-date=$year-01-01", $path
    );
    my $tag_output = lc("$tag_out\n$tag_err");
    if ($tag_output =~ /\b(error|failed|panic|exception)\b/) {
        die "Error: tone publishing-date tag failed for '$path': $tag_out$tag_err";
    }

    verify_tone_publishing_date($path, $year);
}

sub verify_tone_publishing_date {
    my ($path, $year) = @_;

    my ($pub_exit, $pub_out, $pub_err) = run_external_cmd(
        'tone', 'dump', $path, '--format', 'json'
    );
    my $pub_combined = lc("$pub_out\n$pub_err");
    if ($pub_combined =~ /\b(error|failed|panic|exception)\b/) {
        die "Error: tone publishing-date verification failed for '$path': $pub_out$pub_err";
    }
    if ($pub_out !~ /"publishingDate"\s*:\s*"\Q$year\E-01-01/) {
        die "Error: tone publishingDate mismatch for '$path': expected '$year-01-01', got '$pub_out'";
    }
}

sub run_external_cmd {
    my (@cmd) = @_;

    my $stderr_fh = gensym;
    my $stdout_fh;
    my $pid = eval { open3(undef, $stdout_fh, $stderr_fh, @cmd) };
    if (!$pid) {
        die "Error: failed to execute '@cmd': $@";
    }

    my $stdout = do { local $/; <$stdout_fh> // '' };
    my $stderr = do { local $/; <$stderr_fh> // '' };

    waitpid($pid, 0);
    my $exit = $? >> 8;

    return ($exit, $stdout, $stderr);
}

sub is_publishing_year {
    my ($value) = @_;
    return defined $value && $value =~ /^\d{4}$/;
}

sub build_dir_target_path {
    my ($source, $new_name) = @_;
    my $parent = dirname($source);

    return $new_name if $parent eq '.';
    return File::Spec->catdir($parent, $new_name);
}

sub sanitize {
    my ($name) = @_;

    $name =~ s/[\x00-\x1F\x7F]+/_/g;
    $name =~ s/\s+$//;
    $name =~ s/^\s+//;

    if (!length $name) {
        die "Error: resulting directory name is empty. Provide a valid book title.\n";
    }

    return $name;
}

sub usage {
    my ($exit_code) = @_;

    print <<'USAGE';
Usage: 2bookdir.pl [--help] book_file [part-number] [book title]

Arguments:
  book_file     Required. Path to the source book file or directory.
  part-number   Optional. Positive numeric value (for example: 2 or 2.1) used
                to prefix the directory as "Vol. N - ...". If it is a 4-digit
                year, it is treated as PublishingDate and the directory prefix
                becomes "YYYY - ...".
  book title    Optional. If omitted, the filename (without extension) is used.

Behavior:
  For file sources, creates the target directory if needed and moves book_file
  into it.
  For directory sources, renames/moves the source directory to the target
  volume directory name.
  If exactly one mp3/mka/m4b file is found in book_file, it is renamed to
  book title while preserving its extension. If more than one is found, files
  keep their original names. When a single audio file is renamed, its album
  metadata is updated via tone, plus movement for integer volume numbers or
  part for non-integer volume numbers. PublishingDate years set
  meta-publishing-date to YYYY-01-01.
  For directory sources, if one or more top-level jpg/png files exist that are
  not named cover.jpg/cover.png, the largest is copied to cover.jpg/cover.png.
USAGE

    exit $exit_code;
}

sub parse_args {
    my (@args) = @_;

    my ($file, @rest);
    if (-e $args[0]) {
        $file = shift @args;
        @rest = @args;
    } else {
        my $split = find_existing_file_prefix(@args);
        if (defined $split) {
            $file = join(' ', @args[0 .. $split]);
            @rest = @args[$split + 1 .. $#args];
        } else {
            $file = shift @args;
            @rest = @args;
        }
    }

    my ($part, $title);
    if (@rest && $rest[0] =~ /^\d+(?:\.\d+)*$/) {
        $part = shift @rest;
        $title = @rest ? join(' ', @rest) : undef;
    } else {
        $title = @rest ? join(' ', @rest) : undef;
    }

    return ($file, $part, $title);
}

sub find_existing_file_prefix {
    my (@args) = @_;

    return undef if @args < 2;

    for (my $i = $#args; $i >= 1; $i--) {
        my $candidate = join(' ', @args[0 .. $i]);
        return $i if -e $candidate;
    }

    return undef;
}
