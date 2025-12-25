# Machine setup scripts

Idempotent scripts I use to set up my machines.

## Windows

```powershell
iwr -useb https://scripts.scowalt.com/setup/win.ps1 | iex
```

## WSL

```bash
curl -sL https://scripts.scowalt.com/setup/wsl.sh | bash
```

## MacOS

```bash
curl -sL https://scripts.scowalt.com/setup/mac.sh | bash
```

## Ubuntu

```bash
curl -sL https://scripts.scowalt.com/setup/ubuntu.sh | bash
```

## Raspberry Pi

```bash
curl -sL https://scripts.scowalt.com/setup/pi.sh | bash
```

## IPv6-only Servers (DNS64/NAT64)

For IPv6-only servers (e.g., Hetzner Cloud without IPv4), run this to enable connectivity to IPv4-only hosts like GitHub:

```bash
curl -sL https://scripts.scowalt.com/setup/ipv6-dns64.sh | bash
```

This configures [nat64.net](https://nat64.net) DNS servers which provide DNS64/NAT64 translation.
