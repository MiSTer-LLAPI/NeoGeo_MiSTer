# NeoGeo Turbo48

The experimental NeoGeo_Turbo48 core combines LLAPI 1.0.0, four selectable SNAC modes and optional cartridge CPU acceleration. It is based on MiSTer-devel NeoGeo_MiSTer revision `ffaab14`.

## CPU Turbo

Cartridge games start at 12 MHz in AES and MVS modes. Turn **CPU Turbo** on to reveal **CPU Speed**. Select **24 MHz** (the default turbo speed) or **48 MHz (Exp.)**, then choose **Reset & apply**. Turn **CPU Turbo** off and apply a reset to return to 12 MHz. Neo Geo CD and CDZ use 12 MHz in every case.

At 12 and 24 MHz the 68000 uses the original board clock and connects directly to the peripheral bus. The 48 MHz cartridge option selects a separate 68000 running on the existing 96 MHz clock. It exchanges reads and writes through a registered bridge. Reset holds the inactive processor. Games that wait on cartridge memory, video or sound can gain less than the change in CPU rate suggests.

- The video controller receives correctly spaced VRAM read and write strobes in Turbo mode. The CPU waits while the video port is recovering. The intervals follow the native 68000 timing described in the [SNK hardware manual](https://www.neogeodev.org/NG.pdf).
- The SDRAM arbiter prioritizes pending sprite and fixed-layer reads over CPU ROM reads in Turbo mode. An owed refresh remains pending across a busy slot, and reset clears the previous ROM acknowledgement before the first new fetch.

### Zed Blade

On MiSTer, Ricardo reported a startup problem and a missing player ship at 24 MHz. The game updates sprite positions by selecting a VRAM address and then writing data. In Turbo48, this sequence can issue the data write on the next bus cycle. The native video-controller simulation checks the stored bytes and the next write address, including the sprite addresses used by the game. The accelerated modes keep the recovery intervals for VRAM reads and consecutive data writes.

For the hardware test, use the same game, BIOS and video settings at each speed. Apply a reset, check that the game boots, start stage one, and check that the player ship appears and moves. Record startup and ship visibility separately at 12, 24 and 48 MHz Experimental.

### Blazing Star sound

On MiSTer, the same cartridge image lost both music and gunfire at 24 MHz. Both returned after resetting at 12 MHz. In simulation, the accelerated 68000 sent the startup command `$07` while the Z80 was still clearing its sound queue after command `$03`. The Z80 read `$07`, then erased it before the main loop could act on it.

In cartridge turbo mode, the core watches for the Z80 reading `$03` and starting its RAM clear. If `$07` arrives during that sequence, the core holds the write until the Z80 finishes enabling interrupts, with a bounded timeout. Tests using the original sound program and the measured turbo bus intervals confirmed that the Z80 consumed `$07` and then wrote to register `$27` on the YM2610. To check audible output, start the first mission, listen for music and fire the weapon at each CPU speed after **Reset & apply**.

On 25 November 2026, Ricardo retested Blazing Star on his MiSTer with experimental build `45588426313`. Music and gunfire both played at 24 MHz and at 48 MHz.

## USER I/O

| Menu option | Supported controller setup |
| --- | --- |
| LLAPI 2P (default) | BlisSTer or GamerPRO, up to 2 players, with Immediate Repoll |
| SNAC DB9 (MD) | Mega Drive 3-button or 6-button controller, 1 player, with MiSTer Genesis SNAC wiring |
| SNAC DB15 | Neo Geo through a Villena-compatible serial splitter, up to 2 players |
| SNAC SNES | Up to 2 players with a dual-port SNES SNAC adapter |
| SNAC Saturn | Digital Saturn controller, 1 player |

The core releases the USER I/O pins before switching readers. In SNAC modes, USB inputs remain available.

### Autofire

Open **Autofire** below **CPU Turbo**. P1 and P2 can each choose one Neo Geo button (A, B, C or D). Select **Hold** to repeat while pressing it, or **Toggle** to start and stop repetition on successive presses. **Off** gives normal button input. The menu applies to USB, LLAPI and SNAC game input.

**Normal** repeats for two video frames on and two off. **Slow** uses four on and four off, and **Fast** uses one on and one off. At 60 Hz these settings give 15, 7.5 and 30 presses per second respectively.

With SNAC, hold the chosen action and press and release **Start** three times. On the third release the menu selects **Hold** and that button for the player. A different button replaces the previous selection. Repeating the gesture on the active button selects **Off**. The player's speed is preserved. On a SNES pad, physical B maps to Neo Geo A.

Start alone goes straight to the game. Holding exactly one action before pressing Start reserves that press for the SNAC shortcut. In LLAPI mode the adapter handles its own shortcut in firmware. Its internal setting is independent of the core’s Autofire menu. [Bliss-Box controller manual](https://bliss-box.com/pages/manual_4pgp)

## Earlier NeoGeo_Turbo build (24 November)

In **SNAC+LLAPI Enhanced → Console**, select `NeoGeo_Turbo_20261124.rbf`. On the first menu page, **CPU Turbo** sits between **Video Mode** and **USER I/O**. [Update All publication](https://github.com/MiSTer-LLAPI/LLAPI_folder_MiSTer/actions/runs/45491957932)

Quartus Prime Lite 17.0.2 Build 602 passed every timing check. The minimum setup margin is +0.431 ns on HDMI and the minimum hold margin is +0.246 ns. The 96 MHz core clock has +0.486 ns of setup margin. The controller selection is registered on the 48 MHz clock. The build tests covered input selection and the SNAC Start gesture. [Source revision](https://github.com/MiSTer-LLAPI/NeoGeo_MiSTer/tree/1b7f982f287e4e81174219f5db31e65962f32715) · [Build and reports](https://github.com/MiSTer-LLAPI/NeoGeo_MiSTer/actions/runs/45488778503)

The distributed file has SHA-256 `0fd8dfdc752c8e50ec9f5978bafb404782ba4f767dfd4d983eb13b598dcfbdcf`.

## Hardware-tested build before SNAC autofire

- Local filename `NeoGeo_Turbo_20261124.rbf`. [Exact source revision](https://github.com/MiSTer-LLAPI/NeoGeo_MiSTer/tree/74a29693a90114bb0615c22c81ea31251de1565d)
- Quartus Prime Lite 17.0.2 Build 602 passed timing with +0.052 ns minimum setup and +0.246 ns minimum hold margin. [Build and reports](https://github.com/MiSTer-LLAPI/NeoGeo_MiSTer/actions/runs/45465605022)
- Simulations covered VRAM accesses, SDRAM priority and refresh, the four SNAC readers, and exclusive USER I/O selection. Ricardo reported that Shock Troopers and Metal Slug run well on MiSTer at 24 MHz.
- To compare slowdown and graphics, play the same scene in the original Metal Slug 2 (`mslug2`) at 12 MHz and 24 MHz. Check sprites and text as well as responsiveness.
