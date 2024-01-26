Attention: this package installs Discourse without Docker, for several reasons (mostly to support ARM architecture and low-profile servers, to mutualize nginx/postgresql/redis services and to simplify e-mail setup).
As stated by the Discourse team:
> The only officially supported installs of Discourse are [Docker](https://www.docker.io/) based. You must have SSH access to a 64-bit Linux server **with Docker support**. We regret that we cannot support any other methods of installation including cpanel, plesk, webmin, etc.
So please have this in mind when considering asking for Discourse support.

Moreover, you should have in mind Discourse [hardware requirements](https://github.com/discourse/discourse/blob/master/docs/INSTALL.md#hardware-requirements):

- modern single core CPU, dual core recommended
- 1 GB RAM minimum (with swap)
- 64 bit Linux compatible with Docker
- 10 GB disk space minimum

Finally, if installing on a low-end ARM device (e.g. Raspberry Pi):

- installation can last up to 3 hours,
- first access right after installation could take a couple of minutes.
