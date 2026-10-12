# deadlock-vpn-loading-fix

This repo provides two fixes for Deadlock's _"stuck on loading screen"_ bug, which happens mostly because of VPN's and their split tunneling feature.

These two fixes are based around using the cheat command: `sv_cheats 1; restart`:

- **[F9 fix](#fix-1-press-f9-recommended):** adds a keyboard shortcut (`F9`) to execute the command by changing one line in a config file.
- **[Auto-fix script](#fix-2-automatic-optional) (optional):**  Starts Deadlock and presses `F9` for you when the hang happens automatically.

Neither fix modifies game files or touches the game's memory.

I looked into this problem because I was tired of copy-pasting the command or remembering it. 

These scripts are coded by AI.
If you don't trust the code of the script, I recommend to only use the shortcut. It is pretty small and easy to understand by just opening the file in the notepad.

> [!IMPORTANT]
> Read the script before running it, as you should with any script from the internet.

## Symptoms

- When the loading screen never finishes on start and on the start and end of a match.
- When opening the console (`F7`) and entering `sv_cheats 1; restart` gets you in.
- When the console shows this line over and over:

```
[Client] CL:  CCreateGameClientJob creating client connection to '127.0.0.1'
[SteamNetSockets] WSASendTo 127.0.0.1:27015 failed, returned -1, last error=0x2741 The requested address is not valid in its context.
```

If you see that error, these fixes apply to you.

## Why it happens

The hideout (main menu) is a small game lobby running as a local server. Deadlock connects to it over the network at `127.0.0.1:27015` (`localhost`).

Most VPN's split tunneling works by moving the network sockets of excluded apps onto the default network adapter. 
A socket moved that way cannot longer send it to `localhost` and so the connection fails. 

I myself use Mullvad on Win 11 and it's [driver documentation](https://github.com/mullvad/win-split-tunnel) lists this as a known limitation: *"if a UDP socket isn't explicitly bound to `127.0.0.1` before sending, it won't be able to talk to localhost."*

Deadlock tries to do this but fails. This results in the endless loading screen. The console command `restart` reloads the hideout in a way that gets past the hang, so the fix binds it to a key.

## Fix 1: press F9 (recommended)

1. Find your Deadlock folder: in Steam, right-click **Deadlock** → **Manage** → **Browse local files**.
2. Open `game\citadel\cfg\`.
3. Copy [`autoexec.cfg`](autoexec.cfg) from this repository into that folder.
   If an `autoexec.cfg` already exists, open it and add this line instead of replacing the file:
   ```
   bind "F9" "sv_cheats 1; restart"
   ```
4. Start Deadlock. Whenever the loading screen hangs, press `F9` with the console closed.

Deadlock runs `autoexec.cfg` automatically on every start. Steam updates and _"Verify integrity of game files"_ leave it alone. You can change the key if it is already taken.

> [!NOTE]
> If `F9` does nothing, enable the developer console and try again: turn on **Dev command console** in Deadlock's settings, or add `-dev` to the launch options (Steam → right-click **Deadlock** → **Properties** → **Launch options**). The console also lets you type `sv_cheats 1; restart` by hand (`F7`).

## Fix 2: automatic (optional)

[`auto-fix/DeadlockLoadingFix.ps1`](auto-fix/DeadlockLoadingFix.ps1) starts Deadlock itself, watches the game's console log, and presses `F9` when the hang appears. It needs **Fix 1**, because it presses the shortcut.

1. Set up Fix 1.
2. In Steam, right-click **Deadlock** → **Properties** → **Launch options**, and add `-condebug`. This makes the game write its console to `game\citadel\console.log`, which the script reads.
3. Download the `auto-fix` folder anywhere you like.
4. Double-click **`Start Deadlock (loading fix).cmd`** to start the game. The minimized PowerShell window shows what the script is doing:
   ```
   [21:40:47] Deadlock folder: C:\...\steamapps\common\Deadlock
   [21:40:47] Starting Deadlock through Steam...
   [21:40:50] Deadlock is running (PID 27868).
   [21:40:50] Watching C:\...\steamapps\common\Deadlock\game\citadel\console.log
   [21:41:07] Hang detected -> pressed F9 (sv_cheats 1; restart)
   [21:41:08] Loaded map dl_hideout.
   [21:43:54] Deadlock closed. Exiting.
   ```

The script exits when Deadlock is closed. Keep Deadlock as the activbe window while it loads. It only presses `F9` while Deadlock is in the front.

**Finding the game:** the script looks for Deadlock in the Steam library folder, and falls back to the location of a running `deadlock.exe`. If both fail, pass the folder yourself:

```powershell
powershell -ExecutionPolicy Bypass -File DeadlockLoadingFix.ps1 -GamePath "D:\SteamLibrary\steamapps\common\Deadlock"
```

**Why a `.cmd` file:** Windows opens `.ps1` files in Notepad on double-click, on purpose, so downloaded scripts don't run by accident. The `.cmd` file runs the script without changing that setting.

You then can add the icon of Deadlock to the cmd and pin it for example to the taskbar.

## Contribue

If you have more information, have problems, find bugs or have suggestions, please feel free to open Issues or Pull Requests. Thanks!

## Disclaimer

I am not affiliated with or endorsed by Valve, Deadlock or Mullvad. Deadlock is a trademark of Valve Corporation.
