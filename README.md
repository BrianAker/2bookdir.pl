# 2bookdir.pl

`2bookdir.pl` is a small Perl command-line utility that creates a target
directory and moves a book file into it.

## Usage

```bash
2bookdir.pl [--help] [--json] [--as-is] [--reverse] book_file [part-number] [book title]
```

### Arguments

- `book_file` (required): Path to the source book file or directory.
- `--json` (optional): Output a JSON object with `response` (`success` or
  `failure`) and `meta` (`title`, `volume`, `year`).
- `--as-is` (optional): Disable no-separator source-name inference
  (for example, `02 Title.mp3`).
- `--reverse` (optional): For supported dash-split inference formats, swap the
  first and third string before assigning `author` and `title`.
- `part-number` (optional): Positive numeric value (for example: `2` or
  `2.1`). If provided, directory name is prefixed as `Vol. N - ...`.
  If `part-number` is a 4-digit year, it is treated as PublishingDate and
  the directory prefix becomes `YYYY - ...`.
- `book title` (optional): Title to use for the directory name. If omitted,
  the source filename (without extension) is used.

## Examples

```bash
# Use filename as directory name
2bookdir.pl book.epub

# Use part number + explicit title
2bookdir.pl chapter3.pdf 3 "My Book"
```

If exactly one `.mp3`, `.mka`, or `.m4b` file is found in `book_file`, that
audio file is renamed to `book title` while preserving its original extension.
In that single-audio case, the file's album metadata is also updated to
`book title` via `tone`. The volume number is also written via `tone` as:
- `movement` when the volume number is an integer (for example `3`)
- `part` when the volume number is non-integer (for example `2.1`)
  and in non-integer cases `movement` is also set to the whole-number prefix
  (for example `2.1` -> `movement=2`)
PublishingDate years write `--meta-publishing-date=YYYY-01-01` instead of
`movement`/`part`.
If more than one such audio file is found, filenames are not renamed.

When `part-number` is omitted, `book_file` names beginning with a number are
inferred as volume/title sources:
- `02 - Dog God.mp3` -> volume `2`, title `Dog God`
- `02 Fruppy Goop.mp3` -> volume `2`, title `Fruppy Goop` (unless `--as-is`)

For dash-split names (`A - B - C` and `YEAR - A - B - C`), inferred metadata
supports `author`, `series`, `title`, and optional `year`. In these cases:
- `author` is written with `tone --meta-artist`
- `series` is written with `tone --meta-movement-name`
- `year` is written as `--meta-publishing-date=YYYY-01-01`
For example, `2bookdir.pl "Frog God.m4b" 3 "My Dog"` produces:
`Vol. 3 - My Dog/My Dog.m4b`.

For directory sources, if one or more top-level `.jpg`/`.png` files exist
that are not named `cover.jpg` or `cover.png`, the largest is copied to
`cover.jpg` or `cover.png` (matching the selected file extension).

## Install

Install to default prefix (`/usr/local`):

```bash
make install
```

Install to a custom prefix:

```bash
make install PREFIX=/opt/local
```

You can also stage installs with `DESTDIR`:

```bash
make install PREFIX=/usr DESTDIR=/tmp/pkgroot
```

## Test

Run tests (uses `Test::More`):

```bash
make test
```

`make test`/`make check` will create reusable audio fixtures in
`.test-fixtures/` on first run using `ffmpeg`:
- a 2-hour WAV source file
- converted MP3 and M4B files used by tests

These fixture files are git-ignored and reused on subsequent runs.

## License

BSD 2-Clause. See `LICENSE`.
