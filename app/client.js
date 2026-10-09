const $ = id => document.getElementById(id);
let total=0,success=0,elapsed=0,events=[],counts=new Map(),running=false;
function render(){
  $('total').textContent=total;
  $('pods').textContent=counts.size;
  $('latency').textContent=success ? Math.round(elapsed/success) : '--';
  $('success').textContent=total ? Math.round(success/total*100)+'%' : '--';
  $('stream-count').textContent=total+' events';
  if(counts.size){
    $('distribution').replaceChildren();
    [...counts.entries()].sort(([a],[b])=>a.localeCompare(b)).forEach(([pod,value],index)=>{
      const row=document.createElement('div');row.className='pod-row';
      const top=document.createElement('div');top.className='pod-top';
      const name=document.createElement('span');name.className='pod-name';name.textContent=pod;
      const share=document.createElement('span');share.className='pod-share';share.textContent=value.count+' requests / '+Math.round(value.count/success*100)+'%';
      top.append(name,share);
      const track=document.createElement('div');track.className='track';
      const fill=document.createElement('div');fill.className='fill';fill.dataset.index=index%3;fill.style.width=value.count/success*100+'%';track.append(fill);
      const version=document.createElement('div');version.className='version';version.textContent='VERSION '+value.version.slice(0,12);
      row.append(top,track,version);$('distribution').append(row);
    });
  }
  $('stream').replaceChildren();
  for(const event of events){
    const row=document.createElement('tr');
    for(const [index,text] of ['#'+String(event.id).padStart(3,'0'),event.pod,event.ms+' ms',event.ok?'200 OK':'FAILED'].entries()){
      const cell=document.createElement('td');cell.textContent=text;if(index===3)cell.className=event.ok?'ok':'bad';row.append(cell);
    }
    $('stream').append(row);
  }
}
async function sendOne(){
  const start=performance.now();total++;const id=total;
  try{
    const response=await fetch('/api/whoami',{cache:'no-store',signal:AbortSignal.timeout(6000)});
    if(!response.ok)throw Error('Request failed');
    const value=await response.json();if(typeof value.pod!=='string')throw Error('Invalid response');
    const ms=Math.round(performance.now()-start);success++;elapsed+=ms;
    const old=counts.get(value.pod)||{count:0,version:value.version};
    old.count++;counts.set(value.pod,old);events.unshift({id,pod:value.pod,ms,ok:true});
  }catch{events.unshift({id,pod:'Backend unavailable',ms:Math.round(performance.now()-start),ok:false});}
  events=events.slice(0,12);render();
}
$('send').addEventListener('click',async()=>{
  if(running)return;running=true;$('send').disabled=true;$('reset').disabled=true;
  try{for(let i=0;i<30;i++){$('status').textContent='Sending '+(i+1)+' / 30';await sendOne();}}
  finally{running=false;$('send').disabled=false;$('reset').disabled=false;$('status').textContent='Batch complete. '+counts.size+' pods observed.';}
});
$('reset').addEventListener('click',()=>{if(running)return;location.reload();});

$('browser-host').textContent=location.host;
