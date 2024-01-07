{
  debug
  admin localhost:2019
  http_port 80
  https_port 443
  default_sni domain.tld
  key_type rsa4096
}
app.domain.tld {
  reverse_proxy sl-app:7777
}
