import fs from 'node:fs';
import path from 'node:path';
export function selectOffice(settings,exists=file=>!!file&&fs.existsSync(file)) {
 const requested=settings.spreadsheetEngine;
 if(requested && !['wps','excel'].includes(requested))throw Error('表格引擎仅支持 WPS 或 Excel');
 const engine=requested||(exists(settings.wpsExe)?'wps':exists(settings.excelExe)?'excel':'wps');
 const key=engine==='excel'?'excelExe':'wpsExe',exe=settings[key],name=engine==='excel'?'Excel':'WPS';
 const expected=engine==='excel'?'excel.exe':'et.exe';
 if(!exists(exe))throw Error('请在设置中确认'+name+'安装位置');
 if(path.win32.basename(exe).toLowerCase()!==expected)throw Error(name+'必须选择'+expected+'，不能用其他软件代替');
 return{engine,exe,name,progId:engine==='excel'?'Excel.Application':'ket.Application',processName:engine==='excel'?'EXCEL':'et'};
}
