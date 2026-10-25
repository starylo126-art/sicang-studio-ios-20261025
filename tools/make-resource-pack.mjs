// Usage: node tools/make-resource-pack.mjs ../avatar-studio ../私藏衣橱.scstudio
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
const [source,destination]=process.argv.slice(2);
if(!source||!destination)throw Error('Provide the web app directory and output .scstudio path.');
const roots=['assets','models','src','vendor'];
const top=['index.html','studio.css','compact.css','wardrobe.html','wardrobe-embed.css','style.css','app.js','asset-loader.js','catalog.js','palettes.js','color.js','THIRD_PARTY_NOTICES.txt'];
const paths=[...top];
function walk(dir){for(const item of fs.readdirSync(path.join(source,dir),{withFileTypes:true})){const name=dir+'/'+item.name;if(item.isDirectory())walk(name);else if(item.isFile())paths.push(name);}}
roots.forEach(walk);paths.sort();
const files=paths.map(p=>{const data=fs.readFileSync(path.join(source,p));return {path:p,size:data.length,sha256:crypto.createHash('sha256').update(data).digest('hex')};});
const manifest=Buffer.from(JSON.stringify({format:'private-wardrobe-resources',version:1,files}));
const length=Buffer.alloc(4);length.writeUInt32LE(manifest.length);
const out=fs.openSync(destination,'w');
try{fs.writeSync(out,Buffer.from('SCSTUDIO1\n'));fs.writeSync(out,length);fs.writeSync(out,manifest);for(const f of files)fs.writeSync(out,fs.readFileSync(path.join(source,f.path)));}finally{fs.closeSync(out);}
console.log(JSON.stringify({file:path.resolve(destination),entries:files.length,bytes:fs.statSync(destination).size,sha256:crypto.createHash('sha256').update(fs.readFileSync(destination)).digest('hex')},null,2));
