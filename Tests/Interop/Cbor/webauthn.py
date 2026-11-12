import os, json, base64, struct, hashlib, sys
import cbor2
from harness import Tool, norm, parse_ours, b64u

def cose_key_ec2(x, y):
    return cbor2.dumps({1: 2, 3: -7, -1: 1, -2: x, -3: y}, canonical=True)

def auth_data(cred_id, key, ext=None):
    flags = 0x41 | (0x80 if ext else 0)
    head = hashlib.sha256(b'example.com').digest() + bytes([flags]) + struct.pack('>I', 42)
    att = os.urandom(16) + struct.pack('>H', len(cred_id)) + cred_id + key
    tail = cbor2.dumps(ext, canonical=True) if ext else b''
    return head + att + tail

ok = bad = 0
tool = Tool('int wrap')
for i in range(300):
    x, y = os.urandom(32), os.urandom(32)
    cred = os.urandom(16 + i % 48)
    key = cose_key_ec2(x, y)
    ext = {'credProtect': 2, 'hmac-secret': True} if i % 3 == 0 else None
    ad = auth_data(cred, key, ext)
    stmt = {'alg': -7, 'sig': os.urandom(70 + i % 3)}
    if i % 2: stmt['x5c'] = [os.urandom(300), os.urandom(200)]
    att = cbor2.dumps({'fmt': 'packed', 'attStmt': stmt, 'authData': ad}, canonical=True)
    reply = tool.call('D', att.hex())
    j = parse_ours(reply[3:])
    good = j == norm(cbor2.loads(att))
    back = tool.call('E', json.dumps(json.loads(reply[3:]), ensure_ascii=True))
    good = good and back == 'OK ' + att.hex()
    ad_bytes = base64.urlsafe_b64decode(j['authData']['@bytes'] + '=' * (-len(j['authData']['@bytes']) % 4))
    good = good and ad_bytes == ad
    off = 37 + 16 + 2 + len(cred)
    seq = tool.call('S', ad_bytes[off:].hex())
    items = parse_ours(seq[3:])
    want = [norm(cbor2.loads(key))] + ([norm(ext)] if ext else [])
    good = good and items == want
    keyback = tool.call('E', json.dumps(json.loads(seq[3:])[0], ensure_ascii=True))
    good = good and keyback == 'OK ' + key.hex()
    if good: ok += 1
    else:
        bad += 1
        if bad < 4: print('FAIL', i, reply[:200], back[:100], seq[:200])
print('WebAuthn attestation objects:', ok + bad, 'checked,', bad, 'failed')
