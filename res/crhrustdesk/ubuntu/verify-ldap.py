"""Read-only check of the configured AD bind and one account lookup."""

import json
import argparse
import socket
import stat
from pathlib import Path


def tlv(tag, data):
    size = len(data)
    if size < 128:
        length = bytes([size])
    else:
        encoded = size.to_bytes((size.bit_length() + 7) // 8, 'big')
        length = bytes([128 + len(encoded)]) + encoded
    return bytes([tag]) + length + data


def text(value):
    return tlv(4, value.encode('utf-8'))


def integer(value, tag=2):
    data = value.to_bytes(max(1, (value.bit_length() + 7) // 8), 'big')
    if data[0] & 128:
        data = b'\0' + data
    return tlv(tag, data)


def fields(data):
    offset = 0
    while offset < len(data):
        tag, size = data[offset:offset + 2]
        offset += 2
        if size & 128:
            width = size & 127
            if not 1 <= width <= 4:
                raise RuntimeError('Invalid LDAP length')
            size = int.from_bytes(data[offset:offset + width], 'big')
            offset += width
        if offset + size > len(data):
            raise RuntimeError('Incomplete LDAP response')
        yield tag, data[offset:offset + size]
        offset += size


def read_exact(connection, size):
    data = b''
    while len(data) < size:
        part = connection.recv(size - len(data))
        if not part:
            raise RuntimeError('AD closed the LDAP connection')
        data += part
    return data


def receive(connection, message_id):
    header = read_exact(connection, 2)
    if header[0] != 48:
        raise RuntimeError('Invalid LDAP message')
    size = header[1]
    if size & 128:
        width = size & 127
        if not 1 <= width <= 4:
            raise RuntimeError('Invalid LDAP frame length')
        size = int.from_bytes(read_exact(connection, width), 'big')
    if size > 1024 * 1024:
        raise RuntimeError('LDAP response exceeds the verification limit')
    parts = list(fields(read_exact(connection, size)))
    if parts[0][0] != 2 or int.from_bytes(parts[0][1], 'big') != message_id:
        raise RuntimeError('Unexpected LDAP message ID')
    return parts[1]


def check_result(data, operation):
    tag, code = next(fields(data))
    if tag != 10:
        raise RuntimeError('Invalid LDAP result')
    code = int.from_bytes(code, 'big')
    if code:
        raise RuntimeError(operation + ' failed with LDAP result code ' + str(code))


def verify(bind_user, account):
    path = Path('/etc/crhrustdesk/ldap.env')
    info = path.stat()
    if info.st_uid != 0 or stat.S_IMODE(info.st_mode) & 0o077:
        raise RuntimeError('AD secret file must be root-owned and private')
    values = [line.split('=', 1)[1] for line in path.read_text().splitlines()
              if line.startswith('RUSTDESK_API_LDAP_BIND_PASSWORD=')]
    if len(values) != 1:
        raise RuntimeError('AD bind password is missing or ambiguous')
    password = json.loads(values[0])
    if not isinstance(password, str) or not password:
        raise RuntimeError('AD bind password is empty or invalid')
    with socket.create_connection(('172.16.1.10', 389), timeout=5) as connection:
        bind = integer(3) + text(bind_user) + tlv(128, password.encode('utf-8'))
        connection.sendall(tlv(48, integer(1) + tlv(96, bind)))
        tag, result = receive(connection, 1)
        if tag != 97:
            raise RuntimeError('AD did not return a bind result')
        check_result(result, 'Service-account bind')
        print('AD service-account bind succeeded', flush=True)
        equality = tlv(163, text('sAMAccountName') + text(account))
        query = text('DC=crhdomain,DC=local') + integer(2, 10) + integer(0, 10)
        query += integer(2) + integer(5) + tlv(1, b'\0') + equality
        query += tlv(48, text('sAMAccountName') + text('userAccountControl'))
        connection.sendall(tlv(48, integer(2) + tlv(99, query)))
        accounts = []
        while True:
            tag, result = receive(connection, 2)
            if tag == 101:
                check_result(result, 'Directory search')
                break
            if tag == 115:
                continue
            if tag != 100 or len(accounts) >= 2:
                raise RuntimeError('Unexpected directory search response')
            entry = list(fields(result))
            attributes = {}
            for _, attribute in fields(entry[1][1]):
                parts = list(fields(attribute))
                attributes[parts[0][1].decode('utf-8')] = [
                    value.decode('utf-8') for _, value in fields(parts[1][1])]
            accounts.append(attributes)
        if len(accounts) != 1:
            raise RuntimeError('Expected exactly one service account in the configured AD base')
        account = accounts[0]
        enabled = not (int(account['userAccountControl'][0]) & 2)
        if not enabled:
            raise RuntimeError('The AD service account is disabled')
        print('AD directory search succeeded; sAMAccountName and userAccountControl are readable')
        print('Service account is enabled. Password was not displayed or copied.')
        connection.sendall(tlv(48, integer(3) + tlv(66, b'')))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--bind-user', required=True)
    parser.add_argument('--account', required=True)
    args = parser.parse_args()
    try:
        verify(args.bind_user, args.account)
    except RuntimeError as error:
        raise SystemExit(str(error)) from None
    except Exception as error:
        raise SystemExit('LDAP verification failed (' + type(error).__name__ + ')') from None
