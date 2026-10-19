importScripts('waveform-parser.js');
onmessage=async event=>{try{const file=event.data;if(file.size>50*1024*1024)throw Error('Choose a CSV smaller than 50 MB.');postMessage({result:parseRecording(await file.text())})}catch(error){postMessage({error:error.message})}};
