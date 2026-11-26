#!/usr/bin/python
# -*- coding: utf-8 -*-
"""Download running/startup config from an HPE Instant On 1830 over its web UI.

The 1830 has no CLI, SSH or API. This replays what the web UI does:
  1. GET /                                  -> redirect to /cs<hex>/hpe/config/login.htm (session path prefix)
  2. GET /device/wcd?{EncryptionSetting}    -> RSA public key (PKCS#1 PEM) + one-time login token
  3. GET /<prefix>/hpe/config/system.xml?action=login&cred=<hex(RSA-PKCS1v15(user=..&password=..&ssd=true&token=..&))>
  4. GET /<prefix>/hpe/http_download?action=2&ssd=4 (running) / action=3 (startup)
  5. GET /System.xml?action=logout          (gracefulLogout() in js/modules.js)
Undocumented, so a firmware update may break it.
"""

from __future__ import annotations

DOCUMENTATION = r"""
module: instanton_config
short_description: Fetch running and startup config from an HPE Instant On 1830 switch
description: Logs in to the local web UI and downloads both configs. Read-only, never reports changed.
options:
  host: {description: Switch address., type: str, required: true}
  username: {description: Web UI user., type: str, required: true}
  password: {description: Web UI password., type: str, required: true, no_log: true}
  timeout: {description: Per-request timeout in seconds., type: int, default: 15}
"""

RETURN = r"""
running_config: {description: Running config text., type: str, returned: success}
startup_config: {description: Startup config text., type: str, returned: success}
in_sync: {description: Whether running and startup config match, ignoring the device key blocks., type: bool, returned: success}
"""

import binascii
import re
import xml.etree.ElementTree as ET
from http.cookiejar import Cookie, CookieJar
from urllib.parse import quote, urlparse

from ansible.module_utils.basic import AnsibleModule
from ansible.module_utils.urls import Request

try:
    from cryptography.hazmat.primitives.asymmetric import padding
    from cryptography.hazmat.primitives.serialization import load_pem_public_key
    HAS_CRYPTOGRAPHY = True
except ImportError:
    HAS_CRYPTOGRAPHY = False


# Running config ends with the device's SSH host keys and HTTPS certificates, which the
# startup config export leaves out. Each block runs from its header to a line with a single '.'.
KEY_BLOCK = re.compile(r'^(?:ip ssh-client key|crypto certificate) .*?^\.$\n?', re.M | re.S)


def without_keys(config):
    return KEY_BLOCK.sub('', config)


def _cookie(name, value, host):
    return Cookie(0, name, value, None, False, host, False, False, '/', True, False,
                  None, False, None, None, {})


class Switch:
    def __init__(self, host, username, password, timeout):
        self.base = f'http://{host}'
        self.username = username
        self.password = password
        jar = CookieJar()
        # The web UI sets these client-side; the login handler expects them.
        for name, value in (('activeLangId', 'english'), ('firstWelcomeBanner', 'true'), ('userName', username)):
            jar.set_cookie(_cookie(name, value, host))
        self.req = Request(cookies=jar, timeout=timeout, validate_certs=False,
                           headers={'Accept': 'application/xml, text/xml, text/plain, */*'})
        self.prefix = None

    def get(self, path):
        resp = self.req.open('GET', self.base + path)
        return resp.geturl(), resp.read().decode('utf-8', errors='replace')

    def login(self):
        url, _ = self.get('/')
        self.prefix = urlparse(url).path.split('/hpe/')[0]
        if not self.prefix:
            raise RuntimeError(f'unexpected landing URL {url}')

        _, xml = self.get('/device/wcd?' + quote('{EncryptionSetting}'))
        root = ET.fromstring(xml)
        if root.findtext('.//passwEncryptEnable') == '1':
            key = load_pem_public_key(root.findtext('.//rsaPublicKey').strip().encode())
            token = root.findtext('.//loginToken')
            plain = f'user={self.username}&password={self.password}&ssd=true&token={token}&'
            cred = binascii.hexlify(key.encrypt(plain.encode(), padding.PKCS1v15())).decode()
            query = f'cred={cred}'
        else:
            query = f'user={quote(self.username)}&password={quote(self.password)}&ssd=true&'

        _, xml = self.get(f'{self.prefix}/hpe/config/system.xml?action=login&{query}')
        status = ET.fromstring(xml).findtext('.//statusString')
        if status != 'OK':
            raise RuntimeError(f'login failed: {status or xml[:200]}')

    def download(self, action):
        # Without a valid session the switch redirects to login.htm instead of failing.
        url, text = self.get(f'{self.prefix}/hpe/http_download?action={action}&ssd=4')
        if not text.startswith('config-file-header'):
            raise RuntimeError(f'config download (action={action}) returned no config (landed on {url})')
        return text

    def logout(self):
        try:
            self.get('/System.xml?action=logout')
        except Exception:
            pass


def main():
    module = AnsibleModule(
        argument_spec=dict(
            host=dict(type='str', required=True),
            username=dict(type='str', required=True),
            password=dict(type='str', required=True, no_log=True),
            timeout=dict(type='int', default=15),
        ),
        supports_check_mode=True,
    )
    if not HAS_CRYPTOGRAPHY:
        module.fail_json(msg='the cryptography Python package is required')

    p = module.params
    switch = Switch(p['host'], p['username'], p['password'], p['timeout'])
    try:
        switch.login()
        try:
            running = switch.download(2)
            startup = switch.download(3)
        finally:
            switch.logout()
    except Exception as e:
        module.fail_json(msg=f"{p['host']}: {e}")

    module.exit_json(changed=False, running_config=running, startup_config=startup,
                     in_sync=without_keys(running) == without_keys(startup))


if __name__ == '__main__':
    main()
