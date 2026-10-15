import {build} from '../../../paraselene-work/node_modules/vite/dist/node/index.js';
import {fileURLToPath} from 'node:url';
const root=fileURLToPath(new URL('.',import.meta.url));
await build({configFile:false,base:"./",root,cacheDir:root+'.vite-cache',build:{outDir:root+'dist',emptyOutDir:true,minify:true}});
