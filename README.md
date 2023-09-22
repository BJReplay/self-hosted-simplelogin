SimpleLogin
===========

This is a self-hosted docker-compose configuration for [SimpleLogin](https://simplelogin.io).

## Prerequisites

- a Linux server (either a VM or dedicated server). This doc shows the setup for Ubuntu 18.04 LTS but the steps could be adapted for other popular Linux distributions. As most of components run as Docker container and Docker can be a bit heavy, having at least 2 GB of RAM is recommended. The server needs to have the port 25 (email), 80, 443 (for the webapp), 22 (so you can ssh into it) open.

- a domain for which you can config the DNS. It could be a sub-domain. In the rest of the doc, let's say it's `mydomain.com` for the email and `app.mydomain.com` for SimpleLogin webapp. Please make sure to replace these values by your domain name whenever they appear in the doc. A trick we use is to download this README file on your computer and replace all `mydomain.com` occurrences by your domain.

Except for the DNS setup that is usually done on your domain registrar interface, all the below steps are to be done on your server. The commands are to run with `bash` (or any bash-compatible shell like `zsh`) being the shell. If you use other shells like `fish`, please make sure to adapt the commands.

### Some utility packages

These packages are used to verify the setup. Install them by:

```bash
sudo apt update \
  && sudo apt install -y dnsutils
```

## DNS Configuration

### MX record

Create a **MX record** that points `mydomain.com.` to `app.mydomain.com.` with priority 10.

To verify if the DNS works, the following command:

```bash
dig @1.1.1.1 mydomain.com mx
```

should return:

```
mydomain.com.	3600	IN	MX	10 app.mydomain.com.
```

### A record

Create an **A record** that points `app.mydomain.com.` to your server IP.
To verify, the following command:

```bash
dig @1.1.1.1 app.mydomain.com a
```

should return your server IP.

> **Please note** that DNS changes could take up to 24 hours to propagate. In practice, it's a lot faster though (~1 minute or so in our test). In DNS setup, we usually use domain with a trailing dot (`.`) at the end to to force using absolute domain.

### PTR record

From Wikipedia https://en.wikipedia.org/wiki/Reverse_DNS_lookup

> A reverse DNS lookup or reverse DNS resolution (rDNS) is the querying technique of the Domain Name System (DNS) to determine the domain name associated with an IP address – the reverse of the usual "forward" DNS lookup of an IP address from a domain name.

Create a **PTR record** that point

To verify, the following command:

```bash
dig @1.1.1.1 -x $( ip addr show eth0 | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1)
```

should return your domain name.

**Important** Some providers require PTR configuration to be done from their dashboard and ignore DNS records. Please, make sure to properly configure reverse DNS lookup for your domain.

### DKIM

From Wikipedia https://en.wikipedia.org/wiki/DomainKeys_Identified_Mail

> DomainKeys Identified Mail (DKIM) is an email authentication method designed to detect forged sender addresses in emails (email spoofing), a technique often used in phishing and email spam.

Setting up DKIM is highly recommended to reduce the chance for your emails ending up in the recipient's Spam folder.

First you need to generate a private and public key for DKIM:

```bash
openssl genrsa -traditional -out dkim.key 1024
openssl rsa -in dkim.key -pubout -out dkim.pub.key
```

You will need the files `dkim.key` and `dkim.pub.key` for the next steps.

For email gurus, we have chosen 1024 key length instead of 2048 for DNS simplicity as some registrars don't play well with long TXT record.

Set up DKIM by adding a **TXT record** for `dkim._domainkey.mydomain.com.` with the following value:

```
v=DKIM1; k=rsa; p=PUBLIC_KEY
```

with `PUBLIC_KEY` being your `dkim.pub.key` but
- remove the `-----BEGIN PUBLIC KEY-----` and `-----END PUBLIC KEY-----`
- join all the lines on a single line.

For example, if your `dkim.pub.key` is

```
-----BEGIN PUBLIC KEY-----
ab
cd
ef
gh
-----END PUBLIC KEY-----
```

then the `PUBLIC_KEY` would be `abcdefgh`.

You can get the `PUBLIC_KEY` by running this command:

```bash
sed "s/-----BEGIN PUBLIC KEY-----/v=DKIM1; k=rsa; p=/g" $(pwd)/dkim.pub.key | \
  sed 's/-----END PUBLIC KEY-----//g' | \
  tr -d '\n' | awk 1
```

To verify, the following command:

```bash
dig @1.1.1.1 dkim._domainkey.mydomain.com txt
```

should return the above value.

### SPF

From Wikipedia https://en.wikipedia.org/wiki/Sender_Policy_Framework

> Sender Policy Framework (SPF) is an email authentication method designed to detect forging sender addresses during the delivery of the email

Similar to DKIM, setting up SPF is highly recommended.

Create a **TXT record** for `mydomain.com.` with the value:

```
v=spf1 mx ~all
```

What it means is only your server can send email with `@mydomain.com` domain.
To verify, the following command

```bash
dig @1.1.1.1 mydomain.com txt
```

should return the above value.

### DMARC

From Wikipedia https://en.wikipedia.org/wiki/DMARC

> It (DMARC) is designed to give email domain owners the ability to protect their domain from unauthorized use, commonly known as email spoofing

Setting up DMARC is also recommended.

Create a **TXT record** for `_dmarc.mydomain.com.` with the following value

```
v=DMARC1; p=quarantine; adkim=r; aspf=r
```

This is a `relaxed` DMARC policy. You can also use a more strict policy with `v=DMARC1; p=reject; adkim=s; aspf=s` value.

To verify, the following command

```bash
dig @1.1.1.1 _dmarc.mydomain.com txt
```

should return the set value.

For more information on DMARC, please consult https://tools.ietf.org/html/rfc7489

### HSTS

From Wikipedia https://en.wikipedia.org/wiki/HTTP_Strict_Transport_Security

> HTTP Strict Transport Security (HSTS) is a policy mechanism that helps to protect websites against man-in-the-middle attacks such as protocol downgrade attacks and cookie hijacking.

HTTP Strict Transport Security is an extra step you can take to protect your web app from certain man-in-the-middle attacks. It does this by specifying an amount of time (usually a really long one) for which you should only accept HTTPS connections, not HTTP ones.

This repository already enables HSTS, thanks to the following line to the `server` block of the Nginx configuration file:

```
add_header Strict-Transport-Security "max-age: 31536000; includeSubDomains" always;
```

(The `max-age` is the time in seconds to not permit a HTTP connection, in this case it's one year.)

### CAA

From Wikipedia https://en.wikipedia.org/wiki/DNS_Certification_Authority_Authorization

> DNS Certification Authority Authorization (CAA) is an Internet security policy mechanism that allows domain name holders to indicate to certificate authorities whether they are authorized to issue digital certificates for a particular domain name.

[Certificate Authority Authorization](https://letsencrypt.org/docs/caa/) is a step you can take to restrict the list of certificate authorities that are allowed to issue certificates for your domains.

Use [SSLMate’s CAA Record Generator](https://sslmate.com/caa/) to create a **CAA record** with the following configuration:

- `flags`: `0`
- `tag`: `issue`
- `value`: `"sectigo.com"`

To verify if the DNS works, the following command:

```bash
dig @1.1.1.1 mydomain.com caa
```

should return:

```
mydomain.com.	3600	IN	CAA	0 issue "sectigo.com"
```

### MTA-STS

From Wikipedia https://en.wikipedia.org/wiki/Simple_Mail_Transfer_Protocol#SMTP_MTA_Strict_Transport_Security

> SMTP MTA Strict Transport Security defines a protocol for mail servers to declare their ability to use secure channels in specific files on the server and specific DNS TXT records.

[SMTP MTA Strict Transport Security](https://datatracker.ietf.org/doc/html/rfc8461) is an extra step you can take to broadcast the ability of your instance to receive and, optionally enforce, TSL-secure SMTP connections to protect email traffic.

**Note**: a file `/var/www/.well-known/mta-sts.txt` is included in this repository with a content similar to the text shown hereafter.
You **do not need to edit this file** as it will be updated upon startup.

```txt
version: STSv1
mode: testing
mx: app.mydomain.com
max_age: 86400
```
It is recommended to start with `mode: testing` for starters to get time to review failure reports.

Create a **TXT record** for `_mta-sts.mydomain.com.` with the following value:

```txt
v=STSv1; id=UNIX_TIMESTAMP
```

With `UNIX_TIMESTAMP` being the current date/time.

Use the following command to generate the record:

```bash
echo "v=STSv1; id=$(date +%s)"
```

To verify if the DNS works, the following command:

```bash
dig @1.1.1.1 _mta-sts.mydomain.com txt
```

should return a result similar to this one:

```
_mta-sts.mydomain.com.	3600	IN	TXT	"v=STSv1; id=1689416399"
```

### TLSRPT

[SMTP TLS Reporting](https://datatracker.ietf.org/doc/html/rfc8460) is used by SMTP systems to report failures in establishing TLS-secure sessions as broadcast by the MTA-STS configuration.

Configuring MTA-STS in `mode: testing` as shown in the previous section gives you time to review failures from some SMTP senders.

Create a **TXT record** for `_smtp._tls.mydomain.com.` with the following value:

```txt
v=TSLRPTv1; rua=mailto:YOUR_EMAIL
```

The TLSRPT configuration at the DNS level allows SMTP senders that fail to initiate TLS-secure sessions to send reports to a particular email address.  We suggest creating a `tls-reports` alias in SimpleLogin for this purpose.

To verify if the DNS works, the following command

```bash
dig @1.1.1.1 _smtp._tls.mydomain.com txt
```

should return a result similar to this one:

```
_smtp._tls.mydomain.com.	3600	IN	TXT	"v=TSLRPTv1; rua=mailto:tls-reports@mydomain.com"
```

## Docker

If you don't already have Docker installed on your server, please follow the steps on [Docker CE for Ubuntu](https://docs.docker.com/v17.12/install/linux/docker-ce/ubuntu/) to install Docker.

You can also install Docker using the [docker-install](https://github.com/docker/docker-install) script which is

```bash
curl -fsSL https://get.docker.com | sh
```
Enable IPv6 for [the default bridge network](https://docs.docker.com/config/daemon/ipv6/#use-ipv6-for-the-default-bridge-network)

```json
{
  "ipv6": true,
  "fixed-cidr-v6": "2001:db8:1::/64",
  "experimental": true,
  "ip6tables": true
}
```

## Setup

This procedure currently supports:

- Running Postfix on the host Ubuntu server.
- Running everything else in Docker containers.

This includes:

- nginx
- [acme.sh](https://acme.sh) to request and issue SSL certs.

### Postfix

Install `postfix` and `postfix-pgsql`. The latter is used to connect Postfix and the Postgres database in the next steps.

```bash
sudo apt-get install -y postfix postfix-pgsql -y
```

Choose "Internet Site" in Postfix installation window then keep using the proposed value as *System mail name* in the next window.

![](./docs/postfix-installation.png)
![](./docs/postfix-installation2.png)

Replace `/etc/postfix/main.cf` with the following content. Make sure to replace `mydomain.com` by your domain.

```
# POSTFIX config file, adapted for SimpleLogin
smtpd_banner = $myhostname ESMTP $mail_name (Ubuntu)
biff = no

# appending .domain is the MUA's job.
append_dot_mydomain = no

# Uncomment the next line to generate "delayed mail" warnings
#delay_warning_time = 4h

readme_directory = no

# See http://www.postfix.org/COMPATIBILITY_README.html -- default to 2 on
# fresh installs.
compatibility_level = 2

# TLS parameters
smtpd_tls_cert_file=/etc/ssl/certs/ssl-cert-snakeoil.pem
smtpd_tls_key_file=/etc/ssl/private/ssl-cert-snakeoil.key
smtpd_tls_session_cache_database = btree:${data_directory}/smtpd_scache
smtp_tls_session_cache_database = btree:${data_directory}/smtp_scache
smtp_tls_security_level = may
smtpd_tls_security_level = may

# See /usr/share/doc/postfix/TLS_README.gz in the postfix-doc package for
# information on enabling SSL in the smtp client.

alias_maps = hash:/etc/aliases
mynetworks = 127.0.0.0/8 [::ffff:127.0.0.0]/104 [::1]/128 10.0.0.0/24

# Set your domain here
mydestination =
myhostname = app.mydomain.com
mydomain = mydomain.com
myorigin = mydomain.com

relay_domains = pgsql:/etc/postfix/pgsql-relay-domains.cf
transport_maps = pgsql:/etc/postfix/pgsql-transport-maps.cf

# HELO restrictions
smtpd_delay_reject = yes
smtpd_helo_required = yes
smtpd_helo_restrictions =
    permit_mynetworks,
    reject_non_fqdn_helo_hostname,
    reject_invalid_helo_hostname,
    permit

# Sender restrictions:
smtpd_sender_restrictions =
    permit_mynetworks,
    reject_non_fqdn_sender,
    reject_unknown_sender_domain,
    permit

# Recipient restrictions:
smtpd_recipient_restrictions =
   reject_unauth_pipelining,
   reject_non_fqdn_recipient,
   reject_unknown_recipient_domain,
   permit_mynetworks,
   reject_unauth_destination,
   reject_rbl_client zen.spamhaus.org,
   reject_rbl_client bl.spamcop.net,
   permit
```

Check that the ssl certificates `/etc/ssl/certs/ssl-cert-snakeoil.pem` and `/etc/ssl/private/ssl-cert-snakeoil.key` exist. Depending on the linux distribution you are using they may or may not be present. If they are not, you will need to generate them with this command:

```bash
openssl req \
  -x509 \
  -nodes -days 3650 \
  -newkey rsa:2048 \
  -keyout /etc/ssl/private/ssl-cert-snakeoil.key \
  -out /etc/ssl/certs/ssl-cert-snakeoil.pem
```

Create the `/etc/postfix/pgsql-relay-domains.cf` file with the following content.
Make sure that the database config is correctly set, replace `mydomain.com` with your domain, update 'myuser' and 'mypassword' with your postgres credentials.

```
# postgres config
hosts = localhost
user = myuser
password = mypassword
dbname = simplelogin

query = SELECT domain FROM custom_domain WHERE domain='%s' AND verified=true
    UNION SELECT '%s' WHERE '%s' = 'mydomain.com' LIMIT 1;
```

Create the `/etc/postfix/pgsql-transport-maps.cf` file with the following content.
Again, make sure that the database config is correctly set, replace `mydomain.com` with your domain, update 'myuser' and 'mypassword' with your postgres credentials.

```
# postgres config
hosts = localhost
user = myuser
password = mypassword
dbname = simplelogin

# forward to smtp:127.0.0.1:20381 for custom domain AND email domain
query = SELECT 'smtp:127.0.0.1:20381' FROM custom_domain WHERE domain = '%s' AND verified=true
    UNION SELECT 'smtp:127.0.0.1:20381' WHERE '%s' = 'mydomain.com' LIMIT 1;
```

Finally, restart Postfix

```bash
sudo systemctl restart postfix
```

### Run SimpleLogin Docker containers

1. Clone this repository in `/opt/simplelogin`
1. Copy `.env.example` to `.env` and set appropriate values.

- set the `DOMAIN` variable to your domain.
- set the `POSTGRES_USER` variable to match the postgres credentials.
- set the `POSTGRES_PASSWORD` to match the postgres credentials.
- set the `FLASK_SECRET` to an arbitrary secret key.

The SSL certs are issued by ZeroSSL using either:

- ACME challenge
- [Azure DNS challenge](https://github.com/acmesh-official/acme.sh/wiki/dnsapi#37-use-azure-dns)

Please, uncomment the appropriate section from `./acme.sh/Dockerfiles/docker-entrypoint.sh`.

If you are using Azure DNS challenge, update the following values in `.env`:

- set `AZUREDNS_TENANTID` to the Azure tenant hosting the domain DNS zone.
- set `AZUREDNS_SUSCRIPTIONID` to the Azure subscription hosting the domain DNS zone.
- set `AZUREDNS_CLIENTID` to the client id of a service principal with permissions to update the DNS zone.
- set `AZUREDNS_CLIENTSECRET` to the client secret of a service principal with permissions to update the DNS zone.

1. Run the application:

```sh
./up.sh && docker logs -f acme.sh
```

Once successful, you will need to restart nginx:

```
docker compose restart nginx
```

## How-to Upgrade

- Change the image version in `.env`

```env
SL_VERSION=4.6.2-beta
```

- Check migration command
- Restart containers

```sh
./down.sh && ./up.sh
```
