import json
import sys

obj = json.loads(sys.argv[1])

retObj = {}
for output in obj[0]: 
   retObj[output] = obj[0][output]['value']

print(json.dumps(retObj))