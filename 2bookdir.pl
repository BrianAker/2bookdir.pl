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
use JSON::PP qw(encode_json);
use Symbol qw(gensym);

my $VERSION = '2026.02.18-1.5';

my $help = 0;
my $json_output = 0;
my $as_is = 0;
my $reverse = 0;
my $show_version = 0;
my $checkpoint = 0;
my $has_subtitle = 0;
my $series_override;
my $append_title;
GetOptions(
    'help|h'  => \$help,
    'json'    => \$json_output,
    'as-is'   => \$as_is,
    'reverse' => \$reverse,
    'version' => \$show_version,
    'checkpoint' => \$checkpoint,
    'has-subtitle' => \$has_subtitle,
    'series=s' => \$series_override,
    'append-title=s' => \$append_title,
    'apend-title=s'  => \$append_title,
) or usage(1);

usage(0) if $help;
if ($show_version) {
    print build_version() . "\n";
    exit 0;
}
usage(1) if @ARGV < 1;

my ($summary_title, $summary_subtitle, $summary_volume, $summary_year, $summary_author, $summary_series, $summary_asin, $summary_narrators);
my $ok = eval {
    my ($book_file, $part_number, $book_title, $inferred_meta) = parse_args($as_is, $reverse, $has_subtitle, $series_override, @ARGV);
    my $is_dir_source = -d $book_file;
    my @audio_files = find_audio_files($book_file);
    my $audio_count = scalar @audio_files;
    my $resolved_title = resolve_title($book_file, $book_title);
    if (defined $append_title && $append_title ne '') {
        $resolved_title = append_title_suffix($resolved_title, $append_title);
        $book_title = $resolved_title;
    }
    my ($resolved_volume, $resolved_year) = resolve_volume_and_year($part_number, $inferred_meta->{year});
    $summary_title = $resolved_title;
    $summary_subtitle = $inferred_meta->{subtitle};
    $summary_volume = $resolved_volume;
    $summary_year = $resolved_year;
    $summary_author = $inferred_meta->{author};
    $summary_series = $inferred_meta->{series};
    $summary_asin = $inferred_meta->{asin};
    $summary_narrators = $inferred_meta->{narrators};

    if (!-e $book_file) {
        die "Error: book_file '$book_file' does not exist.\n";
    }
    if (!-f $book_file && !-d $book_file) {
        die "Error: '$book_file' is not a regular file or directory.\n";
    }

    my $dir_name = build_dir_name($book_file, $part_number, $book_title, $inferred_meta->{year});

    if ($is_dir_source) {
        my $dest_dir = build_dir_target_path($book_file, $dir_name);
        my $source_abs = File::Spec->rel2abs($book_file);
        my $dest_abs = File::Spec->rel2abs($dest_dir);
        my $same_dir_target = $source_abs eq $dest_abs;

        if (-e $dest_dir && !$same_dir_target) {
            die "Error: destination '$dest_dir' already exists.\n";
        }

        if (!$same_dir_target) {
            move($book_file, $dest_dir)
              or die "Error: failed to move '$book_file' to '$dest_dir': $!\n";
        }

        maybe_rename_single_audio(
            source_root => $book_file,
            dest_root   => $dest_dir,
            title       => $resolved_title,
            bracket_segments => $inferred_meta->{bracket_segments},
            part_number => $part_number,
            author      => $inferred_meta->{author},
            series      => $inferred_meta->{series},
            year        => $inferred_meta->{year},
            asin        => $inferred_meta->{asin},
            subtitle    => $inferred_meta->{subtitle},
            audio_files => \@audio_files,
        );
        maybe_set_multi_audio_album(
            source_root => $book_file,
            dest_root   => $dest_dir,
            album       => $resolved_title,
            audio_files => \@audio_files,
        );
        maybe_create_cover_image($dest_dir);

        emit_success(
            json_output => $json_output,
            moved_from  => $book_file,
            moved_to    => $dest_dir,
            title       => $resolved_title,
            volume      => $resolved_volume,
            year        => $resolved_year,
            author      => $inferred_meta->{author},
            series      => $inferred_meta->{series},
            asin        => $inferred_meta->{asin},
            subtitle    => $inferred_meta->{subtitle},
            narrators   => $inferred_meta->{narrators},
        );
        return 1;
    }

    if (-e $dir_name && !-d $dir_name) {
        die "Error: '$dir_name' exists and is not a directory.\n";
    }
    if (!-d $dir_name) {
        make_path($dir_name) or die "Error: failed to create directory '$dir_name': $!\n";
    }

    my $dest_file = "$dir_name/" . build_dest_name(
        $book_file,
        $book_title,
        $audio_count,
        $inferred_meta->{bracket_segments},
    );
    if (-e $dest_file) {
        die "Error: destination file '$dest_file' already exists.\n";
    }

    move($book_file, $dest_file)
      or die "Error: failed to move '$book_file' to '$dest_file': $!\n";

    if ($audio_count == 1) {
        tone_set_audio_metadata(
            path        => $dest_file,
            album       => $resolved_title,
            title       => $resolved_title,
            part_number => $part_number,
            author      => $inferred_meta->{author},
            series      => $inferred_meta->{series},
            year        => $inferred_meta->{year},
            asin        => $inferred_meta->{asin},
            subtitle    => $inferred_meta->{subtitle},
            narrators   => $inferred_meta->{narrators},
        );
    }

    emit_success(
        json_output => $json_output,
        created_dir => $dir_name,
        moved_from  => $book_file,
        moved_to    => $dest_file,
        title       => $resolved_title,
        volume      => $resolved_volume,
        year        => $resolved_year,
        author      => $inferred_meta->{author},
        series      => $inferred_meta->{series},
        asin        => $inferred_meta->{asin},
        subtitle    => $inferred_meta->{subtitle},
        narrators   => $inferred_meta->{narrators},
    );
    return 1;
};

if (!$ok) {
    my $error = $@ || "Error: unknown failure.\n";
    chomp $error;
    emit_failure(
        json_output => $json_output,
        error       => $error,
        title       => $summary_title,
        subtitle    => $summary_subtitle,
        volume      => $summary_volume,
        year        => $summary_year,
        author      => $summary_author,
        series      => $summary_series,
        asin        => $summary_asin,
        narrators   => $summary_narrators,
    );
    exit 1;
}

exit 0;

sub build_dir_name {
    my ($file, $part, $title, $year_hint) = @_;

    my $title_from_arg = defined $title && length $title;
    my $resolved_title = $title_from_arg ? $title : basename($file);

    # Strip extension only for file sources; directory names may contain dots.
    if (-f $file && !$title_from_arg) {
        $resolved_title =~ s/\.[^.]+$//;
    }
    $resolved_title = decode_book_file_name($resolved_title);
    $resolved_title =~ s/^\s+|\s+$//g;
    $resolved_title =~ s/\s+/ /g;

    my $prefix_value = defined $part && length $part ? $part : $year_hint;
    if (defined $prefix_value && length $prefix_value) {
        if (is_publishing_year($prefix_value)) {
            return sprintf('%s - %s', $prefix_value, sanitize($resolved_title));
        }
        return sprintf('Vol. %s - %s', $prefix_value, sanitize($resolved_title));
    }

    return sanitize($resolved_title);
}

sub resolve_title {
    my ($file, $title) = @_;

    my $title_from_arg = defined $title && length $title;
    my $resolved = $title_from_arg ? $title : basename($file);

    if (-f $file && !$title_from_arg) {
        $resolved =~ s/\.[^.]+$//;
    }
    $resolved = decode_book_file_name($resolved);
    $resolved =~ s/^\s+|\s+$//g;
    $resolved =~ s/\s+/ /g;
    return sanitize($resolved);
}

sub resolve_volume_and_year {
    my ($part, $year_hint) = @_;

    my $volume;
    my $year = $year_hint;

    if (defined $part && $part ne '') {
        if (is_publishing_year($part) && !defined $year_hint) {
            $year = $part;
        } else {
            $volume = $part;
        }
    }

    return ($volume, $year);
}

sub print_summary {
    my ($title, $subtitle, $volume, $year, $author, $series, $asin, $narrators) = @_;

    print "Title: $title\n";
    print "Subtitle: $subtitle\n" if defined $subtitle && $subtitle ne '';
    print "Volume: $volume\n" if defined $volume && $volume ne '';
    print "Year: $year\n" if defined $year && $year ne '';
    print "Author: $author\n" if defined $author && $author ne '';
    print "Series: $series\n" if defined $series && $series ne '';
    print "ASIN: $asin\n" if defined $asin && $asin ne '';
    print "Narrators: $narrators\n" if defined $narrators && $narrators ne '';
}

sub emit_success {
    my (%args) = @_;
    if ($args{json_output}) {
        print encode_json({
            response => 'success',
            meta => {
                title  => $args{title},
                subtitle => $args{subtitle},
                volume => $args{volume},
                year   => $args{year},
                author => $args{author},
                series => $args{series},
                asin   => $args{asin},
                narrators => $args{narrators},
            },
        }) . "\n";
        return;
    }

    print "Created/used directory: $args{created_dir}\n" if defined $args{created_dir};
    print "Moved: $args{moved_from} -> $args{moved_to}\n";
    print_summary($args{title}, $args{subtitle}, $args{volume}, $args{year}, $args{author}, $args{series}, $args{asin}, $args{narrators});
}

sub emit_failure {
    my (%args) = @_;
    if ($args{json_output}) {
        print encode_json({
            response => 'failure',
            error    => $args{error},
            meta => {
                title  => $args{title},
                subtitle => $args{subtitle},
                volume => $args{volume},
                year   => $args{year},
                author => $args{author},
                series => $args{series},
                asin   => $args{asin},
                narrators => $args{narrators},
            },
        }) . "\n";
        return;
    }

    my $error = $args{error};
    $error .= "\n" if $error !~ /\n\z/;
    print STDERR $error;
}

sub build_dest_name {
    my ($file, $title, $audio_count, $bracket_segments) = @_;

    my $source_name = basename($file);
    my $is_file = -f $file;
    my $ext = '';
    if ($is_file) {
        my ($file_ext) = $source_name =~ /(\.[^.]+)$/;
        $ext = defined $file_ext ? $file_ext : '';
    }

    if (defined $title && length $title && $audio_count == 1) {
        my $name = append_bracket_segments($title, $bracket_segments);
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
    my $bracket_segments = $args{bracket_segments};
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

    my $name = append_bracket_segments($title, $bracket_segments);
    $name =~ s/^\s+|\s+$//g;
    $name =~ s/\s+/ /g;
    $name = sanitize($name);
    my $renamed_audio = File::Spec->catfile(dirname($dest_audio), $name . $ext);

    if ($renamed_audio ne $dest_audio) {
        if (-e $renamed_audio) {
            die "Error: destination file '$renamed_audio' already exists.\n";
        }

        move($dest_audio, $renamed_audio)
          or die "Error: failed to rename '$dest_audio' to '$renamed_audio': $!\n";
    }

    tone_set_audio_metadata(
        path        => $renamed_audio,
        album       => $title,
        title       => $title,
        part_number => $args{part_number},
        author      => $args{author},
        series      => $args{series},
        year        => $args{year},
        asin        => $args{asin},
        subtitle    => $args{subtitle},
        narrators   => $args{narrators},
    );
}

sub maybe_set_multi_audio_album {
    my (%args) = @_;
    my $album = $args{album};
    my $audio_files = $args{audio_files} // [];

    return if !defined $album || $album eq '';
    return if @$audio_files <= 1;

    my $source_root = File::Spec->rel2abs($args{source_root});
    my $dest_root = File::Spec->rel2abs($args{dest_root});

    for my $source_audio (@$audio_files) {
        my $source_abs = File::Spec->rel2abs($source_audio);
        my $relative_audio = File::Spec->abs2rel($source_abs, $source_root);
        my $dest_audio = File::Spec->catfile($dest_root, $relative_audio);
        next if !-f $dest_audio;

        tone_set_album_only(
            path  => $dest_audio,
            album => $album,
        );
    }
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
    if (-f $cover_path) {
        my $cover_orig_path = File::Spec->catfile($dir, "cover-orig.$largest->{ext}");
        my $cover_matches_largest = files_identical($cover_path, $largest->{path});
        if (!$cover_matches_largest) {
            if (!-e $cover_orig_path) {
                copy($cover_path, $cover_orig_path)
                  or die "Error: failed to copy '$cover_path' to '$cover_orig_path': $!\n";
            } elsif (!files_identical($cover_orig_path, $cover_path)) {
                # Keep existing non-duplicate backup as-is; do not overwrite.
            }
        }
    }

    if (!-f $cover_path || !files_identical($largest->{path}, $cover_path)) {
        copy($largest->{path}, $cover_path)
          or die "Error: failed to copy '$largest->{path}' to '$cover_path': $!\n";
    }
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
    my $title = $args{title};
    my $part_number = $args{part_number};
    my $author = $args{author};
    my $series = $args{series};
    my $year = $args{year};
    my $asin = $args{asin};
    my $subtitle = $args{subtitle};
    my $narrators = $args{narrators};
    return if (!defined $album || $album eq '') && (!defined $title || $title eq '');

    my @tag_cmd = ('tone', 'tag');
    push @tag_cmd, '--meta-album', $album if defined $album && $album ne '';
    push @tag_cmd, '--meta-title', $title if defined $title && $title ne '';
    push @tag_cmd, '--meta-artist', $author if defined $author && $author ne '';
    push @tag_cmd, '--meta-movement-name', $series if defined $series && $series ne '';
    push @tag_cmd, '--meta-additional-field', "AUDIBLE_ASIN=$asin" if defined $asin && $asin ne '';
    push @tag_cmd, '--meta-subtitle', $subtitle if defined $subtitle && $subtitle ne '';
    push @tag_cmd, '--meta-composer', $narrators if defined $narrators && $narrators ne '';
    push @tag_cmd, '--meta-narrator', $narrators if defined $narrators && $narrators ne '';
    if (defined $part_number && $part_number ne '' && !is_publishing_year($part_number)) {
        if ($part_number =~ /^\d+$/ && $part_number >= 0) {
            push @tag_cmd, '--meta-movement', $part_number;
        } else {
            push @tag_cmd, '--meta-part', $part_number;
            my $whole_number = movement_from_part_number($part_number);
            push @tag_cmd, '--meta-movement', $whole_number if defined $whole_number;
        }
    } elsif (defined $part_number && is_publishing_year($part_number)) {
        push @tag_cmd, "--meta-publishing-date=$part_number-01-01";
    }
    if (defined $year && is_publishing_year($year)) {
        push @tag_cmd, "--meta-publishing-date=$year-01-01";
    }
    push @tag_cmd, $path;

    my ($tag_exit, $tag_out, $tag_err) = run_external_cmd(@tag_cmd);
    my $tag_output = lc("$tag_out\n$tag_err");
    if ($tag_output =~ /\b(error|failed|panic|exception)\b/) {
        die "Error: tone tag failed for '$path': $tag_out$tag_err";
    }
    tone_postprocess($path);

    if (defined $album && $album ne '') {
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
    }
    if (defined $title && $title ne '') {
        my ($title_exit, $title_out, $title_err) = run_external_cmd(
            'tone', 'dump', $path, '--format', 'json', '--query', '$.meta.title'
        );
        my $title_output = lc("$title_out\n$title_err");
        if ($title_output =~ /\b(error|failed|panic|exception)\b/) {
            die "Error: tone title verification failed for '$path': $title_out$title_err";
        }
        if ($title_out !~ /\Q$title\E/) {
            die "Error: tone title mismatch for '$path': expected '$title', got '$title_out'";
        }
    }
    if (defined $subtitle && $subtitle ne '') {
        my ($sub_exit, $sub_out, $sub_err) = run_external_cmd(
            'tone', 'dump', $path, '--format', 'json', '--query', '$.meta.subtitle'
        );
        my $sub_combined = lc("$sub_out\n$sub_err");
        if ($sub_combined =~ /\b(error|failed|panic|exception)\b/) {
            die "Error: tone subtitle verification failed for '$path': $sub_out$sub_err";
        }
        if ($sub_out !~ /\Q$subtitle\E/) {
            my ($alt_exit, $alt_out, $alt_err) = run_external_cmd(
                'tone', 'dump', $path, '--format', 'json', '--query', '$.meta.additionalFields.subtitle'
            );
            my $alt_combined = lc("$alt_out\n$alt_err");
            if ($alt_combined =~ /\b(error|failed|panic|exception)\b/) {
                die "Error: tone subtitle verification failed for '$path': $alt_out$alt_err";
            }
            if ($alt_out !~ /\Q$subtitle\E/) {
                die "Error: tone subtitle mismatch for '$path': expected '$subtitle', got '$sub_out'";
            }
        }
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

            my $whole_number = movement_from_part_number($part_number);
            if (defined $whole_number) {
                my ($mv_exit, $mv_out, $mv_err) = run_external_cmd(
                    'tone', 'dump', $path, '--format', 'json', '--query', '$.meta.movement'
                );
                my $mv_combined = lc("$mv_out\n$mv_err");
                if ($mv_combined =~ /\b(error|failed|panic|exception)\b/) {
                    die "Error: tone movement verification failed for '$path': $mv_out$mv_err";
                }
                if ($mv_out !~ /\Q$whole_number\E/) {
                    die "Error: tone movement mismatch for '$path': expected '$whole_number', got '$mv_out'";
                }
            }
        }
    } elsif (defined $part_number && is_publishing_year($part_number)) {
        verify_tone_publishing_date($path, $part_number);
    }
    if (defined $year && is_publishing_year($year)) {
        verify_tone_publishing_date($path, $year);
    }
    if (defined $asin && $asin ne '') {
        my ($dump_exit, $dump_out, $dump_err) = run_external_cmd(
            'tone', 'dump', $path, '--format', 'json'
        );
        my $dump_combined = lc("$dump_out\n$dump_err");
        if ($dump_combined =~ /\b(error|failed|panic|exception)\b/) {
            die "Error: tone AUDIBLE_ASIN verification failed for '$path': $dump_out$dump_err";
        }
        if ($dump_out !~ /"additionalFields"\s*:\s*\{[\s\S]*?"[^"]*ASIN"\s*:\s*"\Q$asin\E"/i) {
            die "Error: tone AUDIBLE_ASIN mismatch for '$path': expected '$asin'";
        }
    }
}

sub tone_set_album_only {
    my (%args) = @_;
    my $path = $args{path};
    my $album = $args{album};

    return if !defined $album || $album eq '';

    my ($tag_exit, $tag_out, $tag_err) = run_external_cmd(
        'tone', 'tag', '--meta-album', $album, $path
    );
    my $tag_output = lc("$tag_out\n$tag_err");
    if ($tag_output =~ /\b(error|failed|panic|exception)\b/) {
        die "Error: tone album tag failed for '$path': $tag_out$tag_err";
    }
    tone_postprocess($path);

    my ($dump_exit, $dump_out, $dump_err) = run_external_cmd(
        'tone', 'dump', $path, '--format', 'json', '--query', '$.meta.album'
    );
    my $dump_output = lc("$dump_out\n$dump_err");
    if ($dump_output =~ /\b(error|failed|panic|exception)\b/) {
        die "Error: tone album verification failed for '$path': $dump_out$dump_err";
    }
    if ($dump_out !~ /\Q$album\E/) {
        die "Error: tone album mismatch for '$path': expected '$album', got '$dump_out'";
    }
}

sub movement_from_part_number {
    my ($part_number) = @_;
    return undef if !defined $part_number || $part_number eq '';

    if ($part_number =~ /^(\d+)(?:\..+)?$/) {
        return int($1);
    }

    return undef;
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
    tone_postprocess($path);

    verify_tone_publishing_date($path, $year);
}

sub tone_postprocess {
    my ($path) = @_;

    my ($post_exit, $post_out, $post_err) = run_external_cmd(
        'tone',
        'tag',
        '--taggers=remove,m4bfillup',
        '--meta-remove-property=sortalbum',
        '--meta-remove-property=sorttitle',
        $path,
    );
    my $post_output = lc("$post_out\n$post_err");
    if ($post_output =~ /\b(error|failed|panic|exception)\b/) {
        die "Error: tone postprocess failed for '$path': $post_out$post_err";
    }
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

sub files_identical {
    my ($left, $right) = @_;
    return 0 if !defined $left || !defined $right;
    return 0 if !-f $left || !-f $right;

    my $left_size = -s $left;
    my $right_size = -s $right;
    return 0 if !defined $left_size || !defined $right_size;
    return 0 if $left_size != $right_size;

    open my $lfh, '<', $left or return 0;
    open my $rfh, '<', $right or do { close $lfh; return 0; };
    binmode $lfh;
    binmode $rfh;

    my ($lbuf, $rbuf);
    while (1) {
        my $lread = read($lfh, $lbuf, 8192);
        my $rread = read($rfh, $rbuf, 8192);
        if (!defined $lread || !defined $rread) {
            close $lfh;
            close $rfh;
            return 0;
        }
        last if $lread == 0 && $rread == 0;
        if ($lread != $rread || $lbuf ne $rbuf) {
            close $lfh;
            close $rfh;
            return 0;
        }
    }

    close $lfh;
    close $rfh;
    return 1;
}

sub is_publishing_year {
    my ($value) = @_;
    return defined $value && $value =~ /^\d{4}$/;
}

sub parse_year_token {
    my ($value) = @_;
    return undef if !defined $value;
    my $clean = trim($value);

    return $1 if $clean =~ /^(\d{4})$/;
    return $1 if $clean =~ /^\((\d{4})\)$/;
    return $1 if $clean =~ /^\[(\d{4})\]$/;
    return undef;
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
Usage: 2bookdir.pl [--help] [--version] [--json] [--as-is] [--reverse] [--has-subtitle] [--series SERIES] [--append-title TEXT] book_file [part-number] [book title]

Arguments:
  book_file     Required. Path to the source book file or directory.
  --reverse     Optional. Reverse title/author position for supported
                dash-split inference formats.
  --has-subtitle Optional. For dash-split inference, treat the last segment
                as subtitle metadata and remove it from title parsing.
  --series      Optional. Explicit series name. If the series value ends with
                a number, that number is used as inferred volume.
  --append-title Optional. Appends TEXT to the resolved title separated by a
                single space. Alias: --apend-title.
  part-number   Optional. Positive numeric value (for example: 2 or 2.1) used
                to prefix the directory as "Vol. N - ...". If it is a 4-digit
                year, it is treated as PublishingDate and the directory prefix
                becomes "YYYY - ...".
  book title    Optional album name. If omitted, the filename (without
                extension) is used.

Behavior:
  For file sources, creates the target directory if needed and moves book_file
  into it.
  For directory sources, renames/moves the source directory to the target
  volume directory name.
  If exactly one mp3/mka/m4b file is found in book_file, it is renamed to
  book title/album name while preserving its extension. If more than one is
  found, files keep their original names. For single-audio cases, album and
  title metadata are updated via tone, plus movement for integer volume
  numbers or part for non-integer volume numbers. PublishingDate years set
  meta-publishing-date to YYYY-01-01.
  For directory sources, if one or more top-level jpg/png files exist that are
  not named cover.jpg/cover.png, the largest is copied to cover.jpg/cover.png.
USAGE

    exit $exit_code;
}

sub build_version {
    return $VERSION;
}

sub parse_args {
    my ($as_is_mode, $reverse_mode, $has_subtitle_mode, $series_override_value, @args) = @_;

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
    my %inferred_meta;
    if (defined $series_override_value && $series_override_value ne '') {
        my ($first_pass, $series_volume, $has_series_volume) = extract_series_and_volume($series_override_value);
        $inferred_meta{series} = $first_pass;
        $part = $series_volume if $has_series_volume && defined $series_volume;
    }
    if (@rest && $rest[0] =~ /^\d+(?:\.\d+)*$/) {
        $part = shift @rest;
        $title = @rest ? join(' ', @rest) : undef;
    } else {
        $title = @rest ? join(' ', @rest) : undef;
    }

    # If only book_file is provided and it starts with "NUMBER - TITLE",
    # infer part-number and title from the source name.
    if (!defined $part && !defined $title) {
        my $raw_source_name = basename($file);
        my $source_name_modified = 0;
        if (-f $file) {
            $raw_source_name =~ s/\.[^.]+\z//;
        }
        if (!$as_is_mode) {
            my $marker_count = () = $raw_source_name =~ /(?<=\S)_\s/g;
            if ($marker_count == 1 && $raw_source_name =~ /^(.*\S)_\s(.+)$/) {
                my $split_title = trim(decode_book_file_name($1));
                my $split_subtitle = trim(decode_book_file_name($2));
                if ($split_title ne '' && $split_subtitle ne '') {
                    $title = $split_title;
                    $inferred_meta{subtitle} = $split_subtitle if !defined $inferred_meta{subtitle};
                    $source_name_modified = 1;
                    infer_from_subtitle_segment(
                        subtitle => $split_subtitle,
                        part_ref => \$part,
                        meta_ref => \%inferred_meta,
                    );
                }
            }
        }
        my $source_name = $raw_source_name;
        $source_name = decode_book_file_name($source_name);
        { # PARSE UNABRIDGED BLOCK
            if ($source_name =~ /\(UNABRIDGED\)\s*$/i) {
                $source_name =~ s/\s*\(UNABRIDGED\)\s*$//i;
                $source_name = trim($source_name);
                $source_name_modified = 1;
                print "CHECKPOINT: 1: UNABRIDGED\n";
            }
        }
        { # PARSE ASIN BLOCK
            my @bracket_segments = map { trim($_) } ($source_name =~ /\[([^\[\]]+)\]/g);
            @bracket_segments = grep { $_ ne '' } @bracket_segments;
            if (@bracket_segments) {
                $inferred_meta{bracket_segments} = [@bracket_segments];
                $source_name =~ s/\s*\[[^\[\]]+\]\s*//g;
                $source_name = trim($source_name);
                $source_name =~ s/\s+/ /g;
                $source_name_modified = 1;

                for my $segment (@bracket_segments) {
                    if (!defined $inferred_meta{asin} && $segment =~ /^([B0][A-Z0-9]{9})$/) {
                        $inferred_meta{asin} = $1;
                        print "CHECKPOINT: 1: ASIN\n" if $checkpoint;
                    }
                    if (!defined $inferred_meta{year}) {
                        my $parsed_year = parse_year_token($segment);
                        $inferred_meta{year} = $parsed_year if defined $parsed_year;
                    }
                }
            }
        }
        { # PARSE NARRATOR BLOCK
            if ($source_name =~ /\{([^{}]+)\}\s*$/) {
                $inferred_meta{narrators} = trim($1);
                $source_name =~ s/\s*\{[^{}]+\}\s*$//;
                $source_name = trim($source_name);
                $source_name_modified = 1;
                print "CHECKPOINT: 1: NARRATOR\n" if $checkpoint;
            }
        }
        my @dash_split = map { trim($_) } split /\s-\s/, $source_name;

        { # PARSE SUBTITLE BLOCK
            if ($has_subtitle_mode && @dash_split >= 2) {
                $inferred_meta{subtitle} = pop @dash_split;
                $source_name_modified = 1;
                print "CHECKPOINT: 1: SUBTITLE\n" if $checkpoint;
            }
        }

        if (!defined $title && @dash_split == 1 && defined $inferred_meta{subtitle}) {
            my ($first_pass, $series_volume, $has_series_volume) = extract_series_and_volume($dash_split[0]);
            if ($has_series_volume) {
                $title = $dash_split[0];
                $part = $series_volume if !defined $part;
            } else {
                $title = $dash_split[0];
            }
        }

        if (@dash_split >= 2 && @dash_split <= 4) {
            my @work = @dash_split;
            { # PARSE YEAR BLOCK
              my $parsed_year = parse_year_token($work[0]);
              if (defined $parsed_year) {
                $inferred_meta{year} = $parsed_year;
                shift @work;
                print "CHECKPOINT: 1: YEAR\n" if $checkpoint;
              }
            }
            { # PARSE VOLUME BLOCK
              for (my $i = 0; $i < @work; $i++) {
                my ($volume, $remaining_title) = parse_volume_segment($work[$i]);
                next if !defined $volume;
                $part = $volume if !defined $part;
                if (defined $remaining_title && $remaining_title ne '') {
                    $work[$i] = $remaining_title;
                } else {
                    splice @work, $i, 1;
                }
                print "CHECKPOINT: 2: VOLUME\n" if $checkpoint;
                last;
              }
            }
            { # PARSE YEAR BLOCK (after volume extraction)
              my $parsed_year = @work ? parse_year_token($work[0]) : undef;
              if (!defined $inferred_meta{year} && defined $parsed_year) {
                $inferred_meta{year} = $parsed_year;
                shift @work;
                print "CHECKPOINT: 1: YEAR\n" if $checkpoint;
              }
            }

            if (@work == 3) {
                if ($reverse_mode) {
                    @work[0,2] = @work[2,0];
                }
                $inferred_meta{author} = $work[0];
                my ($first_pass, $series_volume, $has_series_volume) = extract_series_and_volume($work[1]);
                $inferred_meta{series} = $first_pass;
                $title = $work[2];
                $part = $series_volume if defined $series_volume;
            } elsif (@work == 1) {
                # Handle cases where year and/or volume tokens were removed and one title remains.
                $title = $work[0];
            } elsif (@work == 2) {
                my $candidate;
                if ($reverse_mode) {
                    $title = $work[0];
                    $candidate = $work[1];
                } else {
                    $title = $work[1];
                    $candidate = $work[0];
                }
                if (!defined $part && $candidate =~ /^\d+(?:\.\d+)*$/) {
                    $part = normalize_inferred_part_number($candidate);
                } elsif (!defined $part && $candidate =~ /^\s*(\d+)\.\s+(.+?)\s*$/) {
                    $part = normalize_inferred_part_number($1);
                    $inferred_meta{series} = trim($2) if trim($2) ne '';
                } else {
                    my ($first_pass, $series_volume, $has_series_volume) = extract_series_and_volume($candidate);
                    if ($has_series_volume) {
                        $inferred_meta{series} = $first_pass;
                        $part = $series_volume if defined $series_volume;
                    } else {
                        $inferred_meta{author} = $candidate;
                    }
                }
                if (!defined $part && defined $title) {
                    my $suffix_part = infer_suffix_volume_number($title);
                    $part = $suffix_part if defined $suffix_part;
                }
            }
        }

        if (!defined $part && !defined $title) {
            if (@dash_split == 2 && $dash_split[0] =~ /^\d+(?:\.\d+)*$/) {
                $part = normalize_inferred_part_number($dash_split[0]);
                $title = $dash_split[1];
            } elsif (
                !$as_is_mode
                && $source_name =~ /^\s*(\d+)\.\s+(.+?)\s*$/
            ) {
                # Inference mode for names like "101. Title".
                $part = normalize_inferred_part_number($1);
                $title = $2;
            } elsif (
                !$as_is_mode
                && $source_name =~ /^\s*(\d+(?:\.\d+)*)\s+(.+?)\s*$/
            ) {
                # New inference mode for names like "02 Title" when no separator is present.
                $part = normalize_inferred_part_number($1);
                $title = $2;
            } elsif (
                !$as_is_mode
                && $source_name =~ /^\s*(.+?)\s+Volume\s+(\d+)\s*$/i
            ) {
                $part = normalize_inferred_part_number($2);
                $title = $source_name;
            } elsif (
                !$as_is_mode
                && $source_name =~ /^\s*(.+?)\s+Vol\s+(\d+)\s*$/i
            ) {
                $part = normalize_inferred_part_number($2);
                $title = $source_name;
            } elsif (
                !$as_is_mode
                && $source_name =~ /^\s*(.+?)\s+Book\s+(\d+)\s*$/i
            ) {
                $part = normalize_inferred_part_number($2);
                $title = $source_name;
            } elsif (
                !$as_is_mode
                && $source_name =~ /^\s*(.+?)\s+(\d+)\s*$/
            ) {
                $part = normalize_inferred_part_number($2);
                $title = $source_name;
            } elsif (
                !$as_is_mode
                && $source_name =~ /^\s*(.+?)\s*[\(\[](\d{4})[\)\]]\s*$/
            ) {
                $inferred_meta{year} = $2 if !defined $inferred_meta{year};
                $title = trim($1);
            }
        }

        if (!defined $title && $source_name_modified) {
            $title = $source_name;
        }

        # Final pass: infer subtitle from title patterns like "Title: Subtitle"
        # or "Title- Subtitle". This is disabled when --as-is is used.
        if (!$as_is_mode) {
            my $subtitle_source = defined $title ? $title : $source_name;
            if (defined $subtitle_source && $subtitle_source =~ /^(.*?\w.*?)(?::\s+|-\s+)(.+)$/) {
                my $parsed_title = trim($1);
                my $parsed_subtitle = trim($2);
                if ($parsed_title ne '' && $parsed_subtitle ne '') {
                    $title = $parsed_title;
                    $inferred_meta{subtitle} = $parsed_subtitle if !defined $inferred_meta{subtitle};
                }
            }
        }
    }

    return ($file, $part, $title, \%inferred_meta);
}

sub decode_book_file_name {
    my ($value) = @_;
    return '' if !defined $value;
    $value =~ s/__/꞉/g;
    $value =~ s/_/ /g;
    return $value;
}

sub append_bracket_segments {
    my ($name, $segments) = @_;
    return $name if !defined $name || $name eq '';
    return $name if !defined $segments || ref($segments) ne 'ARRAY' || !@$segments;

    my @normalized = map { trim($_) } @$segments;
    @normalized = grep { $_ ne '' } @normalized;
    return $name if !@normalized;

    my $suffix = join(' ', map { "[$_]" } @normalized);
    return "$name $suffix";
}

sub infer_from_subtitle_segment {
    my (%args) = @_;
    my $subtitle = $args{subtitle};
    my $part_ref = $args{part_ref};
    my $meta_ref = $args{meta_ref};
    return if !defined $subtitle || $subtitle eq '';

    my $scan = trim($subtitle);
    return if $scan eq '';

    if (!defined $meta_ref->{narrators} && $scan =~ /\{([^{}]+)\}\s*$/) {
        my $narrator = trim($1);
        $meta_ref->{narrators} = $narrator if $narrator ne '';
    }

    my $scan_no_narrator = $scan;
    $scan_no_narrator =~ s/\s*\{[^{}]+\}\s*$//;
    $scan_no_narrator = trim($scan_no_narrator);

    if (!defined $meta_ref->{year}) {
        my $year = parse_year_token($scan_no_narrator);
        if (!defined $year && $scan_no_narrator =~ /[\(\[](\d{4})[\)\]]\s*$/) {
            $year = $1;
        }
        if (!defined $year && $scan_no_narrator =~ /\b(\d{4})\s*$/) {
            $year = $1;
        }
        $meta_ref->{year} = $year if defined $year;
    }

    my $scan_for_volume = $scan_no_narrator;
    $scan_for_volume =~ s/\s*[\(\[]\d{4}[\)\]]\s*$//;
    $scan_for_volume =~ s/\b\d{4}\s*$//;
    $scan_for_volume = trim($scan_for_volume);

    if (!defined $$part_ref) {
        my ($volume, undef) = parse_volume_segment($scan_for_volume);
        if (defined $volume) {
            $$part_ref = $volume;
        } else {
            my $suffix_volume = infer_suffix_volume_number($scan_for_volume);
            $$part_ref = $suffix_volume if defined $suffix_volume;
        }
    }
}

sub append_title_suffix {
    my ($title, $suffix) = @_;
    my $base = trim($title // '');
    my $extra = trim($suffix // '');
    return $base if $extra eq '';
    return $extra if $base eq '';
    return "$base $extra";
}

sub normalize_inferred_part_number {
    my ($value) = @_;
    return $value if !defined $value || $value eq '';

    my @segments = split /\./, $value;
    $segments[0] = int($segments[0]);
    return join('.', @segments);
}

sub trim {
    my ($value) = @_;
    return '' if !defined $value;
    $value =~ s/^\s+|\s+$//g;
    return $value;
}

sub extract_series_and_volume {
    my ($series) = @_;
    my $clean = trim($series);
    return ('', undef, 0) if $clean eq '';

    my @tokens = split /\s+/, $clean;
    my $last = $tokens[-1];
    if ($last =~ /^(\d+(?:\.\d+)?)$/) {
        my $volume = normalize_inferred_part_number($1);
        pop @tokens;
        my $first_pass = trim(join(' ', @tokens));
        $first_pass = $clean if $first_pass eq '';
        return ($first_pass, $volume, 1);
    }

    return ($clean, undef, 0);
}

sub parse_volume_segment {
    my ($value) = @_;
    my $clean = trim($value);
    return (undef, undef) if $clean eq '';

    if ($clean =~ /^(?:Volume|Vol\.?|Book)\s+(\d+)$/i) {
        return (normalize_inferred_part_number($1), undef);
    }
    if ($clean =~ /^(?:Volume|Vol\.?|Book)\s+(\d+)\.\s+(.+)$/i) {
        return (normalize_inferred_part_number($1), trim($2));
    }

    return (undef, undef);
}

sub infer_suffix_volume_number {
    my ($name) = @_;
    return undef if !defined $name;

    if ($name =~ /^\s*(.+?)\s+Volume\s+(\d+)\s*$/i) {
        return normalize_inferred_part_number($2);
    } elsif ($name =~ /^\s*(.+?)\s+Vol\.?\s+(\d+)\s*$/i) {
        return normalize_inferred_part_number($2);
    } elsif ($name =~ /^\s*(.+?)\s+Book\s+(\d+)\s*$/i) {
        return normalize_inferred_part_number($2);
    } elsif ($name =~ /^\s*(.+?)\s+(\d+)\s*$/) {
        return normalize_inferred_part_number($2);
    }

    return undef;
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
