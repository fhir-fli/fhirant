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
| 6 | app locked in Recents (card → More → Lock) | 184/184 | alive; unplugged 14:25:43–15:34:48 (69 min), no kill recorded, same pid, uptime past 4,168 s |

| 7 | fix build, Recents lock OFF, exemption on, cable IN, screen awake | 89/89 | alive 16:31–16:45, uptime to 937 s; no kill recorded. The raw TSV was deleted by mistake on 2026-09-21; the counts are from its summary line before deletion |

| 8 | fix build, Recents lock OFF, exemption on, cable out 11:21 (2026-09-22), locked | 87/88 | killed 11:28:50, 7 min 0 s after unplug (11:21:50), `o-kill(6)`, importance 125, 256 MB; answered again 11:29:05 with uptime 7 s, a fresh server started by the service; then 534 s with no miss, and still up (uptime 627 s) at 11:39 after replug. Down 10–21 s |

Plugged in, the app was never killed: runs 1, 2 and 7, and 105 min for
sensorium (graiai/sensorium/PLAN.md 16.4). Every kill came after unplugging.

Run 4 (the phone in normal use) has not been run.

Back button (`runs/back_button.tsv`, 15:37): the server survived, same
uptime count, the activity paused rather than finished. Two checks right
after pressing back got no answer within 8 s (15:37:36, 15:37:49); cause
unmeasured.

Defects seen:
- After each kill, Android restarted the process 19 s later with the
  foreground service up, and the server did not start: /health refused.
  FIXED (run 8): the service now runs `serverTaskCallback`
  (packages/fhirant/lib/src/services/server_task.dart), which starts the
  server when Android restarted the service and the user had left it on.
- POST_NOTIFICATIONS is never requested, so the service's notification is
  hidden.
- The app does not ask for the battery exemption, and nothing tells the user
  to lock it in Recents.

The iPhone was not tested: Apple suspends an app about 5 s after it leaves
the screen, and no background mode covers serving network requests; the app
stops its server on pause.
