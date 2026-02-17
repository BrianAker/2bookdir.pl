use strict;
use warnings;

use Cwd qw(abs_path getcwd);
use File::Basename qw(basename);
use File::Copy qw(copy);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use IPC::Open3 qw(open3);
use Symbol qw(gensym);
use Test::More;

my $script = abs_path(File::Spec->catfile($FindBin::Bin, '..', '2bookdir.pl'));
ok(defined $script && -f $script, 'script exists');
my $fixture_dir = abs_path(File::Spec->catfile($FindBin::Bin, '..', '.test-fixtures'));
my $fixture_mp3 = abs_path(File::Spec->catfile($fixture_dir, 'source-2h.mp3'));
my $fixture_m4b = abs_path(File::Spec->catfile($fixture_dir, 'source-2h.m4b'));
ok(defined $fixture_mp3 && -f $fixture_mp3, 'fixture mp3 exists');
ok(defined $fixture_m4b && -f $fixture_m4b, 'fixture m4b exists');

my ($exit_help, $out_help, $err_help) = run_cmd('perl', $script, '--help');
is($exit_help, 0, '--help exits successfully');
like($out_help, qr/^Usage: 2bookdir\.pl \[--help\] book_file \[part-number\] \[book title\]/m, 'help shows usage');
is($err_help, '', 'help does not write stderr');

my ($exit_missing, $out_missing, $err_missing) = run_cmd('perl', $script, 'no-such-file.epub');
ok($exit_missing != 0, 'missing file exits non-zero');
like($err_missing, qr/does not exist\./, 'missing file reports useful error');

my $tmp = tempdir(CLEANUP => 1);
my $old_cwd = getcwd();
chdir $tmp or die "failed to chdir to temp dir '$tmp': $!";

write_file('book.epub', 'dummy');
my ($exit_move, $out_move, $err_move) = run_cmd('perl', $script, 'book.epub');
is($exit_move, 0, 'move without part/title succeeds');
ok(-d 'book', 'directory from filename is created');
ok(-f File::Spec->catfile('book', 'book.epub'), 'file moved into target directory');
is($err_move, '', 'successful move does not write stderr');
like($out_move, qr/^Moved: book\.epub -> book\/book\.epub$/m, 'success output includes move details');

write_file('metadata.json', 'dummy');
my ($exit_part, $out_part, $err_part) = run_cmd('perl', $script, 'metadata.json', '3', 'My', 'Title');
is($exit_part, 0, 'move with part and title succeeds');
ok(-d 'Vol. 3 - My Title', 'volume-prefixed directory is created');
ok(-f File::Spec->catfile('Vol. 3 - My Title', 'metadata.json'), 'non-audio file keeps original name');
is($err_part, '', 'part/title move does not write stderr');
like($out_part, qr/^Moved: metadata\.json -> Vol\. 3 - My Title\/metadata\.json$/m, 'part/title move output includes destination');

copy_single_audio_fixture('m4b', 'Frog God.m4b');
my ($exit_spaced, $out_spaced, $err_spaced) = run_cmd('perl', $script, 'Frog', 'God.m4b');
is($exit_spaced, 0, 'unquoted spaced filename succeeds');
ok(-d 'Frog God', 'directory for spaced filename is created');
ok(-f File::Spec->catfile('Frog God', 'Frog God.m4b'), 'spaced filename moved into target directory');
is($err_spaced, '', 'spaced filename move does not write stderr');
like($out_spaced, qr/^Moved: Frog God\.m4b -> Frog God\/Frog God\.m4b$/m, 'spaced filename output includes destination');

copy_single_audio_fixture('m4b', 'Frog God.m4b');
my ($exit_spaced_part, $out_spaced_part, $err_spaced_part) = run_cmd('perl', $script, 'Frog', 'God.m4b', '2');
is($exit_spaced_part, 0, 'unquoted spaced filename with part succeeds');
ok(-d 'Vol. 2 - Frog God', 'volume directory for spaced filename is created');
ok(-f File::Spec->catfile('Vol. 2 - Frog God', 'Frog God.m4b'), 'spaced filename with part moved into target directory');
is($err_spaced_part, '', 'spaced filename with part does not write stderr');
like($out_spaced_part, qr/^Moved: Frog God\.m4b -> Vol\. 2 - Frog God\/Frog God\.m4b$/m, 'spaced filename with part output includes destination');

copy_single_audio_fixture('m4b', 'Frog God.m4b');
my ($exit_spaced_decimal, $out_spaced_decimal, $err_spaced_decimal) = run_cmd('perl', $script, 'Frog', 'God.m4b', '2.1');
is($exit_spaced_decimal, 0, 'unquoted spaced filename with decimal part succeeds');
ok(-d 'Vol. 2.1 - Frog God', 'volume directory for decimal part is created');
ok(-f File::Spec->catfile('Vol. 2.1 - Frog God', 'Frog God.m4b'), 'spaced filename with decimal part moved into target directory');
is($err_spaced_decimal, '', 'spaced filename with decimal part does not write stderr');
like($out_spaced_decimal, qr/^Moved: Frog God\.m4b -> Vol\. 2\.1 - Frog God\/Frog God\.m4b$/m, 'spaced filename with decimal part output includes destination');

copy_single_audio_fixture('m4b', 'Frog God.m4b');
my ($exit_spaced_title, $out_spaced_title, $err_spaced_title) = run_cmd('perl', $script, 'Frog', 'God.m4b', '3', 'My', 'Dog');
is($exit_spaced_title, 0, 'unquoted spaced filename with part and title succeeds');
ok(-d 'Vol. 3 - My Dog', 'volume directory for explicit title is created');
ok(-f File::Spec->catfile('Vol. 3 - My Dog', 'My Dog.m4b'), 'explicit title is used as destination filename');
is(tone_album(File::Spec->catfile('Vol. 3 - My Dog', 'My Dog.m4b')), 'My Dog', 'renamed single audio file album metadata is updated to title');
is(tone_meta(File::Spec->catfile('Vol. 3 - My Dog', 'My Dog.m4b'), '$.meta.movement'), '3', 'integer volume number is written to movement metadata');
is($err_spaced_title, '', 'spaced filename with part and title does not write stderr');
like($out_spaced_title, qr/^Moved: Frog God\.m4b -> Vol\. 3 - My Dog\/My Dog\.m4b$/m, 'spaced filename with part and title output includes destination');

copy_single_audio_fixture('m4b', 'Frog God.m4b');
my ($exit_spaced_title_decimal, $out_spaced_title_decimal, $err_spaced_title_decimal) = run_cmd('perl', $script, 'Frog', 'God.m4b', '2.1', 'My', 'Part');
is($exit_spaced_title_decimal, 0, 'single audio file with decimal part and title succeeds');
ok(-d 'Vol. 2.1 - My Part', 'volume directory for decimal title case is created');
ok(-f File::Spec->catfile('Vol. 2.1 - My Part', 'My Part.m4b'), 'decimal title case file is renamed to title');
is(tone_album(File::Spec->catfile('Vol. 2.1 - My Part', 'My Part.m4b')), 'My Part', 'decimal title case album metadata is updated to title');
is(tone_part(File::Spec->catfile('Vol. 2.1 - My Part', 'My Part.m4b')), '2.1', 'non-integer volume number is written to part metadata');
is($err_spaced_title_decimal, '', 'decimal title case does not write stderr');
like($out_spaced_title_decimal, qr/^Moved: Frog God\.m4b -> Vol\. 2\.1 - My Part\/My Part\.m4b$/m, 'decimal title case output includes destination');

mkdir 'Dog God' or die "failed to create fixture dir 'Dog God': $!";
copy_single_audio_fixture('mp3', File::Spec->catfile('Dog God', 'Dog God.mp3'));
my ($exit_subdir_part, $out_subdir_part, $err_subdir_part) = run_cmd('perl', $script, File::Spec->catfile('Dog God', 'Dog God.mp3'), '1');
is($exit_subdir_part, 0, 'subdirectory source with part succeeds');
ok(-d 'Vol. 1 - Dog God', 'volume directory for subdirectory source is created');
ok(-f File::Spec->catfile('Vol. 1 - Dog God', 'Dog God.mp3'), 'subdirectory source file moved into target directory');
is($err_subdir_part, '', 'subdirectory source with part does not write stderr');
like($out_subdir_part, qr/^Moved: Dog God\/Dog God\.mp3 -> Vol\. 1 - Dog God\/Dog God\.mp3$/m, 'subdirectory source with part output includes destination');

copy_single_audio_fixture('mp3', 'Pigs.mp3');
my ($exit_year_prefix, $out_year_prefix, $err_year_prefix) = run_cmd('perl', $script, 'Pigs.mp3', '1999');
is($exit_year_prefix, 0, 'four-digit year uses publishing-date directory prefix');
ok(-d '1999 - Pigs', 'publishing-date directory is created');
ok(-f File::Spec->catfile('1999 - Pigs', 'Pigs.mp3'), 'audio file moved under publishing-date directory');
like(tone_dump_json(File::Spec->catfile('1999 - Pigs', 'Pigs.mp3')), qr/"publishingDate"\s*:\s*"1999-01-01/, 'publishing-date metadata is set to YYYY-01-01');
is($err_year_prefix, '', 'publishing-date move does not write stderr');
like($out_year_prefix, qr/^Moved: Pigs\.mp3 -> 1999 - Pigs\/Pigs\.mp3$/m, 'publishing-date move output includes destination');

mkdir 'Bundle' or die "failed to create fixture dir 'Bundle': $!";
copy_single_audio_fixture('mp3', File::Spec->catfile('Bundle', 'track01.mp3'));
my ($exit_dir_source, $out_dir_source, $err_dir_source) = run_cmd('perl', $script, 'Bundle', '4');
is($exit_dir_source, 0, 'directory source with part succeeds');
ok(-d 'Vol. 4 - Bundle', 'volume directory for directory source is created');
ok(!-d 'Bundle', 'source directory no longer exists after rename');
ok(-f File::Spec->catfile('Vol. 4 - Bundle', 'track01.mp3'), 'directory contents are preserved after rename');
is($err_dir_source, '', 'directory source with part does not write stderr');
like($out_dir_source, qr/^Moved: Bundle -> Vol\. 4 - Bundle$/m, 'directory source output includes destination');

mkdir 'Pack' or die "failed to create fixture dir 'Pack': $!";
copy_single_audio_fixture('mp3', File::Spec->catfile('Pack', 'track01.mp3'));
my ($exit_dir_title, $out_dir_title, $err_dir_title) = run_cmd('perl', $script, 'Pack', '5', 'My', 'Pack');
is($exit_dir_title, 0, 'directory source with part and title succeeds');
ok(-d 'Vol. 5 - My Pack', 'volume directory for titled directory source is created');
ok(!-d 'Pack', 'titled source directory no longer exists after rename');
ok(-f File::Spec->catfile('Vol. 5 - My Pack', 'My Pack.mp3'), 'single audio file is renamed to title');
ok(!-f File::Spec->catfile('Vol. 5 - My Pack', 'track01.mp3'), 'old audio filename is not kept for single-audio directory');
is(tone_album(File::Spec->catfile('Vol. 5 - My Pack', 'My Pack.mp3')), 'My Pack', 'renamed single audio in directory has album metadata updated to title');
is(tone_meta(File::Spec->catfile('Vol. 5 - My Pack', 'My Pack.mp3'), '$.meta.movement'), '5', 'directory single-audio integer volume is written to movement metadata');
is($err_dir_title, '', 'directory source with part and title does not write stderr');
like($out_dir_title, qr/^Moved: Pack -> Vol\. 5 - My Pack$/m, 'directory source with title output includes destination');

mkdir 'Frog God Folder' or die "failed to create fixture dir 'Frog God Folder': $!";
copy_audio_fixture('mp3', File::Spec->catfile('Frog God Folder', 'Part1.mp3'));
copy_audio_fixture('mp3', File::Spec->catfile('Frog God Folder', 'Part2.mp3'));
my ($exit_dir_multi_audio, $out_dir_multi_audio, $err_dir_multi_audio) = run_cmd('perl', $script, 'Frog God Folder', '3', 'Conversations');
is($exit_dir_multi_audio, 0, 'directory source with multiple audio files and title succeeds');
ok(-d 'Vol. 3 - Conversations', 'volume directory for multi-audio source is created');
ok(!-d 'Frog God Folder', 'multi-audio source directory no longer exists after rename');
ok(-f File::Spec->catfile('Vol. 3 - Conversations', 'Part1.mp3'), 'first audio file is preserved');
ok(-f File::Spec->catfile('Vol. 3 - Conversations', 'Part2.mp3'), 'second audio file is preserved');
is($err_dir_multi_audio, '', 'multi-audio directory source does not write stderr');
like($out_dir_multi_audio, qr/^Moved: Frog God Folder -> Vol\. 3 - Conversations$/m, 'multi-audio directory output includes renamed destination');

mkdir 'Image Book' or die "failed to create fixture dir 'Image Book': $!";
copy_single_audio_fixture('mp3', File::Spec->catfile('Image Book', 'track01.mp3'));
write_file(File::Spec->catfile('Image Book', 'small.jpg'), '12345');
write_file(File::Spec->catfile('Image Book', 'large.png'), '123456789');
my ($exit_cover_copy, $out_cover_copy, $err_cover_copy) = run_cmd('perl', $script, 'Image Book', '6', 'Picture Test');
is($exit_cover_copy, 0, 'directory source with images succeeds');
ok(-d 'Vol. 6 - Picture Test', 'volume directory for image cover test is created');
ok(-f File::Spec->catfile('Vol. 6 - Picture Test', 'cover.png'), 'largest non-cover image is copied to cover with same extension');
is(read_file(File::Spec->catfile('Vol. 6 - Picture Test', 'cover.png')), '123456789', 'cover file content matches largest image source');
ok(!-f File::Spec->catfile('Vol. 6 - Picture Test', 'cover.jpg'), 'only selected extension cover is created');
is($err_cover_copy, '', 'image cover copy test does not write stderr');
like($out_cover_copy, qr/^Moved: Image Book -> Vol\. 6 - Picture Test$/m, 'image cover copy output includes destination');

mkdir 'Image Exclusion' or die "failed to create fixture dir 'Image Exclusion': $!";
copy_single_audio_fixture('mp3', File::Spec->catfile('Image Exclusion', 'track01.mp3'));
write_file(File::Spec->catfile('Image Exclusion', 'cover.jpg'), '12345678901234567890');
write_file(File::Spec->catfile('Image Exclusion', 'poster.jpg'), '1234567');
my ($exit_cover_exclusion, $out_cover_exclusion, $err_cover_exclusion) = run_cmd('perl', $script, 'Image Exclusion', '7', 'Cover Exclusion');
is($exit_cover_exclusion, 0, 'directory source with existing cover image succeeds');
ok(-d 'Vol. 7 - Cover Exclusion', 'volume directory for cover exclusion test is created');
ok(-f File::Spec->catfile('Vol. 7 - Cover Exclusion', 'cover.jpg'), 'cover.jpg exists after move');
is(read_file(File::Spec->catfile('Vol. 7 - Cover Exclusion', 'cover.jpg')), '1234567', 'cover.jpg is replaced from largest non-cover candidate');
is($err_cover_exclusion, '', 'cover exclusion test does not write stderr');
like($out_cover_exclusion, qr/^Moved: Image Exclusion -> Vol\. 7 - Cover Exclusion$/m, 'cover exclusion output includes destination');

chdir $old_cwd or die "failed to restore cwd '$old_cwd': $!";

done_testing();

sub run_cmd {
    my (@cmd) = @_;

    my $stderr_fh = gensym;
    my $pid = open3(undef, my $stdout_fh, $stderr_fh, @cmd);

    my $stdout = do { local $/; <$stdout_fh> // '' };
    my $stderr = do { local $/; <$stderr_fh> // '' };

    waitpid($pid, 0);
    my $exit = $? >> 8;

    return ($exit, $stdout, $stderr);
}

sub write_file {
    my ($path, $contents) = @_;

    open my $fh, '>', $path or die "failed to create '$path': $!";
    print {$fh} $contents;
    close $fh or die "failed to close '$path': $!";
}

sub read_file {
    my ($path) = @_;

    open my $fh, '<', $path or die "failed to open '$path': $!";
    local $/;
    my $contents = <$fh>;
    close $fh or die "failed to close '$path': $!";
    return defined $contents ? $contents : '';
}

sub copy_audio_fixture {
    my ($ext, $dest) = @_;

    my $source = $ext eq 'mp3' ? $fixture_mp3
      : $ext eq 'm4b' ? $fixture_m4b
      : die "unknown audio fixture extension '$ext'";

    copy($source, $dest)
      or die "failed to copy fixture '$source' to '$dest': $!";
}

sub copy_single_audio_fixture {
    my ($ext, $dest) = @_;
    copy_audio_fixture($ext, $dest);
    tag_audio_album_from_filename($dest);
}

sub tag_audio_album_from_filename {
    my ($path) = @_;

    my $name = basename($path);
    $name =~ s/\.[^.]+\z//;
    my $album = $name;
    $album =~ s/^\s+|\s+$//g;
    die "failed to derive album name from '$path'" if $album eq '';

    my ($tag_exit, $tag_out, $tag_err) = run_cmd('tone', 'tag', '--meta-album', $album, $path);
    my $tag_combined = lc("$tag_out\n$tag_err");
    if ($tag_combined =~ /\b(error|failed|panic|exception)\b/) {
        die "tone tag reported an error for '$path': $tag_out$tag_err";
    }

    my ($dump_exit, $dump_out, $dump_err) = run_cmd('tone', 'dump', $path, '--format', 'json', '--query', '$.meta.album');
    my $dump_combined = lc("$dump_out\n$dump_err");
    if ($dump_combined =~ /\b(error|failed|panic|exception)\b/) {
        die "tone dump reported an error for '$path': $dump_out$dump_err";
    }
    if ($dump_out !~ /\Q$album\E/) {
        die "tone album verification failed for '$path': expected '$album', got '$dump_out'";
    }
}

sub tone_album {
    my ($path) = @_;
    return tone_meta($path, '$.meta.album');
}

sub tone_meta {
    my ($path, $query) = @_;

    my ($dump_exit, $dump_out, $dump_err) = run_cmd('tone', 'dump', $path, '--format', 'json', '--query', $query);
    my $dump_combined = lc("$dump_out\n$dump_err");
    if ($dump_combined =~ /\b(error|failed|panic|exception)\b/) {
        die "tone dump reported an error for '$path': $dump_out$dump_err";
    }

    $dump_out =~ s/^\s+|\s+$//g;
    $dump_out =~ s/^"+|"+$//g;
    return $dump_out;
}

sub tone_part {
    my ($path) = @_;
    my $part = tone_meta($path, '$.meta.part');
    return $part if $part ne '';
    return tone_meta($path, '$.meta.additionalFields.part');
}

sub tone_dump_json {
    my ($path) = @_;
    my ($dump_exit, $dump_out, $dump_err) = run_cmd('tone', 'dump', $path, '--format', 'json');
    my $dump_combined = lc("$dump_out\n$dump_err");
    if ($dump_combined =~ /\b(error|failed|panic|exception)\b/) {
        die "tone dump reported an error for '$path': $dump_out$dump_err";
    }
    return $dump_out;
}
