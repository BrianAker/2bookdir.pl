use strict;
use warnings;

use Cwd qw(abs_path getcwd);
use File::Basename qw(basename);
use File::Copy qw(copy);
use File::Path qw(remove_tree);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use IPC::Open3 qw(open3);
use JSON::PP qw(decode_json);
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
like($out_help, qr/^Usage: 2bookdir\.pl \[--help\] \[--version\] \[--json\] \[--dry-run\] \[--skip-tone\] \[--as-is\] \[--reverse\] \[--has-subtitle\] \[--title-is-series\] \[--series SERIES\] \[--order ORDER\] \[--append-title TEXT\] \[--narrator NAME\] book_file \[part-number\] \[book title\]/m, 'help shows usage');
is($err_help, '', 'help does not write stderr');

my ($exit_version, $out_version, $err_version) = run_cmd('perl', $script, '--version');
is($exit_version, 0, '--version exits successfully');
like($out_version, qr/^\d{4}\.\d{2}\.\d{2}-\d+\.\d+\n\z/, '--version prints expected format');
is($err_version, '', '--version does not write stderr');

my ($exit_missing, $out_missing, $err_missing) = run_cmd('perl', $script, 'no-such-file.epub');
ok($exit_missing != 0, 'missing file exits non-zero');
like($err_missing, qr/does not exist\./, 'missing file reports useful error');

my ($exit_missing_json, $out_missing_json, $err_missing_json) = run_cmd('perl', $script, '--json', 'no-such-file-json.epub');
ok($exit_missing_json != 0, 'json missing file exits non-zero');
is($err_missing_json, '', 'json missing file writes no stderr');
my $missing_json = decode_json($out_missing_json);
is($missing_json->{response}, 'failure', 'json missing file reports failure response');
ok(exists $missing_json->{meta}, 'json missing file includes meta');

my $tmp = tempdir(CLEANUP => 1);
my $old_cwd = getcwd();
chdir $tmp or die "failed to chdir to temp dir '$tmp': $!";

copy_single_audio_fixture('m4b', 'Json Dog.m4b');
my ($exit_json_success, $out_json_success, $err_json_success) = run_cmd('perl', $script, '--json', 'Json Dog.m4b', '3', 'Json', 'Dog');
is($exit_json_success, 0, 'json success exits zero');
is($err_json_success, '', 'json success writes no stderr');
my $success_json = decode_json($out_json_success);
is($success_json->{response}, 'success', 'json success reports success response');
is($success_json->{meta}->{title}, 'Json Dog', 'json success includes title in meta');
is($success_json->{meta}->{volume}, '3', 'json success includes volume in meta');
ok(!defined $success_json->{meta}->{year}, 'json success leaves year undefined when not present');

copy_single_audio_fixture('m4b', 'Dry Run Dog.m4b');
my ($exit_dry_run, $out_dry_run, $err_dry_run) = run_cmd('perl', $script, '--dry-run', 'Dry Run Dog.m4b', '2');
is($exit_dry_run, 0, '--dry-run file source exits zero');
ok(-f 'Dry Run Dog.m4b', '--dry-run leaves source file in place');
ok(!-d 'Vol. 2 - Dry Run Dog', '--dry-run does not create destination directory');
is($err_dry_run, '', '--dry-run file source writes no stderr');
like($out_dry_run, qr/^Moved: Dry Run Dog\.m4b -> Vol\. 2 - Dry Run Dog\/Dry Run Dog\.m4b$/m, '--dry-run file source prints expected move line');
like($out_dry_run, qr/^Title: Dry Run Dog$/m, '--dry-run file source prints title summary');
like($out_dry_run, qr/^Volume: 2$/m, '--dry-run file source prints volume summary');

write_file('dry-run-json.epub', 'dummy');
my ($exit_dry_run_json, $out_dry_run_json, $err_dry_run_json) = run_cmd('perl', $script, '--dry-run', '--json', 'dry-run-json.epub', '4');
is($exit_dry_run_json, 0, '--dry-run --json exits zero');
ok(-f 'dry-run-json.epub', '--dry-run --json leaves source file in place');
ok(!-d 'Vol. 4 - dry-run-json', '--dry-run --json does not create destination directory');
is($err_dry_run_json, '', '--dry-run --json writes no stderr');
my $dry_run_json = decode_json($out_dry_run_json);
is($dry_run_json->{response}, 'success', '--dry-run --json reports success');
is($dry_run_json->{meta}->{title}, 'dry-run-json', '--dry-run --json reports inferred title');
is($dry_run_json->{meta}->{volume}, '4', '--dry-run --json reports inferred volume');

copy_single_audio_fixture('m4b', 'Skip Tone Source.m4b');
my ($exit_skip_tone, $out_skip_tone, $err_skip_tone) = run_cmd(
    'perl',
    $script,
    '--skip-tone',
    'Skip Tone Source.m4b',
    '5',
    'Skip Tone Dest'
);
is($exit_skip_tone, 0, '--skip-tone file source exits zero');
ok(-d 'Vol. 5 - Skip Tone Dest', '--skip-tone creates destination directory');
ok(-f File::Spec->catfile('Vol. 5 - Skip Tone Dest', 'Skip Tone Dest.m4b'), '--skip-tone renames and moves file as normal');
is(tone_album(File::Spec->catfile('Vol. 5 - Skip Tone Dest', 'Skip Tone Dest.m4b')), 'Skip Tone Source', '--skip-tone leaves existing album metadata unchanged');
is(tone_meta(File::Spec->catfile('Vol. 5 - Skip Tone Dest', 'Skip Tone Dest.m4b'), '$.meta.movement'), '', '--skip-tone does not set movement metadata');
is($err_skip_tone, '', '--skip-tone does not write stderr');
like($out_skip_tone, qr/^Moved: Skip Tone Source\.m4b -> Vol\. 5 - Skip Tone Dest\/Skip Tone Dest\.m4b$/m, '--skip-tone output includes expected move line');
like($out_skip_tone, qr/^Title: Skip Tone Dest$/m, '--skip-tone output includes title summary');
like($out_skip_tone, qr/^Volume: 5$/m, '--skip-tone output includes volume summary');

copy_single_audio_fixture('m4b', 'Narrator Option.m4b');
my ($exit_narrator_option, $out_narrator_option, $err_narrator_option) = run_cmd(
    'perl',
    $script,
    '--narrator', 'Alex Reader',
    'Narrator Option.m4b',
    '2'
);
is($exit_narrator_option, 0, '--narrator override succeeds');
ok(-d 'Vol. 2 - Narrator Option {Alex Reader}', '--narrator override appends narrator to directory name');
ok(-f File::Spec->catfile('Vol. 2 - Narrator Option {Alex Reader}', 'Narrator Option.m4b'), '--narrator override moves file into narrator-suffixed directory');
is(tone_meta(File::Spec->catfile('Vol. 2 - Narrator Option {Alex Reader}', 'Narrator Option.m4b'), '$.meta.composer'), 'Alex Reader', '--narrator override sets composer metadata');
is(tone_meta(File::Spec->catfile('Vol. 2 - Narrator Option {Alex Reader}', 'Narrator Option.m4b'), '$.meta.narrator'), 'Alex Reader', '--narrator override sets narrator metadata');
is($err_narrator_option, '', '--narrator override does not write stderr');
like($out_narrator_option, qr/^Moved: Narrator Option\.m4b -> Vol\. 2 - Narrator Option \{Alex Reader\}\/Narrator Option\.m4b$/m, '--narrator override output includes expected move line');
like($out_narrator_option, qr/^Narrators: Alex Reader$/m, '--narrator override output includes narrator summary');

mkdir '03. Footown - From the the Shadows'
  or die "failed to create fixture dir '03. Footown - From the the Shadows': $!";
my ($exit_series_prefix_dot, $out_series_prefix_dot, $err_series_prefix_dot) = run_cmd(
    'perl',
    $script,
    '03. Footown - From the the Shadows'
);
is($exit_series_prefix_dot, 0, 'dotted numeric series prefix infers volume/series/title');
ok(-d 'Vol. 3 - From the the Shadows', 'dotted numeric series prefix creates expected volume directory');
ok(!-d '03. Footown - From the the Shadows', 'dotted numeric series prefix source directory no longer exists after rename');
is($err_series_prefix_dot, '', 'dotted numeric series prefix does not write stderr');
like($out_series_prefix_dot, qr/^Title: From the the Shadows$/m, 'dotted numeric series prefix output includes title summary');
like($out_series_prefix_dot, qr/^Volume: 3$/m, 'dotted numeric series prefix output includes volume summary');
like($out_series_prefix_dot, qr/^Series: Footown$/m, 'dotted numeric series prefix output includes series summary');

copy_single_audio_fixture('m4b', 'My Dog Gone Like!.m4b');
my ($exit_series_only, $out_series_only, $err_series_only) = run_cmd('perl', $script, '--series', 'Dog Gone', 'My Dog Gone Like!.m4b');
is($exit_series_only, 0, '--series without numeric suffix sets series and keeps no volume');
ok(-d 'My Dog Gone Like!', '--series without numeric suffix creates title directory');
ok(-f File::Spec->catfile('My Dog Gone Like!', 'My Dog Gone Like!.m4b'), '--series without numeric suffix moves file to title directory');
is($err_series_only, '', '--series without numeric suffix does not write stderr');
like($out_series_only, qr/^Title: My Dog Gone Like!$/m, '--series without numeric suffix output includes title summary');
like($out_series_only, qr/^Series: Dog Gone$/m, '--series without numeric suffix output includes series summary');
unlike($out_series_only, qr/^Volume:/m, '--series without numeric suffix output does not include volume summary');

remove_tree('My Dog Gone Like!');
copy_single_audio_fixture('m4b', 'My Dog Gone Like!.m4b');
my ($exit_series_with_volume, $out_series_with_volume, $err_series_with_volume) = run_cmd('perl', $script, '--series', 'Dog Gone 1', 'My Dog Gone Like!.m4b');
is($exit_series_with_volume, 0, '--series numeric suffix infers volume');
ok(-d 'Vol. 1 - My Dog Gone Like!', '--series numeric suffix creates expected volume directory');
ok(-f File::Spec->catfile('Vol. 1 - My Dog Gone Like!', 'My Dog Gone Like!.m4b'), '--series numeric suffix moves file to expected directory');
is($err_series_with_volume, '', '--series numeric suffix does not write stderr');
like($out_series_with_volume, qr/^Title: My Dog Gone Like!$/m, '--series numeric suffix output includes title summary');
like($out_series_with_volume, qr/^Series: Dog Gone$/m, '--series numeric suffix output includes parsed series summary');
like($out_series_with_volume, qr/^Volume: 1$/m, '--series numeric suffix output includes inferred volume summary');

remove_tree('Vol. 1 - My Dog Gone Like!');
copy_single_audio_fixture('m4b', 'Vol. 1 - My Dog Gone Like!.m4b');
my ($exit_series_with_title_volume, $out_series_with_title_volume, $err_series_with_title_volume) = run_cmd('perl', $script, '--series', 'Dog Gone', 'Vol. 1 - My Dog Gone Like!.m4b');
is($exit_series_with_title_volume, 0, '--series with title volume token keeps explicit series and infers title/volume from source');
ok(-d 'Vol. 1 - My Dog Gone Like!', '--series with title volume token creates expected volume directory');
ok(-f File::Spec->catfile('Vol. 1 - My Dog Gone Like!', 'My Dog Gone Like!.m4b'), '--series with title volume token renames file to inferred title');
is($err_series_with_title_volume, '', '--series with title volume token does not write stderr');
like($out_series_with_title_volume, qr/^Title: My Dog Gone Like!$/m, '--series with title volume token output includes title summary');
like($out_series_with_title_volume, qr/^Series: Dog Gone$/m, '--series with title volume token output includes explicit series summary');
like($out_series_with_title_volume, qr/^Volume: 1$/m, '--series with title volume token output includes inferred volume summary');

copy_single_audio_fixture('mp3', '02 As Is.mp3');
my ($exit_as_is, $out_as_is, $err_as_is) = run_cmd('perl', $script, '--as-is', '02 As Is.mp3');
is($exit_as_is, 0, 'as-is mode disables no-separator volume inference');
ok(-d '02 As Is', 'as-is mode keeps original file-derived directory name');
ok(-f File::Spec->catfile('02 As Is', '02 As Is.mp3'), 'as-is mode keeps original filename');

copy_single_audio_fixture('mp3', '101 Cats.mp3');
my ($exit_as_is_101, $out_as_is_101, $err_as_is_101) = run_cmd('perl', $script, '--as-is', '101 Cats.mp3');
is($exit_as_is_101, 0, 'as-is mode disables numeric-prefix volume inference');
ok(-d '101 Cats', 'as-is mode keeps directory without inferred volume for numeric prefix');
ok(-f File::Spec->catfile('101 Cats', '101 Cats.mp3'), 'as-is mode keeps numeric-prefix filename unchanged');

write_file('book.epub', 'dummy');
my ($exit_move, $out_move, $err_move) = run_cmd('perl', $script, 'book.epub');
is($exit_move, 0, 'move without part/title succeeds');
ok(-d 'book', 'directory from filename is created');
ok(-f File::Spec->catfile('book', 'book.epub'), 'file moved into target directory');
is($err_move, '', 'successful move does not write stderr');
like($out_move, qr/^Moved: book\.epub -> book\/book\.epub$/m, 'success output includes move details');
like($out_move, qr/^Title: book$/m, 'success output includes title summary line');

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
is(tone_title(File::Spec->catfile('Frog God', 'Frog God.m4b')), 'Frog God', 'single-audio inferred album name is copied to title metadata');
is($err_spaced, '', 'spaced filename move does not write stderr');
like($out_spaced, qr/^Moved: Frog God\.m4b -> Frog God\/Frog God\.m4b$/m, 'spaced filename output includes destination');

copy_single_audio_fixture('m4b', 'Frog God.m4b');
my ($exit_spaced_part, $out_spaced_part, $err_spaced_part) = run_cmd('perl', $script, 'Frog', 'God.m4b', '2');
is($exit_spaced_part, 0, 'unquoted spaced filename with part succeeds');
ok(-d 'Vol. 2 - Frog God', 'volume directory for spaced filename is created');
ok(-f File::Spec->catfile('Vol. 2 - Frog God', 'Frog God.m4b'), 'spaced filename with part moved into target directory');
is($err_spaced_part, '', 'spaced filename with part does not write stderr');
like($out_spaced_part, qr/^Moved: Frog God\.m4b -> Vol\. 2 - Frog God\/Frog God\.m4b$/m, 'spaced filename with part output includes destination');
like($out_spaced_part, qr/^Title: Frog God$/m, 'volume output includes title summary line');
like($out_spaced_part, qr/^Volume: 2$/m, 'volume output includes volume summary line');

copy_single_audio_fixture('m4b', 'Foo Dog.m4b');
my ($exit_append_title, $out_append_title, $err_append_title) = run_cmd('perl', $script, '--apend-title', '(The Dogawg)', 'Foo Dog.m4b', '2');
is($exit_append_title, 0, '--append-title alias appends text to resolved title');
ok(-d 'Vol. 2 - Foo Dog (The Dogawg)', '--append-title creates volume directory using appended title');
ok(-f File::Spec->catfile('Vol. 2 - Foo Dog (The Dogawg)', 'Foo Dog (The Dogawg).m4b'), '--append-title renames single audio file using appended title');
is($err_append_title, '', '--append-title case does not write stderr');
like($out_append_title, qr/^Moved: Foo Dog\.m4b -> Vol\. 2 - Foo Dog \(The Dogawg\)\/Foo Dog \(The Dogawg\)\.m4b$/m, '--append-title output includes expected destination');
like($out_append_title, qr/^Title: Foo Dog \(The Dogawg\)$/m, '--append-title output includes appended title summary');
like($out_append_title, qr/^Volume: 2$/m, '--append-title output includes volume summary');

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
is(tone_title(File::Spec->catfile('Vol. 3 - My Dog', 'My Dog.m4b')), 'My Dog', 'renamed single audio file title metadata is updated to title');
is(tone_meta(File::Spec->catfile('Vol. 3 - My Dog', 'My Dog.m4b'), '$.meta.movement'), '3', 'integer volume number is written to movement metadata');
is($err_spaced_title, '', 'spaced filename with part and title does not write stderr');
like($out_spaced_title, qr/^Moved: Frog God\.m4b -> Vol\. 3 - My Dog\/My Dog\.m4b$/m, 'spaced filename with part and title output includes destination');

copy_single_audio_fixture('m4b', 'J.A. Min - Super Dog Book 3: Pup Road.m4b');
my ($exit_pup_road_explicit, $out_pup_road_explicit, $err_pup_road_explicit) = run_cmd(
    'perl',
    $script,
    'J.A. Min - Super Dog Book 3: Pup Road.m4b',
    '3',
    'Pup Road'
);
is($exit_pup_road_explicit, 0, 'explicit title/volume overrides source metadata-like tokens');
ok(-d 'Vol. 3 - Pup Road', 'explicit Pup Road case creates expected volume directory');
ok(-f File::Spec->catfile('Vol. 3 - Pup Road', 'Pup Road.m4b'), 'explicit Pup Road case renames file to explicit title');
is(tone_album(File::Spec->catfile('Vol. 3 - Pup Road', 'Pup Road.m4b')), 'Pup Road', 'explicit Pup Road case sets album metadata to explicit title');
is(tone_title(File::Spec->catfile('Vol. 3 - Pup Road', 'Pup Road.m4b')), 'Pup Road', 'explicit Pup Road case sets title metadata to explicit title');
is(tone_meta(File::Spec->catfile('Vol. 3 - Pup Road', 'Pup Road.m4b'), '$.meta.movement'), '3', 'explicit Pup Road case sets movement metadata from explicit volume');
is($err_pup_road_explicit, '', 'explicit Pup Road case does not write stderr');
like($out_pup_road_explicit, qr/^Moved: J\.A\. Min - Super Dog Book 3: Pup Road\.m4b -> Vol\. 3 - Pup Road\/Pup Road\.m4b$/m, 'explicit Pup Road case output includes expected destination');
like($out_pup_road_explicit, qr/^Title: Pup Road$/m, 'explicit Pup Road case output includes explicit title summary');
like($out_pup_road_explicit, qr/^Volume: 3$/m, 'explicit Pup Road case output includes explicit volume summary');

remove_tree('Vol. 3 - Pup Road');
copy_single_audio_fixture('m4b', 'J.A. Min - Super Dog Book 3: Pup Road.m4b');
my ($exit_pup_road_inferred, $out_pup_road_inferred, $err_pup_road_inferred) = run_cmd(
    'perl',
    $script,
    'J.A. Min - Super Dog Book 3: Pup Road.m4b'
);
is($exit_pup_road_inferred, 0, 'inferred Pup Road case parses colon-left series+volume');
ok(-d 'Vol. 3 - Pup Road', 'inferred Pup Road case creates expected volume directory');
ok(-f File::Spec->catfile('Vol. 3 - Pup Road', 'Pup Road.m4b'), 'inferred Pup Road case renames file to right side of colon');
is(tone_meta(File::Spec->catfile('Vol. 3 - Pup Road', 'Pup Road.m4b'), '$.meta.movementName'), 'Super Dog', 'inferred Pup Road case sets movement-name from left side');
is(tone_meta(File::Spec->catfile('Vol. 3 - Pup Road', 'Pup Road.m4b'), '$.meta.movement'), '3', 'inferred Pup Road case sets movement from left side');
is($err_pup_road_inferred, '', 'inferred Pup Road case does not write stderr');
like($out_pup_road_inferred, qr/^Moved: J\.A\. Min - Super Dog Book 3: Pup Road\.m4b -> Vol\. 3 - Pup Road\/Pup Road\.m4b$/m, 'inferred Pup Road case output includes expected destination');
like($out_pup_road_inferred, qr/^Title: Pup Road$/m, 'inferred Pup Road case output includes parsed title');
like($out_pup_road_inferred, qr/^Volume: 3$/m, 'inferred Pup Road case output includes inferred volume');
like($out_pup_road_inferred, qr/^Series: Super Dog$/m, 'inferred Pup Road case output includes inferred series');
unlike($out_pup_road_inferred, qr/^Subtitle:/m, 'inferred Pup Road case does not keep subtitle');

remove_tree('Vol. 3 - Super Dog 3');
copy_single_audio_fixture('m4b', 'J.A. Min - Super Dog 3: Pup Fantasy.m4b');
my ($exit_title_is_series_author, $out_title_is_series_author, $err_title_is_series_author) = run_cmd(
    'perl',
    $script,
    '--title-is-series',
    'J.A. Min - Super Dog 3: Pup Fantasy.m4b'
);
is($exit_title_is_series_author, 0, '--title-is-series with author and subtitle succeeds');
ok(-d 'Vol. 3 - Super Dog 3', '--title-is-series with author/subtitle creates expected directory');
ok(-f File::Spec->catfile('Vol. 3 - Super Dog 3', 'Super Dog 3.m4b'), '--title-is-series with author/subtitle renames single audio to title');
is($err_title_is_series_author, '', '--title-is-series with author/subtitle writes no stderr');
like($out_title_is_series_author, qr/^Title: Super Dog 3$/m, '--title-is-series with author/subtitle prints title');
like($out_title_is_series_author, qr/^Subtitle: Pup Fantasy$/m, '--title-is-series with author/subtitle prints subtitle');
like($out_title_is_series_author, qr/^Volume: 3$/m, '--title-is-series with author/subtitle prints volume');
like($out_title_is_series_author, qr/^Series: Super Dog$/m, '--title-is-series with author/subtitle prints series');
like($out_title_is_series_author, qr/^Author: J\.A\. Min$/m, '--title-is-series with author/subtitle prints author');

remove_tree('Vol. 3 - Super Dog 3');
copy_single_audio_fixture('m4b', 'Super Dog 3: Pup Fantasy.m4b');
my ($exit_title_is_series_no_author, $out_title_is_series_no_author, $err_title_is_series_no_author) = run_cmd(
    'perl',
    $script,
    '--title-is-series',
    'Super Dog 3: Pup Fantasy.m4b'
);
is($exit_title_is_series_no_author, 0, '--title-is-series with subtitle but no author succeeds');
ok(-d 'Vol. 3 - Super Dog 3', '--title-is-series with subtitle/no author creates expected directory');
ok(-f File::Spec->catfile('Vol. 3 - Super Dog 3', 'Super Dog 3.m4b'), '--title-is-series with subtitle/no author renames single audio to title');
is($err_title_is_series_no_author, '', '--title-is-series with subtitle/no author writes no stderr');
like($out_title_is_series_no_author, qr/^Title: Super Dog 3$/m, '--title-is-series with subtitle/no author prints title');
like($out_title_is_series_no_author, qr/^Subtitle: Pup Fantasy$/m, '--title-is-series with subtitle/no author prints subtitle');
like($out_title_is_series_no_author, qr/^Volume: 3$/m, '--title-is-series with subtitle/no author prints volume');
like($out_title_is_series_no_author, qr/^Series: Super Dog$/m, '--title-is-series with subtitle/no author prints series');
unlike($out_title_is_series_no_author, qr/^Author:/m, '--title-is-series with subtitle/no author does not print author');

remove_tree('Vol. 3 - Super Dog 3');
remove_tree('Super Dog 3');
copy_single_audio_fixture('m4b', 'Super Dog 3: Pup Fantasy.m4b');
my ($exit_no_title_is_series, $out_no_title_is_series, $err_no_title_is_series) = run_cmd(
    'perl',
    $script,
    'Super Dog 3: Pup Fantasy.m4b'
);
is($exit_no_title_is_series, 0, 'without --title-is-series keeps baseline title/subtitle parsing');
ok(-d 'Super Dog 3', 'without --title-is-series creates directory from left side title');
ok(-f File::Spec->catfile('Super Dog 3', 'Super Dog 3.m4b'), 'without --title-is-series renames single audio to left side title');
is($err_no_title_is_series, '', 'without --title-is-series writes no stderr');
like($out_no_title_is_series, qr/^Title: Super Dog 3$/m, 'without --title-is-series prints title');
like($out_no_title_is_series, qr/^Subtitle: Pup Fantasy$/m, 'without --title-is-series prints subtitle');
unlike($out_no_title_is_series, qr/^Volume:/m, 'without --title-is-series does not print volume');
unlike($out_no_title_is_series, qr/^Series:/m, 'without --title-is-series does not print series');
unlike($out_no_title_is_series, qr/^Author:/m, 'without --title-is-series does not print author');

remove_tree('Vol. 3 - Pup Fantasy');
remove_tree('Super Dog 3');
copy_single_audio_fixture('m4b', 'Super Dog 3: Pup Fantasy.m4b');
my ($exit_order_series_title, $out_order_series_title, $err_order_series_title) = run_cmd(
    'perl',
    $script,
    '--order',
    'series-title',
    'Super Dog 3: Pup Fantasy.m4b'
);
is($exit_order_series_title, 0, '--order series-title uses right side as title for colon split');
ok(-d 'Vol. 3 - Pup Fantasy', '--order series-title creates expected volume directory');
ok(-f File::Spec->catfile('Vol. 3 - Pup Fantasy', 'Pup Fantasy.m4b'), '--order series-title renames single audio to right side title');
is(tone_meta(File::Spec->catfile('Vol. 3 - Pup Fantasy', 'Pup Fantasy.m4b'), '$.meta.movementName'), 'Super Dog', '--order series-title sets series metadata from left side');
is(tone_meta(File::Spec->catfile('Vol. 3 - Pup Fantasy', 'Pup Fantasy.m4b'), '$.meta.movement'), '3', '--order series-title sets movement metadata from left side volume');
is($err_order_series_title, '', '--order series-title writes no stderr');
like($out_order_series_title, qr/^Title: Pup Fantasy$/m, '--order series-title prints right side title');
like($out_order_series_title, qr/^Volume: 3$/m, '--order series-title prints inferred volume');
like($out_order_series_title, qr/^Series: Super Dog$/m, '--order series-title prints inferred series');
unlike($out_order_series_title, qr/^Subtitle:/m, '--order series-title does not print subtitle');

remove_tree('Vol. 3 - Pup Fantasy');
copy_single_audio_fixture('m4b', 'Super Dog 3: Pup Fantasy [B0AAAP75QM].m4b');
my ($exit_order_series_title_asin, $out_order_series_title_asin, $err_order_series_title_asin) = run_cmd(
    'perl',
    $script,
    '--order',
    'series-title',
    'Super Dog 3: Pup Fantasy [B0AAAP75QM].m4b'
);
is($exit_order_series_title_asin, 0, '--order series-title with ASIN uses right side as title');
ok(-d 'Vol. 3 - Pup Fantasy', '--order series-title with ASIN creates expected volume directory');
ok(-f File::Spec->catfile('Vol. 3 - Pup Fantasy', 'Pup Fantasy [B0AAAP75QM].m4b'), '--order series-title with ASIN reapplies bracket segment to filename');
is(tone_meta(File::Spec->catfile('Vol. 3 - Pup Fantasy', 'Pup Fantasy [B0AAAP75QM].m4b'), '$.meta.movementName'), 'Super Dog', '--order series-title with ASIN sets series metadata from left side');
is(tone_meta(File::Spec->catfile('Vol. 3 - Pup Fantasy', 'Pup Fantasy [B0AAAP75QM].m4b'), '$.meta.movement'), '3', '--order series-title with ASIN sets movement metadata from left side volume');
like(tone_dump_json(File::Spec->catfile('Vol. 3 - Pup Fantasy', 'Pup Fantasy [B0AAAP75QM].m4b')), qr/"additionalFields"\s*:\s*\{[\s\S]*?"[^"]*ASIN"\s*:\s*"B0AAAP75QM"/i, '--order series-title with ASIN writes AUDIBLE_ASIN metadata');
is($err_order_series_title_asin, '', '--order series-title with ASIN writes no stderr');
like($out_order_series_title_asin, qr/^Title: Pup Fantasy$/m, '--order series-title with ASIN prints right side title');
like($out_order_series_title_asin, qr/^Volume: 3$/m, '--order series-title with ASIN prints inferred volume');
like($out_order_series_title_asin, qr/^Series: Super Dog$/m, '--order series-title with ASIN prints inferred series');
like($out_order_series_title_asin, qr/^ASIN: B0AAAP75QM$/m, '--order series-title with ASIN prints parsed ASIN');
unlike($out_order_series_title_asin, qr/^Subtitle:/m, '--order series-title with ASIN does not print subtitle');

remove_tree('Vol. 3 - Super Dog 3');
copy_single_audio_fixture('m4b', 'Super Dog 3.m4b');
my ($exit_title_is_series_plain, $out_title_is_series_plain, $err_title_is_series_plain) = run_cmd(
    'perl',
    $script,
    '--title-is-series',
    'Super Dog 3.m4b'
);
is($exit_title_is_series_plain, 0, '--title-is-series plain title succeeds');
ok(-d 'Vol. 3 - Super Dog 3', '--title-is-series plain title creates expected directory');
ok(-f File::Spec->catfile('Vol. 3 - Super Dog 3', 'Super Dog 3.m4b'), '--title-is-series plain title keeps expected filename');
is($err_title_is_series_plain, '', '--title-is-series plain title writes no stderr');
like($out_title_is_series_plain, qr/^Title: Super Dog 3$/m, '--title-is-series plain title prints title');
like($out_title_is_series_plain, qr/^Volume: 3$/m, '--title-is-series plain title prints volume');
like($out_title_is_series_plain, qr/^Series: Super Dog$/m, '--title-is-series plain title prints series');
unlike($out_title_is_series_plain, qr/^Subtitle:/m, '--title-is-series plain title has no subtitle');
unlike($out_title_is_series_plain, qr/^Author:/m, '--title-is-series plain title has no author');

copy_single_audio_fixture('m4b', 'Frog God.m4b');
my ($exit_spaced_title_decimal, $out_spaced_title_decimal, $err_spaced_title_decimal) = run_cmd('perl', $script, 'Frog', 'God.m4b', '2.1', 'My', 'Part');
is($exit_spaced_title_decimal, 0, 'single audio file with decimal part and title succeeds');
ok(-d 'Vol. 2.1 - My Part', 'volume directory for decimal title case is created');
ok(-f File::Spec->catfile('Vol. 2.1 - My Part', 'My Part.m4b'), 'decimal title case file is renamed to title');
is(tone_album(File::Spec->catfile('Vol. 2.1 - My Part', 'My Part.m4b')), 'My Part', 'decimal title case album metadata is updated to title');
is(tone_title(File::Spec->catfile('Vol. 2.1 - My Part', 'My Part.m4b')), 'My Part', 'decimal title case title metadata is updated to title');
is(tone_part(File::Spec->catfile('Vol. 2.1 - My Part', 'My Part.m4b')), '2.1', 'non-integer volume number is written to part metadata');
is(tone_meta(File::Spec->catfile('Vol. 2.1 - My Part', 'My Part.m4b'), '$.meta.movement'), '2', 'non-integer volume also writes movement using whole number');
is($err_spaced_title_decimal, '', 'decimal title case does not write stderr');
like($out_spaced_title_decimal, qr/^Moved: Frog God\.m4b -> Vol\. 2\.1 - My Part\/My Part\.m4b$/m, 'decimal title case output includes destination');

copy_single_audio_fixture('m4b', 'Lucky Biggerwolf for Doom (Unabridged).m4b');
my ($exit_unabridged_file, $out_unabridged_file, $err_unabridged_file) = run_cmd('perl', $script, 'Lucky Biggerwolf for Doom (Unabridged).m4b');
is($exit_unabridged_file, 0, 'single unabridged file infers title without unabridged suffix');
ok(-d 'Lucky Biggerwolf for Doom', 'unabridged file creates directory from stripped title');
ok(-f File::Spec->catfile('Lucky Biggerwolf for Doom', 'Lucky Biggerwolf for Doom.m4b'), 'unabridged single audio file is renamed to stripped title');
ok(!-f File::Spec->catfile('Lucky Biggerwolf for Doom', 'Lucky Biggerwolf for Doom (Unabridged).m4b'), 'unabridged source filename is not kept after title rename');
is(tone_album(File::Spec->catfile('Lucky Biggerwolf for Doom', 'Lucky Biggerwolf for Doom.m4b')), 'Lucky Biggerwolf for Doom', 'unabridged single audio file album metadata is updated to stripped title');
is(tone_title(File::Spec->catfile('Lucky Biggerwolf for Doom', 'Lucky Biggerwolf for Doom.m4b')), 'Lucky Biggerwolf for Doom', 'unabridged single audio file title metadata is updated to stripped title');
is($err_unabridged_file, '', 'unabridged file case does not write stderr');
like($out_unabridged_file, qr/^Moved: Lucky Biggerwolf for Doom \(Unabridged\)\.m4b -> Lucky Biggerwolf for Doom\/Lucky Biggerwolf for Doom\.m4b$/m, 'unabridged file output includes expected destination');
like($out_unabridged_file, qr/^Title: Lucky Biggerwolf for Doom$/m, 'unabridged file output includes stripped title summary');

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

copy_single_audio_fixture('mp3', '1993 - Foo.mp3');
my ($exit_checkpoint_year, $out_checkpoint_year, $err_checkpoint_year) = run_cmd('perl', $script, '--checkpoint', '1993 - Foo.mp3');
is($exit_checkpoint_year, 0, '--checkpoint with inferred year in source name succeeds');
ok(-d '1993 - Foo', 'checkpoint year-inferred directory is created');
ok(-f File::Spec->catfile('1993 - Foo', 'Foo.mp3'), 'checkpoint year-inferred audio file is renamed to title');
is($err_checkpoint_year, '', 'checkpoint year-inferred move does not write stderr');
like($out_checkpoint_year, qr/^CHECKPOINT: 1: YEAR$/m, 'checkpoint output includes year checkpoint marker');
like($out_checkpoint_year, qr/^Moved: 1993 - Foo\.mp3 -> 1993 - Foo\/Foo\.mp3$/m, 'checkpoint year-inferred output includes destination');
like($out_checkpoint_year, qr/^Title: Foo$/m, 'checkpoint year-inferred output includes title summary line');
like($out_checkpoint_year, qr/^Year: 1993$/m, 'checkpoint year-inferred output includes year summary line');
my $checkpoint_part = tone_part(File::Spec->catfile('1993 - Foo', 'Foo.mp3'));
ok($checkpoint_part eq '' || lc($checkpoint_part) eq 'null', 'checkpoint year-inferred result does not set part metadata');
my $checkpoint_movement = tone_meta(File::Spec->catfile('1993 - Foo', 'Foo.mp3'), '$.meta.movement');
ok($checkpoint_movement eq '' || lc($checkpoint_movement) eq 'null', 'checkpoint year-inferred result does not set movement metadata');

copy_single_audio_fixture('mp3', '1993 - Volume 3 - Foo.mp3');
my ($exit_checkpoint_year_volume, $out_checkpoint_year_volume, $err_checkpoint_year_volume) = run_cmd('perl', $script, '--checkpoint', '1993 - Volume 3 - Foo.mp3');
is($exit_checkpoint_year_volume, 0, '--checkpoint with inferred year and volume token succeeds');
ok(-d 'Vol. 3 - Foo', 'checkpoint year+volume creates expected directory');
ok(-f File::Spec->catfile('Vol. 3 - Foo', 'Foo.mp3'), 'checkpoint year+volume renames audio file to title');
is($err_checkpoint_year_volume, '', 'checkpoint year+volume does not write stderr');
like($out_checkpoint_year_volume, qr/^CHECKPOINT: 1: YEAR$/m, 'checkpoint year+volume output includes year checkpoint marker');
like($out_checkpoint_year_volume, qr/^CHECKPOINT: 2: VOLUME$/m, 'checkpoint year+volume output includes volume checkpoint marker');
like($out_checkpoint_year_volume, qr/^Created\/used directory: Vol\. 3 - Foo$/m, 'checkpoint year+volume output includes created directory line');
like($out_checkpoint_year_volume, qr/^Moved: 1993 - Volume 3 - Foo\.mp3 -> Vol\. 3 - Foo\/Foo\.mp3$/m, 'checkpoint year+volume output includes expected move line');
like($out_checkpoint_year_volume, qr/^Title: Foo$/m, 'checkpoint year+volume output includes title summary line');
like($out_checkpoint_year_volume, qr/^Volume: 3$/m, 'checkpoint year+volume output includes volume summary line');
like($out_checkpoint_year_volume, qr/^Year: 1993$/m, 'checkpoint year+volume output includes year summary line');

copy_single_audio_fixture('mp3', '1993 - Volume 3 - Asin Foo [B00TEST123].mp3');
my ($exit_checkpoint_asin, $out_checkpoint_asin, $err_checkpoint_asin) = run_cmd('perl', $script, '--checkpoint', '1993 - Volume 3 - Asin Foo [B00TEST123].mp3');
is($exit_checkpoint_asin, 0, '--checkpoint with ASIN/year/volume token succeeds');
ok(-d 'Vol. 3 - Asin Foo', 'checkpoint ASIN case creates expected directory');
ok(-f File::Spec->catfile('Vol. 3 - Asin Foo', 'Asin Foo [B00TEST123].mp3'), 'checkpoint ASIN case renames audio file to title and reapplies bracket segments');
is($err_checkpoint_asin, '', 'checkpoint ASIN case does not write stderr');
like($out_checkpoint_asin, qr/^CHECKPOINT: 1: ASIN$/m, 'checkpoint ASIN case output includes ASIN checkpoint marker');
like($out_checkpoint_asin, qr/^CHECKPOINT: 1: YEAR$/m, 'checkpoint ASIN case output includes year checkpoint marker');
like($out_checkpoint_asin, qr/^CHECKPOINT: 2: VOLUME$/m, 'checkpoint ASIN case output includes volume checkpoint marker');
like($out_checkpoint_asin, qr/^Moved: 1993 - Volume 3 - Asin Foo \[B00TEST123\]\.mp3 -> Vol\. 3 - Asin Foo\/Asin Foo \[B00TEST123\]\.mp3$/m, 'checkpoint ASIN case output includes expected move line');
like($out_checkpoint_asin, qr/^Title: Asin Foo$/m, 'checkpoint ASIN case output includes title summary line');
like($out_checkpoint_asin, qr/^Volume: 3$/m, 'checkpoint ASIN case output includes volume summary line');
like($out_checkpoint_asin, qr/^Year: 1993$/m, 'checkpoint ASIN case output includes year summary line');
like($out_checkpoint_asin, qr/^ASIN: B00TEST123$/m, 'checkpoint ASIN case output includes ASIN summary line');

copy_single_audio_fixture('mp3', '1993 - Volume 3 - Narrated Foo {Jane Roe}.mp3');
my ($exit_checkpoint_narrator, $out_checkpoint_narrator, $err_checkpoint_narrator) = run_cmd('perl', $script, '--checkpoint', '1993 - Volume 3 - Narrated Foo {Jane Roe}.mp3');
is($exit_checkpoint_narrator, 0, '--checkpoint with narrator/year/volume token succeeds');
ok(-d 'Vol. 3 - Narrated Foo {Jane Roe}', 'checkpoint narrator case creates expected directory');
ok(-f File::Spec->catfile('Vol. 3 - Narrated Foo {Jane Roe}', 'Narrated Foo.mp3'), 'checkpoint narrator case renames audio file to title');
is($err_checkpoint_narrator, '', 'checkpoint narrator case does not write stderr');
like($out_checkpoint_narrator, qr/^CHECKPOINT: 1: NARRATOR$/m, 'checkpoint narrator case output includes narrator checkpoint marker');
like($out_checkpoint_narrator, qr/^CHECKPOINT: 1: YEAR$/m, 'checkpoint narrator case output includes year checkpoint marker');
like($out_checkpoint_narrator, qr/^CHECKPOINT: 2: VOLUME$/m, 'checkpoint narrator case output includes volume checkpoint marker');
like($out_checkpoint_narrator, qr/^Moved: 1993 - Volume 3 - Narrated Foo \{Jane Roe\}\.mp3 -> Vol\. 3 - Narrated Foo \{Jane Roe\}\/Narrated Foo\.mp3$/m, 'checkpoint narrator case output includes expected move line');
like($out_checkpoint_narrator, qr/^Title: Narrated Foo$/m, 'checkpoint narrator case output includes title summary line');
like($out_checkpoint_narrator, qr/^Volume: 3$/m, 'checkpoint narrator case output includes volume summary line');
like($out_checkpoint_narrator, qr/^Year: 1993$/m, 'checkpoint narrator case output includes year summary line');
like($out_checkpoint_narrator, qr/^Narrators: Jane Roe$/m, 'checkpoint narrator case output includes narrators summary line');
like(tone_dump_json(File::Spec->catfile('Vol. 3 - Narrated Foo {Jane Roe}', 'Narrated Foo.mp3')), qr/"composer"\s*:\s*"Jane Roe"/i, 'checkpoint narrator case writes composer metadata');

copy_single_audio_fixture('mp3', '1993 - Foo Json [B00TEST124].mp3');
my ($exit_asin_json, $out_asin_json, $err_asin_json) = run_cmd('perl', $script, '--json', '1993 - Foo Json [B00TEST124].mp3');
is($exit_asin_json, 0, 'json ASIN year-inferred case succeeds');
is($err_asin_json, '', 'json ASIN year-inferred case writes no stderr');
my $asin_json = decode_json($out_asin_json);
is($asin_json->{response}, 'success', 'json ASIN year-inferred case reports success');
is($asin_json->{meta}->{title}, 'Foo Json', 'json ASIN year-inferred case reports inferred title');
ok(!defined $asin_json->{meta}->{volume}, 'json ASIN year-inferred case does not set volume');
is($asin_json->{meta}->{year}, '1993', 'json ASIN year-inferred case reports inferred year');
is($asin_json->{meta}->{asin}, 'B00TEST124', 'json ASIN year-inferred case reports parsed ASIN');
like(tone_dump_json(File::Spec->catfile('1993 - Foo Json', 'Foo Json [B00TEST124].mp3')), qr/"additionalFields"\s*:\s*\{[\s\S]*?"[^"]*ASIN"\s*:\s*"B00TEST124"/i, 'json ASIN year-inferred case writes AUDIBLE_ASIN metadata');

copy_single_audio_fixture('m4b', 'Mine Mine 3 [B0AAAP75QM] [113] [44100].m4b');
my ($exit_multi_bracket_asin, $out_multi_bracket_asin, $err_multi_bracket_asin) = run_cmd(
    'perl',
    $script,
    'Mine Mine 3 [B0AAAP75QM] [113] [44100].m4b'
);
is($exit_multi_bracket_asin, 0, 'single audio with multiple bracket segments parses ASIN and reapplies bracket segments');
ok(-d 'Vol. 3 - Mine Mine 3', 'single audio with multiple bracket segments creates expected volume directory');
ok(-f File::Spec->catfile('Vol. 3 - Mine Mine 3', 'Mine Mine 3 [B0AAAP75QM] [113] [44100].m4b'), 'single audio with multiple bracket segments renames file with all bracket segments reapplied');
is($err_multi_bracket_asin, '', 'single audio with multiple bracket segments does not write stderr');
like($out_multi_bracket_asin, qr/^Moved: Mine Mine 3 \[B0AAAP75QM\] \[113\] \[44100\]\.m4b -> Vol\. 3 - Mine Mine 3\/Mine Mine 3 \[B0AAAP75QM\] \[113\] \[44100\]\.m4b$/m, 'single audio with multiple bracket segments output includes expected move line');
like($out_multi_bracket_asin, qr/^Title: Mine Mine 3$/m, 'single audio with multiple bracket segments output includes parsed title');
like($out_multi_bracket_asin, qr/^Volume: 3$/m, 'single audio with multiple bracket segments output includes inferred volume');
like($out_multi_bracket_asin, qr/^ASIN: B0AAAP75QM$/m, 'single audio with multiple bracket segments output includes parsed ASIN');

copy_single_audio_fixture('mp3', '1993 - Plain Foo Json.mp3');
my ($exit_year_json, $out_year_json, $err_year_json) = run_cmd('perl', $script, '--json', '1993 - Plain Foo Json.mp3');
is($exit_year_json, 0, 'json year-inferred case succeeds');
is($err_year_json, '', 'json year-inferred case writes no stderr');
my $year_json = decode_json($out_year_json);
is($year_json->{response}, 'success', 'json year-inferred case reports success');
is($year_json->{meta}->{title}, 'Plain Foo Json', 'json year-inferred case reports inferred title');
ok(!defined $year_json->{meta}->{volume}, 'json year-inferred case does not set volume');
is($year_json->{meta}->{year}, '1993', 'json year-inferred case reports inferred year');

copy_single_audio_fixture('mp3', '02 Fruppy Goop.mp3');
my ($exit_inferred_no_separator, $out_inferred_no_separator, $err_inferred_no_separator) = run_cmd('perl', $script, '02 Fruppy Goop.mp3');
is($exit_inferred_no_separator, 0, 'inferred part/title from source file name without separator succeeds');
ok(-d 'Vol. 2 - Fruppy Goop', 'inferred no-separator volume directory is created');
ok(-f File::Spec->catfile('Vol. 2 - Fruppy Goop', 'Fruppy Goop.mp3'), 'single audio file is renamed using inferred title');
is($err_inferred_no_separator, '', 'inferred no-separator move does not write stderr');
like($out_inferred_no_separator, qr/^Moved: 02 Fruppy Goop\.mp3 -> Vol\. 2 - Fruppy Goop\/Fruppy Goop\.mp3$/m, 'inferred no-separator output includes destination');

copy_single_audio_fixture('mp3', '101 Cats.mp3');
my ($exit_inferred_numeric_prefix, $out_inferred_numeric_prefix, $err_inferred_numeric_prefix) = run_cmd('perl', $script, '101 Cats.mp3');
is($exit_inferred_numeric_prefix, 0, 'inferred part/title from numeric-prefix source file name succeeds');
ok(-d 'Vol. 101 - Cats', 'inferred numeric-prefix volume directory is created');
ok(-f File::Spec->catfile('Vol. 101 - Cats', 'Cats.mp3'), 'single audio file is renamed using inferred numeric-prefix title');
is($err_inferred_numeric_prefix, '', 'inferred numeric-prefix move does not write stderr');
like($out_inferred_numeric_prefix, qr/^Moved: 101 Cats\.mp3 -> Vol\. 101 - Cats\/Cats\.mp3$/m, 'inferred numeric-prefix output includes destination');

copy_single_audio_fixture('mp3', 'Foo__Bar_Baz.mp3');
my ($exit_decode_colon_space, $out_decode_colon_space, $err_decode_colon_space) = run_cmd('perl', $script, 'Foo__Bar_Baz.mp3');
is($exit_decode_colon_space, 0, 'book_file decode converts double underscore to modifier-letter-colon and underscore to space');
ok(-d 'Foo꞉Bar Baz', 'book_file decode creates expected directory name');
ok(-f File::Spec->catfile('Foo꞉Bar Baz', 'Foo__Bar_Baz.mp3'), 'book_file decode keeps original source filename');
is($err_decode_colon_space, '', 'book_file decode case does not write stderr');
like($out_decode_colon_space, qr/^Moved: Foo__Bar_Baz\.mp3 -> Foo꞉Bar Baz\/Foo__Bar_Baz\.mp3$/m, 'book_file decode output includes destination path');
unlike($out_decode_colon_space, qr/^Subtitle:/m, 'book_file decode output does not include subtitle');

copy_single_audio_fixture('mp3', '01__Dog_Gone.mp3');
my ($exit_decode_with_volume, $out_decode_with_volume, $err_decode_with_volume) = run_cmd('perl', $script, '01__Dog_Gone.mp3');
is($exit_decode_with_volume, 0, 'book_file decode works before numeric-prefix volume inference');
ok(-d '01꞉Dog Gone', 'book_file decode + inference creates expected directory');
ok(-f File::Spec->catfile('01꞉Dog Gone', '01__Dog_Gone.mp3'), 'book_file decode + inference keeps original source filename');
is($err_decode_with_volume, '', 'book_file decode + inference case does not write stderr');
like($out_decode_with_volume, qr/^Moved: 01__Dog_Gone\.mp3 -> 01꞉Dog Gone\/01__Dog_Gone\.mp3$/m, 'book_file decode + inference output includes expected move line');
unlike($out_decode_with_volume, qr/^Subtitle:/m, 'book_file decode + inference output does not include decoded subtitle');

copy_single_audio_fixture('mp3', 'Sky꞉Blue.mp3');
my ($exit_modifier_colon_input, $out_modifier_colon_input, $err_modifier_colon_input) = run_cmd('perl', $script, 'Sky꞉Blue.mp3');
is($exit_modifier_colon_input, 0, 'book_file with modifier-letter-colon title succeeds');
ok(-d 'Sky꞉Blue', 'modifier-letter-colon title creates expected directory');
ok(-f File::Spec->catfile('Sky꞉Blue', 'Sky꞉Blue.mp3'), 'modifier-letter-colon title keeps expected filename');
is($err_modifier_colon_input, '', 'modifier-letter-colon title does not write stderr');
like($out_modifier_colon_input, qr/^Moved: Sky꞉Blue\.mp3 -> Sky꞉Blue\/Sky꞉Blue\.mp3$/m, 'modifier-letter-colon title output includes expected move line');
unlike($out_modifier_colon_input, qr/^Subtitle:/m, 'modifier-letter-colon title does not trigger subtitle parsing');

copy_single_audio_fixture('mp3', 'Split One_ Volume 3.mp3');
my ($exit_underscore_subtitle_volume, $out_underscore_subtitle_volume, $err_underscore_subtitle_volume) = run_cmd('perl', $script, 'Split One_ Volume 3.mp3');
is($exit_underscore_subtitle_volume, 0, 'single "_ " subtitle split infers volume from subtitle');
ok(-d 'Vol. 3 - Split One', 'single "_ " subtitle split volume case creates expected volume directory');
ok(-f File::Spec->catfile('Vol. 3 - Split One', 'Split One.mp3'), 'single "_ " subtitle split volume case renames single audio to parsed title');
is($err_underscore_subtitle_volume, '', 'single "_ " subtitle split volume case does not write stderr');
like($out_underscore_subtitle_volume, qr/^Subtitle: Volume 3$/m, 'single "_ " subtitle split volume case prints subtitle');
like($out_underscore_subtitle_volume, qr/^Volume: 3$/m, 'single "_ " subtitle split volume case infers volume from subtitle');

copy_single_audio_fixture('mp3', 'Split Two_ [1994].mp3');
my ($exit_underscore_subtitle_year, $out_underscore_subtitle_year, $err_underscore_subtitle_year) = run_cmd('perl', $script, 'Split Two_ [1994].mp3');
is($exit_underscore_subtitle_year, 0, 'single "_ " subtitle split infers year from subtitle');
ok(-d '1994 - Split Two', 'single "_ " subtitle split year case creates expected year-prefixed directory');
ok(-f File::Spec->catfile('1994 - Split Two', 'Split Two [1994].mp3'), 'single "_ " subtitle split year case renames single audio and reapplies bracket segments');
is($err_underscore_subtitle_year, '', 'single "_ " subtitle split year case does not write stderr');
like($out_underscore_subtitle_year, qr/^Subtitle: \[1994\]$/m, 'single "_ " subtitle split year case prints subtitle');
like($out_underscore_subtitle_year, qr/^Year: 1994$/m, 'single "_ " subtitle split year case infers year from subtitle');

copy_single_audio_fixture('mp3', 'Split Three_ Volume 4 [1998] {Sam Reader}.mp3');
my ($exit_underscore_subtitle_mixed, $out_underscore_subtitle_mixed, $err_underscore_subtitle_mixed) = run_cmd('perl', $script, 'Split Three_ Volume 4 [1998] {Sam Reader}.mp3');
is($exit_underscore_subtitle_mixed, 0, 'single "_ " subtitle split infers volume/year/narrators from subtitle');
ok(-d 'Vol. 4 - Split Three {Sam Reader}', 'single "_ " subtitle split mixed metadata case creates expected volume directory');
ok(-f File::Spec->catfile('Vol. 4 - Split Three {Sam Reader}', 'Split Three [1998].mp3'), 'single "_ " subtitle split mixed metadata case renames single audio and reapplies bracket segments');
is($err_underscore_subtitle_mixed, '', 'single "_ " subtitle split mixed metadata case does not write stderr');
like($out_underscore_subtitle_mixed, qr/^Subtitle: Volume 4 \[1998\] \{Sam Reader\}$/m, 'single "_ " subtitle split mixed metadata case prints subtitle');
like($out_underscore_subtitle_mixed, qr/^Volume: 4$/m, 'single "_ " subtitle split mixed metadata case infers volume from subtitle');
like($out_underscore_subtitle_mixed, qr/^Year: 1998$/m, 'single "_ " subtitle split mixed metadata case infers year from subtitle');
like($out_underscore_subtitle_mixed, qr/^Narrators: Sam Reader$/m, 'single "_ " subtitle split mixed metadata case infers narrators from subtitle');

copy_single_audio_fixture('m4b', 'Master of Dogs_ A LitRPG Progression Fandom [B055855FAG].m4b');
my ($exit_underscore_subtitle_asin, $out_underscore_subtitle_asin, $err_underscore_subtitle_asin) = run_cmd(
    'perl',
    $script,
    'Master of Dogs_ A LitRPG Progression Fandom [B055855FAG].m4b'
);
is($exit_underscore_subtitle_asin, 0, 'single "_ " subtitle split with bracket ASIN infers title and keeps ASIN');
ok(-d 'Master of Dogs', 'single "_ " subtitle split with bracket ASIN creates title directory');
ok(-f File::Spec->catfile('Master of Dogs', 'Master of Dogs [B055855FAG].m4b'), 'single "_ " subtitle split with bracket ASIN renames single audio and reapplies bracket segment');
is($err_underscore_subtitle_asin, '', 'single "_ " subtitle split with bracket ASIN does not write stderr');
like($out_underscore_subtitle_asin, qr/^Moved: Master of Dogs_ A LitRPG Progression Fandom \[B055855FAG\]\.m4b -> Master of Dogs\/Master of Dogs \[B055855FAG\]\.m4b$/m, 'single "_ " subtitle split with bracket ASIN output includes expected move line');
like($out_underscore_subtitle_asin, qr/^Title: Master of Dogs$/m, 'single "_ " subtitle split with bracket ASIN output includes parsed title');
like($out_underscore_subtitle_asin, qr/^Subtitle: A LitRPG Progression Fandom$/m, 'single "_ " subtitle split with bracket ASIN output includes subtitle');
like($out_underscore_subtitle_asin, qr/^ASIN: B055855FAG$/m, 'single "_ " subtitle split with bracket ASIN output includes parsed ASIN');

remove_tree('Master of Dogs');
copy_single_audio_fixture('m4b', 'Master of Dogs_ A LitRPG Progression Fandom [B055855FAG].m4b');
my ($exit_master_dogs_regression, $out_master_dogs_regression, $err_master_dogs_regression) = run_cmd(
    'perl',
    $script,
    'Master of Dogs_ A LitRPG Progression Fandom [B055855FAG].m4b'
);
is($exit_master_dogs_regression, 0, 'explicit master of dogs command regression succeeds');
ok(-d 'Master of Dogs', 'explicit master of dogs command regression creates expected directory');
ok(-f File::Spec->catfile('Master of Dogs', 'Master of Dogs [B055855FAG].m4b'), 'explicit master of dogs command regression creates expected filename');
is($err_master_dogs_regression, '', 'explicit master of dogs command regression writes no stderr');
like($out_master_dogs_regression, qr/^Moved: Master of Dogs_ A LitRPG Progression Fandom \[B055855FAG\]\.m4b -> Master of Dogs\/Master of Dogs \[B055855FAG\]\.m4b$/m, 'explicit master of dogs command regression output includes expected move line');
like($out_master_dogs_regression, qr/^Subtitle: A LitRPG Progression Fandom$/m, 'explicit master of dogs command regression output includes expected subtitle');

copy_single_audio_fixture('m4b', '101.1 Cats.m4b');
my ($exit_inferred_decimal_numeric_prefix, $out_inferred_decimal_numeric_prefix, $err_inferred_decimal_numeric_prefix) = run_cmd('perl', $script, '101.1 Cats.m4b');
is($exit_inferred_decimal_numeric_prefix, 0, 'inferred decimal numeric-prefix source file name succeeds');
ok(-d 'Vol. 101.1 - Cats', 'inferred decimal numeric-prefix volume directory is created');
ok(-f File::Spec->catfile('Vol. 101.1 - Cats', 'Cats.m4b'), 'single audio file is renamed using inferred decimal numeric-prefix title');
is(tone_part(File::Spec->catfile('Vol. 101.1 - Cats', 'Cats.m4b')), '101.1', 'inferred decimal numeric-prefix writes part metadata');
is(tone_meta(File::Spec->catfile('Vol. 101.1 - Cats', 'Cats.m4b'), '$.meta.movement'), '101', 'inferred decimal numeric-prefix writes movement using whole-number prefix');
is($err_inferred_decimal_numeric_prefix, '', 'inferred decimal numeric-prefix move does not write stderr');
like($out_inferred_decimal_numeric_prefix, qr/^Moved: 101\.1 Cats\.m4b -> Vol\. 101\.1 - Cats\/Cats\.m4b$/m, 'inferred decimal numeric-prefix output includes destination');

copy_single_audio_fixture('mp3', '2 - My - Dog.mp3');
my ($exit_dash_three_parts, $out_dash_three_parts, $err_dash_three_parts) = run_cmd('perl', $script, '2 - My - Dog.mp3');
is($exit_dash_three_parts, 0, 'three-part dashed names infer author/series/title');
ok(-d 'Dog', 'three-part dashed name uses third segment as title');
ok(-f File::Spec->catfile('Dog', 'Dog.mp3'), 'three-part dashed name renames file to inferred title');
is($err_dash_three_parts, '', 'three-part dashed name writes no stderr');
like($out_dash_three_parts, qr/^Moved: 2 - My - Dog\.mp3 -> Dog\/Dog\.mp3$/m, 'three-part dashed output uses inferred title destination');

copy_single_audio_fixture('m4b', q{Oh My Gid - Blue Doug 04 - You've Got Dogs.m4b});
my ($exit_dash_three_named, $out_dash_three_named, $err_dash_three_named) = run_cmd('perl', $script, q{Oh My Gid - Blue Doug 04 - You've Got Dogs.m4b});
is($exit_dash_three_named, 0, 'three-part dashed named input infers expected metadata');
ok(-d q{Vol. 4 - You've Got Dogs}, 'three-part dashed named input creates expected volume directory');
ok(-f File::Spec->catfile(q{Vol. 4 - You've Got Dogs}, q{You've Got Dogs.m4b}), 'three-part dashed named input renames file to inferred title');
is($err_dash_three_named, '', 'three-part dashed named input writes no stderr');
like($out_dash_three_named, qr/^Moved: Oh My Gid - Blue Doug 04 - You've Got Dogs\.m4b -> Vol\. 4 - You've Got Dogs\/You've Got Dogs\.m4b$/m, 'three-part dashed named input has expected move output');
like($out_dash_three_named, qr/^Title: You've Got Dogs$/m, 'three-part dashed named input prints title summary');
like($out_dash_three_named, qr/^Volume: 4$/m, 'three-part dashed named input prints volume summary');
like($out_dash_three_named, qr/^Author: Oh My Gid$/m, 'three-part dashed named input prints author summary');
like($out_dash_three_named, qr/^Series: Blue Doug$/m, 'three-part dashed named input prints series summary');

mkdir 'Babba - Agast of the Catbeing 2' or die "failed to create fixture dir 'Babba - Agast of the Catbeing 2': $!";
copy_single_audio_fixture('mp3', File::Spec->catfile('Babba - Agast of the Catbeing 2', 'book.mp3'));
my ($exit_dash_two_suffix_number, $out_dash_two_suffix_number, $err_dash_two_suffix_number) = run_cmd('perl', $script, 'Babba - Agast of the Catbeing 2');
is($exit_dash_two_suffix_number, 0, 'two-part dashed directory with numeric title suffix infers volume and author');
ok(-d 'Vol. 2 - Agast of the Catbeing 2', 'two-part dashed directory with numeric title suffix creates expected volume directory');
ok(!-d 'Babba - Agast of the Catbeing 2', 'two-part dashed source directory is renamed');
ok(-f File::Spec->catfile('Vol. 2 - Agast of the Catbeing 2', 'Agast of the Catbeing 2.mp3'), 'single audio is renamed to inferred title');
is($err_dash_two_suffix_number, '', 'two-part dashed directory with numeric title suffix writes no stderr');
like($out_dash_two_suffix_number, qr/^Moved: Babba - Agast of the Catbeing 2 -> Vol\. 2 - Agast of the Catbeing 2$/m, 'two-part dashed directory output includes expected move line');
like($out_dash_two_suffix_number, qr/^Title: Agast of the Catbeing 2$/m, 'two-part dashed directory output includes title summary');
like($out_dash_two_suffix_number, qr/^Volume: 2$/m, 'two-part dashed directory output includes volume summary');
like($out_dash_two_suffix_number, qr/^Author: Babba$/m, 'two-part dashed directory output includes author summary');

mkdir 'Logo - Lama Lama Lama Mine, Vol 05' or die "failed to create fixture dir 'Logo - Lama Lama Lama Mine, Vol 05': $!";
copy_single_audio_fixture('mp3', File::Spec->catfile('Logo - Lama Lama Lama Mine, Vol 05', 'book.mp3'));
my ($exit_dash_two_suffix_vol05, $out_dash_two_suffix_vol05, $err_dash_two_suffix_vol05) = run_cmd('perl', $script, 'Logo - Lama Lama Lama Mine, Vol 05');
is($exit_dash_two_suffix_vol05, 0, 'two-part dashed directory with "Vol 05" title suffix infers volume and author');
ok(-d 'Vol. 5 - Lama Lama Lama Mine, Vol 05', 'two-part dashed "Vol 05" creates expected volume directory');
ok(!-d 'Logo - Lama Lama Lama Mine, Vol 05', 'two-part dashed "Vol 05" source directory is renamed');
ok(-f File::Spec->catfile('Vol. 5 - Lama Lama Lama Mine, Vol 05', 'Lama Lama Lama Mine, Vol 05.mp3'), 'single audio is renamed to inferred title for "Vol 05" case');
is($err_dash_two_suffix_vol05, '', 'two-part dashed "Vol 05" writes no stderr');
like($out_dash_two_suffix_vol05, qr/^Moved: Logo - Lama Lama Lama Mine, Vol 05 -> Vol\. 5 - Lama Lama Lama Mine, Vol 05$/m, 'two-part dashed "Vol 05" output includes expected move line');
like($out_dash_two_suffix_vol05, qr/^Title: Lama Lama Lama Mine, Vol 05$/m, 'two-part dashed "Vol 05" output includes title summary');
like($out_dash_two_suffix_vol05, qr/^Volume: 5$/m, 'two-part dashed "Vol 05" output includes volume summary');
like($out_dash_two_suffix_vol05, qr/^Author: Logo$/m, 'two-part dashed "Vol 05" output includes author summary');

remove_tree('Vol. 5 - Lama Lama Lama Mine, Vol 05');
copy_single_audio_fixture('mp3', 'Logo - Lama Lama Lama Mine, Vol 05.mp3');
my ($exit_dash_two_file_suffix_vol05, $out_dash_two_file_suffix_vol05, $err_dash_two_file_suffix_vol05) = run_cmd('perl', $script, 'Logo - Lama Lama Lama Mine, Vol 05.mp3');
is($exit_dash_two_file_suffix_vol05, 0, 'two-part dashed file with "Vol 05" title suffix infers volume and author');
ok(-d 'Vol. 5 - Lama Lama Lama Mine, Vol 05', 'two-part dashed file "Vol 05" creates expected volume directory');
ok(-f File::Spec->catfile('Vol. 5 - Lama Lama Lama Mine, Vol 05', 'Lama Lama Lama Mine, Vol 05.mp3'), 'single file is renamed to inferred title for file "Vol 05" case');
is($err_dash_two_file_suffix_vol05, '', 'two-part dashed file "Vol 05" writes no stderr');
like($out_dash_two_file_suffix_vol05, qr/^Moved: Logo - Lama Lama Lama Mine, Vol 05\.mp3 -> Vol\. 5 - Lama Lama Lama Mine, Vol 05\/Lama Lama Lama Mine, Vol 05\.mp3$/m, 'two-part dashed file "Vol 05" output includes expected move line');
like($out_dash_two_file_suffix_vol05, qr/^Title: Lama Lama Lama Mine, Vol 05$/m, 'two-part dashed file "Vol 05" output includes title summary');
like($out_dash_two_file_suffix_vol05, qr/^Volume: 5$/m, 'two-part dashed file "Vol 05" output includes volume summary');
like($out_dash_two_file_suffix_vol05, qr/^Author: Logo$/m, 'two-part dashed file "Vol 05" output includes author summary');

copy_single_audio_fixture('mp3', 'Jane Roe - Vol. 5 - Silver Dog.mp3');
my ($exit_dash_vol_token, $out_dash_vol_token, $err_dash_vol_token) = run_cmd('perl', $script, 'Jane Roe - Vol. 5 - Silver Dog.mp3');
is($exit_dash_vol_token, 0, 'dash-split volume token "Vol. X" is extracted before parsing');
ok(-d 'Vol. 5 - Silver Dog', 'dash-split "Vol. X" creates expected volume directory');
ok(-f File::Spec->catfile('Vol. 5 - Silver Dog', 'Silver Dog.mp3'), 'dash-split "Vol. X" infers expected title');
is($err_dash_vol_token, '', 'dash-split "Vol. X" writes no stderr');
like($out_dash_vol_token, qr/^Moved: Jane Roe - Vol\. 5 - Silver Dog\.mp3 -> Vol\. 5 - Silver Dog\/Silver Dog\.mp3$/m, 'dash-split "Vol. X" output includes expected destination');
like($out_dash_vol_token, qr/^Author: Jane Roe$/m, 'dash-split "Vol. X" infers expected author');

copy_single_audio_fixture('mp3', 'Jane Roe - Book 6 - Blue Dog.mp3');
my ($exit_dash_book_token, $out_dash_book_token, $err_dash_book_token) = run_cmd('perl', $script, 'Jane Roe - Book 6 - Blue Dog.mp3');
is($exit_dash_book_token, 0, 'dash-split volume token "Book X" is extracted before parsing');
ok(-d 'Vol. 6 - Blue Dog', 'dash-split "Book X" creates expected volume directory');
ok(-f File::Spec->catfile('Vol. 6 - Blue Dog', 'Blue Dog.mp3'), 'dash-split "Book X" infers expected title');
is($err_dash_book_token, '', 'dash-split "Book X" writes no stderr');
like($out_dash_book_token, qr/^Moved: Jane Roe - Book 6 - Blue Dog\.mp3 -> Vol\. 6 - Blue Dog\/Blue Dog\.mp3$/m, 'dash-split "Book X" output includes expected destination');
like($out_dash_book_token, qr/^Author: Jane Roe$/m, 'dash-split "Book X" infers expected author');

copy_single_audio_fixture('m4b', '1999 - Jane Roe - Saga 7 - My Tale.m4b');
my ($exit_dash_four_parts, $out_dash_four_parts, $err_dash_four_parts) = run_cmd('perl', $script, '1999 - Jane Roe - Saga 7 - My Tale.m4b');
is($exit_dash_four_parts, 0, 'four-part dashed names infer year/author/series/title');
ok(-d 'Vol. 7 - My Tale', 'four-part dashed name uses inferred series volume for directory');
ok(-f File::Spec->catfile('Vol. 7 - My Tale', 'My Tale.m4b'), 'four-part dashed name renames file to inferred title');
is(tone_meta(File::Spec->catfile('Vol. 7 - My Tale', 'My Tale.m4b'), '$.meta.artist'), 'Jane Roe', 'four-part dashed name writes inferred author metadata');
like(tone_dump_json(File::Spec->catfile('Vol. 7 - My Tale', 'My Tale.m4b')), qr/"publishingDate"\s*:\s*"1999-01-01/, 'four-part dashed name writes inferred year as publishing date');
is($err_dash_four_parts, '', 'four-part dashed name writes no stderr');
like($out_dash_four_parts, qr/^Moved: 1999 - Jane Roe - Saga 7 - My Tale\.m4b -> Vol\. 7 - My Tale\/My Tale\.m4b$/m, 'four-part dashed output uses inferred volume/title destination');
like($out_dash_four_parts, qr/^Year: 1999$/m, 'four-part dashed output includes inferred year summary');

copy_single_audio_fixture('m4b', 'My Reverse Title - Series 9 - Jane Roe.m4b');
my ($exit_reverse_three_parts, $out_reverse_three_parts, $err_reverse_three_parts) = run_cmd('perl', $script, '--reverse', 'My Reverse Title - Series 9 - Jane Roe.m4b');
is($exit_reverse_three_parts, 0, 'reverse mode swaps first and third string in three-part split');
ok(-d 'Vol. 9 - My Reverse Title', 'reverse mode sets title from first string');
ok(-f File::Spec->catfile('Vol. 9 - My Reverse Title', 'My Reverse Title.m4b'), 'reverse mode renames file using reversed title');
is(tone_meta(File::Spec->catfile('Vol. 9 - My Reverse Title', 'My Reverse Title.m4b'), '$.meta.artist'), 'Jane Roe', 'reverse mode sets author from third string');
is($err_reverse_three_parts, '', 'reverse mode three-part writes no stderr');
like($out_reverse_three_parts, qr/^Moved: My Reverse Title - Series 9 - Jane Roe\.m4b -> Vol\. 9 - My Reverse Title\/My Reverse Title\.m4b$/m, 'reverse mode three-part output includes destination');

copy_single_audio_fixture('mp3', 'My Dog Volume 3.mp3');
my ($exit_suffix_volume, $out_suffix_volume, $err_suffix_volume) = run_cmd('perl', $script, 'My Dog Volume 3.mp3');
is($exit_suffix_volume, 0, 'suffix pattern "Volume N" infers volume and title');
ok(-d 'Vol. 3 - My Dog Volume 3', 'suffix "Volume N" creates expected volume directory');
ok(-f File::Spec->catfile('Vol. 3 - My Dog Volume 3', 'My Dog Volume 3.mp3'), 'suffix "Volume N" keeps full title text');
is($err_suffix_volume, '', 'suffix "Volume N" writes no stderr');
like($out_suffix_volume, qr/^Moved: My Dog Volume 3\.mp3 -> Vol\. 3 - My Dog Volume 3\/My Dog Volume 3\.mp3$/m, 'suffix "Volume N" output includes destination');

copy_single_audio_fixture('mp3', 'My Dog Vol 3.mp3');
my ($exit_suffix_vol, $out_suffix_vol, $err_suffix_vol) = run_cmd('perl', $script, 'My Dog Vol 3.mp3');
is($exit_suffix_vol, 0, 'suffix pattern "Vol N" infers volume and title');
ok(-d 'Vol. 3 - My Dog Vol 3', 'suffix "Vol N" creates expected volume directory');
ok(-f File::Spec->catfile('Vol. 3 - My Dog Vol 3', 'My Dog Vol 3.mp3'), 'suffix "Vol N" keeps full title text');
is($err_suffix_vol, '', 'suffix "Vol N" writes no stderr');
like($out_suffix_vol, qr/^Moved: My Dog Vol 3\.mp3 -> Vol\. 3 - My Dog Vol 3\/My Dog Vol 3\.mp3$/m, 'suffix "Vol N" output includes destination');

copy_single_audio_fixture('m4b', 'Foo Knight in Planet Orange Vol. 3.m4b');
my ($exit_suffix_vol_dot, $out_suffix_vol_dot, $err_suffix_vol_dot) = run_cmd('perl', $script, 'Foo Knight in Planet Orange Vol. 3.m4b');
is($exit_suffix_vol_dot, 0, 'suffix pattern "Vol. N" infers volume and title');
ok(-d 'Vol. 3 - Foo Knight in Planet Orange Vol. 3', 'suffix "Vol. N" creates expected volume directory');
ok(-f File::Spec->catfile('Vol. 3 - Foo Knight in Planet Orange Vol. 3', 'Foo Knight in Planet Orange Vol. 3.m4b'), 'suffix "Vol. N" keeps full title text');
is($err_suffix_vol_dot, '', 'suffix "Vol. N" writes no stderr');
like($out_suffix_vol_dot, qr/^Moved: Foo Knight in Planet Orange Vol\. 3\.m4b -> Vol\. 3 - Foo Knight in Planet Orange Vol\. 3\/Foo Knight in Planet Orange Vol\. 3\.m4b$/m, 'suffix "Vol. N" output includes destination');
like($out_suffix_vol_dot, qr/^Title: Foo Knight in Planet Orange Vol\. 3$/m, 'suffix "Vol. N" output includes title summary line');
like($out_suffix_vol_dot, qr/^Volume: 3$/m, 'suffix "Vol. N" output includes volume summary line');

copy_single_audio_fixture('mp3', 'My Dog Book 3.mp3');
my ($exit_suffix_book, $out_suffix_book, $err_suffix_book) = run_cmd('perl', $script, 'My Dog Book 3.mp3');
is($exit_suffix_book, 0, 'suffix pattern "Book N" infers volume and title');
ok(-d 'Vol. 3 - My Dog Book 3', 'suffix "Book N" creates expected volume directory');
ok(-f File::Spec->catfile('Vol. 3 - My Dog Book 3', 'My Dog Book 3.mp3'), 'suffix "Book N" keeps full title text');
is($err_suffix_book, '', 'suffix "Book N" writes no stderr');
like($out_suffix_book, qr/^Moved: My Dog Book 3\.mp3 -> Vol\. 3 - My Dog Book 3\/My Dog Book 3\.mp3$/m, 'suffix "Book N" output includes destination');

copy_single_audio_fixture('mp3', 'My Dog 3.mp3');
my ($exit_suffix_plain, $out_suffix_plain, $err_suffix_plain) = run_cmd('perl', $script, 'My Dog 3.mp3');
is($exit_suffix_plain, 0, 'suffix pattern trailing number infers volume and title');
ok(-d 'Vol. 3 - My Dog 3', 'suffix trailing number creates expected volume directory');
ok(-f File::Spec->catfile('Vol. 3 - My Dog 3', 'My Dog 3.mp3'), 'suffix trailing number keeps full title text');
is($err_suffix_plain, '', 'suffix trailing number writes no stderr');
like($out_suffix_plain, qr/^Moved: My Dog 3\.mp3 -> Vol\. 3 - My Dog 3\/My Dog 3\.mp3$/m, 'suffix trailing number output includes destination');

copy_single_audio_fixture('mp3', '101. Gumby Goop.mp3');
my ($exit_inferred_dot_prefix, $out_inferred_dot_prefix, $err_inferred_dot_prefix) = run_cmd('perl', $script, '101. Gumby Goop.mp3');
is($exit_inferred_dot_prefix, 0, 'inferred part/title from source file name with dot separator succeeds');
ok(-d 'Vol. 101 - Gumby Goop', 'inferred dot-separator volume directory is created');
ok(-f File::Spec->catfile('Vol. 101 - Gumby Goop', 'Gumby Goop.mp3'), 'single audio file is renamed using inferred dot-separator title');
is($err_inferred_dot_prefix, '', 'inferred dot-separator move does not write stderr');
like($out_inferred_dot_prefix, qr/^Moved: 101\. Gumby Goop\.mp3 -> Vol\. 101 - Gumby Goop\/Gumby Goop\.mp3$/m, 'inferred dot-separator output includes destination');
like($out_year_prefix, qr/^Title: Pigs$/m, 'publishing-date output includes title summary line');
like($out_year_prefix, qr/^Year: 1999$/m, 'publishing-date output includes year summary line');

mkdir '02 - Dog God' or die "failed to create fixture dir '02 - Dog God': $!";
copy_single_audio_fixture('mp3', File::Spec->catfile('02 - Dog God', 'book.mp3'));
my ($exit_inferred_prefix, $out_inferred_prefix, $err_inferred_prefix) = run_cmd('perl', $script, '02 - Dog God');
is($exit_inferred_prefix, 0, 'inferred part/title from source directory name succeeds');
ok(-d 'Vol. 2 - Dog God', 'inferred volume directory is created from source name');
ok(!-d '02 - Dog God', 'source directory is renamed to inferred volume directory');
ok(-f File::Spec->catfile('Vol. 2 - Dog God', 'Dog God.mp3'), 'single audio file is renamed to inferred title');
is($err_inferred_prefix, '', 'inferred part/title directory move does not write stderr');
like($out_inferred_prefix, qr/^Moved: 02 - Dog God -> Vol\. 2 - Dog God$/m, 'inferred part/title output includes destination');

mkdir '22 - Bright Red Line' or die "failed to create fixture dir '22 - Bright Red Line': $!";
my ($exit_numeric_dash_prefix, $out_numeric_dash_prefix, $err_numeric_dash_prefix) = run_cmd('perl', $script, '22 - Bright Red Line');
is($exit_numeric_dash_prefix, 0, 'numeric dash-prefix directory infers title and volume');
ok(-d 'Vol. 22 - Bright Red Line', 'numeric dash-prefix directory is renamed with inferred volume');
ok(!-d '22 - Bright Red Line', 'numeric dash-prefix source directory no longer exists after rename');
is($err_numeric_dash_prefix, '', 'numeric dash-prefix directory does not write stderr');
like($out_numeric_dash_prefix, qr/^Title: Bright Red Line$/m, 'numeric dash-prefix output includes title summary');
like($out_numeric_dash_prefix, qr/^Volume: 22$/m, 'numeric dash-prefix output includes volume summary');
unlike($out_numeric_dash_prefix, qr/^Series:/m, 'numeric dash-prefix output does not include series summary');

mkdir 'Wizards First Rule - A Really Good Subtitle' or die "failed to create fixture dir 'Wizards First Rule - A Really Good Subtitle': $!";
copy_single_audio_fixture('m4b', File::Spec->catfile('Wizards First Rule - A Really Good Subtitle', 'book.m4b'));
my ($exit_has_subtitle, $out_has_subtitle, $err_has_subtitle) = run_cmd('perl', $script, '--has-subtitle', 'Wizards First Rule - A Really Good Subtitle');
is($exit_has_subtitle, 0, '--has-subtitle with dashed input succeeds');
ok(-d 'Wizards First Rule', '--has-subtitle strips subtitle segment for inferred title');
ok(!-d 'Wizards First Rule - A Really Good Subtitle', '--has-subtitle source directory no longer exists after rename');
ok(-f File::Spec->catfile('Wizards First Rule', 'Wizards First Rule.m4b'), '--has-subtitle single audio file is renamed to inferred title');
is(tone_meta(File::Spec->catfile('Wizards First Rule', 'Wizards First Rule.m4b'), '$.meta.additionalFields.subtitle'), 'A Really Good Subtitle', '--has-subtitle updates tone subtitle metadata');
is($err_has_subtitle, '', '--has-subtitle case does not write stderr');
like($out_has_subtitle, qr/^Title: Wizards First Rule$/m, '--has-subtitle output includes stripped title summary');
like($out_has_subtitle, qr/^Subtitle: A Really Good Subtitle$/m, '--has-subtitle output includes subtitle summary');

mkdir q{Vol. 4 - Mine Level 42: I the Hidden Dog but I'm Not the Cat Lord Act 4}
  or die q{failed to create fixture dir 'Vol. 4 - Mine Level 42: I the Hidden Dog but I'm Not the Cat Lord Act 4': } . $!;
my ($exit_vol_colon_complex, $out_vol_colon_complex, $err_vol_colon_complex) = run_cmd(
    'perl',
    $script,
    q{Vol. 4 - Mine Level 42: I the Hidden Dog but I'm Not the Cat Lord Act 4}
);
is($exit_vol_colon_complex, 0, 'complex vol-prefixed colon title directory succeeds');
ok(-d 'Vol. 4 - Mine Level 42', 'complex vol-prefixed colon title directory is normalized to parsed title');
ok(!-d q{Vol. 4 - Mine Level 42: I the Hidden Dog but I'm Not the Cat Lord Act 4}, 'complex vol-prefixed colon source directory no longer exists after rename');
is($err_vol_colon_complex, '', 'complex vol-prefixed colon title directory does not write stderr');
like($out_vol_colon_complex, qr/^Moved: Vol\. 4 - Mine Level 42: I the Hidden Dog but I'm Not the Cat Lord Act 4 -> Vol\. 4 - Mine Level 42$/m, 'complex vol-prefixed colon output includes expected move line');
like($out_vol_colon_complex, qr/^Title: Mine Level 42$/m, 'complex vol-prefixed colon output includes parsed title');
like($out_vol_colon_complex, qr/^Subtitle: I the Hidden Dog but I'm Not the Cat Lord Act 4$/m, 'complex vol-prefixed colon output includes parsed subtitle');
like($out_vol_colon_complex, qr/^Volume: 4$/m, 'complex vol-prefixed colon output includes parsed volume');

mkdir '1994 - Book 1 - Wizards First Rule' or die "failed to create fixture dir '1994 - Book 1 - Wizards First Rule': $!";
my ($exit_year_volume_token, $out_year_volume_token, $err_year_volume_token) = run_cmd('perl', $script, '1994 - Book 1 - Wizards First Rule');
is($exit_year_volume_token, 0, 'year + volume-token dashed directory infers title/volume/year');
ok(-d 'Vol. 1 - Wizards First Rule', 'year + volume-token dashed directory is renamed with inferred volume and title');
ok(!-d '1994 - Book 1 - Wizards First Rule', 'year + volume-token dashed source directory no longer exists after rename');
is($err_year_volume_token, '', 'year + volume-token dashed directory does not write stderr');
like($out_year_volume_token, qr/^Moved: 1994 - Book 1 - Wizards First Rule -> Vol\. 1 - Wizards First Rule$/m, 'year + volume-token dashed output includes expected move line');
like($out_year_volume_token, qr/^Title: Wizards First Rule$/m, 'year + volume-token dashed output includes title summary');
like($out_year_volume_token, qr/^Volume: 1$/m, 'year + volume-token dashed output includes volume summary');
like($out_year_volume_token, qr/^Year: 1994$/m, 'year + volume-token dashed output includes year summary');

mkdir '(1994) - Wizards First Rule' or die "failed to create fixture dir '(1994) - Wizards First Rule': $!";
my ($exit_wrapped_year_prefix, $out_wrapped_year_prefix, $err_wrapped_year_prefix) = run_cmd('perl', $script, '(1994) - Wizards First Rule');
is($exit_wrapped_year_prefix, 0, 'parenthesized year prefix infers year and title');
ok(-d '1994 - Wizards First Rule', 'parenthesized year prefix directory is renamed to publishing-date format');
ok(!-d '(1994) - Wizards First Rule', 'parenthesized year prefix source directory no longer exists after rename');
is($err_wrapped_year_prefix, '', 'parenthesized year prefix does not write stderr');
like($out_wrapped_year_prefix, qr/^Title: Wizards First Rule$/m, 'parenthesized year prefix output includes title summary');
like($out_wrapped_year_prefix, qr/^Year: 1994$/m, 'parenthesized year prefix output includes year summary');

remove_tree('1994 - Wizards First Rule');
copy_single_audio_fixture('mp3', 'Wizards First Rule [1994].mp3');
my ($exit_wrapped_year_suffix, $out_wrapped_year_suffix, $err_wrapped_year_suffix) = run_cmd('perl', $script, 'Wizards First Rule [1994].mp3');
is($exit_wrapped_year_suffix, 0, 'bracketed year suffix infers year and title');
ok(-d '1994 - Wizards First Rule', 'bracketed year suffix creates publishing-date directory');
ok(-f File::Spec->catfile('1994 - Wizards First Rule', 'Wizards First Rule [1994].mp3'), 'bracketed year suffix renames audio file and reapplies bracket segments');
is($err_wrapped_year_suffix, '', 'bracketed year suffix does not write stderr');
like($out_wrapped_year_suffix, qr/^Title: Wizards First Rule$/m, 'bracketed year suffix output includes title summary');
like($out_wrapped_year_suffix, qr/^Year: 1994$/m, 'bracketed year suffix output includes year summary');

remove_tree('1994 - Wizards First Rule');

mkdir '1994 - Volume 1. Wizards First Rule {Sam Tsoutsouvas}'
  or die "failed to create fixture dir '1994 - Volume 1. Wizards First Rule {Sam Tsoutsouvas}': $!";
copy_single_audio_fixture(
    'm4b',
    File::Spec->catfile('1994 - Volume 1. Wizards First Rule {Sam Tsoutsouvas}', 'book.m4b')
);
remove_tree('Vol. 1 - Wizards First Rule');
remove_tree('Vol. 1 - Wizards First Rule {Sam Tsoutsouvas}');
my ($exit_year_volume_dotted, $out_year_volume_dotted, $err_year_volume_dotted) = run_cmd(
    'perl',
    $script,
    '1994 - Volume 1. Wizards First Rule {Sam Tsoutsouvas}'
);
is($exit_year_volume_dotted, 0, 'year + dotted volume/title segment with narrator succeeds');
ok(-d 'Vol. 1 - Wizards First Rule {Sam Tsoutsouvas}', 'year + dotted volume/title creates expected volume directory');
ok(!-d '1994 - Volume 1. Wizards First Rule {Sam Tsoutsouvas}', 'year + dotted volume/title source directory no longer exists after rename');
ok(-f File::Spec->catfile('Vol. 1 - Wizards First Rule {Sam Tsoutsouvas}', 'Wizards First Rule.m4b'), 'year + dotted volume/title renames single audio file to inferred title');
is($err_year_volume_dotted, '', 'year + dotted volume/title does not write stderr');
like($out_year_volume_dotted, qr/^Title: Wizards First Rule$/m, 'year + dotted volume/title output includes title summary');
like($out_year_volume_dotted, qr/^Volume: 1$/m, 'year + dotted volume/title output includes volume summary');
like($out_year_volume_dotted, qr/^Year: 1994$/m, 'year + dotted volume/title output includes year summary');
like($out_year_volume_dotted, qr/^Narrators: Sam Tsoutsouvas$/m, 'year + dotted volume/title output includes narrators summary');

remove_tree('Vol. 1 - Wizards First Rule');
remove_tree('Vol. 1 - Wizards First Rule {Sam Tsoutsouvas}');

mkdir 'Vol. 1 - 1994 - Wizards First Rule - A Really Good Subtitle {Sam Tsoutsouvas}'
  or die "failed to create fixture dir 'Vol. 1 - 1994 - Wizards First Rule - A Really Good Subtitle {Sam Tsoutsouvas}': $!";
copy_single_audio_fixture(
    'm4b',
    File::Spec->catfile(
        'Vol. 1 - 1994 - Wizards First Rule - A Really Good Subtitle {Sam Tsoutsouvas}',
        'book.m4b'
    )
);
remove_tree('Vol. 1 - Wizards First Rule');
remove_tree('Vol. 1 - Wizards First Rule {Sam Tsoutsouvas}');
my ($exit_has_subtitle_complex, $out_has_subtitle_complex, $err_has_subtitle_complex) = run_cmd(
    'perl',
    $script,
    '--has-subtitle',
    'Vol. 1 - 1994 - Wizards First Rule - A Really Good Subtitle {Sam Tsoutsouvas}'
);
is($exit_has_subtitle_complex, 0, '--has-subtitle complex dashed input with narrator succeeds');
ok(-d 'Vol. 1 - Wizards First Rule {Sam Tsoutsouvas}', '--has-subtitle complex input creates expected volume directory');
ok(!-d 'Vol. 1 - 1994 - Wizards First Rule - A Really Good Subtitle {Sam Tsoutsouvas}', '--has-subtitle complex source directory no longer exists after rename');
ok(-f File::Spec->catfile('Vol. 1 - Wizards First Rule {Sam Tsoutsouvas}', 'Wizards First Rule.m4b'), '--has-subtitle complex input renames single audio file to inferred title');
is(tone_meta(File::Spec->catfile('Vol. 1 - Wizards First Rule {Sam Tsoutsouvas}', 'Wizards First Rule.m4b'), '$.meta.additionalFields.subtitle'), 'A Really Good Subtitle', '--has-subtitle complex input updates tone subtitle metadata');
is($err_has_subtitle_complex, '', '--has-subtitle complex input does not write stderr');
like($out_has_subtitle_complex, qr/^Title: Wizards First Rule$/m, '--has-subtitle complex output includes title summary');
like($out_has_subtitle_complex, qr/^Subtitle: A Really Good Subtitle$/m, '--has-subtitle complex output includes subtitle summary');
like($out_has_subtitle_complex, qr/^Volume: 1$/m, '--has-subtitle complex output includes volume summary');
like($out_has_subtitle_complex, qr/^Year: 1994$/m, '--has-subtitle complex output includes year summary');
like($out_has_subtitle_complex, qr/^Narrators: Sam Tsoutsouvas$/m, '--has-subtitle complex output includes narrators summary');

copy_single_audio_fixture('m4b', 'So You Want to Breed Dogs!- Lessons from the Lab to the shit-zu [2024].m4b');
my ($exit_inline_subtitle, $out_inline_subtitle, $err_inline_subtitle) = run_cmd(
    'perl',
    $script,
    'So You Want to Breed Dogs!- Lessons from the Lab to the shit-zu [2024].m4b'
);
is($exit_inline_subtitle, 0, 'inline title subtitle marker with bracketed year succeeds');
ok(-d '2024 - So You Want to Breed Dogs!', 'inline subtitle marker with bracketed year creates expected publishing-date directory');
ok(-f File::Spec->catfile('2024 - So You Want to Breed Dogs!', 'So You Want to Breed Dogs! [2024].m4b'), 'inline subtitle marker renames audio file and reapplies bracket segments');
is(
    tone_meta(
        File::Spec->catfile('2024 - So You Want to Breed Dogs!', 'So You Want to Breed Dogs! [2024].m4b'),
        '$.meta.additionalFields.subtitle'
    ),
    'Lessons from the Lab to the shit-zu',
    'inline subtitle marker updates subtitle metadata'
);
is($err_inline_subtitle, '', 'inline subtitle marker does not write stderr');
like($out_inline_subtitle, qr/^Title: So You Want to Breed Dogs!$/m, 'inline subtitle marker output includes parsed title');
like($out_inline_subtitle, qr/^Subtitle: Lessons from the Lab to the shit-zu$/m, 'inline subtitle marker output includes parsed subtitle');
like($out_inline_subtitle, qr/^Year: 2024$/m, 'inline subtitle marker output includes year summary');

copy_single_audio_fixture('m4b', 'R.A. Babish - Super Tumor 4: The Search for the Bump.m4b');
my ($exit_author_colon_subtitle, $out_author_colon_subtitle, $err_author_colon_subtitle) = run_cmd(
    'perl',
    $script,
    'R.A. Babish - Super Tumor 4: The Search for the Bump.m4b'
);
is($exit_author_colon_subtitle, 0, 'author/title input with colon subtitle marker succeeds');
ok(-d 'Super Tumor 4', 'author/title colon subtitle case creates expected title directory');
ok(-f File::Spec->catfile('Super Tumor 4', 'Super Tumor 4.m4b'), 'author/title colon subtitle case renames single audio file to title');
is(
    tone_meta(
        File::Spec->catfile('Super Tumor 4', 'Super Tumor 4.m4b'),
        '$.meta.additionalFields.subtitle'
    ),
    'The Search for the Bump',
    'author/title colon subtitle case updates subtitle metadata'
);
is($err_author_colon_subtitle, '', 'author/title colon subtitle case does not write stderr');
like($out_author_colon_subtitle, qr/^Title: Super Tumor 4$/m, 'author/title colon subtitle output includes parsed title');
like($out_author_colon_subtitle, qr/^Subtitle: The Search for the Bump$/m, 'author/title colon subtitle output includes parsed subtitle');
like($out_author_colon_subtitle, qr/^Author: R\.A\. Babish$/m, 'author/title colon subtitle output includes parsed author');

copy_single_audio_fixture('m4b', q{Hero's, Vol. 4: Light Novel.m4b});
my ($exit_comma_vol_colon, $out_comma_vol_colon, $err_comma_vol_colon) = run_cmd(
    'perl',
    $script,
    q{Hero's, Vol. 4: Light Novel.m4b}
);
is($exit_comma_vol_colon, 0, 'comma + volume keyword before colon keeps left side as title');
ok(-d q{Vol. 4 - Hero's, Vol. 4}, 'comma + volume keyword before colon creates expected directory');
ok(-f File::Spec->catfile(q{Vol. 4 - Hero's, Vol. 4}, q{Hero's, Vol. 4.m4b}), 'comma + volume keyword before colon renames file using full left side title');
is(tone_meta(File::Spec->catfile(q{Vol. 4 - Hero's, Vol. 4}, q{Hero's, Vol. 4.m4b}), '$.meta.movementName'), q{Hero's}, 'comma + volume keyword before colon sets series from text before comma');
is($err_comma_vol_colon, '', 'comma + volume keyword before colon does not write stderr');
like($out_comma_vol_colon, qr/^Title: Hero's, Vol\. 4$/m, 'comma + volume keyword before colon output keeps title unchanged');
like($out_comma_vol_colon, qr/^Subtitle: Light Novel$/m, 'comma + volume keyword before colon output keeps subtitle from right side');
like($out_comma_vol_colon, qr/^Volume: 4$/m, 'comma + volume keyword before colon output includes parsed volume');
like($out_comma_vol_colon, qr/^Series: Hero's$/m, 'comma + volume keyword before colon output includes parsed series');

copy_single_audio_fixture('m4b', 'Rocket Dogs- Into Orbit.m4b');
my ($exit_hyphen_subtitle, $out_hyphen_subtitle, $err_hyphen_subtitle) = run_cmd(
    'perl',
    $script,
    'Rocket Dogs- Into Orbit.m4b'
);
is($exit_hyphen_subtitle, 0, 'single title with hyphen subtitle marker succeeds');
ok(-d 'Rocket Dogs', 'hyphen subtitle marker creates expected title directory');
ok(-f File::Spec->catfile('Rocket Dogs', 'Rocket Dogs.m4b'), 'hyphen subtitle marker renames single audio file to parsed title');
is(
    tone_meta(
        File::Spec->catfile('Rocket Dogs', 'Rocket Dogs.m4b'),
        '$.meta.additionalFields.subtitle'
    ),
    'Into Orbit',
    'hyphen subtitle marker updates subtitle metadata'
);
is($err_hyphen_subtitle, '', 'hyphen subtitle marker does not write stderr');
like($out_hyphen_subtitle, qr/^Title: Rocket Dogs$/m, 'hyphen subtitle marker output includes parsed title');
like($out_hyphen_subtitle, qr/^Subtitle: Into Orbit$/m, 'hyphen subtitle marker output includes parsed subtitle');

mkdir 'Dog Lift Campe 4 - An Doggone Fashion Tale'
  or die "failed to create fixture dir 'Dog Lift Campe 4 - An Doggone Fashion Tale': $!";
copy_single_audio_fixture(
    'm4b',
    File::Spec->catfile('Dog Lift Campe 4 - An Doggone Fashion Tale', 'book.m4b')
);
my ($exit_has_subtitle_series_volume, $out_has_subtitle_series_volume, $err_has_subtitle_series_volume) = run_cmd(
    'perl',
    $script,
    '--has-subtitle',
    'Dog Lift Campe 4 - An Doggone Fashion Tale'
);
is($exit_has_subtitle_series_volume, 0, '--has-subtitle series-volume and subtitle input succeeds');
ok(-d 'Vol. 4 - Dog Lift Campe 4', '--has-subtitle series-volume case creates expected directory');
ok(!-d 'Dog Lift Campe 4 - An Doggone Fashion Tale', '--has-subtitle series-volume source directory no longer exists after rename');
ok(-f File::Spec->catfile('Vol. 4 - Dog Lift Campe 4', 'Dog Lift Campe 4.m4b'), '--has-subtitle series-volume case renames single audio file to inferred title');
is(
    tone_meta(
        File::Spec->catfile('Vol. 4 - Dog Lift Campe 4', 'Dog Lift Campe 4.m4b'),
        '$.meta.additionalFields.subtitle'
    ),
    'An Doggone Fashion Tale',
    '--has-subtitle series-volume case updates subtitle metadata'
);
is($err_has_subtitle_series_volume, '', '--has-subtitle series-volume case does not write stderr');
like($out_has_subtitle_series_volume, qr/^Title: Dog Lift Campe 4$/m, '--has-subtitle series-volume output includes title summary');
like($out_has_subtitle_series_volume, qr/^Subtitle: An Doggone Fashion Tale$/m, '--has-subtitle series-volume output includes subtitle summary');
like($out_has_subtitle_series_volume, qr/^Volume: 4$/m, '--has-subtitle series-volume output includes volume summary');
unlike($out_has_subtitle_series_volume, qr/^Series:/m, '--has-subtitle series-volume output does not include series summary');

remove_tree('Vol. 4 - Dog Lift Campe 4');

mkdir '02.5 - Dog God' or die "failed to create fixture dir '02.5 - Dog God': $!";
copy_single_audio_fixture('m4b', File::Spec->catfile('02.5 - Dog God', 'book.m4b'));
write_file(File::Spec->catfile('02.5 - Dog God', 'cover.jpg'), 'cover-image');
write_file(File::Spec->catfile('02.5 - Dog God', 'book.epub'), 'epub-content');
my ($exit_inferred_decimal_prefix, $out_inferred_decimal_prefix, $err_inferred_decimal_prefix) = run_cmd('perl', $script, '02.5 - Dog God');
is($exit_inferred_decimal_prefix, 0, 'inferred decimal part/title from source directory name succeeds');
ok(-d 'Vol. 2.5 - Dog God', 'inferred decimal volume directory is created from source name');
ok(!-d '02.5 - Dog God', 'decimal source directory is renamed to inferred volume directory');
ok(-f File::Spec->catfile('Vol. 2.5 - Dog God', 'Dog God.m4b'), 'single m4b audio file is renamed to inferred title');
ok(-f File::Spec->catfile('Vol. 2.5 - Dog God', 'cover.jpg'), 'cover.jpg is preserved in inferred decimal directory');
ok(-f File::Spec->catfile('Vol. 2.5 - Dog God', 'book.epub'), 'book.epub is preserved in inferred decimal directory');
is($err_inferred_decimal_prefix, '', 'inferred decimal part/title directory move does not write stderr');
like($out_inferred_decimal_prefix, qr/^Moved: 02\.5 - Dog God -> Vol\. 2\.5 - Dog God$/m, 'inferred decimal part/title output includes destination');

mkdir 'Bundle' or die "failed to create fixture dir 'Bundle': $!";
copy_single_audio_fixture('mp3', File::Spec->catfile('Bundle', 'track01.mp3'));
my ($exit_dir_source, $out_dir_source, $err_dir_source) = run_cmd('perl', $script, 'Bundle', '4');
is($exit_dir_source, 0, 'directory source with part succeeds');
ok(-d 'Vol. 4 - Bundle', 'volume directory for directory source is created');
ok(!-d 'Bundle', 'source directory no longer exists after rename');
ok(-f File::Spec->catfile('Vol. 4 - Bundle', 'Bundle.mp3'), 'single directory audio file is renamed to resolved title');
is($err_dir_source, '', 'directory source with part does not write stderr');
like($out_dir_source, qr/^Moved: Bundle -> Vol\. 4 - Bundle$/m, 'directory source output includes destination');

remove_tree('Vol. 4 - Bundle');
remove_tree('Vol. 04 - Bundle');
mkdir 'Vol. 04 - Bundle' or die "failed to create fixture dir 'Vol. 04 - Bundle': $!";
copy_audio_fixture('mp3', File::Spec->catfile('Vol. 04 - Bundle', 'track01.mp3'));
copy_audio_fixture('mp3', File::Spec->catfile('Vol. 04 - Bundle', 'track02.mp3'));
my ($exit_dir_inferred_vol_prefix, $out_dir_inferred_vol_prefix, $err_dir_inferred_vol_prefix) = run_cmd('perl', $script, 'Vol. 04 - Bundle');
is($exit_dir_inferred_vol_prefix, 0, 'directory source with "Vol. 04 - Title" infers volume and title');
ok(-d 'Vol. 4 - Bundle', 'directory source with inferred volume prefix creates expected directory');
ok(!-d 'Vol. 04 - Bundle', 'directory source with inferred volume prefix source directory is renamed');
ok(-f File::Spec->catfile('Vol. 4 - Bundle', 'track01.mp3'), 'multi-audio file 1 preserved for inferred volume prefix case');
ok(-f File::Spec->catfile('Vol. 4 - Bundle', 'track02.mp3'), 'multi-audio file 2 preserved for inferred volume prefix case');
is($err_dir_inferred_vol_prefix, '', 'directory source with inferred volume prefix does not write stderr');
like($out_dir_inferred_vol_prefix, qr/^Moved: Vol\. 04 - Bundle -> Vol\. 4 - Bundle$/m, 'directory source with inferred volume prefix output includes expected move line');
like($out_dir_inferred_vol_prefix, qr/^Title: Bundle$/m, 'directory source with inferred volume prefix output includes title summary');
like($out_dir_inferred_vol_prefix, qr/^Volume: 4$/m, 'directory source with inferred volume prefix output includes volume summary');

remove_tree('Vol. 4 - Bundle');
mkdir 'Vol. 4 - Bundle' or die "failed to create fixture dir 'Vol. 4 - Bundle': $!";
copy_audio_fixture('mp3', File::Spec->catfile('Vol. 4 - Bundle', 'track01.mp3'));
copy_audio_fixture('mp3', File::Spec->catfile('Vol. 4 - Bundle', 'track02.mp3'));
write_file(File::Spec->catfile('Vol. 4 - Bundle', 'album.jpg'), 'album-image');
my ($exit_dir_already_named, $out_dir_already_named, $err_dir_already_named) = run_cmd('perl', $script, 'Vol. 4 - Bundle');
is($exit_dir_already_named, 0, 'already-normalized directory name succeeds without rename conflict');
ok(-d 'Vol. 4 - Bundle', 'already-normalized directory remains in place');
ok(-f File::Spec->catfile('Vol. 4 - Bundle', 'track01.mp3'), 'already-normalized directory preserves first audio file');
ok(-f File::Spec->catfile('Vol. 4 - Bundle', 'track02.mp3'), 'already-normalized directory preserves second audio file');
ok(-f File::Spec->catfile('Vol. 4 - Bundle', 'album.jpg'), 'already-normalized directory keeps original album image');
ok(-f File::Spec->catfile('Vol. 4 - Bundle', 'cover.jpg'), 'already-normalized directory creates cover.jpg from album.jpg');
is(read_file(File::Spec->catfile('Vol. 4 - Bundle', 'cover.jpg')), 'album-image', 'already-normalized directory cover.jpg content matches album.jpg');
is($err_dir_already_named, '', 'already-normalized directory writes no stderr');
like($out_dir_already_named, qr/^Title: Bundle$/m, 'already-normalized directory output includes title summary');
like($out_dir_already_named, qr/^Volume: 4$/m, 'already-normalized directory output includes volume summary');

remove_tree('Vol. 2 - Foo Dog (The Dogawg)');
mkdir 'Vol. 2 - Foo Dog (The Dogawg)' or die "failed to create fixture dir 'Vol. 2 - Foo Dog (The Dogawg)': $!";
copy_single_audio_fixture('m4b', File::Spec->catfile('Vol. 2 - Foo Dog (The Dogawg)', 'book.m4b'));
my ($exit_dir_append_title_named, $out_dir_append_title_named, $err_dir_append_title_named) = run_cmd('perl', $script, 'Vol. 2 - Foo Dog (The Dogawg)');
is($exit_dir_append_title_named, 0, 'already-normalized appended-title directory with single audio succeeds');
ok(-d 'Vol. 2 - Foo Dog (The Dogawg)', 'already-normalized appended-title directory remains in place');
ok(-f File::Spec->catfile('Vol. 2 - Foo Dog (The Dogawg)', 'Foo Dog (The Dogawg).m4b'), 'already-normalized appended-title directory renames single audio to title');
ok(!-f File::Spec->catfile('Vol. 2 - Foo Dog (The Dogawg)', 'book.m4b'), 'already-normalized appended-title directory removes old single-audio filename');
is($err_dir_append_title_named, '', 'already-normalized appended-title directory does not write stderr');
like($out_dir_append_title_named, qr/^Title: Foo Dog \(The Dogawg\)$/m, 'already-normalized appended-title output includes title summary');
like($out_dir_append_title_named, qr/^Volume: 2$/m, 'already-normalized appended-title output includes volume summary');

mkdir 'The Fool (US Version)' or die "failed to create fixture dir 'The Fool (US Version)': $!";
copy_single_audio_fixture('m4b', File::Spec->catfile('The Fool (US Version)', 'The Fool [US Version].m4b'));
my ($exit_dir_bracket_normalize, $out_dir_bracket_normalize, $err_dir_bracket_normalize) = run_cmd('perl', $script, 'The Fool (US Version)', '2');
is($exit_dir_bracket_normalize, 0, 'directory source with bracket/paren title normalization succeeds');
ok(-d 'Vol. 2 - The Fool (US Version)', 'directory source with bracket/paren normalization creates expected volume directory');
ok(!-d 'The Fool (US Version)', 'directory source with bracket/paren normalization renames source directory');
ok(-f File::Spec->catfile('Vol. 2 - The Fool (US Version)', 'The Fool (US Version).m4b'), 'single audio file is renamed to directory title with parentheses');
ok(!-f File::Spec->catfile('Vol. 2 - The Fool (US Version)', 'The Fool [US Version].m4b'), 'single audio file with square brackets is replaced by parentheses form');
is($err_dir_bracket_normalize, '', 'directory source with bracket/paren normalization does not write stderr');
like($out_dir_bracket_normalize, qr/^Moved: The Fool \(US Version\) -> Vol\. 2 - The Fool \(US Version\)$/m, 'directory source with bracket/paren normalization output includes destination');
like($out_dir_bracket_normalize, qr/^Title: The Fool \(US Version\)$/m, 'directory source with bracket/paren normalization output includes title summary');
like($out_dir_bracket_normalize, qr/^Volume: 2$/m, 'directory source with bracket/paren normalization output includes volume summary');

mkdir 'Pack' or die "failed to create fixture dir 'Pack': $!";
copy_single_audio_fixture('mp3', File::Spec->catfile('Pack', 'track01.mp3'));
my ($exit_dir_title, $out_dir_title, $err_dir_title) = run_cmd('perl', $script, 'Pack', '5', 'My', 'Pack');
is($exit_dir_title, 0, 'directory source with part and title succeeds');
ok(-d 'Vol. 5 - My Pack', 'volume directory for titled directory source is created');
ok(!-d 'Pack', 'titled source directory no longer exists after rename');
ok(-f File::Spec->catfile('Vol. 5 - My Pack', 'My Pack.mp3'), 'single audio file is renamed to title');
ok(!-f File::Spec->catfile('Vol. 5 - My Pack', 'track01.mp3'), 'old audio filename is not kept for single-audio directory');
is(tone_album(File::Spec->catfile('Vol. 5 - My Pack', 'My Pack.mp3')), 'My Pack', 'renamed single audio in directory has album metadata updated to title');
is(tone_title(File::Spec->catfile('Vol. 5 - My Pack', 'My Pack.mp3')), 'My Pack', 'renamed single audio in directory has title metadata updated to title');
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

mkdir 'Foo Dyntasty' or die "failed to create fixture dir 'Foo Dyntasty': $!";
copy_audio_fixture('mp3', File::Spec->catfile('Foo Dyntasty', 'part 1.mp3'));
copy_audio_fixture('mp3', File::Spec->catfile('Foo Dyntasty', 'part 2.mp3'));
copy_audio_fixture('mp3', File::Spec->catfile('Foo Dyntasty', 'part 3.mp3'));
copy_audio_fixture('mp3', File::Spec->catfile('Foo Dyntasty', 'part 4.mp3'));
copy_audio_fixture('mp3', File::Spec->catfile('Foo Dyntasty', 'part5.mp3'));
set_tone_title(File::Spec->catfile('Foo Dyntasty', 'part 1.mp3'), 'Intro');
set_tone_title(File::Spec->catfile('Foo Dyntasty', 'part 2.mp3'), 'Chapter 1');
set_tone_title(File::Spec->catfile('Foo Dyntasty', 'part 3.mp3'), 'Chapter 2');
set_tone_title(File::Spec->catfile('Foo Dyntasty', 'part 4.mp3'), 'Chapter 3');
set_tone_title(File::Spec->catfile('Foo Dyntasty', 'part5.mp3'), 'Outro');
my ($exit_multi_title_preserve, $out_multi_title_preserve, $err_multi_title_preserve) = run_cmd('perl', $script, 'Foo Dyntasty', '1');
is($exit_multi_title_preserve, 0, 'multi-audio directory with per-file title tags succeeds');
ok(-d 'Vol. 1 - Foo Dyntasty', 'multi-audio title-preserve case creates expected volume directory');
ok(!-d 'Foo Dyntasty', 'multi-audio title-preserve source directory is renamed');
ok(-f File::Spec->catfile('Vol. 1 - Foo Dyntasty', 'part 1.mp3'), 'multi-audio title-preserve keeps part 1 filename');
ok(-f File::Spec->catfile('Vol. 1 - Foo Dyntasty', 'part 2.mp3'), 'multi-audio title-preserve keeps part 2 filename');
ok(-f File::Spec->catfile('Vol. 1 - Foo Dyntasty', 'part 3.mp3'), 'multi-audio title-preserve keeps part 3 filename');
ok(-f File::Spec->catfile('Vol. 1 - Foo Dyntasty', 'part 4.mp3'), 'multi-audio title-preserve keeps part 4 filename');
ok(-f File::Spec->catfile('Vol. 1 - Foo Dyntasty', 'part5.mp3'), 'multi-audio title-preserve keeps part5 filename');
is(tone_title(File::Spec->catfile('Vol. 1 - Foo Dyntasty', 'part 1.mp3')), 'Intro', 'multi-audio title-preserve keeps per-file title metadata for part 1');
is(tone_title(File::Spec->catfile('Vol. 1 - Foo Dyntasty', 'part 2.mp3')), 'Chapter 1', 'multi-audio title-preserve keeps per-file title metadata for part 2');
is(tone_title(File::Spec->catfile('Vol. 1 - Foo Dyntasty', 'part 3.mp3')), 'Chapter 2', 'multi-audio title-preserve keeps per-file title metadata for part 3');
is(tone_title(File::Spec->catfile('Vol. 1 - Foo Dyntasty', 'part 4.mp3')), 'Chapter 3', 'multi-audio title-preserve keeps per-file title metadata for part 4');
is(tone_title(File::Spec->catfile('Vol. 1 - Foo Dyntasty', 'part5.mp3')), 'Outro', 'multi-audio title-preserve keeps per-file title metadata for part5');
is(tone_album(File::Spec->catfile('Vol. 1 - Foo Dyntasty', 'part 1.mp3')), 'Foo Dyntasty', 'multi-audio title-preserve sets album metadata for part 1');
is(tone_album(File::Spec->catfile('Vol. 1 - Foo Dyntasty', 'part 2.mp3')), 'Foo Dyntasty', 'multi-audio title-preserve sets album metadata for part 2');
is(tone_album(File::Spec->catfile('Vol. 1 - Foo Dyntasty', 'part 3.mp3')), 'Foo Dyntasty', 'multi-audio title-preserve sets album metadata for part 3');
is(tone_album(File::Spec->catfile('Vol. 1 - Foo Dyntasty', 'part 4.mp3')), 'Foo Dyntasty', 'multi-audio title-preserve sets album metadata for part 4');
is(tone_album(File::Spec->catfile('Vol. 1 - Foo Dyntasty', 'part5.mp3')), 'Foo Dyntasty', 'multi-audio title-preserve sets album metadata for part5');
is($err_multi_title_preserve, '', 'multi-audio title-preserve case does not write stderr');
like($out_multi_title_preserve, qr/^Moved: Foo Dyntasty -> Vol\. 1 - Foo Dyntasty$/m, 'multi-audio title-preserve output includes expected move line');

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
ok(-f File::Spec->catfile('Vol. 7 - Cover Exclusion', 'cover-orig.jpg'), 'original cover.jpg is backed up to cover-orig.jpg');
is(read_file(File::Spec->catfile('Vol. 7 - Cover Exclusion', 'cover-orig.jpg')), '12345678901234567890', 'cover-orig.jpg preserves original cover content');
is($err_cover_exclusion, '', 'cover exclusion test does not write stderr');
like($out_cover_exclusion, qr/^Moved: Image Exclusion -> Vol\. 7 - Cover Exclusion$/m, 'cover exclusion output includes destination');

mkdir 'Image Duplicate Cover' or die "failed to create fixture dir 'Image Duplicate Cover': $!";
copy_single_audio_fixture('mp3', File::Spec->catfile('Image Duplicate Cover', 'track01.mp3'));
write_file(File::Spec->catfile('Image Duplicate Cover', 'cover.jpg'), 'same-image-content');
write_file(File::Spec->catfile('Image Duplicate Cover', 'poster.jpg'), 'same-image-content');
my ($exit_cover_duplicate, $out_cover_duplicate, $err_cover_duplicate) = run_cmd('perl', $script, 'Image Duplicate Cover', '8', 'Cover Duplicate');
is($exit_cover_duplicate, 0, 'directory source with duplicate cover candidate succeeds');
ok(-d 'Vol. 8 - Cover Duplicate', 'volume directory for duplicate cover test is created');
ok(-f File::Spec->catfile('Vol. 8 - Cover Duplicate', 'cover.jpg'), 'cover.jpg exists for duplicate cover test');
is(read_file(File::Spec->catfile('Vol. 8 - Cover Duplicate', 'cover.jpg')), 'same-image-content', 'cover.jpg remains unchanged for duplicate cover test');
ok(!-f File::Spec->catfile('Vol. 8 - Cover Duplicate', 'cover-orig.jpg'), 'cover-orig.jpg is not created when it would be a duplicate');
is($err_cover_duplicate, '', 'duplicate cover test does not write stderr');
like($out_cover_duplicate, qr/^Moved: Image Duplicate Cover -> Vol\. 8 - Cover Duplicate$/m, 'duplicate cover output includes destination');

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

sub tone_title {
    my ($path) = @_;
    return tone_meta($path, '$.meta.title');
}

sub set_tone_title {
    my ($path, $title) = @_;

    my ($tag_exit, $tag_out, $tag_err) = run_cmd('tone', 'tag', '--meta-title', $title, $path);
    my $tag_combined = lc("$tag_out\n$tag_err");
    if ($tag_combined =~ /\b(error|failed|panic|exception)\b/) {
        die "tone tag reported an error for '$path': $tag_out$tag_err";
    }

    my $tagged_title = tone_title($path);
    if ($tagged_title ne $title) {
        die "tone title verification failed for '$path': expected '$title', got '$tagged_title'";
    }
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
    my $part = tone_meta($path, '$.meta.additionalFields.part');
    return $part if $part ne '';
    return tone_meta($path, '$.meta.part');
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
