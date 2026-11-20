import fs from 'node:fs/promises';
import path from 'node:path';
import {mergeHistoryRecords,readHistoryFile}from '../src/history.mjs';
const [input,output]=process.argv.slice(2);if(!input||!output)throw Error('需要历史来源和种子输出路径');
await fs.access(input);
const rows=mergeHistoryRecords(await readHistoryFile(input));if(!rows.length)throw Error('同事包需要非空绘图历史');
await fs.mkdir(path.dirname(output),{recursive:true});await fs.writeFile(output,JSON.stringify(rows,null,2)+'\n','utf8');
console.log(JSON.stringify({rows:rows.length,firstDate:rows[0].date,lastDate:rows.at(-1).date}));
