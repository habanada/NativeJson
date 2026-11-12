import concurrent.futures as cf, json, os, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, 'cose-examples')
API = 'https://api.github.com/repos/cose-wg/Examples/git/trees/master?recursive=1'
RAW = 'https://raw.githubusercontent.com/cose-wg/Examples/master/'

os.makedirs(OUT, exist_ok=True)
tree = json.loads(urllib.request.urlopen(API, timeout=30).read())
paths = [x['path'] for x in tree['tree'] if x['path'].endswith('.json')]


def get(path):
    data = urllib.request.urlopen(RAW + path, timeout=30).read()
    with open(os.path.join(OUT, path.replace('/', '__')), 'wb') as f:
        f.write(data)


with cf.ThreadPoolExecutor(16) as pool:
    list(pool.map(get, paths))
print(len(paths), 'files in', OUT)
