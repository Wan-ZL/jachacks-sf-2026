import json
data = json.load(open('seed_data.json'))
with open('seed_corpus.py', 'w') as f:
    f.write('"""Demo seed corpus compiled into code (regenerated from seed_data.json)."""\n\nDATA = ')
    f.write(repr(data))
    f.write('\n')
print('regenerated seed_corpus.py')
