'use strict';
const fileInput=document.getElementById('csv'),statusLine=document.getElementById('status'),charts=document.getElementById('charts'),summary=document.getElementById('summary'),reset=document.getElementById('reset');
let worker=null,plots=[],revision=0;
function message(text){statusLine.textContent=text;statusLine.hidden=!text}
function clear(){plots.forEach(p=>Plotly.purge(p));plots=[];charts.replaceChildren();summary.replaceChildren();summary.hidden=true;reset.hidden=true}
// Min/max envelope per bucket keeps peaks visible. Invalid samples break lines.
function reduceTrace(t,range){
 const limit=8000;let start=0,end=t.x.length;
 if(range){while(start<end&&t.x[start]<range[0])start++;if(start>0)start--;end=start;while(end<t.x.length&&t.x[end]<=range[1])end++;end=Math.min(t.x.length,end+1)}
 const step=Math.max(1,Math.ceil((end-start)/limit)),ids=[];
 for(let i=start;i<end;i+=step){let lo=i,hi=i,gap=-1;for(let j=i;j<Math.min(end,i+step);j++){if(t.y[j]===null){gap=j;continue}if(t.y[lo]===null||t.y[j]<t.y[lo])lo=j;if(t.y[hi]===null||t.y[j]>t.y[hi])hi=j}ids.push(...[...new Set([i,lo,hi,gap,Math.min(end,i+step)-1].filter(n=>n>=0))].sort((a,b)=>a-b))}
 return {x:ids.map(i=>t.x[i]),y:ids.map(i=>t.y[i])};
}
const labels={ppg:['PPG','Raw counts'],acc:['Accelerometer','g'],gyro:['Gyroscope','°/s'],temp:['Temperature','°C'],humidity:['Humidity','% RH']};
fileInput.addEventListener('change',()=>{
 const file=fileInput.files[0];if(!file)return;const mine=++revision;if(worker)worker.terminate();clear();document.getElementById('filename').textContent=file.name;message('Reading CSV…');
 worker=new Worker('/static/waveform-worker.js');
 worker.onerror=()=>{if(mine===revision)message('Could not read the file. Reload this page and try again.')};
 worker.onmessage=async e=>{if(mine!==revision)return;worker.terminate();worker=null;if(e.data.error){message(e.data.error);return}try{await show(e.data.result,mine)}catch(err){if(mine===revision){clear();message('Could not draw this recording. '+err.message)}}};worker.postMessage(file);
});
async function show(data,mine){
 const warnings=[];if(data.stats.invalid)warnings.push(data.stats.invalid+' invalid samples shown as gaps');if(data.stats.duplicates)warnings.push(data.stats.duplicates+' duplicate frames omitted');if(data.stats.outOfOrder)warnings.push(data.stats.outOfOrder+' out-of-order frames sorted');message(warnings.join(' · '));
 for(const [label,value] of [['Samples',data.stats.rows.toLocaleString()],['Duration',data.duration.toFixed(2)+' s'],['Session ID',data.sessionID]]){const card=document.createElement('div');card.className='stat';const caption=document.createElement('span');caption.textContent=label;const number=document.createElement('strong');number.textContent=value;card.append(caption,number);summary.append(card)}summary.hidden=false;
 for(const [key,traces] of Object.entries(data.groups)){
  if(!traces.length)continue;
  const panel=document.createElement('section');panel.className='panel plot-panel';const top=document.createElement('div');top.className='plot-top';const heading=document.createElement('h2');heading.textContent=labels[key][0];top.append(heading);const controls=document.createElement('div');controls.className='channels';top.append(controls);const plot=document.createElement('div');plot.className='plot';panel.append(top,plot);charts.append(panel);
  const series=traces.map(t=>({...reduceTrace(t),type:'scattergl',mode:'lines',name:t.name,line:{color:t.color,width:1.3},connectgaps:false,hovertemplate:'%{x:.3f} s<br>%{y}<extra>'+t.name+'</extra>'}));
  await Plotly.newPlot(plot,series,{margin:{l:65,r:25,t:10,b:50},font:{family:'system-ui',color:'#172b4d'},paper_bgcolor:'#fff',plot_bgcolor:'#fff',showlegend:false,xaxis:{title:'Time (s)',gridcolor:'#edf1f8',range:[0,data.duration||1]},yaxis:{title:labels[key][1],gridcolor:'#edf1f8',autorange:true},dragmode:'zoom'},{responsive:true,displaylogo:false,scrollZoom:false,modeBarButtonsToRemove:['select2d','lasso2d']});
  if(mine!==revision){Plotly.purge(plot);return}plot.sourceTraces=traces;plots.push(plot);
  traces.forEach((t,index)=>{const label=document.createElement('label'),input=document.createElement('input');input.type='checkbox';input.checked=true;input.setAttribute('aria-label',labels[key][0]+' '+t.name);input.addEventListener('change',()=>Plotly.restyle(plot,{visible:input.checked},[index]));label.append(input,document.createTextNode(t.name));controls.append(label)});
  plot.on('plotly_relayout',event=>{if(syncing)return;if(event['xaxis.autorange'])syncRange(null);else if(event['xaxis.range[0]']!==undefined)syncRange([event['xaxis.range[0]'],event['xaxis.range[1]']])});
 }reset.hidden=!plots.length;
}
let syncing=false;
async function syncRange(range){if(syncing)return;syncing=true;try{await Promise.all(plots.map(async p=>{const values=p.sourceTraces.map(t=>reduceTrace(t,range));await Plotly.restyle(p,{x:values.map(t=>t.x),y:values.map(t=>t.y)});await Plotly.relayout(p,range?{'xaxis.range':range,'yaxis.autorange':true}:{'xaxis.autorange':true,'yaxis.autorange':true})}))}finally{syncing=false}}
reset.addEventListener('click',()=>syncRange(null));
