from pathlib import Path
from json import load

json = Path(__file__).parent / 'pores_n_chemistry.json'
with open(json, 'r') as j:
    d = load(j)
    print(type(d), d)