Si votre Discourse est antérieur à 2026.1 (packaging v1), YunoHost revient à la sauvegarde de sécurité quand la mise à jour échoue, et cette sauvegarde ne démarre que sur un serveur qui a encore les bibliothèques de Debian 11. Vérifiez-les avant la mise à jour :

```bash
ls /usr/lib/x86_64-linux-gnu/libssl.so.1.1 /usr/lib/x86_64-linux-gnu/libffi.so.7
systemctl is-active redis-server
```

S'il en manque une, faites d'abord votre propre sauvegarde et vérifiez que vous savez la restaurer ailleurs.
