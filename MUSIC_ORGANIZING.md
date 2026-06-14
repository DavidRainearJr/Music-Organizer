# Music Folder Organizer

This folder includes `organize-music.ps1`, a PowerShell script for sorting album folders into artist folders.

The script is menu-first by default. When you run it normally, it asks whether to organize the library or show a dry run, then keeps the window open so you can inspect the results.

## Goal

Turn folders like this:

```text
Music/
  Artist One 1984 - First Album/
  Artist Two 1990 - Second Album/
  Artist Three 2001 - Third Album/
```

Into this:

```text
Music/
  Artist One/
    First Album/
  Artist Two/
    Second Album/
  Artist Three/
    Third Album/
```

## Naming Rule

The script recognizes album folders named like this:

```text
Artist Name YYYY - Album Title
```

Examples:

```text
Artist One 1982 - Sample Album
Artist Two 1996 - Another Album
Artist Three 2003 - Final Album
```

The artist folder comes from the text before the year.

The album folder comes from the text after `YYYY -`.

## Random Wrapper Folders

The script also handles random parent folders when they contain one recognizable album folder.

Example:

```text
Music/
  RandomDownloadFolder/
    Artist One 1982 - Sample Album/
      01. Opening Track.mp3
```

Becomes:

```text
Music/
  Artist One/
    Sample Album/
      01. Opening Track.mp3
```

The random wrapper name does not matter. The inner folder name must match `Artist YYYY - Album Title`.

## Redundant Parent Folders

The script treats a folder as a redundant wrapper only when:

- It contains exactly one child folder.
- That child folder is named like `Artist YYYY - Album Title`.
- The wrapper does not contain useful loose files of its own.

After moving the inner album folder, the script deletes the wrapper only if no useful content remains.

Ignored wrapper-only files are:

```text
.DS_Store
desktop.ini
Thumbs.db
```

## What It Will Not Guess

The script intentionally skips ambiguous folders.

It will not guess from loose MP3 files inside a random folder like this:

```text
Music/
  RandomFolderName/
    01. Song.mp3
    02. Song.mp3
```

It will also skip a wrapper if the inner folder is not named like `Artist YYYY - Album Title`.

This is intentional so it does not move music into the wrong artist or album folder.

## Right-Click Use

For easiest use, put `organize-music.ps1` directly inside the music folder you want to organize.

Then right-click `organize-music.ps1` and choose **Run with PowerShell**.

The script will organize the folder it is sitting in. It will not use some random PowerShell starting folder.

It will ask what you want to do first:

```text
Choose an option:
1 - Organize library
2 - Dry run
```

Use `1` to organize the library immediately. The script still runs safety checks before moving anything.

Use `2` to inspect the dry run first.

After a dry run, it asks:

```text
Choose an option:
1 - Apply these changes
2 - Exit without changes
```

Use `1` after the dry-run planned moves look right.

Use `2` to close without changing anything.

The window pauses before closing so you can read the output.

## Terminal Dry Run

From this folder, run:

```powershell
pwsh -ExecutionPolicy Bypass -File .\organize-music.ps1 -Path "C:\Path\To\Music" -NoPrompt
```

Or, if PowerShell is already open in the music folder:

```powershell
.\organize-music.ps1 -NoPrompt
```

The terminal dry run prints planned moves and exits without changing anything.

If you omit `-NoPrompt`, the script uses the same review menu as the right-click flow.

## Apply Changes

After checking the dry run, run:

```powershell
pwsh -ExecutionPolicy Bypass -File .\organize-music.ps1 -Path "C:\Path\To\Music" -Apply
```

Or, from inside the music folder:

```powershell
.\organize-music.ps1 -Apply
```

The `-Apply` option skips the review menu and applies immediately after preflight checks pass.

## Keep Wrapper Folders

By default, empty redundant wrapper folders are removed in apply mode.

To move the albums but keep wrapper folders, run:

```powershell
.\organize-music.ps1 -Apply -KeepWrappers
```

## Safety Rules

The script uses these safety checks:

- Menu-first mode is the default.
- When run without switches, the script asks whether to organize the library or show a dry run.
- The dry-run path asks again before applying changes.
- By default, the script organizes the folder it is located in.
- Existing destination folders are never overwritten.
- If two source folders would move to the same destination, the script stops before moving anything.
- If an artist path already exists as a file instead of a folder, the script stops.
- Wrapper folders are deleted only after the album folder was moved.
- Ambiguous folders are reported instead of guessed.

## Generic Examples

These are examples of cases this script is meant to handle:

```text
Artist One 1984 - Album Title_/Artist One 1984 - Album Title -> Artist One/Album Title
RandomDownloadFolder/Artist Two 1982 - Another Album -> Artist Two/Another Album
Artist Three 1986 - Third Album/ Artist Three 1986 - Third Album -> Artist Three/Third Album
```

## If You Want AI To Do It Manually

If the script reports ambiguous folders, ask an AI assistant to inspect those folders and follow these rules:

```text
Please organize this music folder.
Create artist folders when needed.
Move album folders named "Artist YYYY - Album" into "Artist/Album".
Remove the artist and year from the album folder name.
If a random parent folder contains exactly one recognizable album folder, move the inner album folder and delete the empty parent.
Do not delete any folder that still contains useful files.
Do not overwrite existing destinations.
Show a dry-run style plan before applying changes if anything is ambiguous.
```
