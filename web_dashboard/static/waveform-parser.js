/* VitalWave protocol 3 CSV. Pure parser shared by the worker and tests. */
(function(root){
'use strict';
const columns=['protocol_version','type','protocol_session_id','sequence','watch_timestamp_ms','x_raw','y_raw','z_raw','validity','ppg_raw'];
function parseRecording(text){
 const lines=text.replace(/^\uFEFF/,'').split(/\r?\n/), header=lines.shift().trim().split(',').map(v=>v.trim());
 const index=Object.fromEntries(header.map((v,i)=>[v,i]));
 if(columns.some(k=>!(k in index)))throw Error('Choose a VitalWave recording CSV exported from the app. Required columns are missing.');
 const groups={ppg:[],acc:[],gyro:[],temp:[],humidity:[]};
 const traces=[['IR','ppg','#7161b8'],['Red','ppg','#d35361'],['Green','ppg','#288752'],['Blue','ppg','#2563eb'],['X','acc','#2563eb'],['Y','acc','#cf7045'],['Z','acc','#8561b5'],['X','gyro','#2563eb'],['Y','gyro','#cf7045'],['Z','gyro','#8561b5'],['Temperature','temp','#2563eb'],['Humidity','humidity','#2563eb']].map(([name,group,color])=>({name,group,color,x:[],y:[]}));
 const seen=new Set(),lastTime={},stats={rows:0,invalid:0,duplicates:0,outOfOrder:0},sessions=new Set();let base=null,min=Infinity,max=-Infinity;
 const num=(cells,key)=>{const s=cells[index[key]]?.trim();if(s===undefined||s==='')throw Error('Missing '+key);const n=Number(s);if(!Number.isFinite(n)||!Number.isInteger(n))throw Error('Invalid '+key);return n};
 function bounded(n,lo,hi,label){if(n<lo||n>hi)throw Error('Invalid '+label);return n}
 for(let i=0;i<lines.length;i++){
  if(!lines[i].trim())continue;
  if(++stats.rows>500000)throw Error('This viewer supports up to 500,000 rows per file. Choose a shorter recording.');
  try{
   const c=lines[i].split(',');if(c.length!==header.length)throw Error('Unexpected column count');
   if(num(c,'protocol_version')!==3)throw Error('Unsupported protocol version');
   const type=bounded(num(c,'type'),1,7,'sensor type'),sid=bounded(num(c,'protocol_session_id'),0,4294967295,'session ID'),seq=bounded(num(c,'sequence'),0,65535,'sequence');
   sessions.add(sid);if(sessions.size>1)throw Error('Multiple sessions in one file');
   const ms=bounded(num(c,'watch_timestamp_ms'),0,4294967295,'timestamp');
   const x=bounded(num(c,'x_raw'),-32768,32767,'x'),y=bounded(num(c,'y_raw'),-32768,32767,'y'),z=bounded(num(c,'z_raw'),-32768,32767,'z');
   const valid=num(c,'validity')===1;
   const key=[sid,seq,type,ms,x,y,z,c[index.validity]].join(':');if(seen.has(key)){stats.duplicates++;continue}seen.add(key);
   if(base===null)base=ms;
   // Signed modular difference handles a single clock wrap; recordings must be <24.8 days.
   const time=((ms-base)|0)/1000;
   if(lastTime[type]!==undefined&&time<lastTime[type])stats.outOfOrder++;
   lastTime[type]=time;min=Math.min(min,time);max=Math.max(max,time);
   if(!valid)stats.invalid++;
   function add(k,value){traces[k].x.push(time);traces[k].y.push(valid?value:null)}
   if(type===1){add(4,x*.000061);add(5,y*.000061);add(6,z*.000061)}
   else if(type===2){add(7,x*.00875);add(8,y*.00875);add(9,z*.00875)}
   else if(type===3){add(10,x/100);add(11,y/100)}
   else{
    let ppg=null;
    if(valid){if(y<0||y>7||z!==0)throw Error('Invalid PPG encoding');ppg=(x&65535)|((y&65535)<<16);const stored=c[index.ppg_raw].trim();if(stored!==''&&Number(stored)!==ppg)throw Error('PPG value does not match raw channels')}
    add(type-4,ppg);
   }
  }catch(e){throw Error('Row '+(i+2)+': '+e.message)}
 }
 if(!stats.rows)throw Error('The CSV has no samples.');
 for(const t of traces){if(!t.x.length)continue;const order=t.x.map((_,i)=>i).sort((a,b)=>t.x[a]-t.x[b]);t.y=order.map(i=>t.y[i]);t.x=order.map(i=>t.x[i]-min);groups[t.group].push(t)}
 return {groups,stats,duration:max-min,sessionID:[...sessions][0]};
}
root.parseRecording=parseRecording;
if(typeof module!=='undefined')module.exports={parseRecording};
})(typeof self!=='undefined'?self:globalThis);
