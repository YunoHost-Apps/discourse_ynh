If your Discourse is older than 2026.1 (packaging v1), YunoHost falls back to the safety backup when the upgrade fails, and that backup only starts on a server that still has the libraries of Debian 11. Check them before upgrading:

```bash
ls /usr/lib/x86_64-linux-gnu/libssl.so.1.1 /usr/lib/x86_64-linux-gnu/libffi.so.7
systemctl is-active redis-server
```

If one is missing, make your own backup first and check that you can restore it elsewhere.
