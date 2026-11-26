## Prise en charge multi-utilisateurs

![Login Popup](https://raw.githubusercontent.com/jonmbake/screenshots/master/discourse-ldap-auth/login.png)

L'administrateur par défaut et les utilisateurs YunoHost doivent se connecter via LDAP :

* cliquez sur le bouton "avec LDAP"
* utilisez vos identifiants YunoHost

Lors de la désactivation de la connexion locale et d'autres services d'authentification, cliquez sur le bouton « Connexion » ou « Inscription » pour afficher directement la fenêtre contextuelle de connexion LDAP.

![Désactiver Local](https://raw.githubusercontent.com/jonmbake/screenshots/master/discourse-ldap-auth/disable_local.png)

![Popup de connexion LDAP](https://raw.githubusercontent.com/jonmbake/screenshots/master/discourse-ldap-auth/ldap_popup.png)

## Configuration

Utilisez le panneau d'administration de votre Discourse pour configurer cette application.

### Configuration de "Répondre par e-mail"

* Vous devez créer un utilisateur Yunohost dédié pour Discourse dont la boîte aux lettres sera utilisée par l'application Discourse. Vous pouvez le faire avec `yunohost user create response`, par exemple. Vous devez vous assurer que l'adresse e-mail est configurée pour être sur votre domaine Discourse.

* L'envoi des e-mails ne demande aucune configuration : Discourse passe par le serveur mail de YunoHost avec l'adresse `__APP__@__DOMAIN__`. Gardez cette adresse dans le réglage `notification_email`, car le serveur mail refuse les autres expéditeurs pour cette application.

* Vous devez activer la configuration Pop3 pour Dovecot. Voir [ce fil](https://forum.yunohost.org/t/how-to-enable-pop3-in-yunohost/1662/2) pour savoir comment procéder. Vous pouvez valider votre configuration avec `systemctl restart dovecot && dovecot -n`. N'oubliez pas d'ouvrir les ports dont vous avez besoin ('995' est la valeur par défaut). Vous pouvez valider cela avec `nmap -p 995 yunohostdomain.org`.

* Vous devez ensuite configurer le sondage Pop3 dans l'interface d'administration de Discourse. Veuillez consulter [ce commentaire](https://meta.discourse.org/t/set-up-reply-via-email-support/14003) pour savoir comment procéder. Vous devrez suivre l'étape 5 de ce commentaire. Vous pouvez spécifier votre domaine Yunohost principal pour le `pop3_polling_host`.

Vous devriez maintenant pouvoir commencer à tester. Essayez d'utiliser le `/admin/email` « Envoyer un e-mail de test », puis affichez les onglets « Envoyé » ou « Ignoré », etc. Vous devriez voir un rapport sur ce qui s'est passé avec l'e-mail. Vous pouvez également regarder dans `/var/www/discourse/log/production.log` ainsi que `/var/www/mail.err`. Vous devriez peut-être également utiliser [Rainloop](https://github.com/YunoHost-Apps/rainloop_ynh) ou une autre application client de messagerie Yunohost pour tester rapidement que votre utilisateur et l'utilisateur dédié Yunohost Discourse (`response@...` ) reçoit du courrier.

### "Réponse par e-mail" et transfert de courrier

Si vous utilisez l'interface utilisateur d'administration de YunoHost pour configurer une adresse de transfert de courrier pour vos utilisateurs, vous risquez de rencontrer le problème selon lequel vos utilisateurs répondent par e-mail à partir de l'adresse e-mail transférée et le logiciel Discourse n'est pas capable de comprendre comment recevoir cet e-mail.

Par exemple, votre utilisateur a l'adresse e-mail "foo@myyunohostdomain.org" et tout le courrier est transféré à "foo@theirexternalmail.com". Discourse reçoit des réponses de `foo@theirexternalmail.com` mais ne peut pas comprendre comment les envoyer au compte utilisateur avec `foo@myyunohostdomain.org` configuré.

Pour corriger cela, vous pouvez ajouter manuellement une adresse e-mail secondaire dans le profil de l'utilisateur. Un correctif permet aussi d'utiliser comme adresse principale la première adresse de transfert, si elle existe : dans `Discourse > Plugins > LDAP`, remplacez la valeur du réglage `ldap_email` par `maildrop` au lieu de `email`.

Une autre solution consiste à utiliser les hooks utilisateur de YunoHost pour créer automatiquement les adresses secondaires.

Voici comment configurer une adresse e-mail secondaire pour un compte utilisateur :

```bash
cd /var/www/discourse/discourse
discourse_run() { sudo -u discourse env PATH="/opt/rbenv/versions/discourse/bin:$PATH" RAILS_ENV=production bash -c 'set -a; source ../discourse.env; set +a; exec "$@"' _ "$@"; }
discourse_run bin/rails c
UserEmail.create!(user: User.find_by_username("foo"), email: "foo@theirexternalmail.com")
```

### Intégration LDAP

* dans la pop-up de connexion, vous pouvez choisir "Se connecter avec LDAP" et utiliser vos identifiants YunoHost

![Login Popup](https://raw.githubusercontent.com/jonmbake/screenshots/master/discourse-ldap-auth/login.png)

L'administrateur par défaut et les utilisateurs YunoHost doivent se connecter via LDAP :

* cliquez sur le bouton "avec LDAP"
* utilisez vos identifiants YunoHost

Lors de la désactivation de la connexion locale et d'autres services d'authentification, cliquez sur le bouton « Connexion » ou « Inscription » pour afficher directement la fenêtre contextuelle de connexion LDAP.

![Désactiver Local](https://raw.githubusercontent.com/jonmbake/screenshots/master/discourse-ldap-auth/disable_local.png)

![Popup de connexion LDAP](https://raw.githubusercontent.com/jonmbake/screenshots/master/discourse-ldap-auth/ldap_popup.png)

### Installer des plugins

```bash
cd /var/www/discourse/discourse
discourse_run() { sudo -u discourse env PATH="/opt/rbenv/versions/discourse/bin:$PATH" RAILS_ENV=production bash -c 'set -a; source ../discourse.env; set +a; exec "$@"' _ "$@"; }
discourse_run bin/rake --trace plugin:install repo=https://github.com/discourse/discourse-solved
discourse_run bin/rake --trace db:migrate
discourse_run bin/rake --trace assets:precompile
systemctl restart discourse
```
