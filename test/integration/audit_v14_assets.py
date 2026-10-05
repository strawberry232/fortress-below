"""Audit original bytes, sheet geometry, timings and active asset roles."""
import argparse
import hashlib
import json
from pathlib import Path
from PIL import Image

def audit(project):
    profiles=json.loads((project/'game/data/monsters/animation_profiles.json').read_text(encoding='utf-8'))
    sources=json.loads((project/'game/data/animations/v14_asset_sources.json').read_text(encoding='utf-8'))
    metadata=json.loads((project/'game/data/animations/asset_metadata.json').read_text(encoding='utf-8'))
    failures=[]
    total=0
    for item in sources:
        source=Path(item['source']); target=project/item['target']
        if not source.exists() or not target.exists():
            failures.append('Missing original or adopted asset: '+item['target'])
            continue
        hashes=[hashlib.sha256(f.read_bytes()).hexdigest() for f in [source,target]]
        if len(set(hashes+[item['sha256'],item['source_sha256']]))!=1:
            failures.append('Byte identity failure: '+item['target'])
        total+=1
    actions=[]
    for kind,profile in profiles.items():
        for action,animation in profile['animations'].items():
            count=len(animation['durations_ms'])
            valid=count>1 and all(ms>0 for ms in animation['durations_ms']) and animation['loop']==(action in ['idle','walk'])
            for path in animation['paths']:
                with Image.open(project/path.removeprefix('res://')) as image:
                    expected=(profile['frame_size'][0]*(count if len(animation['paths'])==1 else 1),profile['frame_size'][1])
                    valid=valid and image.size==expected
            if not valid: failures.append('Invalid action geometry or timing: '+kind+'/'+action)
            actions.append({'kind':kind,'action':action,'frames':count,'duration_ms':sum(animation['durations_ms']),'loop':animation['loop'],'procedural_feedback':profile.get('procedural_feedback',False)})
    for item in metadata['assets']:
        if item['path'] in ['res://game/assets/tiny_swords/torch.png','res://game/assets/tiny_swords/tnt.png']:
            if item.get('current_roles') or item.get('current_usage')!='retired_unused':
                failures.append('Retired goblin has an active role: '+item['path'])
    with Image.open(project/'game/assets/tiny_swords/wood_tower.png') as wood:
        wood_bounds=[wood.crop((i*256,0,(i+1)*256,192)).getbbox() for i in range(4)]
    return {'original_files_checked':total,'metadata_records':len(metadata['assets']),'action_profiles_checked':len(actions),'failures':failures,'actions':actions,'wood_alpha_bounds':wood_bounds,'original_files':sources}

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project',type=Path,default=Path.cwd())
    parser.add_argument('--out',type=Path,required=True)
    args=parser.parse_args(); result=audit(args.project)
    args.out.parent.mkdir(parents=True,exist_ok=True)
    args.out.write_text(json.dumps(result,indent=2,ensure_ascii=True)+'\n',encoding='utf-8')
    print(json.dumps({k:result[k] for k in ['original_files_checked','metadata_records','action_profiles_checked','failures']}))
    return 1 if result['failures'] else 0

if __name__=='__main__':
    raise SystemExit(main())
