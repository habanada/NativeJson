import json, random, sys
import cbor2
from harness import Tool, rnd_value, has_bigkey, has_nonunique_keys

r = random.Random(int(sys.argv[2]))
tool = Tool('int det len')
n = bad = 0
for i in range(int(sys.argv[1])):
    v = rnd_value(r, 0, False, False, True)
    if has_nonunique_keys(v) or has_bigkey(v): continue
    text = json.dumps(v, ensure_ascii=True)
    want = cbor2.dumps(v, canonical=True).hex()
    got = tool.call('E', text)
    n += 1
    if got != 'OK ' + want:
        bad += 1
        if bad < 6: print('DIFF', text[:200], '\n  ours', got[:200], '\n  cbor2', want[:200])
print('canonical bytes vs cbor2:', n, 'checked,', bad, 'differ')
