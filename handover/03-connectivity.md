# Stage 3 — Connect the Phone to the Laptop

**Goal:** the phone can reach the C++ server on the laptop over Tailscale.

**Done when:** the phone browser opens
`http://<laptop-tailscale-ip>:8080/api/health` and shows JSON.

No Flutter code is needed for this stage. Test with the phone browser first.

---

## 1. Prerequisites

- Stage 2 checkpoint passed.
- The server runs on the laptop.
- The laptop and phone can install apps.
- You have a Tailscale account (free tier is enough).

---

## 2. Install Tailscale on the laptop

On Ubuntu/Debian:

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

The command prints a login URL. Open it in a browser and sign in.

Check:

```bash
tailscale status
tailscale ip -4
```

Example output:

```text
100.101.102.103
```

That `100.x.y.z` address is the laptop's Tailscale IP. Write it down.

---

## 3. Install Tailscale on the phone

1. Install **Tailscale** from the Play Store.
2. Sign in with the **same account** as the laptop.
3. Turn the Tailscale VPN switch on.
4. Confirm the phone appears in `tailscale status` on the laptop.

Both devices must be in the same tailnet.

---

## 4. Start the server correctly

The server must listen on all interfaces, not just localhost:

```bash
cd ~/development/TasteHub-App
./build/tastehub-server --host 0.0.0.0 --port 8080 --data-dir data
```

If you use `--host 127.0.0.1`, the phone cannot reach it.

Check from the laptop first:

```bash
curl -s http://127.0.0.1:8080/api/health
curl -s http://100.101.102.103:8080/api/health
```

Replace the IP with your own. Both should return:

```json
{"recipes":6,"status":"ok"}
```

If the second one fails, the problem is on the laptop, not the phone.

---

## 5. Open the firewall (if enabled)

Check:

```bash
sudo ufw status
```

If it is active, allow the port:

```bash
sudo ufw allow 8080/tcp
```

If you use a different firewall, allow TCP 8080 on the Tailscale interface.

---

## 6. Test from the phone browser

On the phone, with Tailscale on, open:

```text
http://100.101.102.103:8080/api/health
```

You should see:

```json
{"recipes":6,"status":"ok"}
```

That is the Stage 3 checkpoint. Do not continue until this works.

---

## 7. Optional: use MagicDNS instead of the IP

MagicDNS gives the laptop a name like `my-laptop.tailnet-name.ts.net`.

1. Enable MagicDNS in the Tailscale admin console.
2. On the phone, open:

```text
http://my-laptop:8080/api/health
```

or the full name:

```text
http://my-laptop.tailnet-name.ts.net:8080/api/health
```

If the name does not resolve, use the `100.x.y.z` IP. It always works.

---

## 8. Android cleartext HTTP

Android 9+ blocks plain `http://` traffic by default. The Flutter app will show
an error like:

```text
Cleartext HTTP traffic to 100.101.102.103 not permitted
```

You have two options.

### Option A — allow cleartext for the debug build (simplest)

Create or edit `android/app/src/debug/AndroidManifest.xml` in the Flutter
project:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET"/>
    <application android:usesCleartextTraffic="true" />
</manifest>
```

This only affects debug builds. It is fine for the demo.

### Option B — use Tailscale Serve for HTTPS (cleaner)

On the laptop, with the server running on port 8080:

```bash
tailscale serve --bg 8080
```

On newer Tailscale versions:

```bash
tailscale serve --bg http://localhost:8080
```

Check:

```bash
tailscale serve status
```

You get an HTTPS URL like:

```text
https://my-laptop.tailnet-name.ts.net
```

Test it from the phone browser:

```text
https://my-laptop.tailnet-name.ts.net/api/health
```

Then build Flutter with:

```bash
flutter build apk --dart-define=API_BASE_URL=https://my-laptop.tailnet-name.ts.net
```

No cleartext configuration is needed for HTTPS.

To stop serving:

```bash
tailscale serve reset
```

---

## 9. Fallback connections

Keep these ready in case Tailscale or the venue network fails.

### Fallback 1 — same Wi-Fi

1. Connect the phone and laptop to the same Wi-Fi.
2. Find the laptop's LAN IP:

```bash
hostname -I
```

Example: `192.168.1.42`.

3. On the phone, open:

```text
http://192.168.1.42:8080/api/health
```

If it fails, the Wi-Fi may have "AP isolation" enabled. Use another fallback.

### Fallback 2 — USB with `adb reverse`

1. Enable USB debugging on the phone.
2. Connect the phone by USB.
3. Run:

```bash
adb devices
adb reverse tcp:8080 tcp:8080
```

4. On the phone, use:

```text
http://127.0.0.1:8080
```

This works because `adb` forwards the phone's localhost port to the laptop.
Build the app with:

```bash
flutter build apk --dart-define=API_BASE_URL=http://127.0.0.1:8080
```

### Fallback 3 — phone hotspot

1. Turn on the phone's hotspot.
2. Connect the laptop to the hotspot.
3. Find the laptop's hotspot IP:

```bash
hostname -I
```

4. Use that IP in the app.

---

## 10. Checkpoint

- [ ] `tailscale status` shows both devices.
- [ ] `tailscale ip -4` gives a `100.x.y.z` address.
- [ ] `curl http://127.0.0.1:8080/api/health` works on the laptop.
- [ ] `curl http://100.x.y.z:8080/api/health` works on the laptop.
- [ ] The phone browser shows `/api/health` over Tailscale.
- [ ] You know which fallback you will use if Tailscale fails.
- [ ] The laptop is set to stay awake during the demo.

Keep the laptop awake:

```bash
# GNOME: Settings -> Power -> Automatic Suspend -> Off
# or temporarily:
systemd-inhibit --what=idle:sleep ./build/tastehub-server --host 0.0.0.0 --port 8080 --data-dir data
```

---

## 11. Troubleshooting

| Problem | Cause | Fix |
|---|---|---|
| Phone cannot open the page | Tailscale VPN is off on the phone | Turn the Tailscale switch on |
| Phone cannot open the page | Devices are in different tailnets | Sign in with the same account |
| `curl` works on localhost but not on the Tailscale IP | Server bound to `127.0.0.1` | Use `--host 0.0.0.0` |
| `curl` works on the laptop but not the phone | Firewall blocks 8080 | `sudo ufw allow 8080/tcp` |
| Works on Wi-Fi but not cellular | Tailscale is off | Turn it on; Tailscale works over cellular |
| `Cleartext HTTP traffic ... not permitted` | Android blocks plain HTTP | Use the debug manifest or Tailscale Serve HTTPS |
| `tailscale serve` returns 502 | Server is not running on port 8080 | Start the server, then check `tailscale serve status` |
| MagicDNS name does not resolve | MagicDNS disabled | Use the `100.x.y.z` IP |
| Phone and laptop cannot see each other | One device is offline | `tailscale status`, then reconnect |
| Demo venue has no internet | Tailscale cannot coordinate | Use same Wi-Fi or `adb reverse` |

---

## 12. Handoff to Stage 4

You now have a working API URL. Choose one:

```text
http://100.x.y.z:8080
https://my-laptop.tailnet-name.ts.net
http://127.0.0.1:8080        (only with adb reverse)
```

Use it in Stage 4:

```bash
flutter run -d linux --dart-define=API_BASE_URL=http://127.0.0.1:8080
flutter build apk --dart-define=API_BASE_URL=http://100.x.y.z:8080
```

**Commit:**

```bash
git add -A
git commit -m "Stage 3: Tailscale connectivity notes"
```
