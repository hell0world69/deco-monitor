# Deco Monitor

Watch a TP-Link Deco mesh from an Omarchy desktop: total and per-device live
speeds, every connected device, the Deco units and their internet status, and
alerts when a new device joins. Rebooting Deco units is the one thing it changes.

It talks to the Deco's own local web API (the one behind http://192.168.68.1),
the same API Home Assistant's Deco integration uses. Blocking devices, parental
controls and QoS live in TP-Link's cloud, so they stay in the Deco phone app.

## Pieces

| Piece | What it is |
|---|---|
| `deco` | Python CLI: logs in (RSA + AES, like the Deco web page), prints JSON. `deco watch` polls forever. |
| `deco-monitor.service` | systemd user service running `deco watch 3`; writes `$XDG_RUNTIME_DIR/deco-monitor/status.json` and sends a notification for new devices. |
| `decomon` | Qt Quick app reading that file. |
| bar widget | `hell0world.deco-monitor` omarchy-shell plugin, also reading that file. |

Only the service logs in: the Deco allows one local session at a time, so the
app and the widget never fight over it.

## Setup

```sh
# The Deco owner password (your TP-Link ID password), kept in the GNOME keyring
secret-tool store --label='Deco router' service deco-monitor

bin/install                                   # builds and installs the package
systemctl --user enable --now deco-monitor    # start polling
```

`DECO_HOST` overrides the Deco address (default `192.168.68.1`).

## Commands

```
deco status | clients | nodes | wan     JSON snapshots
deco reboot [MAC...]                    reboot all Deco units, or the given ones
deco raw 'admin/device?form=device_list' '{"operation":"read"}'
```

Speeds from the Deco are kilobits per second.

## Keyboard (decomon)

| Key | Action |
|---|---|
| `/` or `Ctrl+F` | Search devices |
| `Space` | Show or hide idle devices |
| `S` | Sort by speed or name |
| `↑` `↓` | Move through devices |
| `R` | Reboot all Deco units (asks first) |
| `Esc` | Clear search, close dialogs |
| `?` | Show shortcuts |
| `Q` | Quit |

## Development

`bin/build`, `bin/test`, `bin/install`.
