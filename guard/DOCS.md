# Guard (Pi-hole for Home Assistant)

Network-wide ad and tracking protection for your smart home, powered by Pi-hole core.

## Features
- Blocks advertisements and tracking domain queries across all devices on your Wi-Fi (phones, smart TVs, IoT).
- Web administration interface accessible directly from your network at port 8080 (`http://<homeassistant-ip>:8080/admin`).
- Customizable upstream DNS providers (Cloudflare, Quad9, Google, etc.).
- Integrated Gravity engine for automatic blocklist updates.

## Configuration Options
- `password`: Password for the web admin dashboard. If left blank, password authentication is disabled.
- `upstream_dns`: Semicolon or comma-separated upstream DNS servers (e.g. `1.1.1.1;1.0.0.1` or `9.9.9.9;149.112.112.112`).

## Router Setup
To protect your entire network:
1. In your router (e.g., ASUS RT-BE86U), navigate to **LAN** -> **DHCP Server**.
2. Set **DNS Server 1** to your Home Assistant / Raspberry Pi IP address.
3. Leave **DNS Server 2** empty.
4. Save and reboot your connected devices to receive the new DNS settings.
