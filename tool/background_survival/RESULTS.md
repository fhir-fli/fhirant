# Does the fhirant app keep serving off screen? (Android)

OnePlus CPH2749, Android 16, OxygenOS; release APK built from fhirant
1707815; the app's foreground service (type connectedDevice, wake and Wi-Fi
locks). `run.sh poll` checks GET /health over Wi-Fi every 10 s; the TSVs are
in runs/. One run per row, one phone.

| Run | Change from the run before | Checks answered | Outcome |
|---|---|---|---|
| 1 | off screen, plugged in | 60/60 | alive |
| 2 | screen locked (dozing) | 60/60 | alive |
| 3 | unplugged | 34/59 | killed 13:59:13, 5 min 20 s after unplug; `o-kill(6)`, importance 125 (foreground service), 268 MB |
| 5 | battery exemption (adb `deviceidle whitelist`) | 34/71 | killed 14:12:38, 5 min 10 s after unplug; `o-kill(6)`, 245 MB |
| 6 | app locked in Recents (card → More → Lock) | 184/184 | alive 14:25:18–14:57, uptime 1,986 s; still up at 3,314 s |

Run 4 (the phone in normal use) has not been run.

Defects seen:
- After each kill, Android restarted the process 19 s later with the
  foreground service up, and the server did not start: /health refused.
- POST_NOTIFICATIONS is never requested, so the service's notification is
  hidden.
- The app does not ask for the battery exemption, and nothing tells the user
  to lock it in Recents.

The iPhone was not tested: Apple suspends an app about 5 s after it leaves
the screen, and no background mode covers serving network requests; the app
stops its server on pause.
