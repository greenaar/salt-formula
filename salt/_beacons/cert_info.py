"""
cert_info beacon (cryptography-based replacement)
===================================================

Drop-in replacement for Salt's built-in ``salt.beacons.cert_info``.

The stock beacon reads certificate extensions using pyOpenSSL's
``OpenSSL.crypto.X509.get_extensions()`` / ``OpenSSL.crypto.X509Extension``
APIs. Those were deprecated in pyOpenSSL 25.0 and removed entirely in
later releases, which breaks the beacon with:

    Unable to load cert_info beacon: pyOpenSSL >= 25 removed the
    X509Extension API used by this beacon.

This version uses the ``cryptography`` package instead (which pyOpenSSL
itself depends on and Salt already ships), so it keeps working regardless
of pyOpenSSL's version.

Deployment
----------
1. Save this file as ``cert_info.py`` inside a ``_beacons`` directory in
   one of your file_roots, e.g. ``/srv/salt/_beacons/cert_info.py``.
2. Sync it out to minions::

       salt '*' saltutil.sync_beacons

   Placing it under ``_beacons`` makes it override the built-in
   ``cert_info`` beacon of the same name, so no minion config changes
   are required.
3. Restart the minion (or re-run sync + saltutil.refresh_beacons) so the
   new module is picked up cleanly.

Configuration is unchanged from the stock beacon::

    beacons:
      cert_info:
        - files:
            - /etc/pki/tls/certs/mycert.pem
            - /etc/pki/tls/certs/yourcert.pem:
                notify_days: 15
        - notify_days: 45
        - interval: 86400

Event payload mirrors the original beacon's schema as closely as
possible: ``cert_path``, ``extensions`` (list of ``ext_name``/``ext_data``/
``ext_critical``), ``has_expired``, ``issuer``, ``issuer_dict``,
``subject``, ``subject_dict``, ``notAfter``, ``notAfter_raw``,
``notBefore``, ``notBefore_raw``, ``serial_number``,
``signature_algorithm``, ``days_remaining``, and ``notify_days``.

Note: the exact text formatting of ``ext_data`` for some extensions
(e.g. basicConstraints, keyUsage) may differ slightly from pyOpenSSL's
OpenSSL-CLI-style strings, since it's now generated from cryptography's
Python objects rather than OpenSSL's text renderer. subjectAltName is
special-cased to match the old "DNS:x, DNS:y" style since that's the
extension most commonly parsed downstream.
"""

import datetime
import logging
import os

log = logging.getLogger(__name__)

try:
    from cryptography import x509
    from cryptography.hazmat.backends import default_backend

    HAS_CRYPTOGRAPHY = True
except ImportError:
    HAS_CRYPTOGRAPHY = False

__virtualname__ = "cert_info"

DEFAULT_NOTIFY_DAYS = 45

# Map well-known Name attribute OIDs to the short RDN labels pyOpenSSL /
# OpenSSL CLI use (CN, O, OU, C, ST, L, emailAddress, ...) so issuer/subject
# dicts and strings match the old output.
_NAME_OID_SHORT = {
    "2.5.4.3": "CN",
    "2.5.4.6": "C",
    "2.5.4.7": "L",
    "2.5.4.8": "ST",
    "2.5.4.10": "O",
    "2.5.4.11": "OU",
    "1.2.840.113549.1.9.1": "emailAddress",
    "2.5.4.5": "serialNumber",
    "2.5.4.4": "SN",
    "2.5.4.42": "GN",
}

# Map well-known extension OIDs to the short names pyOpenSSL used to
# report, so downstream reactors matching on ext_name keep working.
_OID_NAME_MAP = {
    "2.5.29.14": "subjectKeyIdentifier",
    "2.5.29.15": "keyUsage",
    "2.5.29.17": "subjectAltName",
    "2.5.29.18": "issuerAltName",
    "2.5.29.19": "basicConstraints",
    "2.5.29.31": "cRLDistributionPoints",
    "2.5.29.32": "certificatePolicies",
    "2.5.29.35": "authorityKeyIdentifier",
    "2.5.29.37": "extendedKeyUsage",
    "1.3.6.1.5.5.7.1.1": "authorityInfoAccess",
    "2.5.29.9": "subjectDirectoryAttributes",
    "1.3.6.1.4.1.11129.2.4.2": "signedCertificateTimestampList",
}


def __virtual__():
    if not HAS_CRYPTOGRAPHY:
        return False, "The cryptography library is required for the cert_info beacon"
    return __virtualname__


def _list_to_dict(config):
    """
    Beacon configs arrive as a list of single-key (or multi-key) dicts.
    Flatten to a single dict for easy lookups, keeping 'files' as-is.
    """
    result = {}
    for item in config:
        if isinstance(item, dict):
            result.update(item)
    return result


def _normalize_files(files_cfg):
    """
    'files' entries can be plain path strings, or a one-key dict mapping
    a path to per-file options (e.g. {'/path/to/cert.pem': {'notify_days': 15}}).
    Returns a list of (path, per_file_opts) tuples.
    """
    normalized = []
    for entry in files_cfg or []:
        if isinstance(entry, str):
            normalized.append((entry, {}))
        elif isinstance(entry, dict):
            for path, opts in entry.items():
                normalized.append((path, opts or {}))
    return normalized


def validate(config):
    """
    Validate the beacon configuration.
    """
    if not isinstance(config, list):
        return False, "Configuration for cert_info beacon must be a list"

    config = _list_to_dict(config)

    if "files" not in config or not config["files"]:
        return False, "Configuration for cert_info beacon requires a 'files' list"

    for path, _opts in _normalize_files(config["files"]):
        if not isinstance(path, str):
            return False, "Each entry in 'files' must be a path string"

    return True, "Valid beacon configuration"


def _rdn_short(oid):
    return _NAME_OID_SHORT.get(oid.dotted_string) or (
        oid._name if hasattr(oid, "_name") and oid._name else oid.dotted_string
    )


def _name_to_dict(name):
    """Convert a cryptography x509.Name to a dict of RDN short-name -> value."""
    out = {}
    for attr in name:
        out[_rdn_short(attr.oid)] = attr.value
    return out


def _name_to_str(name):
    """Approximate pyOpenSSL's 'C="US",ST="Utah",CN="example.com"' style string."""
    parts = ['{}="{}"'.format(_rdn_short(attr.oid), attr.value) for attr in name]
    return ",".join(parts)


def _ext_name(oid):
    return _OID_NAME_MAP.get(oid.dotted_string) or (
        oid._name if hasattr(oid, "_name") and oid._name else oid.dotted_string
    )


def _ext_data(ext):
    """
    Render an extension's value as a string. Special-cases subjectAltName
    to match the old 'DNS:x, DNS:y' formatting most reactors parse.
    """
    try:
        if isinstance(ext.value, x509.SubjectAlternativeName):
            parts = []
            for gn in ext.value:
                if isinstance(gn, x509.DNSName):
                    parts.append("DNS:{}".format(gn.value))
                elif isinstance(gn, x509.IPAddress):
                    parts.append("IP Address:{}".format(gn.value))
                elif isinstance(gn, x509.RFC822Name):
                    parts.append("email:{}".format(gn.value))
                elif isinstance(gn, x509.UniformResourceIdentifier):
                    parts.append("URI:{}".format(gn.value))
                else:
                    parts.append(str(gn))
            return ", ".join(parts)
        return str(ext.value)
    except Exception as exc:  # noqa: BLE001 - defensive, extension parsing is best-effort
        log.debug("cert_info beacon: could not render extension %s: %s", ext.oid, exc)
        return repr(ext.value)


def _get_not_after(cert):
    # cryptography >= 42 deprecates not_valid_after in favor of the
    # timezone-aware not_valid_after_utc; support both.
    if hasattr(cert, "not_valid_after_utc"):
        return cert.not_valid_after_utc.replace(tzinfo=None)
    return cert.not_valid_after


def _get_not_before(cert):
    if hasattr(cert, "not_valid_before_utc"):
        return cert.not_valid_before_utc.replace(tzinfo=None)
    return cert.not_valid_before


def _load_cert(path):
    with open(path, "rb") as fp:
        data = fp.read()
    try:
        return x509.load_pem_x509_certificate(data, default_backend())
    except ValueError:
        return x509.load_der_x509_certificate(data, default_backend())


def beacon(config):
    """
    Monitor certificate files for expiration.

    Emits one event containing a 'certificates' list of any certificate
    that is within its notify_days threshold of expiring (or already
    expired), or always includes it if notify_days == -1.
    """
    config = _list_to_dict(config)
    global_notify_days = config.get("notify_days", DEFAULT_NOTIFY_DAYS)
    files_cfg = _normalize_files(config.get("files", []))

    ret = []
    certs_out = []
    now = datetime.datetime.utcnow()

    for path, opts in files_cfg:
        notify_days = opts.get("notify_days", global_notify_days)

        if not os.path.exists(path):
            log.warning("cert_info beacon: certificate file not found: %s", path)
            continue

        try:
            cert = _load_cert(path)
        except Exception as exc:  # noqa: BLE001
            log.error("cert_info beacon: failed to load certificate %s: %s", path, exc)
            continue

        not_after = _get_not_after(cert)
        not_before = _get_not_before(cert)
        days_remaining = (not_after - now).days
        has_expired = not_after < now

        if notify_days != -1 and days_remaining > notify_days:
            continue

        extensions = []
        for i in range(cert.extensions and len(cert.extensions) or 0):
            ext = cert.extensions[i]
            extensions.append(
                {
                    "ext_name": _ext_name(ext.oid),
                    "ext_data": _ext_data(ext),
                    "ext_critical": ext.critical,
                }
            )

        certs_out.append(
            {
                "cert_path": path,
                "extensions": extensions,
                "has_expired": has_expired,
                "issuer": _name_to_str(cert.issuer),
                "issuer_dict": _name_to_dict(cert.issuer),
                "subject": _name_to_str(cert.subject),
                "subject_dict": _name_to_dict(cert.subject),
                "notAfter": not_after.strftime("%Y-%m-%d %H:%M:%SZ"),
                "notAfter_raw": not_after.strftime("%Y%m%d%H%M%SZ"),
                "notBefore": not_before.strftime("%Y-%m-%d %H:%M:%SZ"),
                "notBefore_raw": not_before.strftime("%Y%m%d%H%M%SZ"),
                "serial_number": str(cert.serial_number),
                "signature_algorithm": cert.signature_algorithm_oid._name
                if hasattr(cert.signature_algorithm_oid, "_name")
                else cert.signature_algorithm_oid.dotted_string,
                "days_remaining": days_remaining,
                "notify_days": notify_days,
            }
        )

    if certs_out:
        ret.append({"certificates": certs_out})

    return ret

