# F2 - Command-Line Batch Renaming Cheatsheet

**F2** is a cross-platform command-line tool for batch renaming files and directories **quickly** and **safely**. Written in Go!

## Table of Contents

- [Quick Start](#quick-start)
- [Installation](#installation)
- [Basic Usage](#basic-usage)
- [Core Flags](#core-flags)
- [Advanced Options](#advanced-options)
- [Variables](#variables)
- [Sorting](#sorting)
- [Conflict Resolution](#conflict-resolution)
- [CSV Renaming](#csv-renaming)
- [Pair Renaming](#pair-renaming)
- [Safety Features](#safety-features)
- [Examples](#examples)
- [Environment Variables](#environment-variables)

---

## Quick Start

```bash
# Dry run (default) - preview changes without applying
f2 -f 'jpeg' -r 'jpg'

# Execute the renaming operation
f2 -f 'jpeg' -r 'jpg' -x

# Undo last rename operation
f2 -u
```

---

## Installation

### Go Installation (requires Go 1.23+)
```bash
go install github.com/ayoisaiah/f2/v2/cmd/f2@latest
```

### Other Methods
- Download pre-compiled binaries from [releases page](https://github.com/ayoisaiah/f2/releases)
- See full installation guide at https://f2.freshman.tech/guide/getting-started.html

---

## Basic Usage

```
f2 FLAGS [OPTIONS] [PATHS TO FILES AND DIRECTORIES...]
command | f2 FLAGS [OPTIONS]
```

### Positional Arguments
Optionally provide one or more files and directories to search for matches.
- If omitted, it searches the current directory alone
- Directories are not searched recursively unless `--recursive/-R` is used

---

## Core Flags

| Flag | Short | Description |
|------|-------|-------------|
| `--find` | `-f` | Regular expression pattern for matching files/directories |
| `--replace` | `-r` | Replacement string (supports variables) |
| `--exec` | `-x` | Execute the renaming operation |
| `--undo` | `-u` | Undo last renaming operation |
| `--string-mode` | `-s` | Treat find pattern as literal string |
| `--ignore-case` | `-i` | Ignore case when searching |
| `--ignore-ext` | `-e` | Ignore file extension when searching |
| `--recursive` | `-R` | Search directories recursively |
| `--dry-run` | *(default)* | Preview changes without applying |

### Find & Replace Examples

```bash
# Replace all .jpeg with .jpg
f2 -f 'jpeg' -r 'jpg'

# Replace using regex capture groups
f2 -f 'IMG_(\d{4})' -r 'Photo_${1}'

# Literal string mode (no regex)
f2 -s -f '[test]' -r 'test'

# Case insensitive
f2 -i -f 'readme' -r 'README'
```

---

## Advanced Options

### File Filtering

| Flag | Short | Description |
|------|-------|-------------|
| `--include` | `-I` | Only include files matching pattern |
| `--exclude` | `-E` | Exclude files matching pattern |
| `--exclude-dir` | | Exclude directories matching pattern |
| `--include-dir` | `-d` | Include directories in renaming |
| `--only-dir` | `-D` | Rename only directories |
| `--hidden` | `-H` | Include hidden files/directories |
| `--max-depth` | `-m` | Limit recursive search depth |

```bash
# Only process JSON and YAML files
f2 -I 'json' -I 'yml' -f 'old' -r 'new'

# Exclude test files
f2 -E 'test|spec' -f 'old' -r 'new'

# Process hidden files
f2 -H -f '^\.' -r 'backup_'
```

### Replacement Control

| Flag | Short | Description |
|------|-------|-------------|
| `--replace-limit` | `-l` | Limit replacements per filename |
| `--replace-range` | `-L` | Replace specific match range |
| `--clean` | `-c` | Clean empty directories after rename |

```bash
# Replace only first occurrence
f2 -f 'the' -r 'a' -l 1

# Replace 2nd and 3rd matches only
f2 -f 'word' -r 'replacement' -L '2..3'

# Replace single match by index
f2 -f 'item' -r 'new' -L '2'
```

### Datetime & Metadata

| Flag | Description |
|------|-------------|
| `--dt` | Set default datetime variable path |
| `--timezone` | Set timezone for datetime formatting |
| `--exiftool-opts` | Customize ExifTool output |

```bash
# Use shortened datetime variable syntax
f2 -r '{YYYY}-{MM}-{DD}' --dt 'xt.DateTimeOriginal'

# Set timezone for timestamps
f2 -f '*.dng' -r '{xt.DateTimeOriginal.dt}' --timezone 'Asia/Tokyo'

# Custom date format from ExifTool
f2 -r '{xt.GPSDateTime}' --exiftool-opts '--dateFormat %Y-%m-%d'
```

---

## Variables

F2 supports powerful variables for dynamic renaming:

### Built-in Variables

| Variable | Description |
|----------|-------------|
| `{ext}` | File extension |
| `{name}` | Filename without extension |
| `{dir}` | Directory name |
| `{index}` | Auto-incrementing index |
| `{parentDir}` | Parent directory name |

### Capture Variables

```bash
# Using regex capture groups
f2 -f '(\w+)_(\d+)' -r '${2}_${1}'

# Photo_001.jpg -> 001_Photo.jpg
```

### EXIF/Image Metadata (via ExifTool)

```bash
# Use photo date in filename
f2 -f '*.jpg' -r '{xt.DateTimeOriginal.YYYY}{xt.DateTimeOriginal.MM}{xt.DateTimeOriginal.DD}_{name}{ext}'

# GPS coordinates
f2 -f '*.jpg' -r '{xt.GPSLatitude}_{xt.GPSLongitude}_{name}{ext}'
```

### ID3/Audio Metadata

```bash
# Organize music files
f2 -f '*.mp3' -r '{id3.artist}/{id3.album}/${1}_{id3.title}{ext}'
```

### Variable Syntax

- `{variable}` - Simple variable
- `{variable.path}` - Nested property
- `{${captureGroup}}` - Regex capture reference
- `{xt.PropertyName}` - ExifTool variable
- `{id3.PropertyName}` - ID3 tag variable

---

## Sorting

Sort files before renaming using `--sort` (ascending) or `--sortr` (descending):

| Sort Type | Description |
|-----------|-------------|
| `default` | Lexicographical order |
| `natural` | Natural order (file1, file2, file10) |
| `size` | File size |
| `mtime` | Last modified time |
| `btime` | Creation time |
| `atime` | Last access time |
| `ctime` | Metadata change time |
| `time_var` | Sort by time variable |
| `int_var` | Sort by integer variable |
| `string_var` | Sort by string variable |

```bash
# Sort by modification date
f2 -f '*.jpg' -r 'Photo_{%03d}' --sort 'mtime'

# Sort naturally before numbering
f2 -f 'image*' -r 'img_{%03d}' --sort 'natural'

# Sort by EXIF date
f2 -f '*.jpg' -r '{%03d}' --sort 'time_var' --sort-var 'xt.DateTimeOriginal'

# Reverse sort by size
f2 -f '*.mp3' -r 'track_{%03d}' --sortr 'size'

# Sort within each directory separately
f2 -f '*.jpg' -r '{%03d}' --sort 'mtime' --sort-per-dir

# Reset index per directory
f2 -R -f '*.jpg' -r 'Photo_{%03d}' --reset-index-per-dir
```

---

## Conflict Resolution

F2 detects and can automatically resolve naming conflicts:

| Flag | Description |
|------|-------------|
| `--fix-conflicts` | `-F` | Auto-fix conflicts |
| `--fix-conflicts-pattern` | Custom conflict suffix pattern |
| `--allow-overwrites` | Allow overwriting existing files |

```bash
# Auto-fix conflicts with default pattern (1), (2), etc.
f2 -f 'old' -r 'new' -F

# Custom conflict pattern
f2 -f 'old' -r 'new' -F --fix-conflicts-pattern '_%02d'
# Results: new_01, new_02, etc.

# WARNING: Allow overwriting (use with caution!)
f2 -f 'old' -r 'new' --allow-overwrites -x
```

---

## CSV Renaming

Rename files using a CSV spreadsheet:

```bash
# Basic CSV renaming
f2 --csv renames.csv

# CSV format:
# original_filename,new_filename
# old_name.txt,new_name.txt
# image.jpg,photo_2024.jpg
```

### CSV Example

```csv
original_filename,new_filename
DSC0001.JPG,Vacation_Day1.jpg
DSC0002.JPG,Vacation_Day2.jpg
IMG_1234.png,Screenshot_Homepage.png
```

```bash
f2 --csv renames.csv -x
```

---

## Pair Renaming

Rename files with same name but different extensions together:

| Flag | Description |
|------|-------------|
| `--pair` | `-p` | Enable pair renaming |
| `--pair-order` | Order files by extension |

```bash
# Rename RAW+JPEG pairs
# Before: DSC08533.ARW DSC08533.JPG DSC08534.ARW DSC08534.JPG
f2 -r "Photo_{%03d}" --pair -x
# After: Photo_001.ARW Photo_001.JPG Photo_002.ARW Photo_002.JPG

# Specify which extension takes priority for metadata
f2 -r "{xt.DateTimeOriginal.YYYYMM%d}_{name}{ext}" --pair --pair-order 'arw,jpg' -x
```

---

## Safety Features

### Dry Run by Default
F2 runs in dry-run mode by default. Changes are previewed but not applied until you use `-x/--exec`.

```bash
# Preview only (safe)
f2 -f 'old' -r 'new'

# Apply changes
f2 -f 'old' -r 'new' -x
```

### Undo Functionality
Mistakes can be easily undone:

```bash
# Undo last renaming operation
f2 -u

# Undo and see what would be reverted
f2 -u -x
```

### Conflict Detection
F2 validates all operations before execution:
- Detects target filename conflicts
- Identifies forbidden characters
- Checks filename length limits
- Prevents accidental overwrites

### Quiet Mode
```bash
# Silent mode (only errors shown)
f2 -q -f 'old' -r 'new'
```

### JSON Output
```bash
# Machine-readable output
f2 --json -f 'old' -r 'new'
```

---

## Examples

### Basic Renaming

```bash
# Change file extension
f2 -f '\.jpeg$' -r '.jpg' -x

# Add prefix to all files
f2 -f '(.*)' -r 'backup_$1' -x

# Remove spaces from filenames
f2 -f ' ' -r '_' -x

# Convert to lowercase (using shell)
for f in *; do mv "$f" "$(echo $f | tr '[:upper:]' '[:lower:]')"; done
f2 -f '.*' -r '{name|lower}{ext}' -x
```

### Photo Organization

```bash
# Date-based photo naming
f2 -f '*.jpg' -r '{xt.DateTimeOriginal.YYYY}-{xt.DateTimeOriginal.MM}-{xt.DateTimeOriginal.DD}_{%03d}{ext}' --sort 'time_var' --sort-var 'xt.DateTimeOriginal' -x

# Organize by photographer
f2 -f '*.dng' -r '{xt.Creator}/{xt.DateTimeOriginal.YYYY}/{name}{ext}' -x
```

### Music Library

```bash
# Organize MP3s by artist/album
f2 -f '*.mp3' -r '{id3.artist}/{id3.album}/{id3.trackNumber} - {id3.title}{ext}' -x

# Fix inconsistent track numbering
f2 -f '*.mp3' -r '{id3.artist} - {id3.album} - {%02d} - {id3.title}{ext}' --sort 'natural' -x
```

### Document Management

```bash
# Standardize document naming
f2 -f 'report[_-]?\d{4}' -r 'Report_2024' -i -x

# Add date stamp to files
f2 -f '(.+)\.pdf' -r '$1_20240101.pdf' -x
```

### Recursive Operations

```bash
# Rename throughout directory tree
f2 -R -f 'temp' -r 'permanent' -x

# Limit recursion depth
f2 -R -m 2 -f 'old' -r 'new' -x

# Only rename directories recursively
f2 -R -D -f 'draft' -r 'final' -x
```

---

## Environment Variables

| Variable | Description |
|----------|-------------|
| `F2_DEFAULT_OPTS` | Set default options |
| `F2_NO_COLOR` | Disable colored output |
| `NO_COLOR` | Disable colored output (standard) |

```bash
# Set permanent defaults
export F2_DEFAULT_OPTS="--exec --ignore-ext --recursive"

# Disable colors
export F2_NO_COLOR=1
export NO_COLOR=1
```

### Example Configuration

Add to your `~/.bashrc` or `~/.zshrc`:

```bash
# Always show preview, enable recursive by default
export F2_DEFAULT_OPTS="--recursive --verbose"

# Safe defaults: always dry-run, highlight differences
export F2_DEFAULT_OPTS="--ignore-case --verbose"
```

---

## Common Patterns

### Sequential Numbering
```bash
f2 -f '.*' -r 'Image_{%03d}{ext}' --sort 'natural' -x
# Image_001.jpg, Image_002.jpg, ...
```

### Date Prefix
```bash
f2 -f '(.+)' -r '20240101_$1' -x
# 20240101_document.pdf
```

### Remove Special Characters
```bash
f2 -f '[^a-zA-Z0-9._-]' -r '_' -x
# my file (copy).txt -> my_file__copy_.txt
```

### Swap Words
```bash
f2 -f '(\w+)_(\w+)' -r '${2}_${1}' -x
# first_last.txt -> last_first.txt
```

### Increment Numbers
```bash
f2 -f 'v(\d+)' -r 'v{$1+1}' -x
# v1.txt -> v2.txt (requires expression support)
```

---

## Troubleshooting

### No Matches Found
```bash
# Check if pattern is correct
f2 -f 'pattern'  # Dry run shows what would match

# Try case-insensitive
f2 -i -f 'Pattern'

# Include hidden files
f2 -H -f '\.' 
```

### Conflicts Detected
```bash
# View conflicts in dry-run
f2 -f 'old' -r 'new'

# Auto-resolve
f2 -f 'old' -r 'new' -F

# Custom resolution pattern
f2 -f 'old' -r 'new' -F --fix-conflicts-pattern '_v%d'
```

### Permission Errors
```bash
# Ensure you have write permissions
ls -la /path/to/files

# Run with appropriate permissions
sudo f2 -f 'old' -r 'new' -x  # Use cautiously
```

---

## Resources

- **Official Documentation**: https://f2.freshman.tech
- **GitHub Repository**: https://github.com/ayoisaiah/f2
- **Tutorial**: https://f2.freshman.tech/guide/tutorial.html
- **Real-world Examples**: https://f2.freshman.tech/guide/organizing-image-library.html
- **Changelog**: https://f2.freshman.tech/reference/changelog.html

---

*Generated from F2 v2 source code • MIT License • Ayooluwa Isaiah*
