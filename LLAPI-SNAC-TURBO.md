# Neo Geo LLAPI + SNAC Turbo

This MiSTer build combines LLAPI 1.0.0, four selectable SNAC modes and optional cartridge CPU acceleration. It is based on MiSTer-devel NeoGeo_MiSTer revision `ffaab14`.

## CPU Turbo

Cartridge games in AES and MVS modes start at the original 12 MHz. Set **CPU Turbo** to **On (24 MHz)** and select **Reset & apply** to run the 68000 at 24 MHz. Set it back to **Off** and apply another reset to return to 12 MHz. Neo Geo CD runs at 12 MHz in either case.

- The video controller receives correctly spaced VRAM read and write strobes in Turbo mode. The CPU waits while the video port is recovering. The intervals follow the native 68000 timing described in the [SNK hardware manual](https://www.neogeodev.org/NG.pdf).
- The SDRAM arbiter prioritizes pending sprite and fixed-layer reads over CPU ROM reads in Turbo mode. An owed refresh remains pending across a busy slot, and reset clears the previous ROM acknowledgement before the first new fetch.

## USER I/O

| Menu option | Supported controller setup |
| --- | --- |
| LLAPI 2P (default) | BlisSTer or GamerPRO, up to 2 players, with Immediate Repoll |
| SNAC DB9 (MD) | Mega Drive 3-button or 6-button controller, 1 player, with MiSTer Genesis SNAC wiring |
| SNAC DB15 | Neo Geo through a Villena-compatible serial splitter, up to 2 players |
| SNAC SNES | Up to 2 players with a dual-port SNES SNAC adapter |
| SNAC Saturn | Digital Saturn controller, 1 player |

The core releases the USER I/O pins before switching readers. In SNAC modes, USB inputs remain available.

### SNAC autofire

Hold one Neo Geo action button (A, B, C or D). Keep holding it while pressing and releasing Start three times. The third release toggles autofire for that button. Hold it to fire and release it to stop. Repeat the gesture to return the button to manual fire. On a SNES pad, physical B maps to Neo Geo A.

Each player programs their own buttons. The pulse lasts two video frames followed by two frames off (about 15 shots per second at 60 Hz). Opening the MiSTer menu preserves the settings. Resetting the game or changing USER I/O clears them. A normal Start press goes straight to the game. Holding one action before pressing Start reserves that press for programming. The LLAPI adapter handles its own turbo gesture. [Bliss-Box controller manual](https://bliss-box.com/pages/manual_4pgp)

## Current Update All build

In **SNAC+LLAPI Enhanced → Console**, select `NeoGeo_Turbo_20261124.rbf`. On the first menu page, **CPU Turbo** sits between **Video Mode** and **USER I/O**. [Update All publication](https://github.com/MiSTer-LLAPI/LLAPI_folder_MiSTer/actions/runs/45491957932)

Quartus Prime Lite 17.0.2 Build 602 passed every timing check. The minimum setup margin is +0.431 ns on HDMI and the minimum hold margin is +0.246 ns. The 96 MHz core clock has +0.486 ns of setup margin. The controller selection is registered on the 48 MHz clock. The build tests covered input selection and the SNAC Start gesture. [Source revision](https://github.com/MiSTer-LLAPI/NeoGeo_MiSTer/tree/1b7f982f287e4e81174219f5db31e65962f32715) · [Build and reports](https://github.com/MiSTer-LLAPI/NeoGeo_MiSTer/actions/runs/45488778503)

The distributed file has SHA-256 `0fd8dfdc752c8e50ec9f5978bafb404782ba4f767dfd4d983eb13b598dcfbdcf`.

## Hardware-tested build before SNAC autofire

- Local filename `NeoGeo_Turbo_20261124.rbf`. [Exact source revision](https://github.com/MiSTer-LLAPI/NeoGeo_MiSTer/tree/74a29693a90114bb0615c22c81ea31251de1565d)
- Quartus Prime Lite 17.0.2 Build 602 passed timing with +0.052 ns minimum setup and +0.246 ns minimum hold margin. [Build and reports](https://github.com/MiSTer-LLAPI/NeoGeo_MiSTer/actions/runs/45465605022)
- Simulations covered VRAM accesses, SDRAM priority and refresh, the four SNAC readers, and exclusive USER I/O selection. Ricardo reported that Shock Troopers and Metal Slug run well on MiSTer at 24 MHz.
- To compare slowdown and graphics, play the same scene in the original Metal Slug 2 (`mslug2`) at 12 MHz and 24 MHz. Check sprites and text as well as responsiveness.
