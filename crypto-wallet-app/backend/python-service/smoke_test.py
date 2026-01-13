import requests

BASE = 'http://localhost:8000'

r = requests.post(BASE + '/generate')
print('generate', r.status_code, r.text)
kp = r.json()

r2 = requests.post(BASE + '/sign', json={'privateKey': kp['privateKey'], 'message': 'hello'})
print('sign', r2.status_code, r2.text)
sig = r2.json()['signature']

r3 = requests.post(BASE + '/verify', json={'publicKey': kp['publicKey'], 'message': 'hello', 'signature': sig})
print('verify', r3.status_code, r3.text)
