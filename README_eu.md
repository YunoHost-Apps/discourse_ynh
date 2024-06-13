<!--
Ohart ongi: README hau automatikoki sortu da <https://github.com/YunoHost/apps/tree/master/tools/readme_generator>ri esker
EZ editatu eskuz.
-->

# Discourse YunoHost-erako

[![Integrazio maila](https://dash.yunohost.org/integration/discourse.svg)](https://dash.yunohost.org/appci/app/discourse) ![Funtzionamendu egoera](https://ci-apps.yunohost.org/ci/badges/discourse.status.svg) ![Mantentze egoera](https://ci-apps.yunohost.org/ci/badges/discourse.maintain.svg)

[![Instalatu Discourse YunoHost-ekin](https://install-app.yunohost.org/install-with-yunohost.svg)](https://install-app.yunohost.org/?app=discourse)

*[Irakurri README hau beste hizkuntzatan.](./ALL_README.md)*

> *Pakete honek Discourse YunoHost zerbitzari batean azkar eta zailtasunik gabe instalatzea ahalbidetzen dizu.*  
> *YunoHost ez baduzu, kontsultatu [gida](https://yunohost.org/install) nola instalatu ikasteko.*

## Aurreikuspena

[Discourse](http://www.discourse.org) is the 100% open source discussion platform built for the next decade of the Internet. Use it as a:

- mailing list
- discussion forum
- long-form chat room

To learn more about the philosophy and goals of the project, [visit **discourse.org**](http://www.discourse.org).


**Paketatutako bertsioa:** 2.8.14~ynh4

**Demoa:** <https://try.discourse.org>

## Pantaila-argazkiak

![Discourse(r)en pantaila-argazkia](./doc/screenshots/screenshot.png)

## Dokumentazioa eta baliabideak

- Aplikazioaren webgune ofiziala: <http://Discourse.org>
- Jatorrizko aplikazioaren kode-gordailua: <https://github.com/discourse/discourse>
- YunoHost Denda: <https://apps.yunohost.org/app/discourse>
- Eman errore baten berri: <https://github.com/YunoHost-Apps/discourse_ynh/issues>

## Garatzaileentzako informazioa

Bidali `pull request`a [`testing` abarrera](https://github.com/YunoHost-Apps/discourse_ynh/tree/testing).

`testing` abarra probatzeko, ondorengoa egin:

```bash
sudo yunohost app install https://github.com/YunoHost-Apps/discourse_ynh/tree/testing --debug
edo
sudo yunohost app upgrade discourse -u https://github.com/YunoHost-Apps/discourse_ynh/tree/testing --debug
```

**Informazio gehiago aplikazioaren paketatzeari buruz:** <https://yunohost.org/packaging_apps>
