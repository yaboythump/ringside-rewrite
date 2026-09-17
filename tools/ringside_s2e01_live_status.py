#!/usr/bin/env python3
import os,time,requests,json
KEY=os.environ['RUNPOD_API_KEY']; AUTH={'Authorization':f'Bearer {KEY}'}
PID='ugt1pe6ndmichc'
query=f'''mutation {{ podResume(input: {{ podId: "{PID}", gpuCount: 1 }}) {{ id desiredStatus imageName machineId }} }}'''
g=requests.post('https://api.runpod.io/graphql',params={'api_key':KEY},headers={'Content-Type':'application/json'},json={'query':query},timeout=60)
print('GRAPHQL_HTTP',g.status_code,flush=True)
print('GRAPHQL_BODY',g.text[:4000],flush=True)
for i in range(1,13):
    r=requests.get(f'https://rest.runpod.io/v1/pods/{PID}',headers=AUTH,timeout=30)
    print('REST_HTTP',r.status_code,flush=True)
    if r.ok:
        pod=r.json(); print('POLL',i,'STATUS',pod.get('desiredStatus'),'MACHINE',pod.get('machineId'),'COST',pod.get('costPerHr'),flush=True)
        if pod.get('desiredStatus')=='RUNNING': raise SystemExit(0)
    time.sleep(5)
raise SystemExit('pod did not reach RUNNING')
