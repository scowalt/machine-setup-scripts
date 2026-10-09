def managed_app_unit(home, *, version='24.20.0', origin='https://fixture.example.ts.net',
                     tailscale='/usr/bin/tailscale'):
    prefix = f'{home}/.local/share/mise/installs/node/{version}'
    return f'''# setup-managed bb app v1
[Unit]
Description=Setup-managed bb main server and local execution daemon
StartLimitIntervalSec=0
[Service]
Type=simple
TimeoutStartSec=180
Environment=HOME={home}
Environment=PATH={home}/.local/share/mise/shims:{prefix}/bin:{home}/.local/bin:{home}/.bun/bin:/home/linuxbrew/.linuxbrew/bin:/usr/local/bin:/usr/bin:/bin
Environment=BB_PACKAGE_BINARY={prefix}/bin/bb-app
Environment=BB_TAILSCALE_BIN={tailscale}
Environment=BB_APP_URL={origin}
ExecStart={home}/.config/setup-bb-server/bb-guard app-start
ExecStartPost={home}/.config/setup-bb-server/bb-guard app-ready
Restart=always
RestartSec=10
[Install]
WantedBy=default.target
'''


def managed_ingress_unit(home, *, version='24.20.0', tailscale='/usr/bin/tailscale'):
    prefix = f'{home}/.local/share/mise/installs/node/{version}'
    return f'''# setup-managed bb ingress v1
[Unit]
Description=Setup-managed bb private HTTPS ingress
BindsTo=setup-bb-app.service
After=setup-bb-app.service
StartLimitIntervalSec=0
[Service]
Type=simple
Environment=HOME={home}
Environment=PATH={home}/.local/share/mise/shims:{prefix}/bin:{home}/.local/bin:{home}/.bun/bin:/home/linuxbrew/.linuxbrew/bin:/usr/local/bin:/usr/bin:/bin
Environment=BB_PACKAGE_BINARY={prefix}/bin/bb-app
Environment=BB_TAILSCALE_BIN={tailscale}
ExecStart={home}/.config/setup-bb-server/bb-guard ingress-start
Restart=always
RestartSec=15
'''
