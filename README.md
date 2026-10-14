# KOA Reforged – data pack installer

Source of the optional data pack shipped with **KOA Reforged** (Kingdoms of Amalur: Re-Reckoning) on Nexus Mods
(`KOA_Reforged_DataPack_v1.4.0.zip`, and inside the all-in-one zip as `modding/KoarData/`).

There is **no compiled code** and nothing to build: the installer is a plain-text PowerShell script.
The files in this repository are byte-identical to the ones in the uploaded archive (hashes below).

## Files

| File | Purpose |
|---|---|
| `koar_data.ps1` | The installer (PowerShell 5.1, commented). Modes: `build`, `undo`, `status` |
| `1_status.bat` / `2_build.bat` / `3_undo.bat` | One-line launchers: `powershell -NoProfile -ExecutionPolicy Bypass -File koar_data.ps1 <mode>` |
| `data/koar_items.bin` | 165 item records (game data: clothing items for the Transmog module's outfits) |
| `data/koar_stacks.txt` | Plain text: stack-size changes (record id, offset, old value, new value, name) |
| `README_DATA_PACK.txt` | User instructions |

## What the script does

`build`:
1. Refuses to run while the game is running.
2. Identifies the installed `data\patch_0.pak` by SHA-256 and backs up the original to `modding\KoarData\patch_0.original.pak`.
3. Lists and unpacks it with the game's **official** tool `modding\pakfileunpacker.exe` (shipped with the game by its developers) into a temporary `work` folder.
4. Adds our records to three files from that pak (item records, item list, file index), refusing to continue if any of our item ids already exists, and writes two small `.bundle` files per item. Stack values are only changed where the old value matches.
5. Rebuilds the pak with the game's **official** `modding\pakfilebuilder.exe -c`.
6. Verifies that the new pak lists every original file plus ours, then installs it and deletes the `work` folder.

`undo` restores the backed-up original (only if the installed pak is the one we built). `status` only reads.

The script makes **no network access**, downloads nothing, writes only inside the game folder (`data\patch_0.pak`
and `modding\KoarData\`), and deletes nothing except its own temporary `work` folder. Every step is logged to
`modding\KoarData\koar_data_log.txt`.

`-ExecutionPolicy Bypass` in the launchers is only there so Windows runs this unsigned local script.

## SHA-256

```
14a5e5d08dce0134da9dc9aec9ad01592d2f38ddbd3be595bf9bb3b8ce2ed084  koar_data.ps1
3ae49f0b11215ea9d05b2263508d2a11378e9e6ea06e30a1e034786ce38fc0e9  1_status.bat
2c38e67c66b6772e94d7429f389aa150517e4cfff86441bdbf2deaf216dcf487  2_build.bat
d86e44f7a2bbac088aaca45be2996990bd4e324f312dbf035c981293c727f668  3_undo.bat
c0c2c7d1b9bd3aabec735387ac3b21540a4f5d2b5998b2105a0accfd60852dd7  data/koar_items.bin
e2d51edeb280f9563d148c0b2756aab493aaf33883aa83a9cbc8a6cf572b0940  data/koar_stacks.txt
c5b22f5b87b99be56a1a0151ba720e28c8835935278aac6c33ec30905472d9fa  README_DATA_PACK.txt
43b15fdbcc7b01087baef085f91f520e86616de515ad212dd1bf763bd4368265  KOA_Reforged_DataPack_v1.4.0.zip (the uploaded archive)
```

## Usage

Close the game, run `2_build.bat` (about 5 GB free space needed while it works). `3_undo.bat` restores the original.

Author: Nacho (KOA Reforged).
