import test from'node:test';import assert from'node:assert/strict';
import{makeNarrative,summarize}from'../src/core.mjs';
const base=summarize([{spread:0}]);
const text=(current,previous)=>makeNarrative('2026-11-12',{...base,index:current},[{date:'2026-11-11',index:previous}]);
test('指数完全相同或显示变化为零时，只写基本持平',()=>{
 for(const change of [0,.004,-.004]){const result=text(50+change,50);assert.match(result,/较上一有效统计日基本持平。/);assert.doesNotMatch(result,/上升0\.00|下降0\.00|有所改善|有所转弱/);}
});
test('可显示的指数变动仍报告方向、幅度和对应表述',()=>{
 assert.match(text(50.01,50),/上升0\.01点，发行定价情绪有所改善/);
 assert.match(text(49.99,50),/下降0\.01点，发行定价情绪有所转弱/);
 const first=makeNarrative('2026-11-12',base,[]);assert.doesNotMatch(first,/上一有效统计日/);
});
