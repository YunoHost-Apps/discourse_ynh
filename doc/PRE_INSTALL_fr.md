Attention: ce package installe Discourse sans Docker, pour plusieurs raisons (principalement pour prendre en charge l'architecture ARM et les serveurs discrets, pour mutualiser les services nginx/postgresql/redis et pour simplifier la configuration de la messagerie).
Comme indiqué par l'équipe Discourse :
> Les seules installations officiellement prises en charge de Discourse sont basées sur [Docker](https://www.docker.io/). Vous devez avoir un accès SSH à un serveur Linux 64 bits **avec prise en charge Docker**. Nous regrettons de ne pouvoir prendre en charge aucune autre méthode d'installation, notamment cpanel, plesk, webmin, etc.

Veuillez donc avoir cela à l'esprit lorsque vous envisagez de demander de l'aide à Discourse.

De plus, vous devriez avoir à l'esprit Discourse [exigences matérielles](https://github.com/discourse/discourse/blob/master/docs/INSTALL.md#hardware-requirements) :
- CPU monocœur moderne, double cœur recommandé
- 1 Go de RAM minimum (avec swap)
- Linux 64 bits compatible avec Docker
- 10 Go d'espace disque minimum

Enfin, si vous installez sur un appareil ARM bas de gamme (par exemple Raspberry Pi) :
- l'installation peut durer jusqu'à 3 heures,
- le premier accès juste après l'installation peut prendre quelques minutes.

