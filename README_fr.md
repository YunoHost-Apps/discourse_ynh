# Discourse pour YunoHost

[![Niveau d'intégration](https://dash.yunohost.org/integration/discourse.svg)](https://dash.yunohost.org/appci/app/discourse) ![](https://ci-apps.yunohost.org/ci/badges/discourse.status.svg) ![](https://ci-apps.yunohost.org/ci/badges/discourse.maintain.svg)  
[![Installer Discourse avec YunoHost](https://install-app.yunohost.org/install-with-yunohost.svg)](https://install-app.yunohost.org/?app=discourse)

*[Read this readme in english.](./README.md)*
*[Lire ce readme en français.](./README_fr.md)*

> *Ce package vous permet d'installer Discourse rapidement et simplement sur un serveur YunoHost.
Si vous n'avez pas YunoHost, regardez [ici](https://yunohost.org/#/install) pour savoir comment l'installer et en profiter.*

## Vue d'ensemble

Plateforme de discussion

**Version incluse :** 2.7.0~ynh1

**Démo :** https://try.discourse.org

## Captures d'écran

![](./doc/screenshots/screenshot.png)

## Avertissements / informations importantes

## Configuration

Utilisez le panneau d'administration de votre Discourse pour configurer cette application.

### Configuration de "Répondre par email"

* Vous devez créer un utilisateur YunoHost dédié pour *Discourse* dont la boîte aux lettres sera utilisée par l'application. Vous pouvez le faire avec `yunohost user create response`, par exemple. Vous devez vous assurer que l'adresse email est configurée pour être sur votre domaine *Discourse*.

* Vous devez ensuite configurer votre fichier de configuration `/var/www/discourse/config/discourse.conf` avec les valeurs de configuration SMTP correctes. Veuillez consulter [ce commentaire](https://github.com/YunoHost-Apps/discourse_ynh/issues/2#issuecomment-409510325) pour une explication des valeurs à modifier. Attention, lors de la mise à jour de l'application, vous devrez réappliquer cette configuration.

* Vous devez activer la configuration POP3 pour *Dovecot*. Voir [ce fil](https://forum.yunohost.org/t/how-to-enable-pop3-in-yunohost/1662/2) pour savoir comment procéder. Vous pouvez valider votre configuration avec `systemctl restart dovecot && dovecot -n`. N'oubliez pas d'ouvrir les ports dont vous avez besoin (`995` est la valeur par défaut). Vous pouvez valider cela avec `nmap -p 995 domain.ltd`.

* Vous devez ensuite configurer le sondage Pop3 dans l'interface d'administration de *Discourse*. Veuillez consulter [ce commentaire](https://meta.discourse.org/t/set-up-reply-via-email-support/14003) pour savoir comment procéder. Vous devrez suivre l'étape 5 de ce commentaire. Vous pouvez spécifier votre domaine Yunohost principal pour le `pop3_polling_host`.

Vous devriez maintenant pouvoir commencer à tester. Essayez d'utiliser le `/admin/email` « Envoyer un email de test », puis affichez les onglets « Envoyé » ou « Ignoré », etc. Vous devriez voir un rapport sur ce qui s'est passé avec l'email. Vous pouvez également regarder dans `/var/www/discourse/log/production.log` ainsi que `/var/www/mail.err`. Vous devriez peut-être également utiliser [Rainloop](https://github.com/YunoHost-Apps/rainloop_ynh) ou une autre application client de messagerie YunoHost pour tester rapidement que votre utilisateur et l'utilisateur dédié YunoHost *Discourse* (`response@...`) reçoit du courrier.

### "Réponse par email" et transfert de courrier

Si vous utilisez l'interface utilisateur d'administration de YunoHost pour configurer une adresse de transfert de courrier pour vos utilisateurs, vous risquez de rencontrer le problème selon lequel vos utilisateurs répondent par email à partir de l'adresse e-mail transférée et le logiciel *Discourse* n'est pas en mesure de comprendre comment recevoir cet email.

Par exemple, votre utilisateur a l'adresse email "foo@myyunohostdomain.org" et tout le courrier est transféré à `foo@theirexternalmail.com`. *Discourse* reçoit des réponses de `foo@theirexternalmail.com` mais ne peut pas comprendre comment les envoyer au compte utilisateur avec `foo@myyunohostdomain.org` configuré.

Leur travail est en cours pour permettre [plusieurs adresses email pour un utilisateur](https://meta.discourse.org/t/additional-email-address-per-user-account-support/59847) dans le développement de *Discours* mais dans la version majeure actuelle (2.3 au 06-08-2019), il n'y a pas d'interface Web pour cette fonctionnalité. Il est possible de le configurer via l'interface de ligne de commande mais c'est **expérimental** et vous ne devriez pas entreprendre ce travail à moins de prendre le temps de comprendre ce que vous allez faire.

Voici comment configurer une adresse email secondaire pour un compte utilisateur :

```bash
$ cd /var/www/discours
$ RAILS_ENV=production /opt/rbenv/versions/2.6.0/bin/bundle exec rails c
$ UserEmail.create!(user: User.find_by_username("foo"), email: "foo@theirexternalmail.com")
```

*Discourse* peut maintenant recevoir du courrier de `foo@theirexternalmail.com` et le donner au compte utilisateur avec l'adresse email `foo@myyunohostdomain.org`. 

#### Prise en charge multi-utilisateurs

Pris en charge, avec LDAP et SSO.

![Login Popup](https://raw.githubusercontent.com/jonmbake/screenshots/master/discourse-ldap-auth/login.png)

L'administrateur par défaut et les utilisateurs YunoHost doivent se connecter via LDAP :
* cliquez sur le bouton "avec LDAP"
* utilisez vos identifiants YunoHost

Lors de la désactivation de la connexion locale et d'autres services d'authentification, cliquez sur le bouton « Connexion » ou « Inscription » pour afficher directement la fenêtre contextuelle de connexion LDAP.

![Désactiver Local](https://raw.githubusercontent.com/jonmbake/screenshots/master/discourse-ldap-auth/disable_local.png)

![Popup de connexion LDAP](https://raw.githubusercontent.com/jonmbake/screenshots/master/discourse-ldap-auth/ldap_popup.png) 

## Documentations et ressources

* Site officiel de l'app : http://Discourse.org
* Dépôt de code officiel de l'app : https://github.com/discourse/discourse
* Documentation YunoHost pour cette app : https://yunohost.org/app_discourse
* Signaler un bug : https://github.com/YunoHost-Apps/discourse_ynh/issues

## Informations pour les développeurs

Merci de faire vos pull request sur la [branche testing](https://github.com/YunoHost-Apps/discourse_ynh/tree/testing).

Pour essayer la branche testing, procédez comme suit.
```
sudo yunohost app install https://github.com/YunoHost-Apps/discourse_ynh/tree/testing --debug
ou
sudo yunohost app upgrade discourse -u https://github.com/YunoHost-Apps/discourse_ynh/tree/testing --debug
```

**Plus d'infos sur le packaging d'applications :** https://yunohost.org/packaging_apps