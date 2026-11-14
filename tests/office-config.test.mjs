import test from 'node:test';import assert from 'node:assert/strict';import {selectOffice} from '../src/office-config.mjs';
const wps='C:\\WPS\\et.exe',excel='C:\\Office\\EXCEL.EXE',installed=file=>[wps,excel].includes(file);
test('仅安装Excel时不要求WPS；旧配置继续使用WPS',()=>{
 assert.equal(selectOffice({excelExe:excel},installed).engine,'excel');
 assert.equal(selectOffice({wpsExe:wps},installed).engine,'wps');
 assert.equal(selectOffice({wpsExe:wps,excelExe:excel,spreadsheetEngine:'excel'},installed).progId,'Excel.Application');
});
test('用户明确选定引擎后，缺失或错误路径必须停止，不能改用另一引擎',()=>{
 assert.throws(()=>selectOffice({wpsExe:wps,spreadsheetEngine:'excel'},installed),/Excel安装位置/);
 assert.throws(()=>selectOffice({excelExe:wps,spreadsheetEngine:'excel'},installed),/excel.exe/);
 assert.throws(()=>selectOffice({wpsExe:wps,spreadsheetEngine:'auto'},installed),/仅支持/);
});
