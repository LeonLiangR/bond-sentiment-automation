export const SHEETS=['当日报告','样本及逐券得分','DQ结果','DM原始数据','历史底表'];
export const LABELS=['低估值>5BP','低估值3—5BP','估值±3BP','高估值3—5BP','高估值5—10BP','高估值≥10BP'];
export const SCORING_NOTE=[
 '利差得分：x＝票面利率－DQ定价中枢（单位BP）。x≤−10得1分；−10<x<−3得(−3−x)/7分；−3≤x≤3得0分；3<x<10得−1.5×(x−3)/7分；x≥10得−1.5分。',
 '新情绪指数＝50＋25×有效样本逐券得分之和/N，N为剔除定价失败、空白及未匹配样本后的有效只数。',
 '旧情绪指数＝50＋n₁＋0.5n₂−0.5n₄−n₅−1.5n₆。n₁至n₆依次为x<−5、−5≤x<−3、−3≤x<3、3≤x<5、5≤x<10、x≥10的有效只数，按只数加权，不除以N。'
].join('\n');
export const SCORING_NOTE_HEIGHT=96;
export const HEADERS={
 samples:['样本ID','债券简称','DM债券类型','Wind代码','发行人','有效期限(年)','实际票面利率','DQ下限(%)','DQ上限(%)','DQ中枢(%)','利差(BP)','是否计入指数','逐券得分','指数贡献(点)','处理状态','排除原因'],
 dq:['提交序号','样本ID','债券简称','发行人','担保人','期限(年)','债券类型','主题','发行方式','可续期','次级属性','估值日期','下限(%)','上限(%)','中枢(%)','处理状态','排除原因'],
 history:['日期',...LABELS,'新情绪指数','旧情绪指数','有效样本量','历史文字汇报']
};
export function buildReportPlan(data){
 const {date,valid,sampleA,excluded,summary,raw}=data;if(!raw?.headers||!raw.rows.every(r=>Array.isArray(r.values)))throw Error('DM完整原始底表缺失，请重新读取附件');
 const items=new Map([...valid,...excluded.filter(e=>e.stage!=='DM筛选')].map(x=>[x.sampleId,x])),validIds=new Set(valid.map(s=>s.sampleId));
 const dqItems=[...valid,...excluded.filter(e=>e.stage==='DQ')].sort((a,b)=>a.sourceRow-b.sourceRow);
 if(items.size!==sampleA.length||new Set(dqItems.map(s=>s.binding.batchId+':'+s.binding.dqId)).size!==dqItems.length)throw Error('报表样本或DQ关联不唯一');
 const end=sampleA.length+1,dqEnd=dqItems.length+1,forms={summary:[],samples:[],dq:[]};
 const samples=sampleA.map((s,i)=>{const row=i+2,x=items.get(s.sampleId),ok=validIds.has(s.sampleId);if(!x)throw Error('样本状态缺失：'+s.sampleId);
  for(const [col,source]of [['H','M'],['I','N'],['J','O']])forms.samples.push({cell:col+row,value:`=IF(L${row}=1,INDEX('DQ结果'!$${source}$2:$${source}$${dqEnd},MATCH(A${row},'DQ结果'!$B$2:$B$${dqEnd},0)),"")`});
  forms.samples.push({cell:'K'+row,value:`=IF(L${row}=1,ROUND((G${row}*100-J${row})*100,4),"")`},{cell:'M'+row,value:`=IF(L${row}=1,IF(ABS(K${row})<=3,0,IF(K${row}<0,MIN((-3-K${row})/7,1),-1.5*MIN((K${row}-3)/7,1))),"")`},{cell:'N'+row,value:`=IF(L${row}=1,25*M${row}/'当日报告'!$C$15,"")`});
  return [s.sampleId,s.name,s.dmType,x.wind?.code??null,x.issuer??null,x.term??null,s.coupon,null,null,null,null,ok?1:0,null,null,ok?'定价有效':x.stage==='Wind'?'Wind条款失败':'DQ定价失败',ok?null:x.reason];
 });
 const dq=dqItems.map((s,i)=>{const r=i+2,ok=validIds.has(s.sampleId);forms.dq.push({cell:'O'+r,value:`=IF(P${r}="定价有效",(M${r}+N${r})/2,"")`});return[s.binding.seq,s.sampleId,s.name,s.issuer,s.guarantor||null,s.term,s.bondType,s.theme,s.issueMode,s.renewal,s.subordinate,s.dq.valDate??null,s.dq.prcMin??null,s.dq.prcMax??null,null,ok?'定价有效':'DQ定价失败',ok?null:s.reason];});
 const k=`'样本及逐券得分'!$K$2:$K$${end}`,flag=`'样本及逐券得分'!$L$2:$L$${end}`,scores=`'样本及逐券得分'!$M$2:$M$${end}`;
 const conditions=[['<-5'],['>=-5','<-3'],['>=-3','<3'],['>=3','<5'],['>=5','<10'],['>=10']];
 for(let j=0;j<6;j++){const col=String.fromCharCode(66+j);forms.summary.push({cell:col+'6',value:`=COUNTIFS(${flag},1,${conditions[j].map(c=>`${k},"${c}"`).join(',')})`},{cell:col+'9',value:`=${col}6`},{cell:col+'11',value:`=${col}9*${col}10`});}
 const cells={H6:'=SUM(B6:G6)',H9:'=SUM(B9:G9)',B12:'=SUM(B11:G11)',B15:`=SUM(${scores})`,C15:`=COUNTIFS(${flag},1)`,D15:`=IF(C15=0,"",AVERAGE(${scores}))`,E15:'=IF(C15=0,"",50+25*D15)',F15:'=IF(C15>=25,"正常",IF(C15>=15,"样本偏少","低置信"))',G15:'=50+B6+C6*0.5-E6*0.5-F6-G6*1.5',H15:'=IF(C15=0,"",(B6+C6-E6-F6-G6)/C15)',I15:`=IF(C15<2,"",25*STDEV(${scores})/SQRT(C15))`};
 forms.summary.push(...Object.entries(cells).map(([cell,value])=>({cell,value})));
 const current={date,bins:summary.bins,index:summary.index,oldIndex:summary.oldIndex,n:summary.n,text:data.reportText};const history=[...data.history.filter(h=>h.date<date),current].sort((a,b)=>a.date.localeCompare(b.date));
 const dmExcluded=new Map(excluded.filter(e=>e.stage==='DM筛选').map(e=>[e.sourceRow,e]));
 const dm=raw.rows.map(r=>[...r.values,dmExcluded.has(r.row)?'初筛剔除':'入选样本A',dmExcluded.get(r.row)?.reason??null]);
 return{date,sheets:SHEETS,headers:HEADERS,forms,samples,dq,dm,dmHeaders:[...raw.headers,'初筛状态','初筛原因'],history:history.map(h=>[Date.parse(h.date+'T00:00:00Z')/86400000+25569,...h.bins,h.index,h.oldIndex,h.n,h.text||null]),historyObjects:history,reportText:data.reportText,scoringNote:SCORING_NOTE,scoringNoteHeight:SCORING_NOTE_HEIGHT,summary,source:raw.title,sourceFile:data.article?.name||''};
}
export function checkNativeReport(actual,data,plan){
 const close=(a,b,label)=>{if(typeof a!=='number'||Math.abs(a-b)>1e-8)throw Error('表格结果不一致：'+label+' '+a+' / '+b);};
 if(actual.sheetNames.join('|')!==SHEETS.join('|')||actual.pictureCount!==1)throw Error('报表sheet或内嵌图片不完整');
 if(!['楷体','KaiTi'].includes(actual.fonts?.chinese)||actual.fonts?.english!=='Times New Roman'||actual.fonts?.mixedEnglish!=='Times New Roman'||!['楷体','KaiTi'].includes(actual.fonts?.mixedChinese))throw Error('中英文字体核验未通过：'+JSON.stringify(actual.fonts));
 if(JSON.stringify(actual.dmHeaders)!==JSON.stringify(plan.dmHeaders)||actual.dmData?.length!==data.raw.rows.length)throw Error('DM原始底表表头或记录不完整');
 for(let i=0;i<data.raw.rows.length;i++)for(let j=0;j<data.raw.rows[i].values.length;j++){const expected=data.raw.rows[i].values[j],got=actual.dmData[i][j];if((expected===null||expected==='')&&(got===null||got===''))continue;if(typeof expected==='number'&&typeof got==='number'&&Math.abs(expected-got)<1e-10)continue;if(got!==expected)throw Error('DM原始字段不一致：'+(i+2)+','+(j+1));}
 if(actual.historyTail?.[10]!==data.reportText)throw Error('历史文字未记录');close(actual.historyTail[7],data.summary.index,'历史指数');
 for(const [cell,key]of [['B15','scoreSum'],['C15','n'],['D15','mean'],['E15','index'],['G15','oldIndex'],['H15','netLow']])close(actual.summary[cell],data.summary[key],cell);
 const map=new Map(data.valid.map(s=>[s.sampleId,s]));let contribution=0;
 if(actual.samples.length!==data.sampleA.length||actual.dq.length!==plan.dq.length||actual.dmRows!==data.raw.rows.length)throw Error('导出样本或DQ/DM数量不一致');
 for(let i=0;i<actual.samples.length;i++){const r=actual.samples[i],s=map.get(r[0]);if(r[0]!==data.sampleA[i].sampleId||r[1]!==data.sampleA[i].name)throw Error('样本身份错配');if(s){for(const [col,key]of [[9,'center'],[10,'spread'],[12,'score']])close(r[col],s[key],s.name+key);close(r[13],25*s.score/data.summary.n,s.name+'贡献');contribution+=r[13];}else if([7,8,9,10,12,13].some(col=>r[col]!==null&&r[col]!==''))throw Error('失败样本混入计算');}
 close(50+contribution,data.summary.index,'逐券贡献汇总');
 for(let i=0;i<actual.dq.length;i++){const r=actual.dq[i],p=plan.dq[i];for(const col of [0,1,2,15,16])if((r[col]??null)!==(p[col]??null))throw Error('DQ结果标识或状态错配');if(p[15]!=='定价有效'&&r[14]!==null&&r[14]!=='')throw Error('DQ失败样本产生中枢');}
 if(!actual.mutation?.passed)throw Error('表格指数联动核验未通过');return{passed:true,sheets:5,sampleA:actual.samples.length,dqRows:actual.dq.length,valid:data.summary.n,dmRows:actual.dmRows,index:data.summary.index,pictureEmbedded:true,mutation:actual.mutation};
}
