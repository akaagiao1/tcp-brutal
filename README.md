# <img src="logo.png" width="400">

TCP Brutal is [Hysteria](https://hysteria.network/)'s congestion control algorithm ported to TCP, as a Linux kernel module. Information about Brutal itself can be found in the [Hysteria documentation](https://hysteria.network/docs/advanced/Full-Server-Config/#bandwidth-behavior-explained).

The upstream TCP Brutal project is an official Hysteria subproject. This fork adds Alpine installation support.

**中文文档：[README.zh.md](README.zh.md)**


## Cross-distribution installer (this fork)

Supports Alpine, Debian/Ubuntu and CentOS/RHEL/Rocky/AlmaLinux using apk, apt-get or dnf/yum. Linux **5.10+**, matching kernel development files and permission to load modules are required. Stock CentOS 7/8 kernels are too old for v2.

Install Bash, curl and CA certificates with your package manager, then run as root:

```sh
curl -fL https://raw.githubusercontent.com/akaagiao1/tcp-brutal/master/scripts/install.sh -o install.sh
bash install.sh
```

Installs the module, brutalctl and full iproute tools. A loaded v2 module is reused. Successful installation prompts for client public IPv4 or CIDR and Mbps, applies the rule, and saves it in `/etc/tcp-brutal/rules.conf`. OpenRC (Alpine) or systemd restores saved rules at boot. Run the new configuration step once to save rules from older installations.

Use `bash install.sh tools` to repair tools, or `bash install.sh configure` to open the rule menu. With the module and tool already available, running without arguments opens the menu instead of reinstalling. The interactive add prompt defaults to `0.0.0.0/0`; press Enter at the target prompt, then enter Mbps. This applies one shared rate to all matching IPv4 TCP destinations and is intended for a VPS dedicated to one user. Unattended execution skips configuration. Reconnect clients after adding rules.

The `/0` rule is implemented with managed `0.0.0.0/1` and `128.0.0.0/1` routes, covering all IPv4 without replacing the system-owned default route. `brutalctl list` should report `ROUTE yes` for `/0`; `ROUTE no` means the rule is not selecting Brutal for connections.

Use `bash install.sh add IP Mbps` to add/update, `bash install.sh delete IP` to remove both the live and saved rule, `bash install.sh delete 0` to remove all rules, and `bash install.sh list` to view both. The delete menu numbers all live and saved rules; select a number to remove one or enter 0 to remove all. Deleting does not interrupt existing TCP connections; reconnect to stop using their old parameters. Check for duplicate rules in an older manually created `/etc/local.d/brutal-rules.start` when migrating. Service: `tcp-brutal-rules` (systemctl / rc-service).

Kernel upgrades still require rerunning installation to build the module for the new kernel; this installer does not use DKMS or automatically upgrade/reboot. Rule persistence does not rebuild modules. Container tests cover dependencies, builds and rule logic; real VPS loading/reboot/throughput remain separate verification. See [Linux CI](https://github.com/akaagiao1/tcp-brutal/actions/workflows/linux.yml) and [Chinese instructions](README.zh.md).

When an older v1 DKMS module exists under `updates/dkms`, the installer adds a depmod override selecting the newly installed v2 module under `extra`, preserves the old file for rollback, and verifies that the loaded version is 2.x.

IPv4 CIDR is supported throughout add, update, delete and boot restoration. Bare input such as `223.80.170.224` defaults to `223.80.170.0/24`; explicitly enter `223.80.170.224/32` to match one address. Host bits are normalized. Legacy bare-IP entries already stored by older releases retain their original /32 meaning, while new entries are always saved as explicit CIDR.

Example: `bash install.sh add 223.80.170.224 50` saves `223.80.170.0/24`. Overlapping rules use longest-prefix matching; remove an old /32 explicitly if replacing it with a /24. An ISP address change is not guaranteed to remain within that subnet. /0 matches all IPv4 destinations.

The `/0` value is the interactive default only. Bare IPv4 passed to the direct `add` command still becomes `/24`. Remove the default rule with `bash install.sh delete 0.0.0.0/0`.

---

> **New in v2:** TCP Brutal no longer needs special support from the application. Set a rate for a destination once, and every connection to it uses Brutal, any program, any TCP-based protocol. Stop waiting and use it right now!

## Quick start

### Upstream installer (other distributions)

```bash
bash <(curl -fsSL https://tcp.hy2.sh/)
```

This installs the kernel module through DKMS and the `brutalctl` tool to `/usr/local/bin`. Linux 5.10 or later is required.

On NixOS with flakes, add the module to your `flake.nix`; it provides `brutalctl` as well:

```nix
{
  inputs.tcp-brutal.url = "github:HyNetworks/tcp-brutal";
  
  outputs = { nixpkgs, tcp-brutal, ... }: {
    nixosConfigurations.myHost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        # ... your configuration.nix ...
        tcp-brutal.nixosModules.default
        { boot.tcp-brutal.enable = true; }
      ];
    };
  };
}
```

### Use it for a destination

Run this on the side that sends the data. For downloads from your server, that is the server:

```bash
# Everything sent to 203.0.113.5 shares 100 Mbps, whichever program sends it
brutalctl add 203.0.113.5/32 100
```

The number is the total for all connections to that destination, which should be what the receiving side's link can actually take. A single active connection gets all of it; several share it. No application support is needed: a plain web server, proxy tool, rsync or SSH to that address is covered.

```bash
brutalctl list                   # rules, and how many connections each one has right now
brutalctl add 203.0.113.5/32 50  # change the rate; existing connections follow immediately
brutalctl del 203.0.113.5/32
brutalctl flush
```

**A connection picks up a rule only when it is established, so add rules before making the connections that should use them; running programs need no restart, but their existing connections are unaffected. After that, `add` on the same prefix changes the rate live for every connection in the group, and `del` stops new connections from matching while existing ones keep the old rate until they close.**

Rules do not survive a reboot; put the `add` commands in a boot script if needed.

### Check that it works

Download something from the server and watch the rate, or use the speed test in [example](example): the client opens several connections that share one rate as a group.

```bash
# Server, listening on TCP port 1234
python server.py -p 1234

# Client, connect to example.com:1234, download at 50 Mbps in total
# over 4 connections (-n) for 10 seconds (-t)
python client.py -p 1234 example.com 50
```

The example speaks to the module directly and works without a rule. **With a rule for the client's address in place, the rule's rate wins.**

## How it works

**Brutal sends at the rate you set.** It does not probe for bandwidth like cubic or BBR. It paces packets at the configured rate, and when packets are lost it sends more so that the delivered rate stays at the target. This assumes you know the bandwidth of the path; set it too high and you only produce loss.

**It works on one side.** Brutal controls sending, and the TCP protocol on the wire is unchanged, so the other end needs nothing. Proxy users mostly download, so running it on the server alone gives most of the benefit.

**Groups.** Connections in a group share one rate as their total. Bandwidth is not divided statically: whoever is sending gets it, and a connection that uses less than its share leaves the rest to the others. Groups are formed in two ways: by a destination rule (above), or by an application that sets a group id on its sockets (below).

**Rules.** A rule maps a destination prefix to a group. Two things are needed for it to take effect, and `brutalctl` does both: the rule itself, kept by the module in `/proc/net/tcp_brutal/rules`, and a route that makes the kernel pick brutal for new connections to that prefix, the same as `ip route replace <prefix> via <gateway> congctl lock brutal proto 233` with the next hop copied from the current routing table. Routes it creates carry `proto 233`, so `ip route show proto 233` lists them and `brutalctl` never touches other routes. Use `noroute` if you manage the route yourself, for example when the destination is reached through a policy routing table. When several rules match, the longest prefix wins.

**Rules apply to new connections.** A connection joins a rule's group when it is established. Adding a rule does not affect connections that already exist; changing a rule's rate with `add` updates its group live; deleting a rule leaves its existing connections sharing the old rate until they close, while new ones no longer match.

**Locked by default.** With the route's `lock` and the rule together, applications cannot change the algorithm or the rate on those connections. An application that itself supports TCP Brutal gets `EPERM` when it tries and should simply carry on. Add the rule with `nolock` if applications should be allowed to set their own params instead.

**Do not set brutal as the system default congestion control.** A connection with no rule and no application settings runs at 1 Mbps. Applications that support TCP Brutal enable it on their own sockets, and rules cover everything else, so there is no reason to make it the default.

## For developers

### Enabling it on a socket

```python
s.setsockopt(socket.IPPROTO_TCP, TCP_CONGESTION, "brutal".encode())
```

Then set the send rate, the congestion window gain (1.5x to 2x recommended, written as 15 or 20 since the kernel has no floating point) and optionally a group:

```c
struct brutal_params
{
    u64 rate;      // Send rate in bytes per second
    u32 cwnd_gain; // CWND gain in tenths (10=1.0)
    u64 group_id;  // 0 = rate applies to this connection only (v1 behavior)
} __packed;
```

```python
TCP_BRUTAL_PARAMS = 23301

rate = 2000000 # 2 MB/s
cwnd_gain = 15
group_id = 42
brutal_params_value = struct.pack("<QIQ", rate, cwnd_gain, group_id)
conn.setsockopt(socket.IPPROTO_TCP, TCP_BRUTAL_PARAMS, brutal_params_value)
```

The 12-byte v1 struct without `group_id` is still accepted. The same option can be read back with getsockopt; a group member reports the group's rate, cwnd_gain and group_id:

```python
rate, cwnd_gain, group_id = struct.unpack("<QIQ", conn.getsockopt(socket.IPPROTO_TCP, TCP_BRUTAL_PARAMS, 20))
```

To check which module is loaded, read its version on a connection that already uses brutal. v1 modules, and plain TCP sockets, fail with `ENOPROTOOPT`:

```python
TCP_BRUTAL_VERSION = 23302

# u32: major << 16 | minor << 8 | patch
version = struct.unpack("<I", conn.getsockopt(socket.IPPROTO_TCP, TCP_BRUTAL_VERSION, 4))[0]
supports_groups = version >= 0x020000
```

### Groups

All connections that set the same non-zero `group_id`, from the same user and network namespace, share `rate` as their total. Setting params on any member updates the whole group. A group exists as long as one member is open.

A proxy server typically puts all connections of one client into one group keyed by that client's identity, so the client's bandwidth setting holds across all of its connections. TCP Brutal v1 had no groups, so it was only usable with protocols that multiplex everything into a single TCP connection; with groups, one-connection-per-stream protocols work too.

### Rules and applications

On a connection covered by a locked rule, `TCP_BRUTAL_PARAMS` returns `EPERM`, and because the route is locked, so does `setsockopt(TCP_CONGESTION, "brutal")` even though brutal is already active. Handle both: on `EPERM`, check the current algorithm with `getsockopt(TCP_CONGESTION)`, and if it is brutal, just send. [example/server.py](example/server.py) shows this.

Tools can use the rules file directly instead of `brutalctl`. Reading `/proc/net/tcp_brutal/rules` gives one rule per line as `key=value` pairs with live counters:

```
dst=203.0.113.5/32 rate=12500000 gain=20 lock=1 id=1 members=3 sent=1834021376
```

Writing accepts one command per write, with the rate in bytes per second: `add <prefix>[/<len>] rate=<bytes/s> [gain=<tenths>] [nolock]`, `del <prefix>[/<len>]` and `flush`. `add` on an existing prefix updates it in place. The route is a separate step, which is what `brutalctl` adds on top.

### Exchanging bandwidth in a proxy protocol

Brutal needs to know the bandwidth, and most TCP proxy protocols have no way for the client and server to exchange it. We suggest using the "destination address" field that every proxy protocol has: a client that supports TCP Brutal requests a connection to a special address such as `_BrutalBwExchange`, and if the server accepts, both sides exchange their bandwidth over that connection.

### Building from source

```bash
make && make load   # kernel headers required, e.g. apt install linux-headers-$(uname -r)
make -C tools       # brutalctl
```
