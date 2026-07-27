import json
data = json.load(open('seed_data.json'))
with open('seed_corpus.jac', 'w') as f:
    f.write('"""Demo seed corpus compiled into code (regenerated from seed_data.json).\n'
            'Deploy packaging drops loose data files; a module is always shipped -\n'
            'and the demo corpus is part of the graph program, so it lives in Jac."""\n\n'
            'glob DATA: dict = ')
    f.write(repr(data))
    f.write(';\n\ndef get_data() -> dict {\n    return DATA;\n}\n')
print('regenerated seed_corpus.jac')
