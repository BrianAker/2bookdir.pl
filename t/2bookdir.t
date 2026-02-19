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
like($out_help, qr/^Usage: 2bookdir\.pl \[--help\] \[--version\] \[--json\] \[--as-is\] \[--reverse\] book_file \[part-number\] \[book title\]/m, 'help shows usage');
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
is(tone_meta(File::Spec->catfile('Vol. 2.1 - My Part', 'My Part.m4b'), '$.meta.movement'), '2', 'non-integer volume also writes movement using whole number');
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
ok(-f File::Spec->catfile('Vol. 3 - Asin Foo', 'Asin Foo.mp3'), 'checkpoint ASIN case renames audio file to title');
is($err_checkpoint_asin, '', 'checkpoint ASIN case does not write stderr');
like($out_checkpoint_asin, qr/^CHECKPOINT: 1: ASIN$/m, 'checkpoint ASIN case output includes ASIN checkpoint marker');
like($out_checkpoint_asin, qr/^CHECKPOINT: 1: YEAR$/m, 'checkpoint ASIN case output includes year checkpoint marker');
like($out_checkpoint_asin, qr/^CHECKPOINT: 2: VOLUME$/m, 'checkpoint ASIN case output includes volume checkpoint marker');
like($out_checkpoint_asin, qr/^Moved: 1993 - Volume 3 - Asin Foo \[B00TEST123\]\.mp3 -> Vol\. 3 - Asin Foo\/Asin Foo\.mp3$/m, 'checkpoint ASIN case output includes expected move line');
like($out_checkpoint_asin, qr/^Title: Asin Foo$/m, 'checkpoint ASIN case output includes title summary line');
like($out_checkpoint_asin, qr/^Volume: 3$/m, 'checkpoint ASIN case output includes volume summary line');
like($out_checkpoint_asin, qr/^Year: 1993$/m, 'checkpoint ASIN case output includes year summary line');
like($out_checkpoint_asin, qr/^ASIN: B00TEST123$/m, 'checkpoint ASIN case output includes ASIN summary line');

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
