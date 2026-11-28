# Speed Run for the 48K ZX Spectrum

## Single-load requirement

One initial tape load must support all 15 rounds, every route fork, all five endings and subsequent games. The complete route and artwork archive stays in the Spectrum's 49,152 bytes of RAM. At a checkpoint the engine can pause the race clock and expand the chosen round from RAM. A new game must work with the cassette disconnected.

## Implemented build

`make zx48` builds `build/zx48/speedrun48.tap`, a standard-speed tape taking about 3 minutes 55 seconds. Type `LOAD ""` on a 48K Spectrum. The BASIC program loads the upper image and the ROM tape routine reads the final resident block. The game runs from RAM after that point. The build also emits a snapshot and `build/zx48/memory_map.txt`.

All fifteen rounds retain the 128K edition's road records, object placements, tunnels, fork destinations, palettes and panorama artwork. The archive also holds five regional cloud panels and the 128K title picture. A round keeps one 512-byte panorama and scrolls it in eight-pixel steps. The regional scenery uses fewer near-distance sizes and horizontal offsets. Column-wise packing and shorter sprite directories help fit the new title and audio in RAM.

The 48K version targets one racing update every four refreshes on a single display. It projects the next set of sprites into a second command list and replaces them one character row at a time. The three road rows just below the skyline account for most temporary pixels during raster updates. The renderer can compose each of these sprite-bearing rows in a 288-byte scratch area in the lookup table pages, then copy the completed bitmap and inks to the display. Heavy frames give priority to the top road row and use the incremental writer further down. Traffic and scenery use their own inks over plain road and grass cells. Kerbs and the skyline keep their terrain inks. The car's opaque block is protected from road and sprite writes. Fork edges use four raster lines per step.

The title unpacks the same picture as the 128K build and shows the session's best score. ENTER opens the options for keyboard, Sinclair and Cursor presets, custom keys, sound and difficulty. The beeper plays a monophonic arrangement of the 128K title tune. During racing it sounds during the wait for the next frame and yields as soon as the 50 Hz clock reaches the frame deadline. The full sound setting includes starting lights, bumps, crashes and the last ten timer beeps. Engine mode keeps the speed-sensitive engine alone. The five destination results retain stage times and the finishing bonus.

### Verification

- The tape booted from `LOAD ""` using the 48K ROM in zxsim. The test then disconnected the tape, started a game, paused and resumed it, played to time-up and started a new game.
- The title bitmap and attributes match the 128K artwork above the live text panel. Emulator checks cover options, custom keys, title music and the speaker pulses for the changing engine pitch, starting lights, a crash and the low timer.
- All fifteen round caches matched the generated tracks, palettes, panoramas, clouds and scenery. Eight scripted runs exercised all twenty fork transitions and drew all five destination result screens.
- The stationary fork held the same image across all 75 sampled refreshes. The player car's opaque rows matched a complete sprite in 878 of 880 sampled refreshes during a steering test.
- A newly exposed kerb can look like a solid red tile until its bitmap is drawn. The 48K renderer now publishes its colour after the bitmap and uses the road's paper while clearing an old kerb cell that becomes pavement. The Country-stage regression detected no detached red kerb cells in 624 sampled refreshes. The top three road rows showed 1,752 transient pixels during a separate 1,450-refresh run, down from 12,843 before strip buffering.
- Tunnel mouths, exits and goal gantries are projected before the road draws. Each road row combines the portal and terrain colours before publishing them. Sky rows below the mouth are restored if it recedes behind a crest. A 400-refresh Alpine replay measured 2,504 transient road pixels, compared with 2,194 on the previous silent build and 163,145 before the tunnel fix. The display can still be scanned during a strip copy or while other screen areas update.
- Eight Normal runs averaged 12.484–12.499 fps with beeper audio enabled. Of 24,477 racing intervals, 53 took a fifth refresh. Checkpoint gaps were 14–18 refreshes including the normal racing interval. Peak observed stack use across these runs was 26 of 128 reserved bytes. Physical 48K timing, display behaviour and sound remain unverified.

`make test-zx48 ZX48_ROM=/path/to/48.rom` repeats these checks. Without a ROM path it runs the round and route tests from the snapshot.

## Measurements from the 128K Spectrum build

| Content | Bytes in current packs | Bytes compressed per pack, summed |
|---|---:|---:|
| Five theme packs, including scenery and tunes | 39,423 | 18,709 |
| Fifteen tracks and their object placements | 7,828 | 7,727 |
| Fifteen sets of round artwork and palettes | 7,861 | 6,697 |
| **Total** | **55,112** | **33,133** |

These figures use the Spectrum release snapshot and symbols with the [project compressor](../tools/zpack.py). Storing the 33,133-byte archive and the 6,912-byte display leaves 9,107 bytes for everything else, including the game engine and expanded assets. Tape compression saves load time. Only data that stays compressed during play saves working RAM.

The [sprite generator](../tools/make_scenery.py) emits roadside objects at multiple sizes and horizontal offsets. A separate experiment retained one unshifted bitmap for each distinct object at each existing drawing size and removed the padding used for shifting. The 146 resulting bitmaps totalled 7,059 bytes, or **3,804 bytes** compressed as one stream. This covers themed roadside objects and signs. Sprite directories, colours, the player's car, traffic, and the active cache require separate space. Independently decodable groups also need their own size measurement.

## Original implementation plan

1. **Prove the memory layout with all rounds present.** Add a separate `ZX48` build and standard-speed `.tap`. Keep the 50 Hz clock and remove AY playback, tune data and engine effects. Reuse the existing Spectrum driving logic and artwork. Produce a memory map for racing, checkpoint preparation and restart. Include the screen, resident code and tables, archive, active caches, decoder scratch, interrupt data and stack. Add assembler checks for overlaps at peak use.
2. **Build the active scenery cache at checkpoints.** Store shared signs once and group the unshifted sprites so the engine can decode the selected theme directly from RAM. Generate the horizontal shifts before the race clock resumes. Compare generated sprites at every size and offset with the 128K originals. Measure both the final archive and the largest expanded cache before considering any reduction in drawing sizes.
3. **Keep the exact tracks and all forks.** Encode object distances relative to the preceding object, give frequent types and lateral positions short codes, and encode repeated road segments compactly. Expand the selected round into the existing 608-byte track cache. Compare all 15 decoded tracks with the [stage generator's output](../tools/make_stages.py), including distances, bends, hills, placements, tunnels and fork destinations.
4. **Budget the round artwork and front end.** Retain each round's palette, horizon identity and signature landmarks. Measure shared regional panoramas with per-round additions and reusable cloud shapes. Prioritise in-race scenery over full-screen ending pictures. Use a compact title and results screen while retaining all five destination outcomes.
5. **Measure the single-screen renderer.** Draw to the display at `$4000`, keep one set of drawing state and schedule updates to limit visible tearing. Benchmark hills, dense traffic, overlapping roadside objects, tunnel portals and forks. Target 12.5 fps and record missed four-refresh deadlines as well as average fps. Consider short beeper cues after measuring the silent build.

## First milestone and acceptance checks

Boot the prototype from one tape on an emulated 48K Spectrum, then disconnect the virtual tape. With all round data resident, use a test selector to enter each of the 15 rounds. Record the lowest free RAM during play and during a checkpoint, the largest theme cache, and the slowest preparation time. Verify that resets between rounds preserve the archive.

For the playable build, drive both choices at every fork across multiple runs, reach all five endings, and restart from the title with the tape still disconnected. Check that checkpoint preparation preserves score and remaining race time. Repeat the frame-pacing and visual checks on a physical 48K Spectrum when available.
