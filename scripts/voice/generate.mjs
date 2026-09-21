import {KokoroTTS} from 'kokoro-js';
import {Tensor,RawAudio} from '@huggingface/transformers';
import {mkdir,readFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
const root=new URL('../../',import.meta.url);
const steps=JSON.parse(await readFile(new URL('lib/tutorial-steps.json',root),'utf8'));
const tts=await KokoroTTS.from_pretrained('onnx-community/Kokoro-82M-v1.0-ONNX',{dtype:'fp32',device:'cpu'});
async function voice(name){
 const response=await fetch('https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX/resolve/main/voices/'+name+'.bin');
 if(!response.ok)throw Error('Voice download failed: '+name);
 return new Float32Array(await response.arrayBuffer());
}
const [american,italian]=await Promise.all([voice('am_michael'),voice('im_nicola')]);
// Keep English phonemes, using the approved 85% American / 15% Italian style.
tts.generate_from_ids=async(input_ids)=>{
 const offset=256*Math.min(Math.max(input_ids.dims.at(-1)-2,0),509);
 const style=new Float32Array(256);
 for(let i=0;i<256;i++)style[i]=american[offset+i]*0.85+italian[offset+i]*0.15;
 const {waveform}=await tts.model({input_ids,style:new Tensor('float32',style,[1,256]),speed:new Tensor('float32',[0.98],[1])});
 if(!waveform.data.length||!waveform.data.every(Number.isFinite))throw Error('Invalid audio output');
 return new RawAudio(waveform.data,24000);
};
await mkdir(new URL('public/audio/tutorial/',root),{recursive:true});
for(const step of steps){
 const audio=await tts.generate(step.text,{voice:'am_michael',speed:0.98});
 await audio.save(fileURLToPath(new URL('public/audio/tutorial/'+step.id+'.wav',root)));
 console.log(step.id,(audio.audio.length/audio.sampling_rate).toFixed(2),'seconds');
}
