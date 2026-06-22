Here's a full walkthrough tailored to your nested Proxmox-in-VirtualBox setup.

---

# Architecture 

```
Windows Host 
└── VirtualBox
    └── Proxmox VE (10.0.2.15 via NAT | 192.168.56.10 via Host-Only)
        ├── vmbr0 → VirtualBox NAT → Internet
        └── vmbr1 (inner bridge)
            ├── OPNsense VM
            │   ├── WAN → vmbr0 (upstream internet)
            │   └── LAN → 192.168.1.1 (gateway for inner VMs)
            └── VM1 (ID:101) — XFCE4 desktop
                ├── Gets DHCP from OPNsense (192.168.1.x)
                ├── Accesses OPNsense UI at http://192.168.1.1 via Firefox
                └── startx → launches XFCE4 desktop UI
```

---

## Phase 0 — Identify your Proxmox NICs

SSH into Proxmox (or use the Proxmox VNC shell) and run:

```bash
ip a
```

You'll see two physical NICs — likely named `enp6s18` and `enp6s19` (or `ens18`/`ens19` depending on your VirtualBox NIC type). To figure out which is which:

```bash
# Check which one has a 10.0.2.x address → that's the NAT adapter
# Check which one has 192.168.56.x → that's the Host-Only adapter
```

<!-- For the rest of this guide:
- **NAT NIC** = `enp6s18` (replace with yours)
- **Host-Only NIC** = `enp6s19` (this one's already in vmbr0) -->

---

## Phase 1 — Create the two new bridges in Proxmox

In the **Proxmox web UI** → your node → **Network** → **Create** → **Linux Bridge**

**Bridge 1 — WAN (vmbr1):**
| Field | Value |
|-------|-------|
| Name | `vmbr1` |
| Bridge ports | `enp6s18` (your NAT NIC) |
| IP address | *(leave blank — OPNsense owns this)* |
| Autostart | ✅ |

**Bridge 2 — LAN (vmbr2):**
| Field | Value |
|-------|-------|
| Name | `vmbr2` |
| Bridge ports | *(leave empty — purely internal)* |
| IP address | *(leave blank)* |
| Autostart | ✅ |

Click **Apply Configuration** at the top to commit the changes.

> **Why no IP on vmbr1/vmbr2?** OPNsense will own those networks. Proxmox just acts as a dumb switch.

---

## Phase 2 — Download the OPNsense ISO

In the **Proxmox web UI** → your node → **local** storage → **ISO Images** → **Download from URL**

Grab the latest OPNsense DVD image from:
```
https://mirror.ams1.nl.leaseweb.net/opnsense/releases/25.1/OPNsense-25.1-dvd-amd64.iso.bz2
```

https://pkg.opnsense.org/releases/26.1.6/OPNsense-26.1.6-dvd-amd64.iso.bz2

Or find the latest at `https://opnsense.org/download/` — pick the **DVD (ISO)** image, **amd64**. Paste the URL into Proxmox and let it download directly.

> If the `.bz2` compressed format gives you trouble, you can decompress it on Proxmox after download: `bunzip2 /var/lib/vz/template/iso/OPNsense*.bz2`

---

## Phase 3 — Create the OPNsense VM

**Proxmox web UI** → **Create VM**

Walk through the wizard with these settings:

**General**
- VM ID: `100` (or any free ID)
- Name: `opnsense`

**OS**
- ISO: the OPNsense ISO you downloaded
- Guest OS type: **Other**

**System**
- Machine: `q35`
- BIOS: `SeaBIOS` (default)
- SCSI controller: `VirtIO SCSI`

**Disks**
- Bus: `VirtIO Block`
- Size: `16 GiB`
- Storage: `local-lvm`

**CPU**
- Cores: `2`
- Type: `host` *(important for nested — avoids emulation overhead)*

**Memory**
- RAM: `1024 MB` minimum; `2048 MB` recommended

**Network** — this is the key part: add **two** NICs

- **NIC 1** (WAN): Bridge = `vmbr0`, Model = `VirtIO (paravirt)`
- **NIC 2** (LAN): Bridge = `vmbr1`, Model = `VirtIO (paravirt)`

You add the second NIC after the wizard via **Hardware** → **Add** → **Network Device**.

---

## Phase 4 — Install OPNsense

Start the VM and open the **Console** tab in Proxmox.

1. Boot from the ISO. At the login prompt, log in with:
   - Username: `installer`
   - Password: `opnsense`

2. Walk through the installer:
   - Keymap: choose yours (or accept default)
   - **Install (ZFS)** — recommended even in a VM
   - ZFS config: `stripe` (single disk), select your `vtbd0` disk
   - Confirm and let it install (~2–3 min)

3. When prompted, **change the root password**, then select **Reboot**. Remove the ISO from the CD drive before it boots again (Proxmox → Hardware → CD/DVD → Edit → set to "Do not use any media").

---

## Phase 5 — Assign interfaces and set LAN IP

After reboot, OPNsense boots to a CLI menu. You'll see two interfaces detected — likely `vtnet0` and `vtnet1`.

**Step 5a — Assign WAN/LAN**

Choose option **1) Assign interfaces**:
- Do you want to configure LAGGs? → `n`
- Do you want to configure VLANs? → `n`
- WAN interface: `vtnet0`
- LAN interface: `vtnet1`
- Confirm with `y`

**Step 5b — Set LAN IP**

Choose option **2) Set interface IP address** → select `LAN`:
- Configure IPv4 via DHCP? → `n`
- LAN IPv4 address: `192.168.1.1`
- Subnet bit count: `24`
- Upstream gateway? → press Enter (none for LAN)
- Configure IPv6? → `n`
- Enable DHCP server on LAN? → `y`
- Start of DHCP range: `192.168.1.100`
- End of DHCP range: `192.168.1.200`

OPNsense will print something like: `Web GUI is accessible at https://192.168.1.1`

The WAN (`vtnet0`) will get a DHCP address from the VirtualBox NAT range (10.0.2.x) automatically.

---

## Phase 6 — Access the web UI

Since your laptop can't directly reach `192.168.1.x` (that's inside vmbr2), the easiest option for a lab is to spin up a lightweight VM on the LAN side:

**Quick option — Alpine Linux LXC on vmbr2:**

In Proxmox, download an Alpine LXC template (local → CT Templates → Templates → Alpine), create a container attached to `vmbr2`, start it, and open its console. It'll get a DHCP address from OPNsense (192.168.1.100–.200). Then from within that container:

```bash
curl -k https://192.168.1.1  # confirms web UI is up
```

For a proper browser session, use the **noVNC console** of any VM on vmbr2, open a browser, and hit `https://192.168.1.1`.

**Default OPNsense credentials:**
- Username: `root`
- Password: whatever you set during install (or `opnsense` if you skipped it)

---

## Nested VM gotchas to watch for

**Hardware offloading issues:** If you see dropped packets or weird routing behavior, disable NIC offloading on the Proxmox host for those bridges:

```bash
ethtool -K vmbr1 gso off gro off tso off
ethtool -K vmbr2 gso off gro off tso off
```

Add these to `/etc/network/interfaces` under each bridge to persist across reboots:
```
post-up ethtool -K vmbr1 gso off gro off tso off
```

**WAN won't get DHCP?** Verify that `enp6s18` is actually your NAT NIC with `ip a` — if your bridges are swapped, OPNsense's WAN will be on the wrong side.

**VirtualBox NAT double-NAT:** You'll have NAT inside NAT (VirtualBox NATs for Proxmox, OPNsense NATs for its LAN clients). Totally fine for a lab — just know that any port forwarding to reach services from your laptop needs to be configured at both VirtualBox (port forward on the NAT adapter) and OPNsense.

---

Once the web UI is up, you're ready to start poking around — Pi-hole as a DNS resolver upstream, firewall rules, VLANs via vmbr tagging, WireGuard VPN. All of those are solid next lab steps worth documenting for the portfolio.


1. downloaded xfce4 for mini 
2. run http://192.168.1.1 on firefox of VM
3. `sudo ip addr flush dev eth0` then `sudo dhclient eth0` to clear out stubborn static ghost IP 

- `startx` to launch the desktop environment

![alt text](image.png)

## OPNsense wizard config

hostname: OPNsense
DNS: internal
DNS server: 1.1.1.1
override DNS: y
enable resolver: y
enable DNSSEC support: y
harden DNSSEC data: y
disable WAN: n
type: dhcp
mac(spoofed): n
mtu: def
mss: def
dhcp hostname: def
dont block rfc1918 privnet and bogon netwk
ip addr: 192.168.1.1/24
configure dhcp server: y
optimize for multiwan: n
auto dhcp/dns registration: y
optimize for ipsec: n

## OPNsense intrusion detection
### enabled rules
`ET emerging-malware` — malware C2 traffic
`ET emerging-scan` — port/network scanners
`ET emerging-exploit` — known exploit patterns

![alt text](blacksun_test.png)
![alt text](BlackSun_test_alert.png)

![alt text](idstest.png)
![alt text](idstest_alert.png)