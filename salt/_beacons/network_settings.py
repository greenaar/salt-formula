"""
Beacon to monitor network adapter setting changes on Linux

.. versionadded:: 2016.3.0

Local override of the bundled ``network_settings`` beacon.

The bundled version instantiates ``NDB()`` at module import time and never
closes it. Salt's LazyLoader re-executes beacon modules whenever the beacon
loader is rebuilt (grain refresh, sync_beacons, highstate), so every refresh
constructs a fresh NDB -- each with its own thread, netlink socket and
in-memory SQLite database -- and orphans the previous one. Nothing holds a
reference to the old instance, so its thread runs forever. The threads
accumulate, contend on the GIL, and the minion's CPU climbs steadily with
uptime until a restart resets it.

This version keeps the imports at module scope (so ``__virtual__`` behaves
identically) but defers instantiation until the beacon is actually used, and
caches the instance process-wide so repeated re-imports reuse one object.

If this beacon is not configured, no NDB is ever created at all.
"""

import ast
import logging
import re
import sys

import salt.loader
import salt.utils.beacons

# Importing is cheap and side-effect free; only instantiation is expensive.
# first choice: NDB + compat adapter, requires pyroute2 >= 0.7.1
try:
    from pyroute2 import NDB
    from pyroute2.ndb.compat import ipdb_interfaces_view

    HAS_PYROUTE2 = True
    HAS_NDB = True
except ImportError:
    NDB = None
    ipdb_interfaces_view = None
    HAS_PYROUTE2 = False
    HAS_NDB = False

# backup choice: legacy IPDB, may be dropped in future pyroute2 releases
try:
    from pyroute2 import IPDB

    HAS_PYROUTE2 = True
except ImportError:
    IPDB = None
    # NOTE: deliberately does NOT clear HAS_PYROUTE2 here. The bundled module
    # sets ``IP = None`` in this branch, which wipes a perfectly good NDB
    # instance when pyroute2 ships without IPDB -- leaving HAS_PYROUTE2 True
    # and IP None, so beacon() then fails on a None handle.


log = logging.getLogger(__name__)

__virtualname__ = "network_settings"

# Process-wide handle. Stashed on ``sys`` rather than in a module global
# because the loader re-executes this module on every refresh, which would
# reset a plain global and construct a second NDB. ``sys`` is a true
# per-process singleton and is never re-executed.
_IP_CACHE_ATTR = "_salt_network_settings_ndb"

ATTRS = [
    "family",
    "txqlen",
    "ipdb_scope",
    "index",
    "operstate",
    "group",
    "carrier_changes",
    "ipaddr",
    "neighbours",
    "ifname",
    "promiscuity",
    "linkmode",
    "broadcast",
    "address",
    "num_tx_queues",
    "ipdb_priority",
    "kind",
    "qdisc",
    "mtu",
    "num_rx_queues",
    "carrier",
    "flags",
    "ifi_type",
    "ports",
]

LAST_STATS = {}


class Hashabledict(dict):
    """
    Helper class that implements a hash function for a dictionary
    """

    def __hash__(self):
        return hash(tuple(sorted(self.items())))


def _get_ip():
    """
    Return the process-wide NDB (or legacy IPDB) handle, creating it on first
    use. Returns None if neither is available.
    """
    ip = getattr(sys, _IP_CACHE_ATTR, None)
    if ip is not None:
        return ip

    try:
        if HAS_NDB:
            ip = NDB()
        elif IPDB is not None:
            ip = IPDB()
        else:
            return None
    except Exception:  # pylint: disable=broad-except
        log.error("Unable to initialise pyroute2 handle", exc_info=True)
        return None

    setattr(sys, _IP_CACHE_ATTR, ip)
    return ip


def __virtual__():
    if HAS_PYROUTE2:
        return __virtualname__
    err_msg = "pyroute2 library is missing"
    log.error("Unable to load %s beacon: %s", __virtualname__, err_msg)
    return False, err_msg


def validate(config):
    """
    Validate the beacon configuration
    """
    if not isinstance(config, list):
        return False, "Configuration for network_settings beacon must be a list."
    else:
        config = salt.utils.beacons.list_to_dict(config)

        interfaces = config.get("interfaces", {})
        if isinstance(interfaces, list):
            # Old syntax
            return (
                False,
                "interfaces section for network_settings beacon must be a dictionary.",
            )

        for item in interfaces:
            if not isinstance(config["interfaces"][item], dict):
                return (
                    False,
                    "Interface attributes for network_settings beacon"
                    " must be a dictionary.",
                )
            if not all(j in ATTRS for j in config["interfaces"][item]):
                return False, "Invalid attributes in beacon configuration."
    return True, "Valid beacon configuration"


def _copy_interfaces_info(interfaces):
    """
    Return a dictionary with a copy of each interface attributes in ATTRS
    """
    ret = {}

    for interface in interfaces:
        _interface_attrs_cpy = set()
        for attr in ATTRS:
            if attr in interfaces[interface]:
                attr_dict = Hashabledict()
                attr_dict[attr] = repr(interfaces[interface][attr])
                _interface_attrs_cpy.add(attr_dict)
        ret[interface] = _interface_attrs_cpy

    return ret


def beacon(config):
    """
    Watch for changes on network settings

    By default, the beacon will emit when there is a value change on one of the
    settings on watch. The config also support the onvalue parameter for each
    setting, which instruct the beacon to only emit if the setting changed to
    the value defined.

    Example Config

    .. code-block:: yaml

        beacons:
          network_settings:
            - interfaces:
                eth0:
                  ipaddr:
                  promiscuity:
                    onvalue: 1
                eth1:
                  linkmode:

    The config above will check for value changes on eth0 ipaddr and eth1 linkmode. It will also
    emit if the promiscuity value changes to 1.

    Beacon items can use the * wildcard to make a definition apply to several interfaces. For
    example an eth* would apply to all ethernet interfaces.

    Setting the argument coalesce = True will combine all the beacon results on a single event.
    The example below shows how to trigger coalesced results:

    .. code-block:: yaml

        beacons:
          network_settings:
            - coalesce: True
            - interfaces:
                eth0:
                  ipaddr:
                  promiscuity:

    """
    _config = salt.utils.beacons.list_to_dict(config)

    ret = []
    interfaces = []
    expanded_config = {"interfaces": {}}

    global LAST_STATS

    coalesce = False

    _ip = _get_ip()
    if _ip is None:
        log.error("network_settings beacon: no usable pyroute2 handle")
        return ret

    _stats = _copy_interfaces_info(
        ipdb_interfaces_view(_ip) if HAS_NDB else _ip.by_name
    )

    if not LAST_STATS:
        LAST_STATS = _stats

    if "coalesce" in _config and _config["coalesce"]:
        coalesce = True
        changes = {}

    log.debug("_stats %s", _stats)
    # Get list of interfaces included in config that are registered in the
    # system, including interfaces defined by wildcards (eth*, wlan*)
    for interface_config in _config.get("interfaces", {}):
        if interface_config in _stats:
            interfaces.append(interface_config)
        else:
            # No direct match, try with * wildcard regexp
            for interface_stat in _stats:
                match = re.search(interface_config, interface_stat)
                if match:
                    interfaces.append(interface_stat)
                    expanded_config["interfaces"][interface_stat] = _config[
                        "interfaces"
                    ][interface_config]

    if expanded_config:
        _config["interfaces"].update(expanded_config["interfaces"])

        # config updated so update config
        _config = salt.utils.beacons.list_to_dict(config)

    log.debug("interfaces %s", interfaces)
    for interface in interfaces:
        _send_event = False
        _diff_stats = _stats[interface] - LAST_STATS[interface]
        _ret_diff = {}
        interface_config = _config["interfaces"][interface]

        log.debug("_diff_stats %s", _diff_stats)
        if _diff_stats:
            _diff_stats_dict = {}
            LAST_STATS[interface] = _stats[interface]

            for item in _diff_stats:
                _diff_stats_dict.update(item)
            for attr in interface_config:
                if attr in _diff_stats_dict:
                    config_value = None
                    if interface_config[attr] and "onvalue" in interface_config[attr]:
                        config_value = interface_config[attr]["onvalue"]
                    new_value = ast.literal_eval(_diff_stats_dict[attr])
                    if not config_value or config_value == new_value:
                        _send_event = True
                        _ret_diff[attr] = new_value

            if _send_event:
                if coalesce:
                    changes[interface] = _ret_diff
                else:
                    ret.append(
                        {"tag": interface, "interface": interface, "change": _ret_diff}
                    )

    if coalesce and changes:
        grains_info = salt.loader.grains(__opts__, True)
        __grains__.update(grains_info)
        ret.append({"tag": "result", "changes": changes})

    return ret